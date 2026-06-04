part of 'send_bloc.dart';

@immutable
sealed class SendEvent {}

/// User picked (or shared in) a file to send.
class SelectFile extends SendEvent {
  final File file;

  SelectFile(this.file);
}

/// User tapped send for the given session id.
class SendFile extends SendEvent {
  final String sessionId;

  SendFile(this.sessionId);
}

/// Reset the screen back to its initial state.
class ClearSend extends SendEvent {}

/// The peer's public key arrived over the connection.
class PublicKeyReceived extends SendEvent {
  final String publicKey;

  PublicKeyReceived(this.publicKey);
}
