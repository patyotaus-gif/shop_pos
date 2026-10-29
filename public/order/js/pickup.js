import { apiFetch, shopId, orderContext } from './util.js?v=20261013stock';
import { pickupParts, pickupDays, slotsForDate } from './order-display.mjs';

let options = [];
let enabled = false;
let loading = false;
let failed = false;
export async function refreshPickup() {
  const field = document.getElementById('pickupFields');
  const select = document.getElementById('pickupSlot');
  const mode = document.getElementById('pickupMode');
  const hint = document.getElementById('pickupHint');
  const table = !!orderContext.table;
  field.hidden = table;
  if (table) return;
  loading = true; failed = false; select.disabled = true;
  hint.textContent = 'กำลังตรวจช่วงเวลารับ...';
  const previous = select.value;
  try {
    const response = await apiFetch(`/api/shopPublic?shop=${encodeURIComponent(shopId)}`);
    if (!response.ok) throw Error('load');
    const data = await response.json();
    if (data.ordersClosed) throw Error('closed');
    enabled = data.pickup?.enabled === true;
    options = data.pickup?.slots || [];
    mode.disabled = !enabled;
    if (!enabled) mode.value = 'asap';
    const date = document.getElementById('pickupDate');
    const oldDate = date.value;
    date.replaceChildren();
    for (const day of pickupDays(options)) date.add(new Option(day, day));
    const previousSlot = options.find(s => s.id === previous);
    const wantedDate = previousSlot ? pickupParts(previousSlot.label).date : oldDate;
    if (pickupDays(options).includes(wantedDate)) date.value = wantedDate;
    fillTimes(previous);
    hint.textContent = enabled
      ? options.length ? 'เวลาประเทศไทย • ช่วงเวลาจะจองเมื่อสร้างออเดอร์' : 'ไม่มีช่วงเวลาว่างใน 7 วันนี้ กรุณาติดต่อร้าน'
      : 'ร้านยังไม่เปิดนัดรับล่วงหน้า กรุณารอร้านแจ้งเมื่อพร้อมรับ';
  } catch (_) {
    failed = true;
    hint.textContent = 'ตรวจเวลารับไม่ได้ กรุณากดตรวจช่วงเวลาอีกครั้ง';
  } finally {
    loading = false;
    updateSelect();
  }
}
function updateSelect() {
  const select = document.getElementById('pickupSlot');
  const date = document.getElementById('pickupDate');
  const asap = document.getElementById('pickupMode').value === 'asap';
  select.hidden = !enabled;
  select.disabled = loading || failed || asap;
  date.hidden = !enabled;
  date.disabled = loading || failed || asap;
  document.getElementById('pickupDateLabel').hidden = !enabled;
  document.getElementById('pickupTimeLabel').hidden = !enabled;
  if (asap && options.length) {
    date.value = pickupParts(options[0].label).date;
    fillTimes(options[0].id);
  }
}
function fillTimes(previous) {
  const select = document.getElementById('pickupSlot');
  const daySlots = slotsForDate(options, document.getElementById('pickupDate').value);
  select.replaceChildren();
  for (const slot of daySlots) select.add(new Option(pickupParts(slot.label).time, slot.id));
  if (daySlots.some(s => s.id === previous)) select.value = previous;
}
export function initPickup() {
  document.getElementById('pickupDate').addEventListener('change', () => fillTimes());
  document.getElementById('pickupMode').addEventListener('change', updateSelect);
  document.getElementById('pickupRefresh').addEventListener('click', refreshPickup);
}
export function pickupPayload() {
  if (orderContext.table) return {};
  if (loading || failed) throw Error('กรุณาตรวจช่วงเวลารับก่อนชำระเงิน');
  if (!enabled) return { pickupMode: 'asap' };
  const id = document.getElementById('pickupSlot').value;
  if (!options.some(s => s.id === id)) throw Error('ไม่มีช่วงเวลาว่าง กรุณาติดต่อร้าน');
  return { pickupMode: document.getElementById('pickupMode').value, pickupSlot: id };
}
