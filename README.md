# SecureChat

Flutter Android/iOS messaging prototype with Supabase authentication, username-based direct chats, encrypted text messages and a server-side Ghost Mode cleanup path.

## Setup
1. Run `supabase/schema.sql` in the Supabase SQL Editor.
2. Enable Realtime for `public.encrypted_messages`.
3. Set GitHub repository secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Never use a service-role key in the app.
4. Build Android through GitHub Actions. A signed iOS IPA also requires Apple Developer signing credentials and a matching bundle identifier/profile.

## Implemented
- Email/password signup and login, usernames and direct conversations.
- AES-256-GCM encryption of text on the device. Both users must exchange the same high-entropy secret out of band.
- Supabase Realtime message refresh.
- Ghost Mode marks messages read and removes read-marked messages from the server when the chat is exited.

## Not complete / limitations
This is not a production-ready or independently audited secure messenger. Voice/video calls, photo/video attachments, push notifications, robust identity-bound key exchange, forward secrecy, key rotation, offline deletion retry, abuse/rate limiting and comprehensive tests are not implemented. Offline devices cannot be remotely wiped until they reconnect; screenshots and external copies cannot be erased. Do not use for high-risk communications.
