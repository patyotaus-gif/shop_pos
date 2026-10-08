'use strict';
const {createHash,randomUUID}=require('node:crypto');
const {owner,validId}=require('./order_accounting');
function linesFor(source, order) {
  return (order.items || []).flatMap((i,index)=>{
    if(source==='table' && !['sent','ready'].includes(i.kitchenStatus))return [];
    const note=[...(i.modifiers||[]).map(m=>m.optionName||''),i.notes||i.preparationNote||''].filter(Boolean).join(' • ');
    const key=createHash('sha256').update(JSON.stringify([i.id||String(index),i.productName,i.quantity,note])).digest('hex');
    return [{key,name:String(i.productName||''),quantity:i.quantity,note}];
  });
}
function handlers({db,FieldValue,HttpsError,now=()=>Date.now()}) {
  return {
    claim:async request=>{
      const shopId=owner(request,HttpsError), {source,orderId,reprint}=request.data;
      if(!['table','online'].includes(source)||!validId(orderId))throw new HttpsError('invalid-argument','Invalid order');
      const shop=db.collection('shops').doc(shopId), job=shop.collection('kitchenPrintJobs').doc(`${source}-${orderId}`);
      return db.runTransaction(async tx=>{
        const o=(await tx.get(shop.collection(source==='table'?'tableOrders':'orders').doc(orderId))).data();
        const prior=(await tx.get(job)).data() || {};
        if(!o || (source==='table'?!['open','closed'].includes(o.status):!['paid','accepted','ready','completed'].includes(o.status)))
          throw new HttpsError('failed-precondition','ออเดอร์ยังไม่พร้อมส่งครัวหรือถูกยกเลิก');
        if(prior.status==='printing' && (now()-prior.startedAtMs<600000 || reprint!==true))
          throw new HttpsError('failed-precondition','อีกเครื่องกำลังพิมพ์ หรือยังไม่ทราบผล กรุณาตรวจเครื่องพิมพ์ก่อนพิมพ์ซ้ำ');
        const all=linesFor(source,o), printed=prior.printedKeys || [];
        const lines=reprint===true ? all : all.filter(i=>!printed.includes(i.key));
        if(!lines.length) return {alreadyPrinted:true};
        const attempt=randomUUID(), data={source,orderId,attempt,reprint:reprint===true || prior.status==='needsReview',status:'printing',startedAtMs:now(),
          printedKeys:printed,lines,title:source==='table'||o.tableName?`โต๊ะ ${o.tableName}`:'รับกลับบ้าน',
          pickupLabel:o.pickupLabel || '',customerName:o.customerName || '',updatedAt:FieldValue.serverTimestamp()};
        tx.set(job,data);
        return {jobId:job.id,attempt,reprint:data.reprint,lines,title:data.title,pickupLabel:data.pickupLabel,customerName:data.customerName};
      });
    },
    finish:async request=>{
      const shopId=owner(request,HttpsError),{jobId,attempt,received}=request.data;
      if(!validId(jobId)||typeof attempt!=='string'||typeof received!=='boolean')throw new HttpsError('invalid-argument','Invalid print result');
      const ref=db.collection('shops').doc(shopId).collection('kitchenPrintJobs').doc(jobId);
      return db.runTransaction(async tx=>{
        const o=(await tx.get(ref)).data();
        if(!o || o.attempt!==attempt)throw new HttpsError('failed-precondition','งานพิมพ์เปลี่ยนแล้ว กรุณาตรวจสอบ');
        if(o.status==='printed')return {success:true};
        tx.update(ref,{status:received?'printed':'needsReview',
          printedKeys:received?[...new Set([...(o.printedKeys||[]),...o.lines.map(i=>i.key)])]:(o.printedKeys||[]),
          updatedAt:FieldValue.serverTimestamp()});
        return {success:true};
      });
    },
  };
}
module.exports={handlers,linesFor};
