import {onAuthStateChanged, getIdTokenResult, reload, sendEmailVerification, signOut}
  from 'https://www.gstatic.com/firebasejs/10.12.5/firebase-auth.js';

function verified(result) {
  return result.claims.email_verified === true ||
    ['google.com', 'apple.com'].includes(result.signInProvider);
}

function openVerificationDialog(dialog) {
  const returnFocus = document.activeElement;
  document.body.append(dialog);
  if (typeof dialog.showModal === 'function') {
    try {
      dialog.showModal();
      return () => { dialog.close(); dialog.remove(); };
    } catch { /* Fall back if the browser cannot present a native modal. */ }
  }

  const backdrop = document.createElement('div');
  backdrop.className = 'merchant-verification-backdrop';
  dialog.setAttribute('role', 'dialog');
  dialog.setAttribute('aria-modal', 'true');
  dialog.setAttribute('open', '');
  dialog.tabIndex = -1;
  backdrop.append(dialog);
  document.body.append(backdrop);
  const containFocus = event => {
    if (!dialog.contains(event.target)) dialog.focus();
  };
  const cycleButtons = event => {
    if (event.key !== 'Tab') return;
    const buttons = dialog.querySelectorAll('button:not(:disabled)');
    const first = buttons[0], last = buttons[buttons.length - 1];
    const active = document.activeElement;
    if (event.shiftKey && (active === first || active === dialog)) {
      event.preventDefault(); last.focus();
    } else if (!event.shiftKey && (active === last || active === dialog)) {
      event.preventDefault(); first.focus();
    }
  };
  document.addEventListener('focusin', containFocus);
  dialog.addEventListener('keydown', cycleButtons);
  dialog.focus();
  return () => {
    document.removeEventListener('focusin', containFocus);
    dialog.removeEventListener('keydown', cycleButtons);
    backdrop.remove();
    if (returnFocus?.isConnected) returnFocus.focus();
  };
}

// Keep all signed-in merchant portals behind the same Firebase identity check.
// A cashier PIN never signs in to these web portals.
export function watchVerifiedAccount(auth, showAccount) {
  let cleanup = () => {};
  const unsubscribe = onAuthStateChanged(auth, async user => {
    cleanup();
    cleanup = () => {};
    showAccount(null);
    if (!user) return;
    const current = () => auth.currentUser === user;
    let accepted = false;
    try { accepted = verified(await getIdTokenResult(user)); }
    catch { /* Present a recoverable verification screen. */ }
    if (!current()) return;
    if (accepted) {
      await showAccount(user);
      return;
    }

    const dialog = document.createElement('dialog');
    dialog.className = 'merchant-verification';
    dialog.setAttribute('aria-labelledby', 'verification-title');
    dialog.innerHTML = `<h2 id="verification-title">ยืนยันอีเมลเพื่อเข้าใช้งาน</h2>
      <p>เปิดอีเมลจาก Pokpok แล้วกดลิงก์ยืนยัน จากนั้นกลับมาที่หน้านี้</p>
      <strong></strong><p role="status" aria-live="polite"></p>
      <button type="button" data-check>กดลิงก์แล้ว ตรวจสอบอีกครั้ง</button>
      <button type="button" data-send>ส่งอีเมลยืนยันอีกครั้ง</button>
      <button type="button" data-exit>ออกจากระบบ / ใช้บัญชีอื่น</button>`;
    dialog.querySelector('strong').textContent = user.email || '';
    const status = dialog.querySelector('[role=status]');
    const check = dialog.querySelector('[data-check]');
    const send = dialog.querySelector('[data-send]');
    const key = 'pokpok.verification.sent.' + user.uid + '.' + (user.email || '');
    let sentAt = 0, limitedUntil = 0, busy = false, autoSendPending = true, timer;
    try { sentAt = Number(localStorage.getItem(key)) || 0; } catch { /* memory still works */ }
    function buttons() {
      clearTimeout(timer);
      const elapsed = Date.now() - sentAt;
      const wait = Math.max(limitedUntil - Date.now(), elapsed >= 0 && elapsed < 60000 ? 60000 - elapsed : 0);
      check.disabled = busy;
      send.disabled = busy || wait > 0 || !user.email;
      if (wait) timer = setTimeout(buttons, wait);
    }
    async function process(action) {
      if (busy || !current() || !dialog.isConnected) return;
      busy = true;
      buttons();
      status.textContent = 'กำลังตรวจสอบ…';
      try {
        await reload(user);
        if (!current()) return;
        if (verified(await getIdTokenResult(user, true))) {
          if (!current()) return;
          cleanup();
          cleanup = () => {};
          await showAccount(user);
          return;
        }
        if (!current()) return;
        if (!user.email) {
          status.textContent = 'บัญชีนี้ไม่มีอีเมลสำหรับรับลิงก์ กรุณาออกจากระบบแล้วเข้าสู่ระบบด้วยบัญชีเดิมของร้าน';
          return;
        }
        if (action === 'check' && !autoSendPending) {
          status.textContent = 'ยังไม่พบการยืนยัน กรุณากดลิงก์ในอีเมลล่าสุดแล้วตรวจอีกครั้ง';
          return;
        }
        if (Date.now() < limitedUntil) {
          status.textContent = 'ขอลิงก์หลายครั้งเกินไป กรุณารอสักครู่ก่อนลองใหม่';
          return;
        }
        const delay = action === 'send' ? 60000 : 86400000;
        if (Date.now() - sentAt >= delay || sentAt > Date.now()) {
          auth.languageCode = 'th';
          await sendEmailVerification(user);
          sentAt = Date.now();
          try { localStorage.setItem(key, String(sentAt)); } catch { /* memory still works */ }
        }
        autoSendPending = false;
        status.textContent = 'ส่งลิงก์ยืนยันแล้ว หากยังไม่เห็นอีเมล โปรดตรวจโฟลเดอร์สแปม';
      } catch (e) {
        if (e.code === 'auth/too-many-requests') limitedUntil = Date.now() + 60000;
        status.textContent = e.code === 'auth/too-many-requests'
          ? 'ขอลิงก์หลายครั้งเกินไป กรุณารอสักครู่ก่อนลองใหม่'
          : 'ติดต่อระบบยืนยันอีเมลไม่สำเร็จ กรุณาตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง';
      } finally {
        busy = false;
        if (dialog.isConnected) buttons();
      }
    }
    const onFocus = () => { if (!document.hidden) process('check'); };
    const closeDialog = openVerificationDialog(dialog);
    cleanup = () => {
      clearTimeout(timer);
      document.removeEventListener('visibilitychange', onFocus);
      closeDialog();
    };
    document.addEventListener('visibilitychange', onFocus);
    dialog.addEventListener('cancel', event => event.preventDefault());
    check.onclick = () => process('check');
    send.onclick = () => process('send');
    dialog.querySelector('[data-exit]').onclick = () => signOut(auth).catch(() => {
      status.textContent = 'ออกจากระบบไม่สำเร็จ กรุณาลองอีกครั้ง';
    });
    await process('initial');
  });
  return () => { cleanup(); unsubscribe(); };
}
