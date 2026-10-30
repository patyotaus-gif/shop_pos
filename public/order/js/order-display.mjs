export function pickupParts(label) {
  const match = /^(\d{2}\/\d{2}\/\d{4})\s+(.+)$/.exec(label || '');
  return match ? {date: match[1], time: match[2]} : {date: '', time: label || ''};
}
export function pickupDescription(label) {
  const {date, time} = pickupParts(label);
  return date ? `วันรับสินค้า: ${date}\nเวลารับ: ${time} (เวลาไทย)` : time;
}
export function pickupDays(slots) {
  return [...new Set(slots.map(s => pickupParts(s.label).date))];
}
export function slotsForDate(slots, date) {
  return slots.filter(s => pickupParts(s.label).date === date);
}
export function orderLabel(order) {
  if (order.tableName) return `โต๊ะ ${order.tableName}`;
  if (order.queueSessionId && /^\d{3,}$/.test(order.queueNumber || '') &&
      ['online','takeaway'].includes(order.queueChannel)) {
    return `${order.queueChannel === 'online' ? 'ออนไลน์' : 'กลับบ้าน'} ${order.queueNumber}`;
  }
  return `เลขออเดอร์ ${order.orderNumber || order.orderId || ''}`;
}
