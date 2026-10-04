// Deterministic accounting; the language model never calculates report totals.
const DAY = 86400000;
const money = n => Math.round(Number(n) * 100);
const amount = n => n / 100;
const date = v => v?.toDate ? v.toDate() : new Date(v);
const formatters = new Map();
const fmt = zone => {
  if (formatters.has(zone)) return formatters.get(zone);
  const formatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', hourCycle: 'h23', minute: '2-digit', second: '2-digit',
  });
  formatters.set(zone, formatter);
  return formatter;
};
function parts(value, zone) {
  return Object.fromEntries(fmt(zone).formatToParts(date(value)).map(p => [p.type, p.value]));
}
function key(value, zone) {
  const p = parts(value, zone); return `${p.year}-${p.month}-${p.day}`;
}
function shift(day, count) { return new Date(Date.parse(day) + count * DAY).toISOString().slice(0, 10); }
function midnight(day, zone) {
  const target = Date.parse(day); let guess = target;
  for (let i = 0; i < 4; i++) {
    const p = parts(guess, zone);
    const local = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second);
    guess += target - local;
  }
  return new Date(guess);
}
function windowFor(days, zone, now = new Date()) {
  if (![7, 30, 90].includes(days)) throw new Error('เลือกช่วง 7, 30 หรือ 90 วัน');
  const today = key(now, zone), start = shift(today, -days), previous = shift(start, -days);
  return { days, zone, today, start, previous, from: midnight(previous, zone),
    currentFrom: midnight(start, zone), to: midnight(today, zone), now };
}
function allocate(total, weights) {
  const sum = weights.reduce((a, b) => a + b, 0);
  if (!sum) return weights.map(() => 0);
  const rows = weights.map((w, i) => ({ i, value: Math.floor(total * w / sum), remainder: total * w % sum }));
  let left = total - rows.reduce((s, r) => s + r.value, 0);
  for (const r of [...rows].sort((a, b) => b.remainder - a.remainder || a.i - b.i)) {
    if (left-- > 0) r.value++;
  }
  return rows.map(r => r.value);
}
function knownCost(item) {
  // Legacy zero means either no cost supplied or a real zero: never guess.
  return (item.costKnown === true || (item.costKnown == null && Number(item.costPrice) > 0)) &&
    Number.isFinite(Number(item.costPrice)) && Number(item.costPrice) >= 0 &&
    (item.modifiers || []).every(m => typeof m.costAdjust === 'number' && Number.isFinite(m.costAdjust) && m.costAdjust >= 0);
}
function unitCost(item) { return Number(item.costPrice) + (item.modifiers || []).reduce((s, m) => s + m.costAdjust, 0); }
function normalizeOrders(sales, orders) {
  // Financial totals use the same sale records as POS reports. Orphans require reconciliation.
  return sales.map(s => ({ ...s, source: 'sales' }));
}
function summarize(records, fromDay, toDay, zone) {
  const products = new Map(), categories = new Map(), hours = new Map(), daily = new Map();
  let gross = 0, refunds = 0, discount = 0, service = 0, adjustment = 0,
    net = 0, cost = 0, knownRevenue = 0, units = 0, knownUnits = 0, count = 0,
    invalid = 0, unknownCategory = 0, estimatedPaidAt = 0;
  const sources = [];
  for (const s of records) {
    const at = date(s.createdAt); if (!Number.isFinite(at.getTime())) { invalid++; continue; }
    const day = key(at, zone); if (day < fromDay || day >= toDay) continue;
    const lines = s.items || [], total = money(s.total), cut = money(s.discount || 0), fee = money(s.serviceCharge || 0);
    if (![total, cut, fee].every(Number.isSafeInteger) || total < 0 || cut < 0 || fee < 0 ||
      !lines.length || lines.some(i => !Number.isInteger(i.quantity) || i.quantity <= 0 ||
        !Number.isFinite(Number(i.subtotal)) || Number(i.subtotal) < 0)) { invalid++; continue; }
    const weights = lines.map(i => money(i.subtotal)), subtotal = weights.reduce((a, b) => a + b, 0);
    if (cut > subtotal) { invalid++; continue; }
    gross += total + cut; discount += cut;
    if (s.isRefunded) refunds += total;
    sources.push({ id: s.id, source: s.source || 'sales', receipt: s.receiptNo || s.id,
      at: at.toISOString(), day, time: `${parts(at, zone).hour}:${parts(at, zone).minute}`,
      total: amount(total), refunded: s.isRefunded === true,
      items: lines.map(i => ({ name: String(i.productName || 'ไม่ระบุ'), quantity: i.quantity,
        subtotal: Number(i.subtotal), cost: knownCost(i) ? unitCost(i) : null })) });
    if (s.estimatedPaidAt) estimatedPaidAt++;
    if (s.isRefunded) continue;
    count++; net += total; service += fee; adjustment += total - (subtotal - cut + fee);
    const cuts = allocate(cut, weights);
    daily.set(day, (daily.get(day) || 0) + total);
    const hour = parts(at, zone).hour;
    hours.set(hour, (hours.get(hour) || 0) + total);
    lines.forEach((item, index) => {
      const revenue = weights[index] - cuts[index], known = knownCost(item);
      const cogs = known ? money(unitCost(item)) * item.quantity : 0;
      cost += cogs; units += item.quantity;
      if (known) { knownUnits += item.quantity; knownRevenue += revenue; }
      const category = item.category || 'ไม่ทราบหมวดหมู่ ณ เวลาขาย';
      if (!item.category) unknownCategory++;
      const id = item.productId || item.productName || 'unknown';
      const row = products.get(id) || { id, name: item.productName || id, units: 0, net: 0, cost: 0, knownUnits: 0 };
      row.units += item.quantity; row.net += revenue; row.cost += cogs;
      if (known) row.knownUnits += item.quantity;
      products.set(id, row);
      categories.set(category, (categories.get(category) || 0) + revenue);
    });
  }
  return { from: fromDay, through: shift(toDay, -1), gross: amount(gross), discount: amount(discount),
    refunds: amount(refunds), net: amount(net), count, average: count ? amount(Math.round(net / count)) : null,
    service: amount(service), adjustment: amount(adjustment), units, knownUnits,
    costCoverage: units ? Math.round(knownUnits / units * 1000) / 10 : null,
    grossProfit: units && units === knownUnits ? amount(knownRevenue - cost) : null,
    partialProfit: amount(knownRevenue - cost), knownCost: amount(cost), invalid, unknownCategory, estimatedPaidAt,
    products: [...products.values()].map(r => ({ ...r, net: amount(r.net), cost: amount(r.cost),
      profit: r.units === r.knownUnits ? amount(r.net - r.cost) : null })).sort((a, b) => b.net - a.net),
    categories: [...categories].map(([name, n]) => ({ name, net: amount(n) })).sort((a, b) => b.net - a.net),
    hours: [...hours].map(([hour, n]) => ({ hour, net: amount(n) })).sort((a, b) => b.net - a.net),
    daily: Array.from({ length: Math.round((Date.parse(toDay) - Date.parse(fromDay)) / DAY) }, (_, i) => {
      const day = shift(fromDay, i); return { day, net: amount(daily.get(day) || 0) };
    }), sources: sources.sort((a, b) => b.at.localeCompare(a.at)) };
}
function buildAnalysis({ sales, orders = [], events = [], settings = {}, days = 30, now = new Date() }) {
  const zone = settings.timeZone || 'Asia/Bangkok';
  const w = windowFor(days, zone, now), records = normalizeOrders(sales, orders);
  const current = summarize(records, w.start, w.today, zone);
  const previous = summarize(records, w.previous, w.start, zone);
  const today = summarize(records, w.today, shift(w.today, 1), zone);
  const ids = new Set([...current.products, ...previous.products].map(p => p.id));
  const currentProducts = new Map(current.products.map(p => [p.id, p]));
  const previousProducts = new Map(previous.products.map(p => [p.id, p]));
  const changes = [...ids].map(id => {
    const c = currentProducts.get(id), p = previousProducts.get(id);
    return { id, name: c?.name || p.name, current: c?.net || 0, previous: p?.net || 0,
      difference: amount(money(c?.net || 0) - money(p?.net || 0)) };
  }).sort((a, b) => a.difference - b.difference);
  return { generatedAt: now.toISOString(), timeZone: zone, days, current, previous, today,
    change: amount(money(current.net) - money(previous.net)),
    changePercent: previous.net ? Math.round((current.net / previous.net - 1) * 1000) / 10 : null,
    productChanges: changes, events,
    unlinkedPaidOrderCount: orders.filter(o => ['paid','accepted','ready','completed'].includes(o.status) && !sales.some(s => s.orderId === o.id)).length,
    settings: { timeZone: zone, openWeekdays: settings.openWeekdays || [], configured: !!settings.timeZone },
    notes: [
      'เปรียบเทียบวันปฏิทินที่จบแล้ว ไม่รวมวันนี้; ช่วง 30/90 วันอาจมีจำนวนวันในสัปดาห์ต่างกัน',
      'ยอดสุทธิ = ยอดก่อนส่วนลด − ส่วนลด − บิลคืนเงิน; รวมค่าบริการและยอดปรับเศษสตางค์',
      'คืนเงินหักกลับจากช่วงวันที่ขายตามสถานะล่าสุด ไม่ใช่รายงานกระแสเงินสดวันคืนเงิน; รวมขายเชื่อ',
      'กำไรขั้นต้นหักส่วนลดตามสัดส่วนสินค้า ไม่รวมค่าบริการ/เศษสตางค์ ค่าเช่า ค่าแรง ภาษี หรือค่าใช้จ่ายอื่น',
      'ต้นทุนศูนย์ในบิลเก่าและรายการตัวเลือกอาหารที่ไม่มีต้นทุนแยกถือว่าต้นทุนไม่ครบ ไม่ใช้ต้นทุนปัจจุบันแทนอดีต',
      'นับเฉพาะบิลขายที่บันทึกแล้วเหมือนหน้ารายงาน; ออเดอร์เก่าที่จ่ายแล้วแต่ไม่มีบิลขายต้องตรวจสอบแยก',
      'วันไม่มียอดไม่ได้แปลว่าปิดร้าน; บันทึกบริบทและวันเปิดเป็นข้อมูลประกอบ ไม่ยืนยันสาเหตุของยอดที่เปลี่ยน',
      'ประวัติสินค้าหมดและการเปลี่ยนโปรโมชันอัตโนมัติเริ่มหลังเปิดใช้ฟีเจอร์ ไม่มีประวัติไม่ได้แปลว่าไม่เคยเกิด',
    ] };
}
function promptData(report) {
  const compact = p => ({ ...p, sources: undefined, products: p.products.slice(0, 25),
    categories: p.categories.slice(0, 20), daily: p.daily, hours: p.hours });
  return { ...report, current: compact(report.current), previous: compact(report.previous), today: compact(report.today),
    inventory: report.inventory ? { ...report.inventory, lowStock: report.inventory.lowStock.slice(0, 50), scope: 'สินค้าใกล้หมดปัจจุบันไม่เกิน 50 รายการ ไม่รวมสต็อกตามสูตรวัตถุดิบ ไม่ใช่ประวัติย้อนหลัง' } : undefined,
    productChanges: report.productChanges.slice(0, 15).concat(report.productChanges.slice(-15)),
    events: report.events.slice(0, 50),
    scope: 'สินค้าแสดงอันดับแรก 25 รายการและการเปลี่ยนแปลงหัว/ท้าย 15 รายการ; บริบทล่าสุดไม่เกิน 50 รายการ ข้อมูลเต็มอยู่ในรายงาน ห้ามอ้างว่ารายการที่ไม่อยู่ในชุดย่อยไม่เคยขาย' };
}
module.exports = { windowFor, buildAnalysis, promptData, normalizeOrders, allocate, knownCost, key, midnight };
