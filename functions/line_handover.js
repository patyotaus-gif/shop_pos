const {randomUUID} = require('node:crypto');

// OA Manager typing/replies are not ordinary Messaging API webhook events.
function wantsHuman(text) {
  const value = String(text || '').trim().toLowerCase();
  if (/ไม่(?:ต้องการ|อยาก|ต้อง|ขอ).*คุย(?:กับ)?.*(?:คน|เจ้าหน้าที่|แอดมิน)/.test(value)) return false;
  return /^(เจ้าหน้าที่|แอดมิน|ติดต่อเจ้าหน้าที่|คุยกับคน|หยุดบอท|human|agent)$/i.test(value) ||
    /(?:คุย|ติดต่อ)(?:กับ)?(?:เจ้าหน้าที่|แอดมิน|คนจริง|คนเป็น|คน(?:ได้ไหม|หน่อย|ค่ะ|ครับ|$))/.test(value) ||
    /(?:ขอ|อยาก|ต้องการ|ช่วย).{0,15}(?:คุย|ติดต่อ).{0,8}(?:เจ้าหน้าที่|แอดมิน|คนจริง|คนเป็น|คน(?:\s|$|ค่ะ|ครับ))/.test(value) ||
    /(?:ไม่เอา|ไม่(?:อยาก|ต้องการ)?คุยกับ|หยุดตอบ|หยุดใช้).{0,4}(?:บอท|บอต|bot)/i.test(value);
}

function handlers({db, assertFounder, HttpsError, now = Date.now, profile = async () => null}) {
  const chats = db.collection('lineSupportChats');
  const validId = id => typeof id === 'string' && /^U[0-9a-f]{32}$/i.test(id);
  function refFor(id) {
    if (!validId(id)) throw new HttpsError('invalid-argument', 'Invalid LINE user');
    return chats.doc(id);
  }
  function publicChat(doc) {
    const d = doc.data();
    return {userId: doc.id, displayName: d.displayName || '', mode: d.mode || 'bot',
      preview: d.preview || '', updatedAt: d.updatedAt || 0,
      changedBy: d.changedBy || '', sendingUntil: d.sendingUntil || 0};
  }
  async function receive(event) {
    if (event.source?.type !== 'user' || !validId(event.source?.userId)) return {action: 'ignore'};
    const userId = event.source.userId, ref = refFor(userId);
    const text = event.message?.type === 'text' ? event.message.text : '';
    const eventId = event.webhookEventId || event.message?.id;
    if (!eventId) return {action: 'ignore'};
    const result = await db.runTransaction(async tx => {
      const snap = await tx.get(ref), d = snap.data() || {};
      if ((d.events || []).includes(eventId) || (d.resumedAt && event.timestamp <= d.resumedAt)) return {action: 'ignore'};
      const mode = d.mode || 'bot', requestHuman = mode === 'bot' && wantsHuman(text);
      const epoch = (d.epoch || 0) + 1;
      const preview = /^connect:/i.test(text) ? '[เชื่อมบัญชีร้าน]' : text ? String(text).slice(0, 240) : `[${event.message?.type || 'ข้อความ'}]`;
      tx.set(ref, {mode: requestHuman ? 'waiting' : mode, epoch, preview, updatedAt: now(),
        events: [...(d.events || []).slice(-19), eventId],
        ...(requestHuman ? {changedBy: 'customer', changedAt: now()} : {})}, {merge: true});
      return {action: requestHuman ? 'ack' : mode === 'bot' ? 'bot' : 'ignore', userId, epoch, newChat: !snap.exists};
    });
    if (result.newChat) {
      try { const name = await profile(userId); if (name) await ref.set({displayName: String(name).slice(0, 100)}, {merge: true}); }
      catch { /* Name lookup failure must not undo a pause. */ }
    }
    return result;
  }
  async function replyIfCurrent(ticket, send) {
    if (!['ack', 'bot'].includes(ticket.action)) return false;
    const ref = refFor(ticket.userId), sendId = randomUUID();
    const allowed = await db.runTransaction(async tx => {
      const d = (await tx.get(ref)).data() || {};
      if (d.epoch !== ticket.epoch || d.mode !== (ticket.action === 'ack' ? 'waiting' : 'bot')) return false;
      tx.set(ref, {sendId, sendingUntil: now() + 20000}, {merge: true});
      return true;
    });
    if (!allowed) return false;
    // An HTTP request already submitted to LINE cannot be recalled.
    try { return await send(); }
    finally {
      await db.runTransaction(async tx => {
        const d = (await tx.get(ref)).data() || {};
        if (d.sendId === sendId) tx.set(ref, {sendId: null, sendingUntil: 0}, {merge: true});
      });
    }
  }
  async function list(request) {
    assertFounder(request);
    const after = request.data?.after;
    let query = chats.orderBy('updatedAt', 'desc').orderBy('__name__', 'desc').limit(50);
    if (after) {
      if (!Number.isFinite(after.updatedAt) || !validId(after.userId)) throw new HttpsError('invalid-argument', 'Invalid cursor');
      query = query.startAfter(after.updatedAt, after.userId);
    }
    const snap = await query.get(), rows = snap.docs.map(publicChat), last = rows.at(-1);
    return {chats: rows, next: rows.length === 50 ? {updatedAt: last.updatedAt, userId: last.userId} : null};
  }
  async function setMode(request) {
    assertFounder(request);
    const {userId, mode, expectedMode} = request.data || {};
    if (!['human', 'bot'].includes(mode)) throw new HttpsError('invalid-argument', 'Invalid mode');
    const ref = refFor(userId);
    return db.runTransaction(async tx => {
      const snap = await tx.get(ref), d = snap.data();
      if (!snap.exists) throw new HttpsError('not-found', 'Chat not found');
      if (expectedMode !== d.mode) throw new HttpsError('failed-precondition', 'สถานะแชทเปลี่ยนแล้ว กรุณาโหลดใหม่');
      tx.set(ref, {mode, epoch: (d.epoch || 0) + 1, changedBy: request.auth.uid,
        changedAt: now(), updatedAt: now(), ...(mode === 'bot' ? {resumedAt: now()} : {})}, {merge: true});
      return {mode, sendingUntil: d.sendingUntil > now() ? d.sendingUntil : 0};
    });
  }
  return {receive, replyIfCurrent, list, setMode};
}
module.exports = {handlers, wantsHuman};
