// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get send => 'Отправить файл';

  @override
  String get receive => 'Получить файл';

  @override
  String get keyDerivationInfo => 'Этот текст был получен из ключа шифрования';

  @override
  String get sourceCode => 'Исходный код';

  @override
  String get tapToCopy => 'Нажмите, чтобы скопировать';

  @override
  String get createSession => 'Создать сессию';

  @override
  String get selectFile => 'Выбрать файл';

  @override
  String get inputSessionId => 'Введите ID сессии';

  @override
  String get appName => 'Tuynuk';

  @override
  String get language => 'Язык';

  @override
  String get done => 'Готово';

  @override
  String get save => 'Сохранить';

  @override
  String get setupPin => 'Установить ПИН';

  @override
  String get inputPin => 'Введите ПИН';

  @override
  String get continueAuth => 'Продолжить';

  @override
  String get invalidPin => 'Неверный ПИН';
}
