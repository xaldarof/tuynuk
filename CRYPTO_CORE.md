# Tuynuk — Ядро криптографии

Документ описывает основную криптографическую логику для end-to-end шифрования при передаче файлов.
Все примитивы находятся в `lib/crypto/crypto_core.dart` (`AppCrypto`).

---

## 1. Генерация пары EC-ключей

**Кривая:** secp256r1 (P-256)  
**ГСЧ:** Fortuna CSPRNG, засеянный 32 байтами из `Random.secure()`

```dart
// lib/crypto/crypto_core.dart:189
static AsymmetricKeyPair<ECPublicKey, ECPrivateKey> generateECKeyPair() {
  final keyGen = ECKeyGenerator()
    ..init(ParametersWithRandom(
        ECKeyGeneratorParameters(ECCurve_secp256r1()), _secureRandom()));
  final pair = keyGen.generateKeyPair();
  ...
}

static SecureRandom _secureRandom() {
  final secureRandom = FortunaRandom();
  final seeds = <int>[];
  for (int i = 0; i < 32; i++) seeds.add(Random.secure().nextInt(256));
  secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
  return secureRandom;
}
```

Новая пара ключей генерируется при каждой сессии отправки/получения — никогда не переиспользуется.

---

## 2. Получение общего секрета через ECDH

Оба участника генерируют собственную пару EC-ключей, обмениваются публичными ключами через SignalR, после чего каждый независимо вычисляет одинаковый общий секрет.

```dart
// lib/crypto/crypto_core.dart:212
static Uint8List deriveSharedSecret(ECPrivateKey privateKey, ECPublicKey serverPublicKey) {
  final ecdh = ECDHBasicAgreement();
  ecdh.init(privateKey);
  final sharedSecret = ecdh.calculateAgreement(serverPublicKey);
  // кодируется как 64-символьная hex-строка, затем в байты
  return Uint8List.fromList(
      sharedSecret.toRadixString(16).padLeft(64, '0').codeUnits);
}
```

Результат используется напрямую как ключ AES-256.

---

## 3. Кодирование / декодирование EC-публичного ключа

Публичные ключи сериализуются как несжатые точки (`0x04 || X || Y`) и кодируются в base64 для передачи.

```dart
// lib/crypto/crypto_core.dart:222
static String encodeECPublicKey(ECPublicKey publicKey) {
  // добавляет префикс 0x04, дополняет X и Y до 32 байт каждый
  final byteData = BytesBuilder()
    ..addByte(0x04)
    ..add(xPadded)
    ..add(yPadded);
  return base64Encode(byteData.toBytes());
}

static ECPublicKey decodeECPublicKey(String base64String) {
  final bytes = base64Decode(base64String);
  if (bytes[0] != 0x04) throw ArgumentError('Invalid point encoding');
  // восстанавливает ECPublicKey на кривой ECCurve_secp256r1
}
```

---

## 4. Шифрование файлов AES-256-CBC

**Режим:** CBC + PKCS7 padding  
**Ключ:** 32 байта (первые 32 байта общего секрета ECDH)  
**IV:** 16 случайных байт, предшествующих шифртексту

```dart
// lib/crypto/crypto_core.dart:62
static Uint8List encryptAES(Uint8List plaintext, Uint8List key) {
  final iv = _generateRandomBytes(16);          // крипто-случайный IV
  final cipher = PaddedBlockCipherImpl(
    PKCS7Padding(), CBCBlockCipher(AESEngine()),
  )..init(true, PaddedBlockCipherParameters(
      ParametersWithIV<KeyParameter>(KeyParameter(key.sublist(0, 32)), iv), null));
  final encrypted = cipher.process(plaintext);
  return Uint8List.fromList(iv + encrypted);    // формат: [IV | шифртекст]
}

static Uint8List decryptAES(Uint8List ciphertext, Uint8List key) {
  final iv = ciphertext.sublist(0, 16);
  final encrypted = ciphertext.sublist(16);
  // init false (расшифровка), та же структура ключа/IV
}
```

