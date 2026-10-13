'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const stock=require('./stock_quantity');
const product=()=>({name:'Rice',price:80,stock:2.5,isWeighed:true,unit:'kg',trackLots:true,stockLots:[
  {id:'later',number:'L2',expiresOn:'2099-12-31',quantity:1.5},
  {id:'first',number:'L1',expiresOn:'2099-01-01',quantity:1},
]});
test('FEFO, expiry boundary, exact weighted quantities and restore to original lot',()=>{
  const p=product(),a=stock.allocate(p,1.25,'2099-01-01');
  assert.equal(a.stock,1.25);assert.deepEqual(a.used.map(l=>l.quantity),[1,0.25]);
  assert.equal(stock.available(p,'2099-01-02'),1.5);
  assert.throws(()=>stock.allocate(p,2,'2099-01-02'));
  const restored=stock.restore({...p,...a},1.25,a.used);
  assert.equal(restored.stock,2.5);assert.equal(stock.available({...p,...restored},'2099-01-02'),1.5);
  assert.throws(()=>stock.allocate({...p,isWeighed:false},0.5));
  for(const q of [NaN,Infinity,-1,0,0.0001])assert.equal(stock.valid(q,true),false);
});
test('weighted public menu deducts holds without integer truncation',()=>{
  const inventory=require('./order_inventory');
  const state={products:{rice:product()},groups:{},ingredients:{},held:{products:{rice:0.375},ingredients:{}}};
  assert.equal(inventory.menuStock('rice',state),2.125);
  assert.equal(inventory.requirements([{productId:'rice',quantity:0.125}],state.products,{}).products.rice,0.125);
});
test('online payment and refund each change weighted lots/history once',async()=>{
  const f=require('./accounting_fixture.cjs').fixture({
    'shops/shop/products/rice':product(),
    'shops/shop/orders/o':{status:'pendingPayment',total:100,finalAmount:100,items:[{productId:'rice',price:80,quantity:1.25}],inventoryReservation:{products:{rice:1.25},ingredients:{}}},
    'shops/shop/inventoryControl/online':{products:{rice:1.25},ingredients:{}},
  });
  const args={db:f.db,FieldValue:f.FieldValue,shopId:'shop',orderId:'o',actor:'shop'};
  const confirm=require('./order_accounting').confirmOrder;
  await Promise.all([confirm(args),confirm(args)]);
  assert.equal(f.docs.get('shops/shop/products/rice').stock,1.25);
  assert.equal(f.docs.get('shops/shop/products/rice/stockMovements/sale-order-o').delta,-1.25);
  const refund={db:f.db,FieldValue:f.FieldValue,shopId:'shop',saleId:'order-o',reason:'test',returnToStock:true};
  await require('./refund').refundSale(refund);await require('./refund').refundSale(refund);
  assert.equal(f.docs.get('shops/shop/products/rice').stock,2.5);
  assert.equal(f.docs.get('shops/shop/products/rice/stockMovements/refund-order-o').delta,1.25);
});
test('already paid order with expired lots retains money and flags inventory review',async()=>{
  const p=product();p.stockLots.forEach(l=>l.expiresOn='2020-01-01');
  const f=require('./accounting_fixture.cjs').fixture({'shops/shop/products/rice':p,
    'shops/shop/orders/o':{status:'pendingPayment',total:20,items:[{productId:'rice',price:80,quantity:0.25}]}});
  await require('./order_accounting').confirmOrder({db:f.db,FieldValue:f.FieldValue,shopId:'shop',orderId:'o',actor:'shop'});
  assert.equal(f.docs.get('shops/shop/sales/order-o').total,20);
  assert.equal(f.docs.get('shops/shop/sales/order-o').needsReview,true);
  assert.equal(f.docs.get('shops/shop/products/rice').stock,2.5);
});
