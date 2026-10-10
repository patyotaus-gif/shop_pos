const {test} = require('node:test');
const assert = require('node:assert/strict');
const {receiptProfile} = require('./receipt_profile');
const {fixture} = require('./accounting_fixture.cjs');
const {confirmOrder} = require('./order_accounting');
const settings = {name: 'Issuer', address: 'Address', taxId: '9100192800912',
  branch: 'Head office', receiptVatEnabled: true, receiptVatRate: 7};
test('receipt VAT requires explicit valid settings, preserving display-only issuer data', () => {
  assert.equal(receiptProfile().vatEnabled, false);
  assert.equal(receiptProfile(settings).vatEnabled, true);
  for (const change of [{receiptVatEnabled:false},{taxId:'123'},{name:''},{address:''},
    {receiptVatRate:NaN},{receiptVatRate:-1},{receiptVatRate:101},{receiptVatRate:7.001}])
    assert.equal(receiptProfile({...settings,...change}).vatEnabled, false);
  assert.equal(receiptProfile({...settings, receiptVatRate:7.25}).vatRate, 7.25);
});
test('online checkout freezes issuer settings and does not add VAT or rewrite on retry', async () => {
  const f = fixture({'shops/shop/settings/shop':settings,
    'shops/shop/orders/o':{status:'pendingPayment',total:107,items:[{productId:'p',price:107,quantity:1}]},
    'shops/shop/products/p':{stock:10,price:107}});
  const args = {...f,shopId:'shop',orderId:'o',actor:'shop'};
  await confirmOrder(args);
  const sale = f.docs.get('shops/shop/sales/order-o');
  assert.deepEqual(sale.receiptProfile, receiptProfile(settings));
  assert.equal(sale.total,107);assert.equal(f.docs.get('shops/shop/moneyMovements/sale-order-o').amountMinor,10700);
  f.docs.set('shops/shop/settings/shop',{...settings,name:'Changed',receiptVatRate:10});
  await confirmOrder(args);
  assert.deepEqual(f.docs.get('shops/shop/sales/order-o').receiptProfile, receiptProfile(settings));
  assert.equal(f.docs.get('shops/shop/products/p').stock,9);
});
