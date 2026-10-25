# SecureChat

Flutter Android/iOS messaging app using Supabase Auth, Postgres and Realtime.

## Setup
1. Run `supabase/schema.sql` in the Supabase SQL Editor for a fresh project. The current connected project has also had the call-signaling table and private encrypted-media bucket applied.
2. GitHub repository secrets must be `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Use only a publishable/anon key in the app; never expose a service-role/secret key.
3. Android APK and unsigned iOS app builds run from the `main` branch through GitHub Actions. Apple signing and a distributable IPA are intentionally deferred.

## Implemented for test
- Email/password registration and login; username-based one-to-one chats.
- Realtime message refresh and read status.
- AES-256-GCM text encryption on-device. Both chat participants must exchange the same high-entropy secret phrase out of band.
- Photo and video attachments are encrypted on-device and uploaded to a private Supabase Storage bucket; download/decryption happens on the recipient device. Attachment limit: 40 MB.
- Voice and video calls use WebRTC with Supabase signaling. For the first test, both users should be signed in and have the same chat open. The current build uses a public STUN server and has no TURN fallback, so calls may fail on restrictive mobile/carrier networks.
- Ghost Mode removes read-marked messages, call signaling rows, and stored encrypted media when the chat is exited while online.

## Important limitations
This is a test build, not a production-ready or independently audited secure messenger. The shared-phrase encryption does not yet provide authenticated identity-bound key exchange, forward secrecy or managed key rotation. Call connectivity is not guaranteed without TURN. Incoming calls are only handled while the recipient has that chat open. Push notifications, full call-history UI, offline cleanup retries, abuse/rate limiting and comprehensive automated/integration tests remain outstanding. Deletion cannot erase screenshots, exported copies or data already saved outside the app. Do not use for high-risk communications.

## Basic test
1. Create two accounts with different usernames on two devices.
2. Open a direct chat between them; set the same long secret phrase on both devices.
3. Send text in both directions and confirm it decrypts on the other device.
4. Send a small photo and video and open each on the receiving device.
5. Keep the same chat open on both devices; test voice call, then video call, and hang up from either side.
6. Repeat in Ghost Mode and verify that read messages and media disappear after leaving the chat while online.


## Push notifications and background calls

Supabase remains the authentication, database, realtime and call-signaling backend. Firebase Cloud Messaging is used only as the mobile push transport because Android/iOS do not reliably deliver Supabase Realtime events to an app that is suspended or terminated.

### One-time configuration required
1. In Firebase Console, create Android and iOS apps for the Securechat Firebase project. For iOS, upload an APNs authentication key in Firebase Console so FCM can deliver notifications to Apple devices.
2. Add these GitHub Actions repository secrets. They are build-time Firebase client settings, not service-account credentials:
   - `FIREBASE_API_KEY`
   - `FIREBASE_PROJECT_ID`
   - `FIREBASE_MESSAGING_SENDER_ID`
   - `FIREBASE_ANDROID_APP_ID`
   - `FIREBASE_IOS_APP_ID`
3. Apply `supabase/migrations/20261025140000_push_tokens.sql` in the existing project's Supabase SQL Editor. A new project can use the updated `supabase/schema.sql`.
4. Deploy the Edge Function from this repository with `supabase functions deploy securechat-push`, and set the Edge Function secret `FIREBASE_SERVICE_ACCOUNT_JSON` to the Firebase service-account JSON. Never add that JSON to GitHub or the source code.
5. Test notifications on real devices with notifications allowed. Android foreground-call capture uses a microphone/camera foreground service; OS permissions and device battery restrictions still apply.

If the Firebase build-time secrets are absent, the app intentionally keeps running but push notifications stay disabled. An incoming notification cannot be delivered reliably to a terminated app until the Edge Function, token table, Firebase project and APNs settings are configured.
