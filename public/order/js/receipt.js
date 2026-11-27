import {findReceipt, isConfirmedPayment, watchCustomerPayment} from './customer-payment.js';
import {pickupDescription, orderLabel} from './order-display.mjs';

const params = new URLSearchParams(location.search);
const orderId = params.get('order');
const reference = findReceipt(orderId);
const heading = document.querySelector('h1');
const description = document.getElementById('description');
const note = document.querySelector('.note');
const orderNumber = document.getElementById('orderNumber');
const pickup = document.getElementById('pickup');
const number = (params.get('number') || orderId || '').slice(0, 128);
const queue = (params.get('queue') || '').slice(0, 128);

function setReference(label, number, pickupLabel) {
  orderNumber.textContent = label || (number ? 'เลขออเดอร์ ' + number : '');
  if (label && number && label !== 'เลขออเดอร์ ' + number) orderNumber.textContent += ' · อ้างอิง ' + number;
  pickup.textContent = pickupDescription(pickupLabel);
}

function show(title, explanation, hint, confirmed = false) {
  document.title = title;
  if (heading.textContent !== title) heading.textContent = title;
  heading.classList.toggle('confirmed', confirmed);
  description.textContent = explanation;
  note.textContent = hint;
}

setReference(queue, number, (params.get('pickup') || '').slice(0, 100));

function showStatus(order) {
  setReference(orderLabel(order), order.orderNumber || order.orderId, order.pickupLabel);
  if (isConfirmedPayment(order.status)) {
    const message = {paid:'เก็บเลขออเดอร์นี้ไว้ติดต่อร้าน', accepted:'ร้านกำลังเตรียมออเดอร์',
      ready:'ออเดอร์พร้อมรับที่ร้าน', completed:'ออเดอร์เสร็จสิ้นแล้ว'};
    show('ร้านยืนยันรับเงินแล้ว', message[order.status], 'ชำระเงินเรียบร้อย ไม่ต้องโอนซ้ำ', true);
  } else if (order.status === 'cancelled') {
    show('ยกเลิกออเดอร์แล้ว', 'หากมีการโอนเงิน กรุณาแจ้งเลขออเดอร์และแสดงสลิปกับร้าน', 'กรุณาติดต่อร้านก่อนทำรายการใหม่');
  } else if (order.status === 'pendingPayment' && order.awaitingReview) {
    show('ส่งสลิปแล้ว รอร้านยืนยัน', 'ร้านได้รับสลิปแล้ว หน้านี้จะอัปเดตเมื่อร้านตรวจยอดเงินเข้า', 'หากโอนเงินแล้ว ไม่ต้องโอนซ้ำ');
  } else {
    show('ร้านยังไม่ได้ยืนยันการชำระเงิน', 'เปิดออเดอร์เดิมจากเมนูร้านเพื่อตรวจสอบขั้นตอนชำระเงิน', 'หากโอนเงินแล้ว เก็บสลิปไว้และไม่ต้องโอนซ้ำ');
  }
}

if (reference) {
  watchCustomerPayment(reference, showStatus, () =>
    show('ยังตรวจสถานะไม่ได้', 'หากต้องการทราบยอดทันที กรุณาแจ้งเลขออเดอร์กับร้าน', 'หากโอนเงินแล้ว ไม่ต้องโอนซ้ำ'));
} else if (params.has('review') || orderId?.startsWith('web-')) {
  show('เปิดสถานะออเดอร์บนเครื่องเดิม', 'เปิดด้วยเบราว์เซอร์ที่ใช้สั่ง หรือแจ้งเลขออเดอร์ให้ร้านตรวจสอบ', 'หากโอนเงินแล้ว ไม่ต้องโอนซ้ำ');
} else {
  // Legacy hosted checkout returns here without an anonymous order credential.
  show('รายละเอียดออเดอร์', 'เก็บเลขออเดอร์ไว้ตรวจสอบการชำระเงินและเวลารับสินค้ากับร้าน', 'หากชำระเงินแล้ว ไม่ต้องชำระซ้ำ');
}
