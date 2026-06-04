import 'dart:io';

import 'package:safe_file_sender/dev/logger.dart';
import 'package:safe_file_sender/io/downloader.dart';
import 'package:safe_file_sender/models/base/base_event_listener.dart';
import 'package:safe_file_sender/models/environment.dart';
import 'package:safe_file_sender/models/event_listeners.dart';
import 'package:signalr_netcore/json_hub_protocol.dart';
import 'package:signalr_netcore/signalr_client.dart';

class ConnectionClient {
  final BaseEventListeners _eventNotifier;
  late HubConnection? _connection;
  static String baseUrl = 'https://unsubserviently-noncommendatory-flynn.ngrok-free.dev/';

  void buildSignalR() {
    _connection = HubConnectionBuilder()
        .withUrl('${baseUrl}hubs/session')
        .withHubProtocol(JsonHubProtocol())
        .withSingleListener(true)
        .build();
  }

  Future<void> createSession(String publicKeyBase64) async {
    _log('Creating session : $isConnected');
    _connection?.send('CreateSession', args: [
      {
        'publicKey': publicKeyBase64,
      }
    ]);
  }

  Future<void> joinSession(String identifier, String publicKey) async {
    try {
      _connection?.send('JoinSession', args: [
        {
          'identifier': identifier,
          'publicKey': publicKey,
        }
      ]).onError((value, trace) {
        _log(trace.toString());
      }).catchError((onError) {
        _log(onError);
      }).then((value) {
        logMessage('Join session end');
      });
    } catch (e) {
      logMessage(e.toString());
    }
  }

  Future<bool> sendFile(
      String filePath, String fileName, String sessionId, String hmac) async {
    try {
      await Downloader.uploadFile(filePath, sessionId, hmac,
          onUpdate: (progress) {
        //
      }, onError: () {
        throw Exception();
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _listenEvents() async {
    _connection?.on('OnSessionCreated', (message) async {
      _log('OnSessionCreated : $message');
      (_eventNotifier as ReceiverListeners)
          .onIdentifierReceived(message![0].toString());
    });
    _connection?.on('OnSessionReady', (message) async {
      _log('OnSessionReady : $message');
      _eventNotifier.onPublicKeyReceived(message![0].toString());
    });
    _connection?.on('OnFileUploaded', (message) async {
      _log('OnFileUploaded : $message');
      (_eventNotifier as ReceiverListeners).onFileReceived(
        message![0].toString(),
        message[1].toString(),
        message[2].toString(),
      );
    });
  }

  bool get isConnected => _connection?.state == HubConnectionState.Connected;

  Future<void> connect() async {
    try {
      if (_connection?.state != HubConnectionState.Disconnected) return;
      await _connection?.start();
      _log(
          'IsConnected : ${_connection?.state == HubConnectionState.Connected}');
      if (_connection?.state == HubConnectionState.Connected) {
        _listenEvents();
        _eventNotifier.onConnected();
      }
    } catch (e) {
      logMessage(e.toString());
    }
  }

  Future<void> disconnect() async {
    await _connection?.stop();
  }

  ConnectionClient(this._eventNotifier) {
    buildSignalR();
  }

  _log(dynamic message) => logMessage(message);

  Future<void> downloadFile(String fileId, String fileName, String savePath,
      {required Function(File path, String fileName) onSuccess,
      required Function() onError}) async {
    try {
      Downloader.download(fileId, fileName,
          onSuccess: (String downloadedPath) async {
        final file = File(downloadedPath);
        onSuccess.call(
          file,
          fileName,
        );
      });
    } catch (e) {
      onError.call();
      logMessage('Download failed: $e');
    }
  }
}
