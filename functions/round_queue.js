'use strict';

// Display-only queue. Financial receipt IDs and payment idempotency never use it.
const fields = value => value?.queueNumber && value?.queueSessionId && ['online','takeaway'].includes(value.queueChannel)
  ? {queueNumber:value.queueNumber,queueChannel:value.queueChannel,queueSessionId:value.queueSessionId} : {};
const millis = value => value?.toMillis?.() ?? (value instanceof Date ? +value : null);
function onlineChannel(order, now=Date.now()) {
  if (order.tableName || order.tableId || order.orderType==='dineInPrepaid' || order.pickupMode==='scheduled') return null;
  const pickup=millis(order.pickupStartAt);
  const day=value=>Math.floor((value+7*3600000)/86400000);
  return pickup!==null && day(pickup)>day(now) ? null : 'online';
}
function label(value) {
  if (value?.tableName) return `โต๊ะ ${value.tableName}`;
  const q=fields(value);
  return q.queueNumber ? `${q.queueChannel==='online'?'ออนไลน์':'กลับบ้าน'} ${q.queueNumber}` : null;
}
async function prepare(tx, shop, channel, {existing, context, occurredAt}={}) {
  const saved=fields(existing);
  if (saved.queueNumber) return {fields:saved,write:()=>{}};
  if (!['online','takeaway'].includes(channel)) return {fields:{},write:()=>{}};
  context ??= await require('./money_ledger').ledgerContext(tx,shop);
  if (!context.sessionId || (millis(occurredAt)!==null && millis(context.openedAt)!==null && millis(occurredAt)<millis(context.openedAt)))
    return {fields:{},write:()=>{}};
  const session=(await tx.get(shop.collection('cashSessions').doc(context.sessionId))).data();
  if (session?.status!=='open') return {fields:{},write:()=>{}};
  const ref=shop.collection('counters').doc(`queue-${context.sessionId}-${channel}`);
  const previous=(await tx.get(ref)).data()?.seq ?? 0;
  if (!Number.isSafeInteger(previous)||previous<0||previous>=Number.MAX_SAFE_INTEGER-1) throw Error('Invalid round queue counter');
  const seq=previous+1;
  return {fields:{queueNumber:String(seq).padStart(3,'0'),queueChannel:channel,queueSessionId:context.sessionId},
    write:()=>tx.set(ref,{seq,sessionId:context.sessionId,channel})};
}
module.exports={prepare,fields,label,onlineChannel};
