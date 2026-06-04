part of 'receive_bloc.dart';

@immutable
sealed class ReceiveEvent {}

/// User tapped "create session" to start receiving.
class CreateSession extends ReceiveEvent {}

/// Reset the screen back to its initial state.
class ClearReceive extends ReceiveEvent {}

/// The peer's public key arrived over the connection.
class PublicKeyReceived extends ReceiveEvent {
  final String publicKey;

  PublicKeyReceived(this.publicKey);
}

/// The server generated a session identifier to share with the sender.
class IdentifierReceived extends ReceiveEvent {
  final String identifier;

  IdentifierReceived(this.identifier);
}

/// The sender uploaded a file; carries the metadata needed to fetch it.
class FileReceived extends ReceiveEvent {
  final String fileId;
  final String fileName;
  final String hmac;

  FileReceived(this.fileId, this.fileName, this.hmac);
}
