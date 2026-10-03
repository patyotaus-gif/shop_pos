# Google / Apple sign-in setup

The app now has Google/Apple choices on login/signup, and Settings → เชื่อมบัญชี for adding a provider to the existing owner UID. Staff PIN sessions cannot link providers. New identities finish shop name/type/tier and terms consent before a shop is created. Existing shop documents are never overwritten during signup retries. The subscription website also supports both providers and rejects accounts without a shop.

Signing in with a different Apple private-relay email may create a separate identity. Existing owners should sign in using their original method first, then explicitly link Apple/Google in Settings. No automatic merging of different shop UIDs is attempted.

## External setup required before release

Project: `shop-pos-89294`. Package/bundle ID: `app.pokpok.pos`.

1. In [Firebase Authentication providers](https://console.firebase.google.com/project/shop-pos-89294/authentication/providers), enable **Google**, select the project support email and save. Firebase creates the OAuth client configuration. Verified enabled on 2026-09-28; Android and iOS SDK configurations have been refreshed.
2. Register the Android release SHA-1 (the helper can do this): `38:26:91:A7:6C:F1:70:60:20:24:A8:15:51:04:E8:FA:7F:D9:19:9F`. Add Google Play App Signing's certificate too if it differs from the direct APK signing certificate.
3. Run `node scripts/configure_social_auth.cjs --register-sha --refresh-google` with the existing Firebase CLI login. It downloads native configs, sets iOS GIDClientID and reversed-client URL scheme, and avoids printing credentials. This repository tracks the Firebase client configuration files; OAuth client secrets and Apple private keys must remain in the provider configuration, never in these files.
4. In Apple Developer, enable **Sign in with Apple** for the app identifier, regenerate its provisioning profile, create/configure a Service ID for Android/web, and a Sign in with Apple key. Set the domain `shop-pos-89294.firebaseapp.com` and return URL `https://shop-pos-89294.firebaseapp.com/__/auth/handler`. Enter Service ID, Team ID, Key ID and private key directly in Firebase's Apple provider settings; never place the key in Dart, source control or chat.
5. For Apple private-relay email delivery, configure permitted sender domains/email addresses in Apple Developer as described in Firebase's Apple setup guide.
6. Run `node scripts/configure_social_auth.cjs` to check provider readiness. Missing settings return exit code 2. Rebuild Android/iOS after refreshing native Google config; iOS requires the updated Apple provisioning capability.

The app entitlement enables Apple Sign-In, but does not create that capability in the Apple Developer account or supply its signing credentials.

## Acceptance checks before publishing

Local validation: 57 Flutter tests passed, including onboarding, explicit link confirmation, cancellation, account-collision handling, and signup retry preservation. A mocked Edge browser check passed the subscription flow for existing/missing shops, cancellation, collisions and mobile layout. These checks do not verify real provider credentials or native account selection; the device checks below remain required.

- Real Google/Apple login on a device: account selection, cancellation, new-user onboarding, restart and owner handoff from staff mode.
- Existing email owner links Google/Apple: UID, shop, paid tier and subscription dates stay unchanged.
- An account already linked to another Firebase UID produces an actionable error and never merges stores.
- Apple private-relay address works, including repeat login when Apple no longer supplies the name.
- A newly authenticated user without a shop completes setup once; retried setup never resets a trial or overwrites a paid plan.
- Subscription website enters the same shop as the app and does not offer payment for a missing shop.

Google icon: official asset from https://developers.google.com/static/identity/images/g-logo.png. Google client setup follows https://firebase.google.com/docs/auth/flutter/federated-auth and the google_sign_in package; Apple setup follows https://firebase.google.com/docs/auth/ios/apple.
