import {apiFetch, shopId, fmtBaht} from './util.js?v=20261013stock';
import {items, total, onCartChange} from './cart.js?v=20261013stock';
let ready = null, revision = 0, quoteError = '';
const lines = () => items().map(i=>({productId:i.id,quantity:i.quantity,optionIds:i.optionIds || [],...(i.notes ? {notes:i.notes} : {})}));
const fingerprint = () => JSON.stringify(lines());
const status = () => document.getElementById('giftStatus');
function setPaymentAvailable(available, issue = '') {
  document.getElementById('checkoutActions').disabled = !available;
  const hint = document.getElementById('checkoutIssue');
  hint.textContent = issue;
  hint.hidden = !issue;
}
export function giftText(gifts) {
  return (gifts || []).map(g=>`ของแถม: ${g.productName} × ${g.quantity} (ฟรี)`).join('\n');
}
export function bundleText(bundles) {
  return (bundles || []).map(b=>`${b.name} × ${b.sets} ชุด • ลด ${fmtBaht(b.discountMinor/100)}`).join('\n');
}
export function promotionTotal() {
  return total()-(ready?.cart===fingerprint()?ready.discount:0);
}
export function giftPayload() {
  if (quoteError) throw Error(quoteError);
  if (!ready || ready.cart!==fingerprint()) throw Error('กรุณาตรวจของแถมก่อนชำระเงิน');
  return {buyGetQuote:ready.gifts,bundleQuote:ready.bundles};
}
export async function refreshGifts() {
  ready=null;
  quoteError='';
  setPaymentAvailable(false);
  document.dispatchEvent(new Event('promotionsChanged'));
  const current=++revision, cart=fingerprint();
  status().textContent='กำลังตรวจชุดสินค้าและของแถม…';
  try {
    const response=await apiFetch('/api/createPromptPayOrder',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({shopId,action:'quoteGifts',items:lines()})});
    const data=await response.json();
    if (current!==revision || cart!==fingerprint()) return;
    if (!response.ok || !Array.isArray(data.buyGet)) throw Error(data.error || 'ตรวจของแถมไม่สำเร็จ กรุณาลองอีกครั้ง');
    const bundles=data.bundles || [];
    ready={cart,gifts:data.buyGet,bundles,discount:bundles.reduce((s,b)=>s+b.discountMinor,0)/100};
    setPaymentAvailable(true);
    status().textContent=[bundleText(bundles),giftText(data.buyGet)].filter(Boolean).join('\n') || 'ตะกร้านี้ไม่มีของแถมหรือส่วนลดชุดสินค้า';
    document.dispatchEvent(new Event('promotionsChanged'));
  } catch(error) {
    if (current===revision) {
      quoteError = error.name === 'TypeError' || error.name === 'SyntaxError'
        ? 'ตรวจข้อมูลการชำระเงินไม่ได้ กรุณาตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง'
        : error.message || 'ตรวจข้อมูลการชำระเงินไม่ได้ กรุณาลองอีกครั้ง';
      status().textContent = '';
      setPaymentAvailable(false, quoteError);
    }
  }
}
export function initBuyGet() {
  document.getElementById('giftRefresh').addEventListener('click',refreshGifts);
  onCartChange(()=>{
    ++revision;ready=null;quoteError='';
    setPaymentAvailable(false);
    status().textContent='ตะกร้าเปลี่ยนแล้ว กรุณาตรวจของแถมอีกครั้ง';
  });
}
