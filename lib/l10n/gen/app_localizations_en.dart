// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get send => 'Send file';

  @override
  String get receive => 'Receive file';

  @override
  String get keyDerivationInfo => 'This text were derived from the encryption key';

  @override
  String get sourceCode => 'Source code';

  @override
  String get tapToCopy => 'Tap to copy';

  @override
  String get createSession => 'Create session';

  @override
  String get selectFile => 'Select file';

  @override
  String get inputSessionId => 'Input session ID';

  @override
  String get appName => 'Tuynuk';

  @override
  String get language => 'Language';

  @override
  String get done => 'Done';

  @override
  String get save => 'Save';

  @override
  String get setupPin => 'Setup PIN';

  @override
  String get inputPin => 'Input PIN';

  @override
  String get continueAuth => 'Continue';

  @override
  String get invalidPin => 'Invalid PIN';
}
