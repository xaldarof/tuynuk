import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:safe_file_sender/cache/hive/adapters/download_file_adapter.dart';
import 'package:safe_file_sender/cache/hive/hive_manager.dart';
import 'package:safe_file_sender/cache/preferences_cache_keys.dart';
import 'package:safe_file_sender/crypto/crypto_core.dart';
import 'package:safe_file_sender/dev/logger.dart';
import 'package:safe_file_sender/ui/dialogs/loading_dialog.dart';
import 'package:safe_file_sender/ui/widgets/close_screen_button.dart';
import 'package:safe_file_sender/ui/widgets/common_inherited_widget.dart';
import 'package:safe_file_sender/utils/file_utils.dart';
import 'package:share_plus/share_plus.dart';

class TransmissionHistoryScreen extends StatefulWidget {
  final Set<String> selectedFileIds;

  const TransmissionHistoryScreen({super.key, this.selectedFileIds = const {}});

  @override
  State<TransmissionHistoryScreen> createState() =>
      _TransmissionHistoryScreenState();
}

class _TransmissionHistoryScreenState extends State<TransmissionHistoryScreen> {
  List<DownloadFile> _files = [];

  @override
  void initState() {
    _loadFiles();
    super.initState();
  }

  _loadFiles() async {
    final directory = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/downloads');
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    _files = await HiveManager.getFiles();

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const CloseScreenButton(),
      body: Container(
        padding: const EdgeInsets.all(16),
        child: _files.isEmpty
            ? const Center(
                child: Icon(
                  CupertinoIcons.cube_box,
                  color: Colors.white12,
                  size: 100,
                ),
              )
            : ListView.builder(
                itemCount: _files.length,
                itemBuilder: (context, index) {
                  final downloadedFile = _files[index];
                  final fileName = FileUtils.fileName(downloadedFile.path);
                  return InkWell(
                    onTap: () async {
                      _handleTap(context, downloadedFile, fileName);
                    },
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () {
                            final isDeleted =
                                File(downloadedFile.path).safeDelete();
                            HiveManager.removeDownloadFile(
                                downloadedFile.fileId);
                            _files.remove(downloadedFile);
                            if (_files.isEmpty) {
                              Navigator.pop(context);
                            } else {
                              setState(() {});
                            }
                          },
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                          ),
                        ),
                        Flexible(
                          child: Container(
                            margin: const EdgeInsets.all(12),
                            child: Text(
                              fileName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontSize: 10, color: Colors.green),
                            ),
                          ),
                        ),
                        if (widget.selectedFileIds
                            .contains(downloadedFile.fileId))
                          const Badge(),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  @override
  void dispose() {
    FileUtils.clearDecryptedCache();
    super.dispose();
  }

  void _handleTap(BuildContext context, DownloadFile downloadedFile,
      String fileName) async {
    LoadingDialog.showLoadingDialog(context);

    if (context.mounted) {
      final decryptResult = await _decryptFile(downloadedFile, fileName);
      if (context.mounted) {
        LoadingDialog.hideLoadingDialog(context);
      }
      if (decryptResult != null) {
        Share.shareXFiles([XFile(decryptResult)]).then((value) async {
          FileUtils.clearDecryptedCache();
        });
      } else {
        LoadingDialog.hideLoadingDialog(context);
      }
    } else {
      logMessage('unmounted');
    }
  }

  Future<String?> _decryptFile(
      DownloadFile downloadedFile, String fileName) async {
    try {
      final decryptedFile = File(
          '${(await getApplicationDocumentsDirectory()).path}/downloads/temp/$fileName');
      await decryptedFile.create(recursive: true);

      final encryptedSecretKey = downloadedFile.secretKey;
      final decryptedSecretKey = await AppCrypto.decryptAESInIsolate(
          base64Decode(encryptedSecretKey),
          AppCrypto.sha256Digest(utf8.encode(context.appTempData.getPin()!),
              salt: base64Decode(downloadedFile.salt)));
      final decryptedBytes = await AppCrypto.decryptAESInIsolate(
          File(downloadedFile.path).readAsBytesSync(), decryptedSecretKey);
      decryptedFile.writeAsBytesSync(decryptedBytes);
      return decryptedFile.path;
    } catch (e) {
      logMessage(e.toString());
      return null;
    }
  }
}
