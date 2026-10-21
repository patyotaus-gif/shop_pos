'use strict';
// Server-owned spool. Delivery to a socket is deliberately distinct from a
// human confirming paper output. Ambiguous jobs never retry themselves.
const {createHash, randomUUID} = require('node:crypto');
const {owner, validId} = require('./order_accounting');
const {linesFor} = require('./kitchen_print');
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const ready = order => ['paid', 'accepted', 'ready', 'completed'].includes(order?.status);
function candidates(source, before, after, sourceId) {
  if (!after) return [];
  if (source === 'sale') {
    if (before || after.isDebt === true || after.isRefunded === true || after.paymentMethod === 'credit') return [];
    const jobs = [{id: `receipt-${sourceId}`, kind: 'receipt', source, sourceId}];
    // Counter takeaway has no table/online preparation order of its own.
    if (!after.orderId && !after.tableName && ['takeaway', 'lineMan', 'grab', 'otherDelivery'].includes(after.salesChannel)) {
      const lines = linesFor('sale', after);
      if (lines.length) jobs.unshift({id: `counter-${sourceId}`, kind: 'kitchen', source, sourceId,
        lines, title: 'หน้าร้าน • รับกลับบ้าน / เดลิเวอรี', customerName: after.customerName || '', pickupLabel: ''});
    }
    return jobs;
  }
  if (source === 'table' ? after.status !== 'open' : !ready(after)) return [];
  const previous = new Set((source === 'table' || ready(before) ? linesFor(source, before || {}) : []).map(l => l.key));
  const lines = linesFor(source, after).filter(l => !previous.has(l.key));
  if (!lines.length) return [];
  return [{id: `kitchen-${hash([source, sourceId, lines.map(l => l.key)])}`, kind: 'kitchen', source, sourceId, lines,
    title: after.tableName ? `โต๊ะ ${after.tableName}` : 'รับกลับบ้าน / ออนไลน์',
    customerName: after.customerName || '', pickupLabel: after.pickupLabel || ''}];
}
function handlers({db, FieldValue, HttpsError, now = () => Date.now()}) {
  const shop = id => db.collection('shops').doc(id);
  const configRef = id => shop(id).collection('autoPrintConfig').doc('current');
  const jobRef = (id, jobId) => shop(id).collection('autoPrintJobs').doc(jobId);
  const fail = message => { throw new HttpsError('failed-precondition', message); };
  function device(request) {
    const shopId = owner(request, HttpsError), data = request.data;
    if (!validId(data.deviceId)) throw new HttpsError('invalid-argument', 'Invalid device');
    return {shopId, data};
  }
  function owns(c, data) {
    if (!c?.enabled || c.deviceId !== data.deviceId || c.session !== data.session) fail('เครื่องหลักเปลี่ยนหรือหยุดพิมพ์แล้ว');
  }
  return {
    configure: async request => {
      const {shopId, data} = device(request);
      if (typeof data.enabled !== 'boolean' || (data.enabled &&
          (typeof data.kitchen !== 'boolean' || typeof data.receipts !== 'boolean' || (!data.kitchen && !data.receipts)))) {
        throw new HttpsError('invalid-argument', 'เลือกเอกสารที่จะพิมพ์');
      }
      return db.runTransaction(async tx => {
        const ref = configRef(shopId), c = (await tx.get(ref)).data() || {};
        if (data.enabled && c.enabled && c.deviceId !== data.deviceId && now() - c.heartbeatAtMs < 120000) {
          fail('เครื่องหลักอีกเครื่องยังทำงานอยู่ กดปิดพิมพ์อัตโนมัติของร้านก่อนเปลี่ยนเครื่อง');
        }
        if (!data.enabled) {
          // An owner may stop a remote primary; old completion tokens can still
          // resolve its in-flight job, but cannot claim another one.
          tx.set(ref, {...c, enabled: false});
          return {enabled: false};
        }
        const session = randomUUID();
        const next = {...c, enabled: true, deviceId: data.deviceId,
          deviceName: String(data.deviceName || 'เครื่องหลัก').slice(0, 80), session,
          kitchen: data.kitchen, receipts: data.receipts,
          enabledAtMs: c.enabled ? c.enabledAtMs : now(), heartbeatAtMs: now()};
        tx.set(ref, next);
        return {enabled: true, session};
      });
    },
    heartbeat: async request => {
      const {shopId, data} = device(request);
      return db.runTransaction(async tx => {
        const ref = configRef(shopId), c = (await tx.get(ref)).data();
        owns(c, data);
        if (data.jobId != null) {
          if (!validId(data.jobId)) throw new HttpsError('invalid-argument', 'Invalid job');
          const j = (await tx.get(jobRef(shopId, data.jobId))).data();
          if (!j || j.status !== 'sending' || j.attempt !== data.attempt ||
              j.deviceId !== data.deviceId || j.session !== data.session) fail('งานพิมพ์เปลี่ยนแล้ว');
          const collection = j.source === 'sale' ? 'sales' : j.source === 'table' ? 'tableOrders' : 'orders';
          const order = (await tx.get(shop(shopId).collection(collection).doc(j.sourceId))).data();
          if (!order || order.status === 'cancelled' || order.isRefunded || order.isDebt) fail('บิลเปลี่ยนแปลง ตรวจสอบก่อนพิมพ์');
          if (j.kind === 'kitchen') {
            const current = new Set(linesFor(j.source, order).map(l => l.key));
            if (j.lines.some(l => !current.has(l.key))) fail('รายการครัวเปลี่ยนแปลง ตรวจสอบก่อนพิมพ์');
          }
        }
        tx.update(ref, {heartbeatAtMs: now()});
        return {enabled: true};
      });
    },
    enqueue: async ({shopId, source, sourceId, before, after, eventAtMs}) => {
      const jobs = candidates(source, before, after, sourceId);
      if (!jobs.length || !Number.isFinite(eventAtMs)) return;
      await db.runTransaction(async tx => {
        const c = (await tx.get(configRef(shopId))).data();
        if (!c?.enabled || eventAtMs < c.enabledAtMs) return;
        // Offline/history imports must not unexpectedly print old receipts.
        if (source === 'sale' && after.createdAt?.toMillis && after.createdAt.toMillis() < c.enabledAtMs) return;
        const eligible = jobs.filter(j => j.kind === 'receipt' ? c.receipts : c.kitchen);
        const existing = await Promise.all(eligible.map(j => tx.get(jobRef(shopId, j.id))));
        eligible.forEach((j, i) => {
          if (!existing[i].exists) tx.create(jobRef(shopId, j.id), {...j, status: 'pending',
            createdAtMs: eventAtMs, updatedAt: FieldValue.serverTimestamp()});
        });
      });
    },
    claim: async request => {
      const {shopId, data} = device(request);
      const pending = await shop(shopId).collection('autoPrintJobs')
        .where('status', '==', 'pending').orderBy('createdAtMs').limit(1).get();
      return db.runTransaction(async tx => {
        const ref = configRef(shopId), c = (await tx.get(ref)).data();
        owns(c, data);
        if (c.activeJob) return {blocked: c.activeJob};
        if (pending.empty) return {empty: true};
        const jr = pending.docs[0].ref, j = (await tx.get(jr)).data();
        if (j?.status !== 'pending') return {empty: true};
        if (j.kind === 'receipt' ? !c.receipts : !c.kitchen) {
          tx.update(jr, {status: 'skipped'});
          return {empty: true};
        }
        const collection = j.source === 'sale' ? 'sales' : j.source === 'table' ? 'tableOrders' : 'orders';
        const order = (await tx.get(shop(shopId).collection(collection).doc(j.sourceId))).data();
        const kr = j.kind === 'kitchen' ? shop(shopId).collection('kitchenPrintJobs').doc(`${j.source}-${j.sourceId}`) : null;
        const k = kr ? (await tx.get(kr)).data() || {} : {};
        if (!order || order.status === 'cancelled' || order.isRefunded || order.isDebt) {
          tx.update(jr, {status: 'skipped'}); return {empty: true};
        }
        let lines = j.lines || [];
        if (kr) {
          if (['printing', 'needsReview'].includes(k.status)) {
            tx.update(jr, {status: 'needsReview', reason: 'ตรวจงานครัวเดิมก่อนพิมพ์'});
            tx.update(ref, {activeJob: jr.id});
            return {blocked: jr.id};
          }
          const current = new Set(linesFor(j.source, order).map(l => l.key));
          lines = lines.filter(l => current.has(l.key) && (j.reprint || !(k.printedKeys || []).includes(l.key)));
          if (!lines.length) { tx.update(jr, {status: 'skipped'}); return {empty: true}; }
        }
        const attempt = randomUUID();
        tx.update(jr, {status: 'sending', attempt, deviceId: data.deviceId,
          session: data.session, startedAtMs: now(), lines});
        tx.update(ref, {activeJob: jr.id, heartbeatAtMs: now()});
        if (kr) tx.set(kr, {...k, status: 'printing', source: j.source, orderId: j.sourceId,
          attempt, startedAtMs: now(), lines, reprint: j.reprint === true,
          printedKeys: k.printedKeys || [], updatedAt: FieldValue.serverTimestamp()});
        return {...j, lines, jobId: jr.id, attempt};
      });
    },
    finish: async request => {
      const {shopId, data} = device(request);
      if (!validId(data.jobId) || !['sent', 'needsReview'].includes(data.outcome)) throw new HttpsError('invalid-argument', 'Invalid result');
      return db.runTransaction(async tx => {
        const ref = configRef(shopId), c = (await tx.get(ref)).data() || {};
        const jr = jobRef(shopId, data.jobId), j = (await tx.get(jr)).data();
        if (!j || j.attempt !== data.attempt || j.deviceId !== data.deviceId || j.session !== data.session) fail('งานพิมพ์เปลี่ยนแล้ว');
        if (j.status !== 'sending') return {success: true};
        const kr = j.kind === 'kitchen' ? shop(shopId).collection('kitchenPrintJobs').doc(`${j.source}-${j.sourceId}`) : null;
        const k = kr ? (await tx.get(kr)).data() : null;
        tx.update(jr, {status: data.outcome, reason: String(data.reason || '').slice(0, 200), updatedAt: FieldValue.serverTimestamp()});
        if (c.activeJob === jr.id && data.outcome === 'sent') tx.update(ref, {activeJob: null});
        if (kr && k?.attempt === data.attempt) tx.update(kr, {status: data.outcome,
          printedKeys: data.outcome === 'sent' ? [...new Set([...(k.printedKeys || []), ...j.lines.map(l => l.key)])] : k.printedKeys || [],
          updatedAt: FieldValue.serverTimestamp()});
        return {success: true};
      });
    },
    review: async request => {
      const shopId = owner(request, HttpsError), {jobId, action} = request.data;
      if (!validId(jobId) || !['retry', 'received', 'skip'].includes(action)) throw new HttpsError('invalid-argument', 'Invalid review');
      return db.runTransaction(async tx => {
        const cr = configRef(shopId), c = (await tx.get(cr)).data() || {};
        const jr = jobRef(shopId, jobId), j = (await tx.get(jr)).data();
        if (!j || !['needsReview', 'sending', 'sent'].includes(j.status)) fail('งานนี้ไม่ต้องตรวจซ้ำ');
        if (j.status === 'sending' && now() - j.startedAtMs < 300000) fail('กำลังส่งงาน กรุณารอ 5 นาทีก่อนตรวจผล');
        const kr = j.kind === 'kitchen' ? shop(shopId).collection('kitchenPrintJobs').doc(`${j.source}-${j.sourceId}`) : null;
        const k = kr ? (await tx.get(kr)).data() : null;
        if (k?.status === 'printing' && k.attempt !== j.attempt && now() - k.startedAtMs < 600000) fail('มีงานพิมพ์ด้วยมือกำลังทำงาน');
        tx.update(jr, {status: action === 'retry' ? 'pending' : action === 'received' ? 'confirmed' : 'skipped',
          reprint: action === 'retry', reviewedAtMs: now(), reason: '', updatedAt: FieldValue.serverTimestamp()});
        if (c.activeJob === jobId) tx.update(cr, {activeJob: null});
        if (kr && k) tx.update(kr, {status: action === 'received' ? 'printed' : 'sent',
          printedKeys: action === 'received' ? [...new Set([...(k.printedKeys || []), ...j.lines.map(l => l.key)])] : k.printedKeys || [],
          updatedAt: FieldValue.serverTimestamp()});
        return {success: true};
      });
    },
  };
}
module.exports = {handlers, candidates};
