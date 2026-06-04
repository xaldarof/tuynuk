part of 'receive_bloc.dart';

@immutable
class ReceiveState {
  final TransferStateEnum transferState;
  final List<TransferStateEnum> history;
  final String? identifier;
  final String? sharedKeyDigest;

  /// Set once for a successfully received & saved file, so the UI can present
  /// the transmission-history sheet. Cleared on the following reset.
  final String? receivedFileId;

  const ReceiveState({
    this.transferState = TransferStateEnum.initial,
    this.history = const [],
    this.identifier,
    this.sharedKeyDigest,
    this.receivedFileId,
  });

  bool get canReceive => transferState.isIdle;

  ReceiveState copyWith({
    TransferStateEnum? transferState,
    List<TransferStateEnum>? history,
    String? identifier,
    String? sharedKeyDigest,
    String? receivedFileId,
  }) {
    return ReceiveState(
      transferState: transferState ?? this.transferState,
      history: history ?? this.history,
      identifier: identifier ?? this.identifier,
      sharedKeyDigest: sharedKeyDigest ?? this.sharedKeyDigest,
      receivedFileId: receivedFileId ?? this.receivedFileId,
    );
  }
}
