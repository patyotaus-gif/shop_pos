'use strict';
const round = n => Math.round(n * 1000) / 1000;
const valid = (n, weighed = false, zero = false) => typeof n === 'number' && Number.isFinite(n) && n >= (zero ? 0 : 0.001) && n <= 100000000 && (weighed ? Math.abs(n * 1000 - Math.round(n * 1000)) < 1e-6 : Number.isInteger(n));
const today = () => new Date(Date.now() + 7 * 3600000).toISOString().slice(0, 10);
function lotsOf(p) {
  const lots = (p.stockLots || []).map(l => ({...l}));
  const ids = new Set();
  for (const l of lots) {
    if (!l.id || ids.has(l.id) || !l.number || !/^\d{4}-\d{2}-\d{2}$/.test(l.expiresOn) ||
        !Number.isFinite(Date.parse(l.expiresOn)) || new Date(l.expiresOn).toISOString().slice(0,10)!==l.expiresOn || !valid(l.quantity,true,true)) throw Error('ข้อมูลล็อตไม่ครบ กรุณาตรวจสต๊อก');
    ids.add(l.id);
  }
  if (Math.abs(lots.reduce((s,l)=>s+l.quantity,0)-Number(p.stock||0))>1e-6) throw Error('จำนวนล็อตไม่ตรงกับสต๊อก กรุณาตรวจสอบ');
  return lots;
}
function available(p, day=today()) {
  if (!p.trackLots) {
    const n=Number(p.stock||0);
    if(!Number.isFinite(n))throw Error('จำนวนสต๊อกไม่ถูกต้อง');
    return n;
  }
  return round(lotsOf(p).reduce((s,l)=>s+(l.expiresOn>=day?l.quantity:0),0));
}
function allocate(p,q,day=today()) {
  if (!valid(q,p.isWeighed===true)) throw Error('จำนวนสินค้าไม่ถูกต้อง');
  if (!p.trackLots) return {stock:round(available(p)-q),used:[]};
  const lots=lotsOf(p).sort((a,b)=>`${a.expiresOn}:${a.id}`.localeCompare(`${b.expiresOn}:${b.id}`)),used=[];
  let left=q;
  for(const l of lots) {
    if(l.expiresOn<day || left<=0)continue;
    const take=Math.min(l.quantity,left);
    if(take<=0)continue;
    used.push({...l,quantity:take});l.quantity=round(l.quantity-take);left=round(left-take);
  }
  if(left>0)throw Error('ล็อตที่ยังไม่หมดอายุมีไม่พอ');
  return {stock:round(Number(p.stock||0)-q),stockLots:lots,used};
}
function restore(p,q,used) {
  const update={stock:round(Number(p.stock||0)+q)};
  if(!p.trackLots)return update;
  const lots=lotsOf(p);
  if(!Array.isArray(used)||Math.abs(used.reduce((s,l)=>s+Number(l.quantity||0),0)-q)>1e-6)throw Error('ไม่มีประวัติล็อตเดิม กรุณาคืนเงินโดยไม่คืนสต๊อกแล้วตรวจนับแยก');
  for(const row of used) {
    const l=lots.find(l=>l.id===row.id);
    if(l) {
      if(l.number!==row.number||l.expiresOn!==row.expiresOn)throw Error('ข้อมูลล็อตเปลี่ยน กรุณาตรวจสต๊อก');
      l.quantity=round(l.quantity+row.quantity);
    } else lots.push({...row});
  }
  update.stockLots=lots;lotsOf({...p,...update});return update;
}
function write(tx,ref,p,update,{id,kind='sale',actor,referenceId,reason=''},FieldValue) {
  const {used,...data}=update;
  tx.update(ref,{...data,stockRevision:Number(p.stockRevision||0)+1});
  tx.set(ref.collection('stockMovements').doc(id),{kind,delta:round(data.stock-Number(p.stock||0)),before:Number(p.stock||0),after:data.stock,unit:p.unit||'ชิ้น',actor:actor||'',referenceId:referenceId||'',reason,createdAt:FieldValue.serverTimestamp(),...(used?.length?{lots:used}:{})});
}
module.exports={round,valid,today,lotsOf,available,allocate,restore,write};
