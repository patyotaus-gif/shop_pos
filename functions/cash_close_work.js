'use strict';
const LIMIT=10000, DAY=86400000, TH_OFFSET=7*3600000;
const millis=value=>value?.toMillis?.() ?? (value instanceof Date?value.getTime():typeof value==='number'?value:NaN);

// Operational readiness is independent of when accounting was activated.
// Old unresolved work must not disappear merely because a new round was opened.
async function inspectOpenWork(tx,shop,{now=Date.now()}={}) {
  const [orders,tables]=await Promise.all([
    tx.get(shop.collection('orders').where('status','in',['pendingPayment','paid','accepted','ready']).limit(LIMIT+1)),
    tx.get(shop.collection('tableOrders').where('status','==','open').limit(LIMIT+1)),
  ]);
  const issues=[];
  if(orders.size>LIMIT||tables.size>LIMIT)issues.push({type:'tooManyRecords',id:''});
  const tomorrow=Math.floor((now+TH_OFFSET)/DAY)*DAY-TH_OFFSET+DAY;
  let pendingOrderCount=0,unfinishedOrderCount=0,futureOrderCount=0;
  for(const row of orders.docs.slice(0,LIMIT)) {
    const o=row.data(), unpaid=o.status==='pendingPayment';
    if(unpaid)pendingOrderCount++;
    const pickupAt=millis(o.pickupStartAt);
    const future=o.pickupMode==='scheduled'&&Number.isFinite(pickupAt)&&pickupAt>=tomorrow;
    if(future)futureOrderCount++;
    const detail={id:row.id,label:String(o.customerName||o.tableName||row.id).slice(0,100)};
    if(unpaid&&(o.slipReviewStatus==='awaitingOwner'||o.slipUrl||o.bankMatchStatus==='awaitingOwner'))
      issues.push({type:'unreviewedPayment',...detail});
    else if(!future) {
      if(!unpaid)unfinishedOrderCount++;
      issues.push({type:unpaid?'pendingOrder':'unfinishedOrder',...detail});
    }
  }
  for(const row of tables.docs.slice(0,LIMIT))
    issues.push({type:'openTable',id:row.id,label:String(row.data().tableName||row.id).slice(0,100)});
  return {issues,pendingOrderCount,unfinishedOrderCount,openTableCount:Math.min(tables.size,LIMIT),futureOrderCount};
}
module.exports={inspectOpenWork};
