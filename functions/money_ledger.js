'use strict';
function minor(value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || Math.abs(value) > 1e9) throw new Error('Invalid money amount');
  return Math.round(value * 100);
}
// Read before any transaction writes. Every writer conflicts with session close.
async function ledgerContext(tx, shop) {
  const ref = shop.collection('cashControl').doc('current');
  const snap = await tx.get(ref);
  return { ref, sessionId: snap.data()?.sessionId || null, openedAt: snap.data()?.openedAt || null };
}
function writeMovement(tx, shop, context, id, data, FieldValue) {
  const late=!!(context.openedAt?.toMillis && data.occurredAt?.toMillis && data.occurredAt.toMillis()<context.openedAt.toMillis());
  tx.create(shop.collection('moneyMovements').doc(id), {
    ...data, sessionId: late?null:context.sessionId, needsReconciliation:late||!context.sessionId,
    recordedAt: FieldValue.serverTimestamp(), schemaVersion: 1,
  });
  tx.set(context.ref, { sessionId: context.sessionId, revision: FieldValue.increment(1) }, { merge: true });
}
function saleMovement(sale, actor) {
  const total = minor(sale.total);
  return { kind: 'sale', amountMinor: sale.isDebt ? 0 : total, salesMinor: total,
    debtMinor: sale.isDebt ? total : 0, method: sale.isDebt ? 'credit' : sale.paymentMethod,
    occurredAt: sale.createdAt, actor: actor || null };
}
function summarizeMovements(rows, openingFloat) {
  let gross=0, debt=0, refund=0, cash=0, cashSales=0, bills=0, collections=0, cashIn=0, cashOut=0;
  const byMethod={};
  for (const r of rows) {
    const amount=r.amountMinor || 0;
    gross += r.salesMinor || 0; debt += r.debtMinor || 0; refund += r.refundMinor || 0;
    if (r.kind==='sale') { bills++; if(r.method==='cash')cashSales+=amount; }
    if (r.kind==='debtPayment') collections+=amount;
    if (r.method==='cash') cash+=amount;
    if (r.kind==='cashIn') {cashIn+=amount;continue;}
    if (r.kind==='cashOut') {cashOut-=amount;continue;}
    if (r.method && r.method!=='credit') byMethod[r.method]=(byMethod[r.method]||0)+amount;
  }
  return {billCount:bills,grossTotal:gross/100,debtTotal:debt/100,refundTotal:refund/100,
    cashSales:cashSales/100,expectedCash:(minor(openingFloat)+cash)/100,openingFloat,
    debtCollections:collections/100,cashIn:cashIn/100,cashOut:cashOut/100,
    byMethod:Object.fromEntries(Object.entries(byMethod).map(([k,v])=>[k,v/100]))};
}
module.exports={minor,ledgerContext,writeMovement,saleMovement,summarizeMovements};
