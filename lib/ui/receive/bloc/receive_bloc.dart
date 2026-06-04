import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:convert/convert.dart';
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:safe_file_sender/cache/hive/hive_manager.dart';
import 'package:safe_file_sender/common/app_temp_data.dart';
import 'package:safe_file_sender/crypto/crypto_core.dart';
import 'package:safe_file_sender/dev/logger.dart';
import 'package:safe_file_sender/io/connection_client.dart';
import 'package:safe_file_sender/models/event_listeners.dart';
import 'package:safe_file_sender/models/state_controller.dart';

part 'receive_event.dart';

part 'receive_state.dart';

class ReceiveBloc extends Bloc<ReceiveEvent, ReceiveState>
    implements ReceiverListeners {
  final AppTempData _appTempData;
  late final ConnectionClient _connectionClient;
  ECPrivateKey? _privateKey;
  Uint8List? _sharedKey;

  ReceiveBloc(this._appTempData) : super(const ReceiveState()) {
    _connectionClient = ConnectionClient(this);
    on<CreateSession>(_onCreateSession);
    on<ClearReceive>(_onClear);
    on<PublicKeyReceived>(_onPublicKeyReceived);
    on<IdentifierReceived>(_onIdentifierReceived);
    on<FileReceived>(_onFileReceived);
  }

  Future<void> _onCreateSession(
      CreateSession event, Emitter<ReceiveState> emit) async {
    if (!state.transferState.isIdle) return;
    emit(_log(state.copyWith(history: const []), TransferStateEnum.connection));

    await _connectionClient.connect();
    if (!_connectionClient.isConnected) {
      emit(_log(state, TransferStateEnum.connectionError));
      return;
    }
    emit(_log(state, TransferStateEnum.connected));
    emit(_log(state, TransferStateEnum.generatingKey));

    final keyPair = AppCrypto.generateECKeyPair();
    _privateKey = keyPair.privateKey;

    emit(_log(state, TransferStateEnum.creatingSession));
    _connectionClient
        .createSession(AppCrypto.encodeECPublicKey(keyPair.publicKey));
  }

  Future<void> _onPublicKeyReceived(
      PublicKeyReceived event, Emitter<ReceiveState> emit) async {
    logMessage('PublicKey : ${event.publicKey}');
    emit(_log(state, TransferStateEnum.sharedKeyDeriving));

    final sharedKey = AppCrypto.deriveSharedSecret(
        _privateKey!, AppCrypto.decodeECPublicKey(event.publicKey));
    _sharedKey = sharedKey;
    logMessage('Shared key derived [${sharedKey.length}] $sharedKey');
    emit(_log(state, TransferStateEnum.sharedKeyDerived));

    final digest = hex.encode(AppCrypto.sha256Digest(sharedKey));
    emit(_log(state.copyWith(sharedKeyDigest: digest),
        TransferStateEnum.sharedKeyDigest));
    emit(_log(state, TransferStateEnum.waitingFile));
  }

  Future<void> _onIdentifierReceived(
      IdentifierReceived event, Emitter<ReceiveState> emit) async {
    emit(_log(state.copyWith(identifier: event.identifier),
        TransferStateEnum.identifierGenerated));
  }

  Future<void> _onFileReceived(
      FileReceived event, Emitter<ReceiveState> emit) async {
    emit(_log(state, TransferStateEnum.fileIdReceived));
    final savePath = (await getApplicationCacheDirectory()).path;
    emit(_log(state, TransferStateEnum.downloadingFile));

    final completer = Completer<File?>();
    _connectionClient.downloadFile(
      event.fileId,
      event.fileName,
      savePath,
      onSuccess: (file, fileName) => completer.complete(file),
      onError: () => completer.complete(null),
    );
    final file = await completer.future;

    if (file == null) {
      emit(_log(state, TransferStateEnum.fileDeleteError));
      _resetSecrets();
      emit(const ReceiveState());
      return;
    }

    emit(_log(state, TransferStateEnum.checkingHmac));
    final fileBytes = file.readAsBytesSync();
    final hmacLocal =
        hex.encode(await AppCrypto.generateHMACIsolate(_sharedKey!, fileBytes));

    if (hmacLocal != event.hmac) {
      logMessage('HMAC check failed: local $hmacLocal  remote ${event.hmac}');
      emit(_log(state, TransferStateEnum.hmacError));
      _resetSecrets();
      emit(const ReceiveState());
      return;
    }

    logMessage('HMAC check success');
    emit(_log(state, TransferStateEnum.hmacSuccess));
    emit(_log(state, TransferStateEnum.savingEncryptedFile));

    final derivedKey = _appTempData.getPinDerivedKey();
    final encryptedSecretKey =
        await AppCrypto.encryptAESInIsolate(_sharedKey!, derivedKey!);
    await HiveManager.saveFile(
      event.fileId,
      file.path,
      event.hmac,
      base64Encode(encryptedSecretKey),
      _appTempData.getPinDerivedKeySalt()!,
    );

    // Surface the saved file so the UI can present the history sheet, then
    // reset back to idle so a new session can be started.
    emit(state.copyWith(receivedFileId: event.fileId));
    await _connectionClient.disconnect();
    _resetSecrets();
    emit(const ReceiveState());
  }

  Future<void> _onClear(ClearReceive event, Emitter<ReceiveState> emit) async {
    _resetSecrets();
    emit(const ReceiveState());
  }

  void _resetSecrets() {
    _privateKey = null;
    _sharedKey = null;
  }

  /// Appends [status] to the running history and makes it the current state.
  ReceiveState _log(ReceiveState current, TransferStateEnum status) {
    return current.copyWith(
      transferState: status,
      history: [...current.history, status],
    );
  }

  @override
  Future<void> onConnected() async {}

  @override
  Future<void> onPublicKeyReceived(String publicKey) async {
    add(PublicKeyReceived(publicKey));
  }

  @override
  Future<void> onIdentifierReceived(String identifier) async {
    add(IdentifierReceived(identifier));
  }

  @override
  Future<void> onFileReceived(
      String fileId, String fileName, String hmac) async {
    add(FileReceived(fileId, fileName, hmac));
  }

  @override
  Future<void> close() async {
    await _connectionClient.disconnect();
    return super.close();
  }
}
