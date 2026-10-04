'use strict';
const { Jimp } = require('jimp');
const { randomUUID } = require('node:crypto');
const MAX_BYTES = 5 * 1024 * 1024;
const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);

class SlipError extends Error {
  constructor(status, code, message) { super(message); this.status=status; this.code=code; }
}

async function decodeSlip(input) {
  if (typeof input !== 'string') throw new SlipError(400,'invalid_image','กรุณาเลือกรูปสลิป');
  if (input.length > Math.ceil(MAX_BYTES / 3) * 4 + 100) {
    throw new SlipError(413,'image_too_large','รูปสลิปใหญ่เกิน 5 MB กรุณาย่อรูปแล้วลองใหม่');
  }
  const raw = input.replace(/^data:image\/jpeg;base64,/, '');
  if (!raw.length || raw.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(raw)) {
    throw new SlipError(400,'invalid_image','อ่านรูปสลิปไม่ได้ กรุณาใช้รูป JPG หรือ PNG จากแกลเลอรี');
  }
  const bytes = Buffer.from(raw,'base64');
  if (bytes.length > MAX_BYTES) throw new SlipError(413,'image_too_large','รูปสลิปใหญ่เกิน 5 MB กรุณาย่อรูปแล้วลองใหม่');
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) {
    throw new SlipError(400,'invalid_image','รูปสลิปไม่ถูกต้อง กรุณาเลือกรูปใหม่');
  }
  try {
    // Jimp 1.x exports a class, not a top-level read function. fromBuffer
    // forwards decoder limits (read(Buffer) in 1.6 does not forward options).
    await Jimp.fromBuffer(bytes, {'image/jpeg': {maxResolutionInMP:8,maxMemoryUsageInMB:64}});
  } catch (_) {
    throw new SlipError(400,'invalid_image','อ่านรูปสลิปไม่ได้ กรุณาใช้รูปที่ชัดเจนหรือย่อรูปแล้วลองใหม่');
  }
  return bytes;
}

function createSlipUpload({db, getBucket, FieldValue, verifyAppCheck, logger=console}) {
  return async (req,res) => {
    res.set('Access-Control-Allow-Origin','*');
    res.set('Access-Control-Allow-Methods','POST, OPTIONS');
    res.set('Access-Control-Allow-Headers','Content-Type, X-Firebase-AppCheck');
    res.set('X-Content-Type-Options','nosniff');
    res.set('X-Pokpok-Slip-Version','2');
    if (req.method === 'OPTIONS') return res.status(204).send('');
    if (req.method !== 'POST') return res.status(405).json({error:'Method Not Allowed'});
    if (!(await verifyAppCheck(req,res))) return;
    const {shopId,orderId,slipBase64}=req.body || {};
    if (!validId(shopId) || !validId(orderId)) return res.status(400).json({error:'invalid_order',reason:'ลิงก์ออเดอร์ไม่ถูกต้อง'});
    let stage='readOrder', uploadedFile, attached=false;
    try {
      const ref=db.collection('shops').doc(shopId).collection('orders').doc(orderId);
      const order=await ref.get();
      if (!order.exists) throw new SlipError(404,'order_not_found','ไม่พบออเดอร์นี้ กรุณาติดต่อร้าน');
      if (order.data().status !== 'pendingPayment') throw new SlipError(409,'order_processed','ออเดอร์นี้ดำเนินการแล้ว กรุณาตรวจสอบกับร้านก่อนส่งสลิปซ้ำ');
      stage='decodeImage';
      const bytes=await decodeSlip(slipBase64);
      stage='saveImage';
      const bucket=getBucket();
      const token=randomUUID();
      // Unique object per attempt: never overwrite evidence already attached
      // to a paid order if confirmation races with another upload.
      const file=bucket.file(`shops/${shopId}/orderSlips/${orderId}/${randomUUID()}.jpg`);
      await file.save(bytes,{resumable:false,metadata:{contentType:'image/jpeg',
        cacheControl:'private, max-age=3600',metadata:{firebaseStorageDownloadTokens:token}}});
      uploadedFile=file;
      const slipUrl=`https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucket.name)}/o/${encodeURIComponent(file.name)}?alt=media&token=${token}`;
      stage='attachOrder';
      attached=await db.runTransaction(async tx=>{
        const latest=await tx.get(ref);
        if (!latest.exists || latest.data().status !== 'pendingPayment') return false;
        tx.update(ref,{slipUrl,slipReviewStatus:'awaitingOwner',slipSubmittedAt:FieldValue.serverTimestamp()});
        return true;
      });
      if (!attached) throw new SlipError(409,'order_processed','สถานะออเดอร์เปลี่ยนแล้ว กรุณาตรวจสอบกับร้าน');
      return res.json({success:true,awaitingReview:true});
    } catch (error) {
      // Only delete after a confirmed state conflict. A lost database response
      // may still have committed the URL, so preserve evidence on unknown errors.
      if (uploadedFile && error instanceof SlipError && error.code === 'order_processed') {
        await uploadedFile.delete().catch(()=>{});
      }
      if (error instanceof SlipError) return res.status(error.status).json({success:false,error:error.code,reason:error.message});
      // No image data, customer identity, bearer URLs or raw provider message.
      logger.error('slip_upload_failed',{stage,code:String(error.code || error.name || 'unknown').slice(0,60)});
      return res.status(503).json({success:false,error:'slip_upload_unavailable',
        reason:'ระบบรับสลิปขัดข้องชั่วคราว กรุณาลองอีกครั้ง หรือติดต่อร้านพร้อมเลขออเดอร์ โดยไม่ต้องโอนซ้ำ'});
    }
  };
}
module.exports={createSlipUpload,decodeSlip,MAX_BYTES};
