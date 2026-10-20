import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

/// AES-256-GCM payload encryption. This is a starter helper, not Signal Protocol.
class CryptoService {
  static final _algorithm = AesGcm.with256bits();
  static final _random = Random.secure();

  static Future<Map<String, String>> encryptText({
    required String plaintext,
    required String sharedSecret,
    required String conversationId,
  }) async {
    final box = await _encrypt(utf8.encode(plaintext), sharedSecret, conversationId);
    return _encodeBox(box);
  }

  static Future<String> decryptText({
    required Map<String, dynamic> payload,
    required String sharedSecret,
    required String conversationId,
  }) async => utf8.decode(await decryptBytes(
    ciphertext: base64Decode(payload['ciphertext'] as String),
    nonce: base64Decode(payload['nonce'] as String),
    mac: base64Decode(payload['mac'] as String),
    sharedSecret: sharedSecret,
    conversationId: conversationId,
  ));

  static Future<Map<String, String>> encryptBytes({
    required List<int> bytes,
    required String sharedSecret,
    required String conversationId,
  }) async => _encodeBox(await _encrypt(bytes, sharedSecret, conversationId));

  static Future<List<int>> decryptBytes({
    required List<int> ciphertext,
    required List<int> nonce,
    required List<int> mac,
    required String sharedSecret,
    required String conversationId,
  }) async {
    final key = await _deriveKey(sharedSecret, utf8.encode('SecureChat-v1:$conversationId'));
    return _algorithm.decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
      aad: utf8.encode(conversationId),
    );
  }

  static Future<SecretBox> _encrypt(List<int> clear, String secret, String conversationId) async {
    if (secret.trim().length < 16) {
      throw ArgumentError('Sohbet anahtarı en az 16 karakter olmalı.');
    }
    final key = await _deriveKey(secret, utf8.encode('SecureChat-v1:$conversationId'));
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    return _algorithm.encrypt(clear, secretKey: key, nonce: nonce, aad: utf8.encode(conversationId));
  }

  static Map<String, String> _encodeBox(SecretBox box) => {
    'ciphertext': base64Encode(box.cipherText),
    'nonce': base64Encode(box.nonce),
    'mac': base64Encode(box.mac.bytes),
    'version': '1',
  };

  static Future<SecretKey> _deriveKey(String secret, List<int> salt) async {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 600000, bits: 256);
    return kdf.deriveKey(secretKey: SecretKey(utf8.encode(secret)), nonce: salt);
  }
}
