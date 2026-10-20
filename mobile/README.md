# SecureChat Mobile (Flutter + Firebase)

Android and iOS client foundation. This is not production-ready and has not been security-audited.

## Local setup
1. Install Flutter and the Firebase CLI.
2. From the repository root: `cd mobile`
3. Install FlutterFire CLI and configure both platforms:
   `dart pub global activate flutterfire_cli`
   `flutterfire configure`
4. Ensure Firebase Authentication (Email/Password), Cloud Firestore, and Firebase Storage are enabled in the Firebase console.
5. Run `flutter pub get`, then `flutter run` on Android or iOS.

FlutterFire generates platform files (including `firebase_options.dart`) from your own Firebase project. Do not commit service-account JSON or Firebase Admin credentials into the app. Client configuration is not a substitute for restrictive Security Rules.

## Current scaffold
- Email/password account flow
- Unique lowercase username reservation and username lookup
- Direct-chat UI
- AES-256-GCM encryption utility for text payloads using a shared secret
- Ghost-mode UI and best-effort deletion hook

## Not implemented / not verified yet
- Signal Protocol / Double Ratchet, prekeys, key verification, forward secrecy and secure multi-device key management
- Production-grade read receipts and server-enforced disappearing messages
- Encrypted photo/video/file transfer and Firebase Storage rules
- WebRTC voice/video calls, call signaling, TURN configuration, push notifications and call lifecycle
- Android/iOS build, Firebase project integration, automated tests, dependency audit and independent security audit

**Important:** The current shared-secret AES-GCM helper is a starter only. Never market this build as “unhackable” or as equivalent to Signal/WhatsApp E2EE. Firebase server rules must be configured before real user data is stored. Ghost mode cannot stop screenshots, screen recording, notification previews, or copies made by recipients.
