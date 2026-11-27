import {initializeApp} from 'https://www.gstatic.com/firebasejs/10.12.5/firebase-app.js';
import {getToken} from 'https://www.gstatic.com/firebasejs/10.12.5/firebase-app-check.js';
import {setupAppCheck} from '/appcheck.js';

const app = initializeApp({
  apiKey: 'AIzaSyDfkL865SPzygJ0Kcqb4l0UaoXaSuz63F0',
  authDomain: 'shop-pos-89294.firebaseapp.com',
  projectId: 'shop-pos-89294',
  storageBucket: 'shop-pos-89294.firebasestorage.app',
  messagingSenderId: '1010156115465',
  appId: '1:1010156115465:web:01f80dfe21f2767ea68ad8',
});
const appCheck = setupAppCheck(app);
window.__appCheckToken = async () => (await getToken(appCheck, false)).token;
