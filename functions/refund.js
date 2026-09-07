// The Stripe request and Firestore transaction can both be retried safely.
async function refundSale({ db, stripe, shopId, saleId, reason, FieldValue }) {
  const shop = db.collection('shops').doc(shopId);
  const saleRef = shop.collection('sales').doc(saleId);
  const snapshot = await saleRef.get();
  if (!snapshot.exists) throw new Error('Sale not found');
  const sale = snapshot.data();
  if (sale.isRefunded) return { success: true, stripeRefundId: sale.stripeRefundId || null };
  let stripeRefundId = null;
  let stripeRefundStatus = null;
  if (sale.stripePaymentIntentId) {
    // Metadata also allows recovery after Stripe's idempotency-key retention.
    const previous = await stripe.refunds.list({ payment_intent: sale.stripePaymentIntentId, limit: 100 });
    let refund = previous.data.find(r => r.metadata?.pokpokSaleId === saleId && r.metadata?.pokpokShopId === shopId);
    if (!refund) {
      refund = await stripe.refunds.create({
        payment_intent: sale.stripePaymentIntentId,
        reason: 'requested_by_customer',
        metadata: { pokpokSaleId: saleId, pokpokShopId: shopId },
      }, { idempotencyKey: `pokpok-refund-${shopId}-${saleId}` });
    }
    if (['failed', 'canceled'].includes(refund.status)) throw new Error('Stripe refund did not complete; contact support');
    stripeRefundId = refund.id;
    stripeRefundStatus = refund.status;
  }
  const debts = sale.isDebt ? await shop.collection('debts').where('saleId', '==', saleId).get() : null;
  return db.runTransaction(async tx => {
    const current = await tx.get(saleRef);
    if (!current.exists) throw new Error('Sale not found');
    if (current.data().isRefunded) return { success: true, stripeRefundId: current.data().stripeRefundId || null };
    const quantities = new Map();
    for (const item of current.data().items) quantities.set(item.productId, (quantities.get(item.productId) || 0) + item.quantity);
    const products = [];
    for (const [id, quantity] of quantities) {
      const ref = shop.collection('products').doc(id);
      if ((await tx.get(ref)).exists) products.push({ ref, quantity });
    }
    tx.update(saleRef, { isRefunded: true, refundedAt: FieldValue.serverTimestamp(),
      refundReason: reason || '', stripeRefundId, stripeRefundStatus });
    for (const { ref, quantity } of products) tx.update(ref, { stock: FieldValue.increment(quantity) });
    if (current.data().isDebt && debts) for (const debt of debts.docs) tx.delete(debt.ref);
    return { success: true, stripeRefundId };
  });
}
module.exports = { refundSale };
