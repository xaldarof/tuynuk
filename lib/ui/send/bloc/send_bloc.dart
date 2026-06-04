import 'dart:io';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:convert/convert.dart';
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:safe_file_sender/crypto/crypto_core.dart';
import 'package:safe_file_sender/dev/logger.dart';
import 'package:safe_file_sender/io/connection_client.dart';
import 'package:safe_file_sender/models/event_listeners.dart';
import 'package:safe_file_sender/models/state_controller.dart';
import 'package:safe_file_sender/utils/file_utils.dart';
import 'package:safe_file_sender/utils/validators.dart';

part 'send_event.dart';

part 'send_state.dart';

class SendBloc extends Bloc<SendEvent, SendState> implements SenderListeners {
  late final ConnectionClient _connectionClient;
  ECPrivateKey? _privateKey;
  ECPublicKey? _publicKey;
  Uint8List? _sharedKey;
  String? _sessionId;

  SendBloc() : super(const SendState()) {
    _connectionClient = ConnectionClient(this);
    on<SelectFile>(_onSelectFile);
    on<SendFile>(_onSendFile);
    on<ClearSend>(_onClear);
    on<PublicKeyReceived>(_onPublicKeyReceived);
  }

  Future<void> _onSelectFile(SelectFile event, Emitter<SendState> emit) async {
    if (!state.transferState.isIdle) return;
    if (!Validators.canHandleFile(event.file)) return;
    emit(state.copyWith(
      selectedFile: event.file,
      fileBytes: event.file.readAsBytesSync().toList(),
    ));
  }

  Future<void> _onSendFile(SendFile event, Emitter<SendState> emit) async {
    final sessionId = event.sessionId.trim().toUpperCase();
    if (sessionId.isEmpty ||
        state.selectedFile == null ||
        !state.transferState.isIdle) {
      return;
    }
    _sessionId = sessionId;
    emit(_log(state.copyWith(history: const []), TransferStateEnum.loading));

    await _connectionClient.connect();
    emit(_log(state, TransferStateEnum.connection));

    if (!_connectionClient.isConnected) {
      emit(_log(state, TransferStateEnum.connectionError));
      return;
    }
    emit(_log(state, TransferStateEnum.connected));
    emit(_log(state, TransferStateEnum.generatingKey));

    final pair = AppCrypto.generateECKeyPair();
    _privateKey = pair.privateKey;
    _publicKey = pair.publicKey;

    emit(_log(state, TransferStateEnum.joining));
    _connectionClient.joinSession(
        sessionId, AppCrypto.encodeECPublicKey(_publicKey!));
  }

  Future<void> _onPublicKeyReceived(
      PublicKeyReceived event, Emitter<SendState> emit) async {
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

    final hmac = await _encryptAndGenerateHmac(emit);
    await _writeAndSendFile(hmac, emit);
  }

  Future<String> _encryptAndGenerateHmac(Emitter<SendState> emit) async {
    emit(_log(state, TransferStateEnum.encryptionFile));
    final encrypted = await AppCrypto.encryptAESInIsolate(
        state.selectedFile!.readAsBytesSync(), _sharedKey!);

    emit(_log(state, TransferStateEnum.generatingHmac));
    final hmac = hex.encode(await AppCrypto.generateHMACIsolate(
        _sharedKey!, encrypted));

    emit(state.copyWith(fileBytes: encrypted));
    return hmac;
  }

  Future<void> _writeAndSendFile(String hmac, Emitter<SendState> emit) async {
    emit(_log(state, TransferStateEnum.writingEncryptedFile));

    final encFile = File(
        '${(await getApplicationCacheDirectory()).path}/enc_${FileUtils.fileName(state.selectedFile!.path)}');
    encFile.writeAsBytesSync(state.fileBytes);

    final fileName = FileUtils.fileName(state.selectedFile!.path);
    state.selectedFile?.safeDelete();

    emit(_log(state, TransferStateEnum.sendingFile));
    final sent =
        await _connectionClient.sendFile(encFile.path, fileName, _sessionId!, hmac);

    encFile.safeDelete();
    logMessage('Sent : $sent');

    emit(_log(
        state,
        sent
            ? TransferStateEnum.fileSent
            : TransferStateEnum.connectionError));
  }

  Future<void> _onClear(ClearSend event, Emitter<SendState> emit) async {
    state.selectedFile?.safeDelete(recursive: true);
    _resetSecrets();
    emit(const SendState());
  }

  void _resetSecrets() {
    _privateKey = null;
    _publicKey = null;
    _sharedKey = null;
    _sessionId = null;
  }

  /// Appends [status] to the running history and makes it the current state.
  SendState _log(SendState current, TransferStateEnum status) {
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
  Future<void> close() async {
    state.selectedFile?.safeDelete(recursive: true);
    await _connectionClient.disconnect();
    return super.close();
  }
}
