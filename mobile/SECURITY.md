# Security notes

- TLS protects traffic in transit; client-side encryption protects message bodies from the database provider only when keys remain on the endpoints.
- This branch's AES-GCM helper uses a user-supplied shared secret. It is not Signal Protocol and currently has no per-message ratchet, forward secrecy, identity verification, or audited key exchange.
- Never put Firebase Admin/service-account credentials in a mobile app.
- Firestore rules must be deployed and tested before any real accounts use the app. Rules cannot validate whether ciphertext is honest plaintext unless the client protocol is designed and verified accordingly.
- Ghost mode is best-effort. A recipient can screenshot, record, photograph the screen, or copy content. Reliable deletion requires server-side expiry and deletion triggers, and cannot erase backups or a recipient's copies.
- Voice/video calls require WebRTC signaling and STUN/TURN infrastructure. Call media security and peer identity must be reviewed separately.
- Treat attachments as untrusted input; encrypt locally before upload, use random object IDs, size/type limits, authenticated access rules, and avoid public download URLs.
- Before release: implement a reviewed Signal Protocol library, verify fingerprints/safety numbers, store private keys in platform secure storage, add rate limits/abuse controls, deploy strict rules, run tests, dependency scanning, penetration testing, and independent cryptographic review.
