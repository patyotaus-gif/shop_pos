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
