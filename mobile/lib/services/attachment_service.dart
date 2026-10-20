import 'dart:typed_data';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'crypto_service.dart';
import 'firebase_bootstrap.dart';

class AttachmentService {
  static const maxBytes = 20 * 1024 * 1024;

  static Future<void> pickAndSend({
    required String conversationId,
    required String senderUid,
    required String sharedSecret,
    required bool ghost,
  }) async {
    final picker = ImagePicker();
    final file = await picker.pickMedia();
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw ArgumentError('Dosya boş olamaz ve 20 MB sınırını aşamaz.');
    }

    final lowerName = file.name.toLowerCase();
    final kind = lowerName.endsWith('.mp4') ||
            lowerName.endsWith('.mov') ||
            lowerName.endsWith('.m4v')
        ? 'video'
        : 'photo';

    final encrypted = await CryptoService.encryptBytes(
      bytes: bytes,
      sharedSecret: sharedSecret,
      conversationId: conversationId,
    );
    final messages = FirebaseBootstrap.db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages');
    final doc = messages.doc();
    final path = 'conversations/$conversationId/${doc.id}.bin';

    await FirebaseBootstrap.storage.ref(path).putData(
      Uint8List.fromList(base64Decode(encrypted['ciphertext']!)),
      SettableMetadata(contentType: 'application/octet-stream'),
    );

    // Original filename and MIME type are deliberately not stored in plaintext.
    final encryptedName = await CryptoService.encryptText(
      plaintext: file.name,
      sharedSecret: sharedSecret,
      conversationId: conversationId,
    );
    await doc.set({
      'kind': kind,
      'storagePath': path,
      'nonce': encrypted['nonce'],
      'mac': encrypted['mac'],
      'nameCiphertext': encryptedName['ciphertext'],
      'nameNonce': encryptedName['nonce'],
      'nameMac': encryptedName['mac'],
      'senderUid': senderUid,
      'createdAt': FieldValue.serverTimestamp(),
      'ghost': ghost,
      'readBy': [senderUid],
      'version': '1',
    });
  }

  static List<int> _decodeBase64(String value) {
    // Kept local to avoid exposing the clear file or public download URL.
    return base64Decode(value);
  }

  static Future<Uint8List> decryptAttachment({
    required Map<String, dynamic> message,
    required String sharedSecret,
    required String conversationId,
  }) async {
    final path = message['storagePath'] as String;
    final encryptedBytes = await FirebaseBootstrap.storage.ref(path).getData(maxBytes);
    if (encryptedBytes == null) throw StateError('Şifreli dosya indirilemedi.');
    final clear = await CryptoService.decryptBytes(
      ciphertext: encryptedBytes,
      nonce: _decodeBase64(message['nonce'] as String),
      mac: _decodeBase64(message['mac'] as String),
      sharedSecret: sharedSecret,
      conversationId: conversationId,
    );
    return Uint8List.fromList(clear);
  }

  static Future<String> decryptFilename({
    required Map<String, dynamic> message,
    required String sharedSecret,
    required String conversationId,
  }) => CryptoService.decryptText(
    payload: {
      'ciphertext': message['nameCiphertext'],
      'nonce': message['nameNonce'],
      'mac': message['nameMac'],
    },
    sharedSecret: sharedSecret,
    conversationId: conversationId,
  );
}
