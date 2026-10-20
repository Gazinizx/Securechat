import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_bootstrap.dart';

class ProfileService {
  static final _db = FirebaseBootstrap.db;

  static Future<void> saveUsername(String username) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Önce giriş yapmalısın.');
    final normalized = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(normalized)) {
      throw ArgumentError('Kullanıcı adı 3-20 karakter; harf, sayı ve _ içerebilir.');
    }
    final ref = _db.collection('usernames').doc(normalized);
    await _db.runTransaction((tx) async {
      final existing = await tx.get(ref);
      if (existing.exists && existing.data()?['uid'] != user.uid) {
        throw StateError('Bu kullanıcı adı alınmış.');
      }
      tx.set(ref, {'uid': user.uid, 'username': normalized});
      tx.set(_db.collection('users').doc(user.uid), {
        'username': normalized,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static Future<Map<String, dynamic>?> findByUsername(String username) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final doc = await _db.collection('usernames').doc(normalized).get();
    if (!doc.exists) return null;
    return doc.data();
  }
}
