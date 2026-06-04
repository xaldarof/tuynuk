import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:safe_file_sender/ui/dialogs/dialog_utils.dart';
import 'package:safe_file_sender/ui/history/transmission_history_screen.dart';
import 'package:safe_file_sender/ui/receive/bloc/receive_bloc.dart';
import 'package:safe_file_sender/ui/theme.dart';
import 'package:safe_file_sender/ui/widgets/close_screen_button.dart';
import 'package:safe_file_sender/ui/widgets/common_inherited_widget.dart';
import 'package:safe_file_sender/ui/widgets/encrypted_key_matrix.dart';
import 'package:safe_file_sender/ui/widgets/status_logger.dart';
import 'package:safe_file_sender/utils/context_utils.dart';
import 'package:safe_file_sender/utils/string_utils.dart';

class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appTempData = context.appTempData;
    return BlocProvider<ReceiveBloc>(
      create: (_) => ReceiveBloc(appTempData),
      child: const _ReceiveView(),
    );
  }
}

class _ReceiveView extends StatelessWidget {
  const _ReceiveView();

  @override
  Widget build(BuildContext context) {
    return BlocListener<ReceiveBloc, ReceiveState>(
      listenWhen: (previous, current) =>
          previous.receivedFileId != current.receivedFileId &&
          current.receivedFileId != null,
      listener: (context, state) {
        TransmissionHistoryScreen(
          selectedFileIds: {state.receivedFileId!},
        ).showAsModalBottomSheet(context);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        bottomNavigationBar: const CloseScreenButton(),
        backgroundColor: Colors.black,
        body: Container(
          margin: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: BlocBuilder<ReceiveBloc, ReceiveState>(
              builder: (context, state) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const Padding(padding: EdgeInsets.all(12)),
                    ElevatedButton(
                      onPressed: () {
                        if (state.canReceive) {
                          context.read<ReceiveBloc>().add(CreateSession());
                        }
                      },
                      child: (!state.canReceive)
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
                    const Padding(padding: EdgeInsets.all(16)),
                    StatusLogger(history: state.history),
                    const Padding(padding: EdgeInsets.all(24)),
                    if (state.identifier != null)
                      InkWell(
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: state.identifier!));
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                state.identifier!,
                                style: AppTheme.textTheme.titleMedium
                                    ?.copyWith(fontSize: 20),
                              ),
                              Text(
                                context.localization.tapToCopy,
                                style: AppTheme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white54, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
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
