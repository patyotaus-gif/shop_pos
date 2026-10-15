const {test}=require('node:test'),assert=require('node:assert/strict');
const {fixture}=require('./accounting_fixture.cjs');
const {HttpsError}=require('firebase-functions/v2/https');
const {handlers}=require('./table_promotions');
function setup() {
  let clock=new Date('2026-10-15T06:00:00Z');
  const end=+clock+86400000;
  const items=[{id:'tea-line',productId:'tea',productName:'Tea',quantity:2,price:50,costPrice:10,kitchenStatus:'sent'},
    {id:'cake-line',productId:'cake',productName:'Cake',quantity:1,price:25,costPrice:5,kitchenStatus:'pending'}];
  const f=fixture({'shops/s/products/tea':{price:50,stock:20,costPrice:10,name:'Tea'},
    'shops/s/products/cake':{price:25,stock:20,costPrice:5,name:'Cake'},
    'shops/s/tables/t':{status:'occupied',currentOrderId:'o'},
    'shops/s/tableOrders/o':{tableId:'t',tableName:'T1',status:'open',items},
    'shops/s/settings/shop':{serviceChargePercent:10},
    'shops/s/cashControl/current':{sessionId:'round'},
    'shops/s/buyGetPromotions/tea':{active:true,revision:'g',endsAt:end,buyQuantity:2,giftQuantity:1,maxSets:5,giftProductId:'cake'},
    'shops/s/promotionSettings/bundles':{bundles:[{id:'set',name:'Tea Cake',revision:'b',active:true,endsAt:end,maxSets:5,priceMinor:10000,
      components:[{productId:'cake',quantity:1},{productId:'tea',quantity:2}]}]},
    'shops/s/coupons/SAVE10':{code:'SAVE10',active:true,endsAt:end,kind:'percent',value:10,minSubtotalMinor:2000,maxUses:1,claimed:0}});
  const api=handlers({...f,HttpsError,now:()=>clock});
  const call=data=>api({auth:{uid:'s',token:{}},data:{shopId:'s',orderId:'o',...data}});
  const order=()=>f.docs.get('shops/s/tableOrders/o');
  const apply=async(code='SAVE10')=>{
    const {promotion:p}=await call({action:'preview',couponCode:code});
    await call({action:'apply',couponCode:code,revision:p.revision});return p;
  };
  const send=()=>{for(const i of order().items)i.kitchenStatus='sent';};
  const close=p=>call({action:'close',revision:p.revision,expectedTotalMinor:p.totalMinor,paid:200,paymentMethod:'cash',splitCount:1});
  return {...f,api,call,order,apply,send,close,setClock:d=>clock=d};
}
test('table stacks set, gift and coupon; service on net; close/retry/refund exactly once',async()=>{
  const f=setup(),p=await f.apply();
  assert.equal(p.subtotalMinor,12500);assert.equal(p.discountMinor,3500);assert.equal(p.serviceMinor,900);assert.equal(p.totalMinor,9900);
  assert.equal(f.docs.get('shops/s/coupons/SAVE10').claimed,0);
  await assert.rejects(()=>f.close(p),/ส่งของแถม/);f.send();
  const [a,b]=await Promise.all([f.close(p),f.close(p)]);assert.equal(a.saleId,b.saleId);
  const sale=f.docs.get('shops/s/sales/'+a.saleId);
  assert.equal(sale.total,99);assert.equal(sale.discount,35);assert.equal(sale.serviceCharge,9);assert.equal(sale.change,101);
  assert.equal(sale.items.at(-1).isGift,true);assert.equal(sale.items.at(-1).costPrice,5);
  assert.equal(f.docs.get('shops/s/products/cake').stock,18);assert.equal(f.docs.get('shops/s/products/tea').stock,18);
  assert.equal(f.docs.get('shops/s/coupons/SAVE10').claimed,1);
  assert.equal(f.docs.get('shops/s/moneyMovements/sale-'+a.saleId).amountMinor,9900);
  assert.equal(f.docs.get('shops/s/tables/t').status,'available');
  const args={...f,shopId:'s',saleId:a.saleId,reason:'test',returnToStock:true};
  await require('./refund').refundSale(args);await require('./refund').refundSale(args);
  assert.equal(f.docs.get('shops/s/products/cake').stock,20);
  assert.equal(f.docs.get('shops/s/coupons/SAVE10').claimed,1);
});
test('apply retry preserves gifts sent to kitchen; order more appends only new entitlement',async()=>{
  const f=setup(),p=await f.apply('');f.send();
  const sent=f.order().items.at(-1).id;
  await f.call({action:'apply',revision:p.revision,couponCode:''});
  assert.equal(f.order().items.at(-1).id,sent);
  assert.equal(f.order().items.at(-1).kitchenStatus,'sent');
  f.order().items[0].quantity=4;
  await assert.rejects(()=>f.close(p),/รายการเปลี่ยน/);
  await f.apply('');
  const gifts=f.order().items.filter(i=>i.isGift);
  assert.equal(gifts.length,2);assert.equal(gifts[0].id,sent);assert.equal(gifts[1].kitchenStatus,'pending');
  assert.equal(gifts.reduce((s,i)=>s+i.quantity,0),2);
});
test('reducing pending gifts is safe; a prepared gift cannot silently disappear',async()=>{
  const f=setup();await f.apply('');f.order().items[0].quantity=1;
  await f.apply('');assert.equal(f.order().items.filter(i=>i.isGift).length,0);
  f.order().items[0].quantity=2;await f.apply('');f.send();f.order().items[0].quantity=1;
  await assert.rejects(()=>f.apply(''),/ส่งครัวแล้ว/);
  assert.equal(f.order().items.filter(i=>i.isGift).length,1);
});
test('concurrent tables claim the last coupon only at close; loser has no partial sale or stock writes',async()=>{
  const f=setup(),p=await f.apply();f.send();
  f.docs.set('shops/s/tableOrders/o2',{...structuredClone(f.order()),tableId:'t2'});
  f.docs.set('shops/s/tables/t2',{status:'occupied',currentOrderId:'o2'});
  const results=await Promise.allSettled([f.close(p),f.call({action:'close',orderId:'o2',revision:p.revision,expectedTotalMinor:p.totalMinor,paid:99,paymentMethod:'cash',splitCount:1})]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(f.docs.get('shops/s/coupons/SAVE10').claimed,1);
  assert.equal([...f.docs.keys()].filter(k=>k.startsWith('shops/s/sales/')).length,1);
  assert.equal(f.docs.get('shops/s/products/cake').stock,18);
});
test('stale preview, stock reservation, service change and invalid payment cannot close',async()=>{
  const f=setup();const {promotion:old}=await f.call({action:'preview'});
  f.order().items[0].quantity=3;
  await assert.rejects(()=>f.call({action:'apply',revision:old.revision}),/เปลี่ยน/);
  const p=await f.apply('');f.send();
  f.docs.set('shops/s/inventoryControl/online',{products:{cake:20}});
  await assert.rejects(()=>f.close(p),/จองออนไลน์/);
  f.docs.delete('shops/s/inventoryControl/online');
  f.docs.get('shops/s/settings/shop').serviceChargePercent=5;
  await assert.rejects(()=>f.close(p),/ค่าบริการเปลี่ยน/);
  f.docs.get('shops/s/settings/shop').serviceChargePercent=10;
  await assert.rejects(()=>f.call({action:'close',revision:p.revision,expectedTotalMinor:1,paid:1,paymentMethod:'cash',splitCount:1}),/ไม่ตรง/);
  assert.equal([...f.docs.keys()].filter(k=>k.startsWith('shops/s/sales/')).length,0);
});
test('locked set and gifts survive promo expiry/menu price change; unclaimed coupon still checked',async()=>{
  const f=setup(),p=await f.apply('');f.send();
  f.setClock(new Date('2026-10-17T06:00:00Z'));
  f.docs.get('shops/s/products/tea').price=80;
  await f.close(p);assert.equal(f.docs.get('shops/s/sales/table-o').total,110);
  const g=setup(),q=await g.apply();g.send();g.setClock(new Date('2026-10-17T06:00:00Z'));
  await assert.rejects(()=>g.close(q),/หมดอายุ/);
  assert.equal(g.docs.get('shops/s/coupons/SAVE10').claimed,0);
});
test('cancelled table cannot redeem; anonymous, staff and another shop rejected',async()=>{
  const f=setup(),p=await f.apply();f.order().status='cancelled';
  await assert.rejects(()=>f.close(p),/ยกเลิก/);
  assert.equal(f.docs.get('shops/s/coupons/SAVE10').claimed,0);
  for(const auth of [undefined,{uid:'other'},{uid:'s',token:{staffRole:'cashier'}}])
    await assert.rejects(()=>f.api({auth,data:{shopId:'s',orderId:'o',action:'preview'}}),e=>e.code==='permission-denied');
});
test('legacy line IDs normalize on apply and remain billable',async()=>{
  const f=setup();delete f.order().items[0].id;const p=await f.apply('');f.send();
  assert.equal(f.order().items[0].id,'legacy-0');await f.close(p);
});

test('automatic sync and send compute once, keep gift identity, and send paid/free dishes atomically',async()=>{
  const f=setup();
  const {promotion:p}=await f.call({action:'sync'});
  assert.equal(p.totalMinor,11000);
  const id=f.order().items.at(-1).id;
  await Promise.all([f.call({action:'send'}),f.call({action:'send'})]);
  assert.equal(f.order().items.filter(i=>i.isGift).length,1);
  assert.equal(f.order().items.at(-1).id,id);
  assert.ok(f.order().items.every(i=>i.kitchenStatus==='sent'));
  assert.equal(f.docs.get('shops/s/products/cake').stock,20);
  assert.equal([...f.docs.keys()].filter(k=>k.startsWith('shops/s/sales/')).length,0);
  f.order().items[0].quantity=4;
  const {promotion:q}=await f.call({action:'send'});
  assert.equal(f.order().items.filter(i=>i.isGift).reduce((s,i)=>s+i.quantity,0),2);
  assert.ok(f.order().items.every(i=>i.kitchenStatus==='sent'));
  await f.call({action:'close',revision:q.revision,expectedTotalMinor:q.totalMinor,paid:q.totalMinor/100,paymentMethod:'cash',splitCount:1});
  assert.equal(f.docs.get('shops/s/products/cake').stock,17);
});

test('coupon is checked before payment; removing an expired coupon retains agreed gifts and bundles',async()=>{
  const f=setup();await f.apply();f.send();
  f.setClock(new Date('2026-10-17T06:00:00Z'));
  await assert.rejects(()=>f.call({action:'sync'}),/หมดอายุ/);
  assert.equal(f.docs.get('shops/s/coupons/SAVE10').claimed,0);
  const {promotion:p}=await f.call({action:'sync',couponCode:''});
  assert.equal(p.totalMinor,11000);assert.equal(p.coupon,null);
  assert.equal(f.order().items.filter(i=>i.isGift).length,1);
  await f.close(p);
});

test('owner explicitly keeps prepared gift, with reason in sale; subsequent edits do not ask again',async()=>{
  const f=setup();const p=await f.apply('');f.send();
  f.order().items[0].quantity=1;
  await assert.rejects(()=>f.call({action:'sync'}),/ของแถมส่งครัวแล้ว/);
  await assert.rejects(()=>f.call({action:'sync',keepPreparedGifts:true,revision:p.revision}),/เหตุผล/);
  await assert.rejects(()=>f.call({action:'sync',keepPreparedGifts:true,revision:'old',reason:'ร้านให้ฟรี'}),/เหตุผล/);
  const {promotion:q}=await f.call({action:'sync',keepPreparedGifts:true,revision:p.revision,reason:'ร้านยินดีให้ของแถมเดิม'});
  assert.equal(q.totalMinor,8250);
  assert.equal(q.retainedGifts[0].actor,'s');
  assert.equal(q.retainedGifts[0].reason,'ร้านยินดีให้ของแถมเดิม');
  f.order().items[1].quantity=2;
  const {promotion:r}=await f.call({action:'sync'});
  assert.equal(r.retainedGifts.length,1);
  await f.close(r);
  const sale=f.docs.get('shops/s/sales/table-o');
  assert.equal(sale.retainedGifts[0].reason,'ร้านยินดีให้ของแถมเดิม');
  assert.equal(sale.items.filter(i=>i.isGift).length,1);
  assert.equal(f.docs.get('shops/s/products/cake').stock,17);
});

test('failed automatic send leaves kitchen and coupon unchanged',async()=>{
  const f=setup();await f.apply();
  f.docs.get('shops/s/coupons/SAVE10').claimed=1;
  const before=structuredClone(f.order());
  await assert.rejects(()=>f.call({action:'send'}),/สิทธิ์ครบ/);
  assert.deepEqual(f.order(),before);
});
test('recipe gifts include purchased and free ingredients; online holds block partial consumption',async()=>{
  const f=setup();Object.assign(f.docs.get('shops/s/products/cake'),{stockMode:'recipe',recipe:[{ingredientId:'flour',qty:0.1}]});
  f.docs.set('shops/s/ingredients/flour',{stock:0.2});
  f.docs.set('shops/s/inventoryControl/online',{ingredients:{flour:0.1}});
  await assert.rejects(()=>f.apply(''),/วัตถุดิบไม่พอ/);
  assert.equal(f.order().tablePromotion,undefined);
  f.docs.get('shops/s/ingredients/flour').stock=1;
  const p=await f.apply('');f.send();await f.close(p);
  assert.equal(f.docs.get('shops/s/ingredients/flour').stock,0.8);
  assert.equal(f.docs.get('shops/s/sales/table-o').ingredientUsage.flour,0.2);
  assert.equal(f.docs.get('shops/s/products/cake').stock,20);
});
test('same product ordered at different prices still closes without an incorrect bundle',async()=>{
  const f=setup();f.order().items[0].quantity=1;
  f.order().items.push({...f.order().items[0],id:'different-price',price:40});
  const p=await f.apply('');assert.deepEqual(p.bundles,[]);
  assert.equal(p.subtotalMinor,11500);assert.equal(p.totalMinor,12650);
  f.send();await f.close(p);
  assert.equal(f.docs.get('shops/s/sales/table-o').total,126.5);
});
test('older client dropping gift metadata cannot turn gifts into paid quantities or earn cascading gifts',async()=>{
  const f=setup();await f.apply('');
  delete f.order().items.at(-1).isGift;
  await assert.rejects(()=>f.apply(''),/ข้อมูลของแถมถูกเปลี่ยน/);
  assert.equal([...f.docs.keys()].filter(k=>k.startsWith('shops/s/sales/')).length,0);
});
