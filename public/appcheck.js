// ── Firebase App Check (web) ───────────────────────────────────────────────
// Single source of truth for the reCAPTCHA v3 site key + App Check setup,
// shared by /order, /supplier and /subscribe.
//
// Register the web app in Firebase Console → App Check → Apps → "Add app" with
// the reCAPTCHA v3 provider, then paste the generated *site key* below. The
// site key is public by design (it ships in client HTML); abuse is bounded by
// the allowed-domains list you set in the reCAPTCHA admin console.
import { initializeAppCheck, ReCaptchaV3Provider }
  from "https://www.gstatic.com/firebasejs/10.12.5/firebase-app-check.js";

export const RECAPTCHA_SITE_KEY = "6Ld3oRktAAAAALXvbO67phOApeT3chrl99j4yu6h";

// Attaches App Check tokens to every Firebase SDK call (Firestore, Functions,
// Storage) made through `app`. Call once, right after initializeApp() and
// before getAuth/getFirestore/etc. so the very first request carries a token.
export function setupAppCheck(app) {
  return initializeAppCheck(app, {
    provider: new ReCaptchaV3Provider(RECAPTCHA_SITE_KEY),
    isTokenAutoRefreshEnabled: true,
  });
}
