import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

/// AES-256-GCM payload encryption. The secret must be shared out-of-band and
/// never uploaded. This utility is a foundation, NOT a Signal Protocol
/// implementation: no ratchet, forward secrecy, or identity verification yet.
class CryptoService {
  static final _algorithm = AesGcm.with256bits();
  static final _random = Random.secure();

  static Future<Map<String, String>> encryptText({
    required String plaintext,
    required String sharedSecret,
    required String conversationId,
  }) async {
    if (sharedSecret.trim().length < 16) {
      throw ArgumentError('Sohbet anahtarı en az 16 karakter olmalı.');
    }
    final salt = utf8.encode('SecureChat-v1:$conversationId');
    final key = await _deriveKey(sharedSecret, salt);
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final box = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(conversationId),
    );
    return {
      'ciphertext': base64Encode(box.cipherText),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'version': '1',
    };
  }

  static Future<String> decryptText({
    required Map<String, dynamic> payload,
    required String sharedSecret,
    required String conversationId,
  }) async {
    final key = await _deriveKey(
      sharedSecret,
      utf8.encode('SecureChat-v1:$conversationId'),
    );
    final box = SecretBox(
      base64Decode(payload['ciphertext'] as String),
      nonce: base64Decode(payload['nonce'] as String),
      mac: Mac(base64Decode(payload['mac'] as String)),
    );
    final clear = await _algorithm.decrypt(
      box,
      secretKey: key,
      aad: utf8.encode(conversationId),
    );
    return utf8.decode(clear);
  }

  static Future<SecretKey> _deriveKey(String secret, List<int> salt) async {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 600000,
      bits: 256,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(secret)),
      nonce: salt,
    );
  }
}
