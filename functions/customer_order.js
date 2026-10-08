'use strict';
const {createHash, timingSafeEqual} = require('node:crypto');
const tokenHash = token => createHash('sha256').update(token).digest('hex');
const validToken = token => typeof token === 'string' && /^[a-f0-9]{64}$/i.test(token);
const authorized = (order, token) => validToken(token) && typeof order.customerTokenHash === 'string'
  && /^[a-f0-9]{64}$/i.test(order.customerTokenHash)
  && timingSafeEqual(Buffer.from(order.customerTokenHash),Buffer.from(tokenHash(token)));
const validId = id => typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id);
function normalizePhone(value) {
  if (typeof value !== 'string' || !/^[+\d\s().-]+$/.test(value)) return null;
  const p = value.replace(/[\s().-]/g,'');
  return /^(?:0\d{8,9}|\+[1-9]\d{7,14})$/.test(p) ? p : null;
}
function handler({db, FieldValue, verifyAppCheck}) {
  return async (req,res) => {
    res.set('Access-Control-Allow-Origin','*');
    res.set('Access-Control-Allow-Methods','POST, OPTIONS');
    res.set('Access-Control-Allow-Headers','Content-Type, X-Firebase-AppCheck');
    res.set('Cache-Control','no-store');
    if(req.method==='OPTIONS') return res.status(204).send('');
    if(req.method!=='POST') return res.status(405).json({error:'Method Not Allowed'});
    if(!await verifyAppCheck(req,res)) return;
    const {shopId,orderId,customerToken,action} = req.body || {};
    if(!validId(shopId)||!validId(orderId)||!['status','cancel'].includes(action)) return res.status(400).json({error:'ข้อมูลออเดอร์ไม่ถูกต้อง'});
    try {
      const shop=db.collection('shops').doc(shopId), ref=shop.collection('orders').doc(orderId);
      const result=await db.runTransaction(async tx=>{
        const snap=await tx.get(ref), o=snap.data();
        if(!o || !authorized(o,customerToken)) throw Object.assign(Error('ไม่พบสิทธิ์เปิดออเดอร์นี้ กรุณาติดต่อร้าน'),{status:403});
        const settings=(await tx.get(shop.collection('settings').doc('shop'))).data() || {};
        let status=o.status;
        if(action==='cancel' && status!=='cancelled') {
          if(status!=='pendingPayment' || o.paidAt || o.saleId || o.slipUrl || o.slipSubmittedAt || o.bankMatchStatus || o.bankMatchAt || o.autoConfirmed || o.paymentRef || o.stripeSessionId)
            throw Object.assign(Error('ออเดอร์มีข้อมูลการชำระแล้ว กรุณาติดต่อร้านเพื่อตรวจสอบ โดยไม่ต้องโอนซ้ำ'),{status:409});
          status='cancelled';
          const release=await require('./order_inventory').prepareRelease(tx,shop,o);
          release();
          tx.update(ref,{status,cancelReason:'ลูกค้ายืนยันว่ายังไม่ได้โอนและยกเลิก',statusUpdatedAt:FieldValue.serverTimestamp(),statusUpdatedBy:'customer'});
        }
        return {orderId,status,total:o.total,finalAmount:o.finalAmount ?? o.total,
          pickupLabel:o.pickupLabel || null,awaitingReview:!!o.slipUrl || !!o.bankMatchStatus,
          promptpayId:o.promptpayIdSnapshot || settings.promptpayId,
          promptpayName:o.promptpayNameSnapshot ?? settings.promptpayName ?? ''};
      });
      return res.json(result);
    } catch(e) {return res.status(e.status || 503).json({error:e.status?e.message:'ตรวจสถานะไม่ได้ กรุณาลองใหม่ โดยไม่ต้องโอนซ้ำ'});}
  };
}
module.exports={tokenHash,validToken,authorized,normalizePhone,handler};
