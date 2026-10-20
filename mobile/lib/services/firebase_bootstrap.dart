import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseBootstrap {
  static Future<void> initialize() async {
    // FlutterFire CLI generates platform configuration for Android and iOS.
    // Do not ship placeholder credentials or a service-account key in the client.
    try {
      await Firebase.initializeApp();
    } on FirebaseException {
      // No generated platform config yet: app shows setup instructions.
    } catch (_) {
      // A missing generated FirebaseOptions is handled by the setup screen.
    }
  }

  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get db => FirebaseFirestore.instance;
  static FirebaseStorage get storage => FirebaseStorage.instance;
}
