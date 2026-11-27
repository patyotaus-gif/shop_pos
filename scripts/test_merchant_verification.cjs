// Mobile merchant UI against local Auth/Firestore adapters. The Firebase OOB
// flow itself is exercised by functions/native_checkout.integration.cjs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const publicDir = path.resolve(__dirname, '../public');

(async () => {
  const browser = await chromium.launch({executablePath:process.env.BROWSER_EXECUTABLE, headless:true});
  try {
    const page = await browser.newPage({viewport:{width:360, height:800}});
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/*', async route => {
      const url = new URL(route.request().url());
      const js = body => route.fulfill({contentType:'text/javascript', body});
      if (url.hostname === 'www.gstatic.com') {
        const sdk = url.pathname.split('/').pop();
        const modules = {
          'firebase-app.js':'export const initializeApp = () => ({});',
          'firebase-auth.js':`
            const user = {uid:'test-merchant',email:'merchant@example.test'};
            const auth = {currentUser:localStorage.signedOut ? null : user};
            export const getAuth = () => auth;
            export const getIdTokenResult = async () => ({claims:{email_verified:localStorage.verified === 'yes'}, signInProvider:localStorage.provider || 'password'});
            export const reload = async () => {};
            export const sendEmailVerification = async () => {
              if (localStorage.failSend) throw Error('offline');
              localStorage.sends = String(Number(localStorage.sends || 0) + 1);
            };
            export const onAuthStateChanged = (_, fn) => {auth.listener = fn; queueMicrotask(() => fn(auth.currentUser)); return () => {};};
            export const signOut = async () => {localStorage.signedOut = 'yes';auth.currentUser=null; await auth.listener(null);};
            export const signInWithEmailAndPassword = async () => {};
            export const signInWithPopup = async () => {};
            export class GoogleAuthProvider {} export class OAuthProvider {}
          `,
          'firebase-firestore.js':`
            export const getFirestore = () => ({}); export const doc = (_, ...parts) => parts.join('/');
            export const getDoc = async key => {
              window.readPaths ||= []; window.readPaths.push(key);
              return {exists:() => key.startsWith('shops/'), data:() => ({name:'Verified shop'})};
            };
          `,
          'firebase-functions.js':'export const getFunctions=()=>({}), httpsCallable=()=>()=>{};',
          'firebase-app-check.js':'export const getToken=async()=>({});',
        };
        if (modules[sdk]) return js(modules[sdk]);
      }
      if (url.origin !== 'https://pokpok.test') return route.abort();
      if (url.pathname === '/appcheck.js') return js('export const setupAppCheck=()=>({});');
      const name = url.pathname.endsWith('/') ? url.pathname + 'index.html' : url.pathname;
      const file = path.resolve(publicDir, '.' + name);
      if (!file.startsWith(publicDir + path.sep) || !fs.existsSync(file)) return route.abort();
      return route.fulfill({path:file});
    });
    await page.addInitScript(() => {
      if (!sessionStorage.initialized) { localStorage.failSend = 'yes'; sessionStorage.initialized = '1'; }
    });
    await page.goto('https://pokpok.test/subscribe/');
    const dialog = page.getByRole('dialog');
    const status = dialog.getByRole('status');
    await status.getByText(/ติดต่อระบบยืนยันอีเมลไม่สำเร็จ/).waitFor();
    await page.evaluate(() => {
      delete localStorage.failSend;
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await status.getByText(/ส่งลิงก์ยืนยันแล้ว/).waitFor();
    assert.equal(await page.evaluate(() => localStorage.sends), '1');
    assert.equal(await dialog.locator('[data-send]').isDisabled(), true);
    assert.deepEqual(await page.evaluate(() => window.readPaths || []), []);
    await page.reload();
    await status.getByText(/ส่งลิงก์ยืนยันแล้ว/).waitFor();
    assert.equal(await page.evaluate(() => localStorage.sends), '1');
    await dialog.locator('[data-check]').click();
    await status.getByText(/ยังไม่พบการยืนยัน/).waitFor();
    await page.evaluate(() => {
      const key = Object.keys(localStorage).find(k => k.startsWith('pokpok.verification.sent.'));
      localStorage.setItem(key,String(Date.now() - 120000));
    });
    await page.reload();
    await status.getByText(/ส่งลิงก์ยืนยันแล้ว/).waitFor();
    await dialog.locator('[data-send]').click();
    await page.waitForFunction(() => localStorage.sends === '2');
    await page.evaluate(() => localStorage.verified = 'yes');
    await dialog.locator('[data-check]').click();
    await page.locator('#shopName').getByText('Verified shop').waitFor();
    assert.equal(await dialog.count(), 0);
    await page.evaluate(() => {delete localStorage.verified; localStorage.provider = 'apple.com';});
    await page.reload();
    await page.locator('#shopName').getByText('Verified shop').waitFor();
    assert.equal(await dialog.count(), 0);
    await page.evaluate(() => {delete localStorage.provider;});
    await page.reload();
    await dialog.locator('[data-exit]').click();
    await page.locator('#login-view').waitFor();
    assert.equal(await dialog.count(), 0);
    // Some installed WebKit browsers have no native modal dialog. They still
    // need the email, focus containment, sign-out and a way back after verification.
    await page.addInitScript(() => { HTMLDialogElement.prototype.showModal = undefined; });
    await page.evaluate(() => localStorage.clear());
    await page.reload();
    await status.getByText(/ส่งลิงก์ยืนยันแล้ว/).waitFor({timeout:7000});
    assert.deepEqual(await page.evaluate(() => window.readPaths || []), []);
    assert.equal(await page.evaluate(() => localStorage.sends), '1');
    await page.locator('#email').evaluate(input => input.focus());
    assert.equal(await dialog.evaluate(modal => modal.contains(document.activeElement)), true);
    await dialog.locator('[data-exit]').focus();
    await page.keyboard.press('Tab');
    assert.equal(await dialog.locator('[data-check]').evaluate(button => button === document.activeElement), true);
    await page.keyboard.press('Shift+Tab');
    assert.equal(await dialog.locator('[data-exit]').evaluate(button => button === document.activeElement), true);
    await page.keyboard.press('Escape');
    await dialog.locator('[data-exit]').click();
    await page.locator('#login-view').waitFor();
    assert.equal(await dialog.count(), 0);
    await page.locator('#email').focus();
    assert.equal(await page.locator('#email').evaluate(input => input === document.activeElement), true);
    await page.evaluate(() => delete localStorage.signedOut);
    await page.reload();
    await dialog.waitFor();
    await page.evaluate(() => localStorage.verified = 'yes');
    await dialog.locator('[data-check]').click();
    await page.locator('#shopName').getByText('Verified shop').waitFor();
    assert.equal(await dialog.count(), 0);
    assert.deepEqual(errors, []);
    console.log('PASS merchant verification UI: first-send recovery, cooldown, resend, verified return, Apple, account switch, and keyboard-accessible fallback without showModal');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
