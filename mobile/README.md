# SecureChat Mobile (Flutter + Firebase)

Android and iOS client foundation. This is not production-ready and has not been security-audited.

## Local setup
1. Install Flutter stable and the Firebase CLI.
2. From the repository root: `cd mobile`
3. Generate Android/iOS native project files: `flutter create . --platforms=android,ios`
4. Install and run FlutterFire configuration:
   `dart pub global activate flutterfire_cli`
   `flutterfire configure`
5. Enable Firebase Authentication (Email/Password), Cloud Firestore, and Firebase Storage in your Firebase console.
6. Add the generated `google-services.json` and `GoogleService-Info.plist` through FlutterFire setup; never add Firebase Admin/service-account credentials to a client.
7. Add Android microphone/camera permissions and iOS `NSMicrophoneUsageDescription` / `NSCameraUsageDescription` entries before testing calls.
8. Run `flutter pub get`, then `flutter run` on Android or iOS.

## Current scaffold
- Email/password account flow
- Unique lowercase username reservation and username lookup
- Direct-chat UI
- AES-256-GCM text and attachment payload encryption using a user-shared secret
- Encrypted photo/video upload and client-side decrypt/viewer
- Initial WebRTC audio/video call signaling and call screen
- Ghost-mode read tracking and best-effort deletion when leaving a chat

## Required before real users
- Deploy and test `firestore.rules.example` and `storage.rules.example` after review; these examples are not automatically deployed.
- Configure TURN servers for reliable calls. The sample STUN-only setup is not enough for many real networks.
- Add push notifications, call timeout/retry, offline handling, attachment type validation, and automated integration tests.
- Replace shared-secret keying with a reviewed Signal Protocol implementation, safety-number verification, forward secrecy, and secure multi-device key management.
- Run dependency scanning, platform builds, penetration testing, and an independent cryptographic review.

**Important:** This is a development scaffold, not a production-secure messenger. Ghost mode cannot prevent screenshots, screen recordings, camera photos, or copies made by recipients. Deletion cannot erase content already copied or backed up.
