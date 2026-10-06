// Pickup scheduling uses the shop's Thailand clock, never the caller's clock.
const MINUTE = 60000;
const DAY = 86400000;
const OFFSET = 7 * 60 * MINUTE;
function config(raw = {}) {
  raw = raw && typeof raw === 'object' ? raw : {};
  const integer = (value, fallback, min, max) => Number.isInteger(value) && value >= min && value <= max ? value : fallback;
  return {
    enabled: raw.enabled === true,
    openMinute: integer(raw.openMinute, 540, 0, 1439),
    closeMinute: integer(raw.closeMinute, 1080, 1, 1440),
    prepMinutes: integer(raw.prepMinutes, 30, 5, 240),
    slotMinutes: [15, 30, 60].includes(raw.slotMinutes) ? raw.slotMinutes : 15,
    capacity: integer(raw.capacity, 5, 1, 100),
    weekdays: Array.isArray(raw.weekdays) ? [...new Set(raw.weekdays.filter(v => Number.isInteger(v) && v >= 0 && v <= 6))] : [0, 1, 2, 3, 4, 5, 6],
  };
}
function slots(raw, now = Date.now()) {
  const c = config(raw);
  if (!c.enabled || c.closeMinute <= c.openMinute) return [];
  const midnight = Math.floor((now + OFFSET) / DAY) * DAY - OFFSET;
  const result = [];
  for (let d = 0; d < 7; d++) {
    const day = midnight + d * DAY;
    if (!c.weekdays.includes(new Date(day + OFFSET).getUTCDay())) continue;
    for (let m = c.openMinute; m + c.slotMinutes <= c.closeMinute; m += c.slotMinutes) {
      const start = day + m * MINUTE;
      if (start < now + c.prepMinutes * MINUTE) continue;
      const end = start + c.slotMinutes * MINUTE;
      const date = new Date(start + OFFSET).toISOString().slice(0, 10);
      const time = v => new Date(v + OFFSET).toISOString().slice(11, 16);
      result.push({ id: String(start), start: new Date(start).toISOString(), end: new Date(end).toISOString(),
        label: `${date.slice(8)}/${date.slice(5, 7)}/${date.slice(0, 4)} ${time(start)}–${time(end)} น.` });
    }
  }
  return result;
}
function overlapping(docs, slot) {
  const start = Number(slot.id), end = Date.parse(slot.end);
  return docs.filter(doc => {
    const order = doc.data();
    const from = Number(order.pickupSlot);
    const to = order.pickupEndAt?.toMillis?.() ?? new Date(order.pickupEndAt).getTime();
    // Pending payments retain capacity until explicitly cancelled, since the
    // customer might still be transferring money. Completed orders used it too.
    return order.status !== 'cancelled' && from < end && to > start;
  }).length;
}
async function availability(shopRef, raw, now = Date.now()) {
  const c = config(raw), options = slots(c, now);
  if (!options.length) return { enabled: c.enabled, prepMinutes: c.prepMinutes, slots: [], timezone: 'Asia/Bangkok' };
  const snapshot = await shopRef.collection('orders').where('pickupSlot', '>=', String(Number(options[0].id) - 60 * MINUTE))
    .where('pickupSlot', '<', String(Date.parse(options.at(-1).end))).limit(2001).get();
  return { enabled: true, prepMinutes: c.prepMinutes, timezone: 'Asia/Bangkok',
    slots: snapshot.size > 2000 ? [] : options.filter(s => overlapping(snapshot.docs, s) < c.capacity) };
}
async function createWithPickup({ db, shopRef, orderRef, order, requestedSlot, pickupMode, now = () => Date.now() }) {
  return db.runTransaction(async tx => {
    const prior = await tx.get(orderRef);
    if (prior.exists) {
      const saved = prior.data();
      if (!order.requestSignature || saved.requestSignature !== order.requestSignature || saved.status !== 'pendingPayment')
        throw Error('ช่วงเวลาหรือออเดอร์เปลี่ยนไป กรุณาตรวจออเดอร์เดิมกับร้าน');
      return { pickupLabel: saved.pickupLabel || null, total: saved.total, finalAmount: saved.finalAmount };
    }
    const settings = (await tx.get(shopRef.collection('settings').doc('shop'))).data() || {};
    if (settings.ordersClosed === true) throw Error('ร้านปิดรับออเดอร์ชั่วคราว');
    const c = config(settings.pickup);
    let pickup = {};
    if (order.tableId || order.orderType === 'dineInPrepaid') {
      if (requestedSlot) throw Error('เวลานัดรับใช้สำหรับออเดอร์รับกลับบ้านเท่านั้น');
      if (!order.tableId || order.orderType !== 'dineInPrepaid' || settings.tableOrderMode !== 'prepaid')
        throw Error('เวลานัดรับไม่ตรงกับประเภทออเดอร์ กรุณาสแกน QR ใหม่');
      const table = await tx.get(shopRef.collection('tables').doc(order.tableId));
      if (!table.exists) throw Error('เวลานัดรับไม่ตรงกับโต๊ะ กรุณาสแกน QR ใหม่');
      order = { ...order, tableName: String(table.data().name || '') };
    } else if (c.enabled) {
      const slot = slots(c, now()).find(s => s.id === requestedSlot);
      if (!slot) throw Error('ช่วงเวลารับเปลี่ยนไป กรุณาเลือกเวลาใหม่');
      // Serialize shop reservations even when an owner changes interval length.
      const lock = shopRef.collection('pickupSlots').doc('control');
      const previous = await tx.get(lock);
      const existing = await tx.get(shopRef.collection('orders')
        .where('pickupSlot', '>=', String(Number(slot.id) - 60 * MINUTE))
        .where('pickupSlot', '<', String(Date.parse(slot.end))).limit(2001));
      if (existing.size > 2000 || overlapping(existing.docs, slot) >= c.capacity) throw Error('ช่วงเวลานี้เต็มแล้ว กรุณาเลือกช่วงอื่น');
      pickup = { pickupMode: pickupMode === 'asap' ? 'asap' : 'scheduled', pickupSlot: slot.id,
        pickupStartAt: new Date(slot.start), pickupEndAt: new Date(slot.end), pickupLabel: slot.label, pickupTimezone: 'Asia/Bangkok' };
      tx.set(lock, { revision: Number(previous.data()?.revision || 0) + 1 });
    } else {
      if (requestedSlot) throw Error('ร้านปิดการนัดรับล่วงหน้า กรุณาเลือกใหม่');
      pickup = { pickupMode: 'asap' };
    }
    tx.create(orderRef, { ...order, ...pickup });
    return { ...pickup, total: order.total, finalAmount: order.finalAmount };
  });
}
module.exports = { config, slots, availability, createWithPickup };
