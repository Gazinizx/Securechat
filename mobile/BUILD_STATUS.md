# Build status

This is the initial Firebase/Flutter scaffold on branch `flutter-firebase-mvp`.

| Feature | Status |
|---|---|
| Android/iOS Flutter project structure | Scaffolded; not built on either platform |
| Firebase email/password auth | UI/service wired; requires Firebase project configuration |
| Username lookup | Initial implementation; requires deployed/tested Firestore rules |
| Text encryption | AES-256-GCM helper using a shared secret; not Signal Protocol |
| Ghost mode | Client-side best-effort deletion when leaving a chat; not guaranteed |
| Photo/video/file messages | Not implemented |
| Voice/video calls | Not implemented |
| Push notifications | Not implemented |
| App Store / Play Store release | Not built or submitted |

Do not use with sensitive real conversations until Firebase rules, key exchange, disappearing-message behavior, and the complete app are tested and independently reviewed.
