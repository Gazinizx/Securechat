import 'package:flutter_test/flutter_test.dart';
import 'package:securechat/services/crypto_service.dart';

void main() {
  const secret = 'a-long-demo-secret-phrase-2026';
  const conversation = 'test-conversation-123';

  test('AES-GCM text payload round-trips', () async {
    const message = 'Merhaba SecureChat';
    final encrypted = await CryptoService.encryptText(
      plaintext: message,
      sharedSecret: secret,
      conversationId: conversation,
    );
    expect(encrypted.containsKey('ciphertext'), isTrue);
    expect(encrypted.containsKey('nonce'), isTrue);
    expect(encrypted.containsKey('mac'), isTrue);
    final decrypted = await CryptoService.decryptText(
      payload: encrypted,
      sharedSecret: secret,
      conversationId: conversation,
    );
    expect(decrypted, message);
  });

  test('AES-GCM rejects the wrong secret', () async {
    final encrypted = await CryptoService.encryptText(
      plaintext: 'secret',
      sharedSecret: secret,
      conversationId: conversation,
    );
    await expectLater(
      CryptoService.decryptText(
        payload: encrypted,
        sharedSecret: 'a-different-demo-secret',
        conversationId: conversation,
      ),
      throwsA(anything),
    );
  });
}