Тяжёлые операции выполняются в Dart `Isolate` (`encryptAESInIsolate` / `decryptAESInIsolate`), чтобы не блокировать UI-поток.

---

## 5. Тег целостности HMAC-SHA256

После шифрования отправитель вычисляет HMAC над шифртекстом, используя тот же общий ключ. Получатель проверяет его перед расшифровкой, отклоняя подделанные файлы.

```dart
// lib/crypto/crypto_core.dart:285
static Uint8List generateHMAC(Uint8List key, Uint8List message) {
  var hmacSha256 = HMac(SHA256Digest(), 64);
  hmacSha256.init(KeyParameter(key));
  return hmacSha256.process(message);
}
```

HMAC кодируется в hex и передаётся как параметр запроса (`?HMAC=...`) при загрузке. На стороне получателя:

```dart
// lib/ui/receive_screen.dart:199
final hmacLocal = hex.encode(
    await AppCrypto.generateHMACIsolate(_sharedKey!, fileBytes));
if (hmacLocal != hmac) { /* отклонить */ }
```

---

## 6. Вывод ключа PBKDF2 (PIN → ключ файла)

Используется для получения ключа локального хранилища из PIN-кода пользователя — для шифрования общего ECDH-ключа в состоянии покоя.

```dart
// lib/crypto/crypto_core.dart:24
static Uint8List deriveKey(String input) {
  final mac = HMac(SHA256Digest(), 64);
  final pbkdf2 = PBKDF2KeyDerivator(mac)
    ..init(Pbkdf2Parameters(generateSaltPRNG(), 100000, 32));
  return pbkdf2.process(utf8.encode(input));
}
```

- **100 000 итераций** HMAC-SHA256
- **32-байтовый результат** используется как ключ AES
- Соль генерируется через `AES/CTR/PRNG` (`generateSaltPRNG`)

---

## 7. Аутентификация по PIN (хэш SHA-256)

Сам PIN хранится как hex-кодированный SHA-256 хэш (без соли) в `EncryptedSharedPreferences`.

```dart
// lib/ui/pin/pin_screen.dart:85
hex.encode(AppCrypto.sha256Digest(utf8.encode(pin)))
```

Отдельно используется SHA-256 с солью в качестве ключа шифрования файлов для текущей сессии:

```dart
// lib/ui/pin/pin_screen.dart:117
final salt = AppCrypto.generateSalt();                // 16 случайных байт
final fileEncryptedKey = AppCrypto.sha256Digest(utf8.encode(pin), salt: salt);
```

---

## 8. Зашифрованная локальная база данных (Hive)

Бокс `downloads` в Hive шифруется AES. Ключ — SHA-256 дайджест PIN (байты инвертируются перед передачей в `HiveAesCipher`):

```dart
// lib/cache/hive/hive_manager.dart:18
await Hive.openBox<DownloadFile>(downloads,
    encryptionCipher: HiveAesCipher(key.reversed.toList()));
```

Каждая запись хранит общий ECDH-ключ, зашифрованный с помощью ключа, производного от PIN:

```dart
// lib/ui/receive_screen.dart:215
final encryptedSecretKey = await AppCrypto.encryptAESInIsolate(_sharedKey!, derivedKey!);
HiveManager.saveFile(fileId, ..., base64Encode(encryptedSecretKey), salt);
```

---

## Общая схема end-to-end

```
Получатель                              Отправитель
──────────                              ───────────
generateECKeyPair()                     generateECKeyPair()
createSession(pubKey) ──pubKey──▶       joinSession(id, pubKey)
                      ◀──pubKey──       OnSessionReady
deriveSharedSecret()                    deriveSharedSecret()
        │                                       │
        └──── одинаковый общий секрет ──────────┘
                                        encryptAES(файл, sharedKey)
                                        generateHMAC(sharedKey, шифртекст)
                                        upload(шифртекст, hmac)
onFileReceived(fileId, hmac) ◀──────────
generateHMAC(sharedKey, шифртекст) → проверка
decryptAES(шифртекст, sharedKey)
encryptAESInIsolate(sharedKey, pinDerivedKey) → сохранить в Hive
```
