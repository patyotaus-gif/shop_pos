// Historical pre-fix audit (1.2.38). Expected to fail after fixes; NOT a release gate.
// Current acceptance: customer_order.integration.cjs.
// Must be run against an isolated Firestore emulator only.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const { confirmOrder } = require('./order_accounting');
(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('Emulator required');
  const app = admin.initializeApp({ projectId: 'demo-pokpok-admin' }, 'audit-journeys');
  try {
    const db = app.firestore(), FieldValue = admin.firestore.FieldValue;
    const source = fs.readFileSync(require.resolve('./index'), 'utf8');
    const exported = {}, scope = {
      exports: exported, onRequest: (_, handler) => handler,
      admin: { firestore: Object.assign(() => db, { FieldValue }) },
      _verifyAppCheck: async () => true, loadModifierGroups: async () => ({}),
      priceLine: require('./tableorder').priceLine, pickupScheduling: require('./pickup'), require, console,
    };
    require('node:vm').runInNewContext(source.slice(source.indexOf('exports.createPromptPayOrder ='), source.indexOf('exports.stripeWebhook =')), scope);
    require('node:vm').runInNewContext(source.slice(source.indexOf('exports.getShopPublic ='), source.indexOf('exports.createOrderCheckout =')), scope);
    const shopId = 'audit-customer-journeys', shop = db.doc('shops/' + shopId);
    await shop.set({ name: 'Isolated audit shop' });
    await shop.collection('settings').doc('shop').set({ promptpayId: '0812345678', tableOrderMode: 'prepaid' });
    await shop.collection('products').doc('last').set({ name: 'Last item', price: 50, stock: 1 });
    const call = async (fn, req) => {
      const result = { status: 200 };
      const res = { set() {}, status(n) { result.status = n; return this; }, json(data) { result.data = data; }, send() {} };
      await fn(req, res); return result;
    };
    const checkout = extra => call(exported.createPromptPayOrder, { method: 'POST', body: {
      shopId, customerName: 'Audit customer', customerPhone: '0800000000', items: [{ productId: 'last', quantity: 1 }], ...extra,
    }});
    const findings = [];
    const two = await Promise.all([checkout({}), checkout({})]);
    assert.ok(two.every(o => o.status === 200));
    for (const o of two) await confirmOrder({ db, FieldValue, shopId, orderId: o.data.orderId, actor: shopId });
    const stock = (await shop.collection('products').doc('last').get()).data().stock;
    assert.equal(stock, -1);
    findings.push({ id: 'DATA-01', action: 'Two customers order the last stock unit, then owner confirms both simulated payments', actual: 'Both receive payable orders; stock becomes negative', stock,
      note: 'Actual incoming money is still recorded. Missing safeguard is availability/reservation before requesting payment.' });
    await shop.collection('products').doc('last').update({ stock: 0 });
    assert.equal((await checkout({})).status, 200);
    const phone = await checkout({ customerPhone: 'abc' });
    assert.equal(phone.status, 200);
    findings.push({ id: 'UX-03', action: 'Submit invalid phone abc directly to shipped handler', actual: 'Server accepts it too' });
    await shop.collection('tables').doc('t1').set({ name: 'A1' });
    await shop.collection('products').doc('last').update({ stock: 10 });
    const table = await checkout({ orderType: 'dineInPrepaid', tableId: 't1', tableName: 'A1' });
    assert.equal(table.status, 200);
    const paid = await confirmOrder({ db, FieldValue, shopId, orderId: table.data.orderId, actor: shopId });
    const sale = (await shop.collection('sales').doc(paid.saleId).get()).data();
    assert.equal(sale.salesChannel, 'takeaway');
    findings.push({ id: 'DATA-02', action: 'Prepaid table QR order -> confirm payment', expected: 'Dine-in sales channel', actual: sale.salesChannel });
    const original = (await shop.collection('orders').doc(table.data.orderId).get()).data();
    findings.push({ id: 'UI-04', action: 'Compare paid order card amount with recorded sale', orderCardAmount: original.total, saleTotal: sale.total, finalAmount: original.finalAmount,
      note: 'Paid card uses order.total, while accounting correctly records transferred finalAmount including matching satang.' });
    await shop.collection('products').doc('recipe').set({ name: 'Recipe dish', price: 60, stock: 0, stockMode: 'recipe', recipe: [{ ingredientId: 'rice', qty: 1 }] });
    await shop.collection('ingredients').doc('rice').set({ name: 'Rice', stock: 20 });
    const menu = await call(exported.getShopPublic, { query: { shop: shopId } });
    const recipe = menu.data.products.find(p => p.id === 'recipe');
    assert.equal(recipe.stock, 0);
    assert.equal(recipe.stockMode, undefined);
    findings.push({ id: 'DATA-03', action: 'Publish recipe product with ingredient stock but no finished-goods stock', actual: 'Public menu exposes stock 0 and no recipe availability; browser disables adding the dish' });
    const report = { version: '1.2.38+55', type: 'actual HTTP handler and accounting module on Firestore emulator; App Check stubbed, no bank transfer', findings };
    fs.writeFileSync('../.remember/tmp/audit56-backend-findings.json', JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report, null, 2));
  } finally { await app.delete(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
