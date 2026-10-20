# SecureChat

Flutter starter for Android and iOS with Supabase integration scaffolding.

## Honest status
This is a foundation, not a finished secure messenger. The inbox and settings screens are UI scaffolding. Production authentication, real-time messaging, verified end-to-end encryption, media transfer, push notifications, audio/video calling, and the two-device Ghost Mode deletion protocol are not implemented yet. Do not use for sensitive communication or publish as a finished product.

## Setup
1. Create a Supabase project.
2. Review and run `supabase/schema.sql` only after reviewing the access policies.
3. Configure GitHub Actions secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
4. Never put a Supabase service-role key in a mobile app.

## Android
The GitHub Actions workflow can produce a release APK artifact after a successful build. Open Actions, run Android APK, and download its artifact.

## iOS
A signed IPA requires Apple Developer signing credentials and a provisioning profile. Configure `IOS_P12_BASE64`, `IOS_P12_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`, `IOS_TEAM_ID`, and the matching bundle ID before running the workflow.

## Security plan
Use a reviewed E2EE protocol and vetted implementation; do not invent cryptography. Store private keys in platform secure storage, encrypt media on-device, minimize metadata, protect every database row with tested RLS, and independently audit before release. No app can guarantee zero vulnerabilities or erase screenshots/external copies.
