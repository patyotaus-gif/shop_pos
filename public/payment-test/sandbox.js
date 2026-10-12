import {initializeApp} from 'https://www.gstatic.com/firebasejs/10.12.5/firebase-app.js';
import {getAuth, signInWithEmailAndPassword, signInWithPopup, GoogleAuthProvider, onAuthStateChanged, signOut}
  from 'https://www.gstatic.com/firebasejs/10.12.5/firebase-auth.js';
import {getFunctions, httpsCallable} from 'https://www.gstatic.com/firebasejs/10.12.5/firebase-functions.js';
import {setupAppCheck} from '/appcheck.js';

const app = initializeApp({apiKey:'AIzaSyDfkL865SPzygJ0Kcqb4l0UaoXaSuz63F0',
  authDomain:'shop-pos-89294.firebaseapp.com', projectId:'shop-pos-89294',
  appId:'1:1010156115465:web:01f80dfe21f2767ea68ad8'});
setupAppCheck(app);
const auth = getAuth(app), functions = getFunctions(app, 'asia-southeast1');
const call = async (name, data = {}) => (await httpsCallable(functions, name)(data)).data;
const $ = id => document.getElementById(id);
let config, user, saved, busy = false;
const terminal = new Set(['successful','failed','expired','reversed','refunded','rejected']);
const labels = {creating:'กำลังสร้างรายการ กรุณาตรวจสถานะอีกครั้ง', unknown:'ยังยืนยันผลไม่ได้ กรุณาตรวจ Charge ID ใน Omise ก่อนเริ่มใหม่',
  pending:'รอยืนยันการชำระเงิน', successful:'ชำระเงินทดลองสำเร็จ', failed:'ชำระเงินทดลองไม่สำเร็จ',
  expired:'รายการหมดอายุ', reversed:'ยกเลิกรายการแล้ว', refunded:'มีการคืนเงินทดลอง', rejected:'คำขอทดลองไม่สำเร็จ ยังไม่ได้สร้างรายการชำระ'};
