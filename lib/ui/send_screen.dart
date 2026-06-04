import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:safe_file_sender/models/state_controller.dart';
import 'package:safe_file_sender/ui/send/bloc/send_bloc.dart';
import 'package:safe_file_sender/ui/theme.dart';
import 'package:safe_file_sender/ui/widgets/close_screen_button.dart';
import 'package:safe_file_sender/ui/widgets/encrypted_key_matrix.dart';
import 'package:safe_file_sender/ui/widgets/snap_effect.dart';
import 'package:safe_file_sender/ui/widgets/status_logger.dart';
import 'package:safe_file_sender/utils/context_utils.dart';
import 'package:safe_file_sender/utils/string_utils.dart';

class SendScreen extends StatelessWidget {
  final SharedMediaFile? sharedFile;

  const SendScreen({super.key, required this.sharedFile});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SendBloc>(
      create: (_) {
        final bloc = SendBloc();
        final shared = sharedFile;
        if (shared != null) {
          bloc.add(SelectFile(File(shared.path)));
        }
        return bloc;
      },
      child: const _SendView(),
    );
  }
}

class _SendView extends StatefulWidget {
  const _SendView();

  @override
  State<_SendView> createState() => _SendViewState();
}

class _SendViewState extends State<_SendView> {
  final GlobalKey<SnappableState> _key = GlobalKey();
  final TextEditingController _textEditingController = TextEditingController();

  @override
  void dispose() {
    _textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SendBloc, SendState>(
      listenWhen: (previous, current) =>
          previous.transferState != current.transferState,
      listener: (context, state) {
        if (state.transferState == TransferStateEnum.fileSent) {
          _key.currentState?.snap();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        bottomNavigationBar: const CloseScreenButton(),
        backgroundColor: Colors.black,
        body: Container(
          margin: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: BlocBuilder<SendBloc, SendState>(
              builder: (context, state) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const Padding(padding: EdgeInsets.all(24)),
                    TextField(
                      style: AppTheme.textTheme.titleMedium,
                      controller: _textEditingController,
                      decoration: InputDecoration(
                        hintStyle: AppTheme.textTheme.titleMedium
                            ?.copyWith(color: Colors.white54),
                        hintText: context.localization.inputSessionId,
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Colors.white60)),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const Padding(padding: EdgeInsets.all(12)),
                    ElevatedButton(
                      onPressed: () {
                        if (_textEditingController.text.trim().isNotEmpty &&
                            state.selectedFile != null &&
                            state.canSend) {
                          context
                              .read<SendBloc>()
                              .add(SendFile(_textEditingController.text));
                        }
                      },
                      child: (!state.canSend)
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              context.localization.send,
                              style: AppTheme.textTheme.titleMedium,
                            ),
                    ),
                    const Padding(padding: EdgeInsets.all(16)),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        if (!state.canSend) return;
                        final files =
                            (await FilePicker.platform.pickFiles())?.files ?? [];
                        if (files.isEmpty) return;
                        if (!context.mounted) return;
                        context
                            .read<SendBloc>()
                            .add(SelectFile(File(files.first.path!)));
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Snappable(
                          key: _key,
                          onSnapped: () {
                            _textEditingController.clear();
                            context.read<SendBloc>().add(ClearSend());
                            _key.currentState?.reset();
                          },
                          child: Container(
                            height: 42,
                            alignment: Alignment.center,
                            child: state.selectedFile == null
                                ? Text(
                                    context.localization.selectFile,
                                    style: AppTheme.textTheme.titleMedium,
                                  )
                                : ListView.builder(
                                    itemExtent: 34,
                                    itemCount:
                                        (state.fileBytes.length * .01).toInt(),
                                    scrollDirection: Axis.horizontal,
                                    itemBuilder: (e, index) {
                                      final bit = state.fileBytes[index]
                                          .toRadixString(2)
                                          .padLeft(8, '0');
                                      return Text(
                                        bit,
                                        style: AppTheme.textTheme.titleMedium,
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const Padding(padding: EdgeInsets.all(16)),
                    StatusLogger(history: state.history),
                    const Padding(padding: EdgeInsets.all(6)),
                    if (state.sharedKeyDigest != null)
                      EncryptionKeyWidget(
                        keyMatrix: StringUtils.splitByLength(
                            state.sharedKeyDigest!, 2),
                      )
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
