import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:safe_file_sender/cache/hive/hive_manager.dart';
import 'package:safe_file_sender/io/connection_client.dart';
import 'package:safe_file_sender/models/event_listeners.dart';
import 'package:safe_file_sender/models/state_controller.dart';
import 'package:safe_file_sender/ui/dialogs/dialog_utils.dart';
import 'package:safe_file_sender/ui/history/transmission_history_screen.dart';
import 'package:safe_file_sender/ui/theme.dart';
import 'package:safe_file_sender/ui/widgets/close_screen_button.dart';
import 'package:safe_file_sender/ui/widgets/common_inherited_widget.dart';
import 'package:safe_file_sender/ui/widgets/encrypted_key_matrix.dart';
import 'package:safe_file_sender/utils/context_utils.dart';
import 'package:safe_file_sender/utils/string_utils.dart';

import '../crypto/crypto_core.dart';
import '../dev/logger.dart';
import 'widgets/status_logger.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen>
    implements ReceiverListeners {
  late ConnectionClient _connectionClient;
  ECPrivateKey? _privateKey;
  Uint8List? _sharedKey;
  String? _identifier;
  String? _sharedKeyDigest;

  @override
  void initState() {
    _connectionClient = ConnectionClient(this);
    super.initState();
  }

  final TransferStateController _receiverStateController =
      TransferStateController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      bottomNavigationBar: const CloseScreenButton(),
      backgroundColor: Colors.black,
      body: Container(
        margin: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
              ),
              ElevatedButton(
                onPressed: () {
                  if (_receiverStateController.canReceive) {
                    _receive();
                  }
                },
                child: (!_receiverStateController.canReceive)
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        context.localization.createSession,
                        style: AppTheme.textTheme.titleMedium,
                      ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
              ),
              StatusLogger(controller: _receiverStateController),
              const Padding(
                padding: EdgeInsets.all(24),
              ),
              if (_identifier != null)
                InkWell(
                  onTap: () {
                    if (_identifier == null) return;
                    Clipboard.setData(ClipboardData(text: _identifier!));
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _identifier!,
                          style: AppTheme.textTheme.titleMedium
                              ?.copyWith(fontSize: 20),
                        ),
                        Text(
                          context.localization.tapToCopy,
                          style: AppTheme.textTheme.titleMedium
                              ?.copyWith(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.all(6),
              ),
              if (_sharedKeyDigest != null)
                EncryptionKeyWidget(
                  keyMatrix: StringUtils.splitByLength(_sharedKeyDigest!, 2),
                )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _receive() async {
    _receiverStateController.history.clear();
    _receiverStateController.logStatus(TransferStateEnum.connection);
    setState(() {});
    await _connectionClient.connect();

    if (!mounted) return;
    if (_connectionClient.isConnected) {
      _receiverStateController.logStatus(TransferStateEnum.connected);
      _receiverStateController.logStatus(TransferStateEnum.generatingKey);
      final keyPair = AppCrypto.generateECKeyPair();
      _privateKey = keyPair.privateKey;
      _receiverStateController.logStatus(TransferStateEnum.creatingSession);
      _connectionClient
          .createSession(AppCrypto.encodeECPublicKey(keyPair.publicKey));
    } else {
      _receiverStateController.logStatus(TransferStateEnum.connectionError);
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _connectionClient.disconnect();
    super.dispose();
  }

  @override
  Future<void> onConnected() async {
    //
  }

  @override
  Future<void> onPublicKeyReceived(String publicKey) async {
    logMessage('PublicKey : $publicKey');
    _receiverStateController.logStatus(TransferStateEnum.sharedKeyDeriving);
    final sharedKey = AppCrypto.deriveSharedSecret(
        _privateKey!, AppCrypto.decodeECPublicKey(publicKey));
    _receiverStateController.logStatus(TransferStateEnum.sharedKeyDerived);
    logMessage('Shared key derived [${sharedKey.length}] $sharedKey');
    _sharedKey = sharedKey;
    _sharedKeyDigest = hex.encode(AppCrypto.sha256Digest(_sharedKey!));
    _receiverStateController.logStatus(TransferStateEnum.sharedKeyDigest);
    _receiverStateController.logStatus(TransferStateEnum.waitingFile);
    setState(() {});
  }

  @override
  Future<void> onIdentifierReceived(String identifier) async {
    _identifier = identifier;
    _receiverStateController.logStatus(TransferStateEnum.identifierGenerated);
    setState(() {});
  }

  @override
  Future<void> onFileReceived(
      String fileId, String fileName, String hmac) async {
    _receiverStateController.logStatus(TransferStateEnum.fileIdReceived);
    final path = File((await getApplicationCacheDirectory()).path);
    _receiverStateController.logStatus(TransferStateEnum.downloadingFile);

    _connectionClient.downloadFile(fileId, fileName, path.path,
        onSuccess: (file, fileName) async {
      _receiverStateController.logStatus(TransferStateEnum.checkingHmac);
      final fileBytes = file.readAsBytesSync();
      final hmacLocal = hex
          .encode(await AppCrypto.generateHMACIsolate(_sharedKey!, fileBytes));
      if (hmacLocal == hmac) {
        _receiverStateController.logStatus(TransferStateEnum.hmacSuccess);
        logMessage('HMAC check success');
      } else {
        logMessage('HMAC check failed: local $hmacLocal  remote $hmac');
        _receiverStateController.logStatus(TransferStateEnum.hmacError);
        _clear();
        return;
      }
      _receiverStateController.logStatus(TransferStateEnum.savingEncryptedFile);

      if (mounted) {
        final derivedKey = context.appTempData.getPinDerivedKey();

        final encryptedSecretKey =
            await AppCrypto.encryptAESInIsolate(_sharedKey!, derivedKey!);

        HiveManager.saveFile(
                fileId,
                file.path,
                hmac,
                base64Encode(encryptedSecretKey),
                context.appTempData.getPinDerivedKeySalt()!)
            .then((value) {
          TransmissionHistoryScreen(
            selectedFileIds: {fileId},
          ).showAsModalBottomSheet(
            context,
          );
        });
      }
      _clear();
      await _connectionClient.disconnect();
    }, onError: () {
      _receiverStateController.logStatus(TransferStateEnum.fileDeleteError);
      _clear();
    });
  }

  _clear() {
    setState(() {
      _sharedKeyDigest = null;
      _receiverStateController.logStatus(TransferStateEnum.initial);
      _privateKey = null;
      _identifier = null;
    });
  }
}