const key = () => `pokpok-omise-sandbox-v1:${user.uid}`;
function store(value) { localStorage.setItem(key(), JSON.stringify(value)); saved = value; }
function message(text) { $('status').textContent = text; }
function errorMessage(e) {
  return e.code?.includes('permission-denied') ? 'บัญชีนี้ไม่มีสิทธิ์ทดสอบ กรุณาใช้บัญชีผู้ดูแล Pokpok'
    : e.code?.includes('unauthenticated') ? 'กรุณาเข้าสู่ระบบใหม่'
    : e.code?.includes('failed-precondition') ? e.message
    : 'ดำเนินการไม่ได้ กรุณาลองตรวจสถานะอีกครั้ง หากมีรายการเดิมอย่าเริ่มจ่ายซ้ำ';
}
async function run(action) {
  if (busy) return;
  busy = true; document.querySelectorAll('button').forEach(b => b.disabled = true);
  try { await action(); } catch (e) { message(errorMessage(e)); }
  finally { busy = false; document.querySelectorAll('button').forEach(b => b.disabled = false); }
}
function show(data) {
  // Nothing in return URL parameters is used as evidence of a paid transaction.
  if (data.testMode !== true || data.amount !== 10000) throw Error('Invalid test response');
  store({...saved, attemptId:data.attemptId, status:data.status});
  $('newPayment').hidden = true; $('existingPayment').hidden = false;
  $('startNew').hidden = !terminal.has(data.status);
  $('recovery').hidden = !!data.chargeId || terminal.has(data.status);
  $('authorize').hidden = true;
  if (data.authorizeUri) {
    const url = new URL(data.authorizeUri);
    if (url.protocol === 'https:' && !url.username && !url.password &&
        (url.hostname === 'omise.co' || url.hostname.endsWith('.omise.co'))) {
      $('authorize').href = url.href; $('authorize').hidden = false;
    }
  }
  message(`${labels[data.status] || 'กำลังตรวจสอบ'}\nยอดทดลอง ฿100.00${data.chargeId ? `\n${data.chargeId}` : ''}`);
}
async function refresh() {
  if (!saved) return;
  try {
    show(await call('omiseSandboxStatus', {attemptId:saved.attemptId,
      ...($('chargeId').value.trim() ? {chargeId:$('chargeId').value.trim()} : {})}));
  } catch (e) {
    // If the first HTTP request never reached Firebase, replay its SAME ID/nonce.
    if (e.code === 'functions/not-found' && saved.nonce) show(await call('omiseSandboxCreate', saved));
    else throw e;
  }
}
async function submitNonce(method, nonce) {
  const value = {attemptId:crypto.randomUUID(), method, nonce};
  // Local storage must succeed BEFORE sending the payment request.
  store(value);
  $('newPayment').hidden = true; $('existingPayment').hidden = false; $('startNew').hidden = true;
  message('กำลังสร้างรายการทดลอง…');
  show(await call('omiseSandboxCreate', value));
}
$('loginForm').addEventListener('submit', e => {e.preventDefault(); run(async () => {
  try { await signInWithEmailAndPassword(auth, $('email').value.trim(), $('password').value); }
  finally { $('password').value = ''; }
});});
$('googleLogin').onclick = () => run(() => signInWithPopup(auth, new GoogleAuthProvider()));
$('logout').onclick = () => run(() => signOut(auth));
$('method').onchange = () => { $('phoneRow').hidden = $('method').value !== 'truemoney'; };
$('refresh').onclick = () => run(refresh);
$('startNew').onclick = () => {
  if (busy || !terminal.has(saved?.status)) return;
  localStorage.removeItem(key()); saved = null;
  history.replaceState(null, '', location.pathname);
  $('newPayment').hidden = false; $('existingPayment').hidden = true;
  $('authorize').hidden = true; $('chargeId').value = ''; message('พร้อมทดสอบรายการใหม่');
};
$('pay').onclick = () => {
  if (busy || !config || saved) return;
  if (!window.OmiseCard || !window.Omise) {message('โหลดแบบฟอร์มชำระเงินไม่ได้ กรุณารีเฟรชหน้า'); return;}
  const method = $('method').value;
  if (method === 'card') {
    busy = true; $('pay').disabled = true;
    let submitted = false;
    OmiseCard.configure({publicKey:config.publicKey});
    try {
      OmiseCard.open({amount:config.amount, currency:'THB', locale:'th', defaultPaymentMethod:'credit_card', otherPaymentMethods:[],
        frameLabel:'Pokpok · ทดสอบเท่านั้น',
        onCreateTokenSuccess:nonce => {if (submitted) return; submitted = true; busy = false; run(() => submitNonce(method, nonce));},
        onFormClosed:() => {if (!submitted) {busy = false; $('pay').disabled = false;}}
      });
    } catch (_) {busy = false; $('pay').disabled = false; message('เปิดแบบฟอร์มไม่ได้ กรุณาลองใหม่');}
  } else {
    const phone = $('phone').value.trim();
    if (!/^0\d{9}$/.test(phone)) {message('กรุณากรอกเบอร์ทดสอบ 10 หลัก เริ่มด้วย 0'); return;}
    run(async () => {
      Omise.setPublicKey(config.publicKey);
      const nonce = await new Promise((resolve, reject) => Omise.createSource('truemoney',
        {amount:config.amount, currency:'THB', phone_number:phone}, (status, source) => {
          if (status < 300 && source.livemode === false && /^src_test_/.test(source.id)) resolve(source.id);
          else reject(Error('TrueMoney test unavailable'));
        }));
      await submitNonce(method, nonce);
    });
  }
};
onAuthStateChanged(auth, async account => {
  user = account; config = null; saved = null;
  $('loginPanel').hidden = !!account; $('paymentPanel').hidden = true;
  if (!account) {message('เข้าสู่ระบบเพื่อเริ่มทดสอบ'); return;}
  $('account').textContent = account.email || 'ผู้ดูแลระบบ';
  try {
    config = await call('omiseSandboxConfig');
    if (auth.currentUser?.uid !== account.uid) return;
    if (config.testMode !== true || config.amount !== 10000 || !/^pkey_test_/.test(config.publicKey)) throw Error('Invalid config');
    $('paymentPanel').hidden = false;
    saved = JSON.parse(localStorage.getItem(key()) || 'null');
    const returned = new URLSearchParams(location.search).get('attempt');
    if (returned && /^[a-f0-9-]{36}$/i.test(returned) && returned !== saved?.attemptId) store({attemptId:returned});
    $('newPayment').hidden = !!saved; $('existingPayment').hidden = !saved;
    if (saved) await run(refresh); else message('พร้อมทดสอบด้วยเงินจำลอง ฿100.00');
  } catch (e) {
    message(errorMessage(e));
    // Keep sign-out available when signed in with an ordinary shop account.
    $('paymentPanel').hidden = false; $('newPayment').hidden = true; $('existingPayment').hidden = true;
  }
});
