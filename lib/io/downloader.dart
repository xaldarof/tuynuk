import 'package:background_downloader/background_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:safe_file_sender/dev/logger.dart';
import 'package:safe_file_sender/io/connection_client.dart';

class Downloader {
  const Downloader._();

  static final _downloader = FileDownloader();

  static Future<void> uploadFile(String filePath, String sessionId, String hmac,
      {Function(int percentage)? onUpdate, Function()? onError}) async {
    try {
      String fileName = filePath.split('/').last;
      logMessage('Uploading $fileName');
      final task = UploadTask(
        taskId: DateTime.now().millisecondsSinceEpoch.toString(),
        url: '${ConnectionClient.baseUrl}api/Files/UploadFile',
        filename: fileName,
        updates: Updates.statusAndProgress,
        baseDirectory: BaseDirectory.temporary,
        fileField: 'formFile',
        urlQueryParameters: {
          'sessionIdentifier': sessionId,
          'HMAC': hmac,
        },
      );
      var prev = 0;
      final response = await _downloader.upload(
        task,
        onStatus: (status) async {
          logMessage('Upload status : $status');
          if (status == TaskStatus.failed) {
            return;
          }
        },
        onProgress: (progress) {
          final percent = (progress * 100).toInt();
          logMessage('Upload progress : $percent');
          if ((prev - percent).abs() > 20 || percent == 100) {
            onUpdate?.call(percent.abs());
            prev = percent;
          }
        },
      );
      // _downloader.cancelTaskWithId(task.taskId);
      // _downloader.destroy();
      logMessage('Response body upload : ${response.responseBody}');
    } catch (e) {
      onError?.call();
      logMessage('Upload error : ${e.toString()}');
    }
  }

  static Future<void> download(String fileId, String fileName,
      {Function(int percentage)? onReceive,
      Function()? onError,
      Function(String path)? onSuccess}) async {
    try {
      final task = DownloadTask(
        url: '${ConnectionClient.baseUrl}api/Files/GetFile?fileId=$fileId',
        updates: Updates.statusAndProgress,
        filename: fileName,
        allowPause: true,
        directory: 'downloads',
      );
      var prev = 0;
      _downloader.enqueue(
        task,
      );
      _downloader.registerCallbacks(
          taskProgressCallback: (TaskProgressUpdate update) async {
        final percent = (update.progress * 100).toInt();
        logMessage(update.task.headers);
        if ((prev - percent).abs() > 10 || percent == 100) {
          onReceive?.call(percent.abs());
          prev = percent;
          if (percent == 100) {
            final path =
                '${(await getApplicationDocumentsDirectory()).path}/downloads/$fileName';
            onSuccess?.call(path);
          }
        }
      });
    } catch (e) {
      logMessage('Download error : ${e.toString()}');
      onError?.call();
    }
  }

  void taskProgressCallback(TaskProgressUpdate update) {
    // print(
    //     'taskProgressCallback for ${update.task} with progress ${update.progress} '
    //         'and expected file size ${update.expectedFileSize}');
  }

  static void cancelAll() async {
    _downloader.cancelTaskWithId('uploading_id');
  }
}
