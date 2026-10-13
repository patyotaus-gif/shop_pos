const {test}=require('node:test'),assert=require('node:assert/strict');
const bundles=require('./bundles'),{fixture}=require('./accounting_fixture.cjs');
const {createWithPickup}=require('./pickup'),{confirmOrder,handlers}=require('./order_accounting');
const {refundSale}=require('./refund'),{HttpsError}=require('firebase-functions/v2/https');
const owner=data=>({auth:{uid:'shop',token:{}},data:{shopId:'shop',...data}});
const config={id:'set',name:'Tea and Cake',components:[{productId:'cake',quantity:1},{productId:'tea',quantity:2}],
  priceMinor:10000,maxSets:2,endsAt:Date.now()+86400000,active:true,revision:'r1'};
function setup(){
  const f=fixture({'shops/shop/products/tea':{name:'Tea',price:50,stock:20,costPrice:10},
    'shops/shop/products/cake':{name:'Cake',price:25,stock:10,costPrice:5},
    'shops/shop/promotionSettings/bundles':{bundles:[structuredClone(config)]}});
  const shopRef=f.db.collection('shops').doc('shop');
  const items=[{productId:'tea',productName:'Tea',price:50,quantity:2,costPrice:10},
    {productId:'cake',productName:'Cake',price:25,quantity:1,costPrice:5}];
  const quote=(lines=items)=>bundles.quote(shopRef,lines);
  const create=async(id,edit={})=>createWithPickup({...f,shopRef,orderRef:shopRef.collection('orders').doc(id),order:{
    items,total:125,finalAmount:125.31,paymentMethod:'promptpay',status:'pendingPayment',requestSignature:id,
    bundleQuote:await quote(),...edit}});
  return {...f,shopRef,items,quote,create};
}
test('bundle owner config rejects overlaps, invalid quantities/options and prices',async()=>{
  const f=setup(),manage=bundles.manage({...f,HttpsError});
  for(const e of [{components:[config.components[0]]},{maxSets:11},{priceMinor:0},{endsAt:0},
    {components:[config.components[0],config.components[0]]}])assert.throws(()=>bundles.config({...config,...e}));
  await assert.rejects(()=>manage({auth:{uid:'other'},data:{shopId:'shop',...config,action:'save'}}));
  await assert.rejects(()=>manage({auth:{uid:'shop',token:{staffRole:'cashier'}},data:{shopId:'shop',...config,action:'save'}}));
  await assert.rejects(()=>manage(owner({...config,id:'second',action:'save'})),/ซ้ำ/);
  await assert.rejects(()=>manage(owner({...config,priceMinor:12500,action:'save'})),/ต่ำกว่า/);
  await manage(owner({...config,action:'save'}));
  assert.equal(f.docs.get('shops/shop/promotionSettings/bundles').bundles[0].components[0].productName,'Cake');
  f.docs.get('shops/shop/products/cake').modifierGroupIds=['option'];
  await assert.rejects(()=>manage(owner({...config,action:'save'})),/ตัวเลือก/);
  await manage(owner({id:'set',action:'toggle',active:false}));
  assert.deepEqual(await f.quote(),[]);
  await manage(owner({id:'set',action:'delete'}));
  assert.deepEqual(f.docs.get('shops/shop/promotionSettings/bundles').bundles,[]);
});
test('bundle counts full sets across notes, excludes options and gifts, caps sets; individual promos never cost more',async()=>{
  const f=setup();
  assert.equal((await f.quote())[0].discountMinor,2500);
  assert.deepEqual(await f.quote([f.items[0]]),[]);
  const split=[{...f.items[0],quantity:1,notes:'one'},{...f.items[0],quantity:1,notes:'two'},f.items[1]];
  assert.equal((await f.quote(split))[0].sets,1);
  assert.equal((await f.quote(f.items.map(i=>({...i,quantity:i.quantity*5}))))[0].sets,2);
  assert.deepEqual(await f.quote([{...f.items[0],isGift:true},f.items[1]]),[]);
  assert.deepEqual(await f.quote([{...f.items[0],optionIds:['x']},f.items[1]]),[]);
  const catalog=await bundles.catalog(f.shopRef);assert.equal(catalog[0].priceMinor,10000);
  assert.equal(JSON.stringify(catalog).includes('costPrice'),false);
  f.docs.get('shops/shop/products/tea').salePrice=35;
  assert.deepEqual(await f.quote(),[]); // 35*2+25 is already cheaper than the set.
});
test('stale or forged bundle quote/price fails before reservation; original input remains unchanged',async()=>{
  const f=setup(),original=structuredClone(f.items),q=await f.quote();
  await assert.rejects(()=>f.create('x',{bundleQuote:[{...q[0],discountMinor:1}]}),/ชุดสินค้า/);
  f.docs.get('shops/shop/products/tea').price=60;
  await assert.rejects(()=>f.create('x',{bundleQuote:q}),/ชุดสินค้า/);
  await assert.rejects(()=>f.create('x'),/ราคาเปลี่ยน/); // priced lines stale, even if promo preview is new.
  assert.deepEqual(f.items,original);assert.equal(f.docs.has('shops/shop/orders/x'),false);
});
test('bundle + buy/get + percentage coupon use net amount, hold all stock, confirm/refund exactly once',async()=>{
  const f=setup();
  f.docs.set('shops/shop/buyGetPromotions/tea',{buyQuantity:2,giftQuantity:1,giftProductId:'cake',maxSets:1,active:true,revision:'g',endsAt:config.endsAt});
  f.docs.set('shops/shop/coupons/SAVE10',{code:'SAVE10',kind:'percent',value:10,minSubtotalMinor:2000,maxUses:10,claimed:0,active:true,endsAt:config.endsAt});
  const gifts=await require('./buy_get').quote(f.shopRef,f.items);
  const edit={buyGetQuote:gifts,couponCode:'SAVE10',couponQuote:{subtotalMinor:10000,discountMinor:1000}};
  const first=await f.create('o',edit);await f.create('o',edit);
  assert.equal(first.total,90);assert.equal(first.finalAmount,90.31);
  const o=f.docs.get('shops/shop/orders/o');assert.equal(o.subtotal,125);assert.equal(o.discount,35);
  assert.equal(o.items.length,3);assert.equal(o.inventoryReservation.products.cake,2);
  // Recorded terms survive deleting/changing promotions before the customer pays.
  f.docs.get('shops/shop/promotionSettings/bundles').bundles=[];
  const a={...f,shopId:'shop',orderId:'o',actor:'shop'};
  const {saleId}=await confirmOrder(a);await confirmOrder(a);
  const sale=f.docs.get('shops/shop/sales/'+saleId);
  assert.equal(sale.total,90.31);assert.equal(sale.discount,35);assert.equal(sale.bundleDiscount,25);
  assert.equal(sale.paymentAdjustment,.31);assert.equal(sale.items[2].costPrice,5);
  assert.equal(f.docs.get('shops/shop/products/cake').stock,8);
  await refundSale({...f,shopId:'shop',saleId,actor:'shop',reason:'test',returnToStock:true});
  await refundSale({...f,shopId:'shop',saleId,actor:'shop',reason:'test',returnToStock:true});
  assert.equal(f.docs.get('shops/shop/products/cake').stock,10);
  assert.equal(f.docs.get('shops/shop/products/tea').stock,20);
});
test('bundle cancellation restores held inventory; tampered stored discount blocks confirmation',async()=>{
  const f=setup();f.docs.get('shops/shop/products/cake').stock=1;
  await f.create('a');await assert.rejects(()=>f.create('b'),/ไม่พอ/);
  await handlers({...f,HttpsError}).transition(owner({orderId:'a',status:'cancelled',reason:'test'}));
  await f.create('b');f.docs.get('shops/shop/orders/b').bundleDiscount=99;
  await assert.rejects(()=>confirmOrder({...f,shopId:'shop',orderId:'b',actor:'shop'}),/Bundle/);
  assert.equal(f.docs.has('shops/shop/sales/order-b'),false);
});
test('bundle savings do not reduce unrelated product revenue; bill discount follows net amounts',()=>{
  const {allocate}=require('./analytics'),{cutsForBundles}=require('./bundle_allocation');
  const items=[{productId:'tea',quantity:2,subtotal:100},{productId:'cake',quantity:1,subtotal:25},{productId:'extra',quantity:1,subtotal:100}];
  const cuts=cutsForBundles(items,[{sets:1,discountMinor:2500,components:[
    {productId:'tea',quantity:2,unitPriceMinor:5000},{productId:'cake',quantity:1,unitPriceMinor:2500}]}],allocate);
  assert.deepEqual(cuts,[2000,500,0]);
  const net=items.map((i,n)=>i.subtotal*100-cuts[n]),tail=allocate(1000,net);
  assert.deepEqual(net.map((v,n)=>(v-tail[n])/100),[76,19,95]);
});
