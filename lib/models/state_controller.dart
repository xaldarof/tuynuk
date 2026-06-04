enum TransferStateEnum {
  loading('Loading'),
  generatingKey('Generating key pair'),
  sharedKeyDeriving('Shared key calculation'),
  sharedKeyDerived('Shared key derived'),
  failed('Failed'),
  sendingFile('Sending encrypted file'),
  initial('Initial'),
  connection('Connecting to the server'),
  connectionError('Connection error'),
  connected('Connected'),
  joining('Joining to the session'),
  encryptionFile('Encrypting file'),
  writingFile('Writing file'),
  writingEncryptedFile('Writing encrypted file'),
  generatingHmac('Generating HMAC'),
  waitingFile('Waiting file'),
  identifierGenerated('Identifier generated'),
  creatingSession('Creating session'),
  fileIdReceived('File id received'),
  decryptionFile('Decryption file'),
  downloadingFile('Downloading file'),
  checkingHmac('Checking data integrity'),
  hmacError('File corrupted'),
  hmacSuccess('File NOT corrupted'),
  fileDeleteError('File deletion error'),
  sharedKeyDigest('Shared key digest'),
  savingEncryptedFile('Saving encrypted file'),
  fileSent('File sent'),
  clearing('Clearing');

  const TransferStateEnum(this.value);

  final String value;

  /// Terminal/idle states from which a new transfer can be started.
  bool get isIdle =>
      this == TransferStateEnum.initial ||
      this == TransferStateEnum.connectionError;
}
