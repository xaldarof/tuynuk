part of 'send_bloc.dart';

@immutable
class SendState {
  final TransferStateEnum transferState;
  final List<TransferStateEnum> history;
  final File? selectedFile;
  final List<int> fileBytes;
  final String? sharedKeyDigest;

  const SendState({
    this.transferState = TransferStateEnum.initial,
    this.history = const [],
    this.selectedFile,
    this.fileBytes = const [],
    this.sharedKeyDigest,
  });

  bool get canSend => transferState.isIdle;

  SendState copyWith({
    TransferStateEnum? transferState,
    List<TransferStateEnum>? history,
    File? selectedFile,
    List<int>? fileBytes,
    String? sharedKeyDigest,
  }) {
    return SendState(
      transferState: transferState ?? this.transferState,
      history: history ?? this.history,
      selectedFile: selectedFile ?? this.selectedFile,
      fileBytes: fileBytes ?? this.fileBytes,
      sharedKeyDigest: sharedKeyDigest ?? this.sharedKeyDigest,
    );
  }
}
