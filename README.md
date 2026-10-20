# SecureChat

A minimal browser-based end-to-end encrypted chat starter.

## Security model
- Message bodies are encrypted in the browser with Web Crypto AES-GCM before being sent to the database.
- The encryption key is derived locally from a room passphrase using PBKDF2-SHA-256 and a per-room salt.
- The server stores ciphertext, IV, and room identifier; it must never receive the passphrase.
- Use a long, unique passphrase and share it with recipients through a separate trusted channel.
- This is an MVP, not a professionally audited secure messenger. It does not implement the Signal Protocol / Double Ratchet, forward secrecy, identity verification, secure multi-device key management, or metadata protection. Do not use it for highly sensitive communications until independently reviewed.

## Run
1. Create a Supabase project.
2. Run `supabase/schema.sql` in the Supabase SQL Editor.
3. Open `index.html` from a local web server (HTTPS is required outside localhost).
4. Enter your Supabase Project URL and anon/publishable key in the app. These are public client settings, not service-role secrets.
5. Choose the same room name and a strong shared passphrase on both devices.

## Important
- Never put a Supabase service-role key in this app.
- Database access is restricted to authenticated users by RLS. For the starter, users must sign in with Supabase Auth before reading or sending messages.
- Keep the room passphrase out of chat messages.
- No security claim is a guarantee that there are zero vulnerabilities. Have the code and deployment independently audited before production use.
