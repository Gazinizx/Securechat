# Build status

This is the initial Firebase/Flutter scaffold on branch `flutter-firebase-mvp`. GitHub Actions static analysis and Android debug build workflow has been added, but a successful run has not yet been verified.

| Feature | Status |
|---|---|
| Android/iOS Flutter source | Added; native platform folders are generated with `flutter create . --platforms=android,ios` |
| Firebase email/password auth | UI/service wired; requires a configured Firebase project |
| Username lookup | Initial implementation; requires deployed/tested Firestore rules |
| Text encryption | AES-256-GCM with shared secret; not Signal Protocol |
| Ghost mode | Read tracking and best-effort delete after all participants read and leave; not guaranteed |
| Photo/video messages | Encrypted upload and client-side viewer added; not integration-tested |
| Voice/video calls | Initial WebRTC signaling and call UI added; requires camera/mic permissions and TURN for reliability |
| Push notifications | Not implemented |
| App Store / Play Store release | Not built or submitted |

Do not use with sensitive real conversations until Firebase rules, key exchange, disappearing-message behavior, platform builds, and the complete app are tested and independently reviewed.
