const {test}=require('node:test'),assert=require('node:assert/strict');
const buyGet=require('./buy_get'),{fixture}=require('./accounting_fixture.cjs');
const {createWithPickup}=require('./pickup'),{confirmOrder,handlers}=require('./order_accounting');
const {refundSale}=require('./refund'),{HttpsError}=require('firebase-functions/v2/https');
const owner=data=>({auth:{uid:'shop',token:{}},data:{shopId:'shop',...data}});
const config={buyProductId:'tea',giftProductId:'cake',buyQuantity:2,giftQuantity:1,maxSets:2,endsAt:Date.now()+86400000};
function setup() {
  const f=fixture({'shops/shop/products/tea':{name:'Tea',stock:20,price:50,costPrice:10},
    'shops/shop/products/cake':{name:'Cake',stock:3,price:20,costPrice:5},
    'shops/shop/buyGetPromotions/tea':{...config,active:true,revision:'r1'}});
  const shopRef=f.db.collection('shops').doc('shop');
  const items=[{productId:'tea',productName:'Tea',price:50,quantity:2,costPrice:10}];
  const quote=(list=items)=>buyGet.quote(shopRef,list);
  const create=async(id,edit={})=>createWithPickup({...f,shopRef,orderRef:shopRef.collection('orders').doc(id),order:{
    requestSignature:id,status:'pendingPayment',paymentMethod:'promptpay',total:100,finalAmount:100.35,items,
    buyGetQuote:await quote(),...edit}});
  return {...f,shopRef,items,quote,create};
}
test('buy/get config limits, owner access and gift choices',async()=>{
  const f=setup(),manage=buyGet.manage({...f,HttpsError});
  for(const extra of [{buyQuantity:0},{giftQuantity:1.5},{maxSets:11},{giftQuantity:99,maxSets:2},{endsAt:0}])
    assert.throws(()=>buyGet.config({...config,...extra}),/ซื้อแถม/);
  await assert.rejects(()=>manage({auth:{uid:'other'},data:{shopId:'shop',...config,action:'save'}}));
  await assert.rejects(()=>manage({auth:{uid:'shop',token:{staffRole:'cashier'}},data:{shopId:'shop',...config,action:'save'}}));
  await manage(owner({...config,action:'save'}));
  assert.equal(f.docs.get('shops/shop/buyGetPromotions/tea').buyName,'Tea');
  f.docs.get('shops/shop/products/cake').modifierGroupIds=['required'];
  await assert.rejects(()=>manage(owner({...config,action:'save'})),/ตัวเลือกเสริม/);
});
test('combine paid quantities only, cap sets, do not cascade or mutate original lines',async()=>{
  const f=setup();
  assert.equal((await f.quote([{...f.items[0],quantity:1}])).length,0);
  assert.equal((await f.quote([{...f.items[0],quantity:1},{...f.items[0],quantity:1}]))[0].quantity,1);
  assert.equal((await f.quote([{...f.items[0],quantity:10}]))[0].quantity,2);
  f.docs.set('shops/shop/buyGetPromotions/cake',{...config,buyProductId:'cake',giftProductId:'tea',active:true,revision:'r2'});
  const copy=structuredClone(f.items);await f.create('o');
  assert.deepEqual(f.items,copy);
  assert.equal(f.docs.get('shops/shop/orders/o').items.length,2);
  assert.equal(f.docs.get('shops/shop/orders/o').items[1].price,0);
});
test('same product gifts reserve purchased and free stock together; retry never doubles gifts',async()=>{
  const f=setup();f.docs.get('shops/shop/buyGetPromotions/tea').giftProductId='tea';
  await f.create('a');await f.create('a');
  const saved=f.docs.get('shops/shop/orders/a');
  assert.equal(saved.items.length,2);assert.equal(saved.inventoryReservation.products.tea,3);
  f.docs.get('shops/shop/products/tea').stock=5;
  await assert.rejects(()=>f.create('b'),/ไม่พอ/);
  assert.equal(f.docs.has('shops/shop/orders/b'),false);
});
test('expiry or changed promo requires new preview; cancelled order releases gift inventory',async()=>{
  const f=setup(),q=await f.quote();
  f.docs.get('shops/shop/buyGetPromotions/tea').active=false;
  await assert.rejects(()=>f.create('a',{buyGetQuote:q}),/โปรโมชั่นเปลี่ยน/);
  f.docs.get('shops/shop/buyGetPromotions/tea').active=true;
  f.docs.get('shops/shop/products/cake').stock=1;
  await f.create('a');await assert.rejects(()=>f.create('b'),/ไม่พอ/);
  await handlers({...f,HttpsError}).transition(owner({orderId:'a',status:'cancelled',reason:'no payment'}));
  await f.create('b');
  assert.equal(f.docs.get('shops/shop/inventoryControl/online').products.cake,1);
  f.docs.get('shops/shop/buyGetPromotions/tea').endsAt=0;
  assert.deepEqual(await f.quote(),[]);
});
test('gift and coupon payment preserve costs, net cash amount and refund stock once',async()=>{
  const f=setup();f.docs.set('shops/shop/coupons/SAVE10',{code:'SAVE10',kind:'percent',value:10,minSubtotalMinor:2000,
    maxUses:10,claimed:0,active:true,endsAt:config.endsAt});
  await f.create('a',{couponCode:'SAVE10',couponQuote:{subtotalMinor:10000,discountMinor:1000}});
  f.docs.get('shops/shop/buyGetPromotions/tea').active=false;
  const args={...f,shopId:'shop',orderId:'a',actor:'shop'};
  const {saleId}=await confirmOrder(args);await confirmOrder(args);
  const sale=f.docs.get('shops/shop/sales/'+saleId);
  assert.equal(sale.total,90.35);assert.equal(sale.discount,10);assert.equal(sale.paymentAdjustment,.35);
  assert.equal(sale.items[1].subtotal,0);assert.equal(sale.items[1].costPrice,5);
  assert.equal(f.docs.get('shops/shop/products/cake').stock,2);
  await refundSale({...f,shopId:'shop',saleId,actor:'shop',reason:'test',returnToStock:true});
  await refundSale({...f,shopId:'shop',saleId,actor:'shop',reason:'test',returnToStock:true});
  assert.equal(f.docs.get('shops/shop/products/cake').stock,3);
  assert.equal(f.docs.get('shops/shop/products/tea').stock,20);
});
test('gift recipe reserves ingredients and restores them after refund',async()=>{
  const f=setup();f.docs.get('shops/shop/products/cake').stockMode='recipe';
  f.docs.get('shops/shop/products/cake').recipe=[{ingredientId:'flour',qty:2}];
  f.docs.set('shops/shop/ingredients/flour',{stock:5});
  await f.create('a');
  assert.equal(f.docs.get('shops/shop/orders/a').inventoryReservation.ingredients.flour,2);
  const {saleId}=await confirmOrder({...f,shopId:'shop',orderId:'a',actor:'shop'});
  assert.equal(f.docs.get('shops/shop/ingredients/flour').stock,3);
  await refundSale({...f,shopId:'shop',saleId,actor:'shop',reason:'test',returnToStock:true});
  const restore={...f,shop:f.shopRef,saleRef:f.shopRef.collection('sales').doc(saleId)};
  await require('./ingredient_accounting').restore(restore);
  await require('./ingredient_accounting').restore(restore);
  assert.equal(f.docs.get('shops/shop/ingredients/flour').stock,5);
});
