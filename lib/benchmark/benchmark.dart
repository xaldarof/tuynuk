import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

///Test file [encoding,decoding] in base64 format
void main() async {
  final start = DateTime.now().millisecondsSinceEpoch;
  final file = File(
      "C:/Users/User/AndroidStudioProjects/cancellable_requester/safe_file_sender/test_files/input.exe");
  final output = File(
      "C:/Users/User/AndroidStudioProjects/cancellable_requester/safe_file_sender/test_files/output.exe");
  final base64 = await Isolate.run(
      () => Future.value(base64Encode(file.readAsBytesSync())));
  await output.writeAsBytes(base64Decode(base64));
  final end = DateTime.now().millisecondsSinceEpoch;
  print("Benchmark : ${(end - start)} ms");
}
