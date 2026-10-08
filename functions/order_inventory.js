'use strict';
const {computeUsage} = require('./inventory');
const idOK = id => typeof id === 'string' && id.length > 0 && id.length <= 200 && !id.includes('/');
const available = value => Math.max(0, Number(value) || 0);

// Reservations are the pending orders themselves: cancellation releases them
// atomically by changing status. No TTL may discard a possibly paid order.
function requirements(items, products, groups) {
  const counted = {};
  for (const item of items) {
    const p = products[item.productId];
    if (!p || !Number.isInteger(item.quantity) || item.quantity < 1) throw Error('สินค้าเปลี่ยนไป กรุณาเลือกใหม่');
    if (p.stockMode !== 'recipe') counted[item.productId] = (counted[item.productId] || 0) + item.quantity;
    else if (!(p.recipe || []).some(r => r.qty > 0 && idOK(r.ingredientId))) throw Error('สินค้ายังไม่มีสูตรวัตถุดิบ กรุณาติดต่อร้าน');
  }
  const ingredients = computeUsage(items, products, groups);
  if (Object.keys(ingredients).some(id => !idOK(id))) throw Error('สูตรวัตถุดิบไม่ถูกต้อง');
  return {products: counted, ingredients};
}
function held(docs, products, groups) {
  const result = {products: {}, ingredients: {}};
  for (const doc of docs) {
    const o = doc.data();
    let r = o.inventoryReservation;
    if (!r) {
      // Legacy pending orders have no frozen recipe. Be conservative.
      const live = (o.items || []).filter(i => products[i.productId]);
      r = requirements(live, products, groups);
    }
    for (const type of ['products','ingredients']) for (const [id, qty] of Object.entries(r[type] || {}))
      result[type][id] = (result[type][id] || 0) + qty;
  }
  return result;
}
async function readState(shop, get = ref => ref.get()) {
  const [ps, gs, ins, pending] = await Promise.all([
    get(shop.collection('products')), get(shop.collection('modifierGroups')),
    get(shop.collection('ingredients')),
    get(shop.collection('orders').where('status','==','pendingPayment').limit(1001)),
  ]);
  if (pending.size > 1000) throw Error('กรุณาให้ร้านตรวจออเดอร์ค้างก่อนรับเพิ่ม');
  const map = s => Object.fromEntries(s.docs.map(d => [d.id, d.data()]));
  const products = map(ps), groups = map(gs), ingredients = map(ins);
  return {products, groups, ingredients, held: held(pending.docs, products, groups)};
}
function menuStock(id, state) {
  const p = state.products[id];
  if (!p) return 0;
  if (p.stockMode !== 'recipe') return Math.floor(available(p.stock) - Math.min(available(p.stock),state.held.products[id] || 0));
  const usage = computeUsage([{productId:id,quantity:1}], state.products, state.groups);
  if (!Object.keys(usage).length) return 0;
  return Math.max(0, Math.min(9999, ...Object.entries(usage).map(([iid,q]) =>
    Math.floor((available(state.ingredients[iid]?.stock) - (state.held.ingredients[iid] || 0) + 1e-9) / q))));
}
async function reserve(tx, shop, items) {
  // A single serialization document prevents concurrent checkout phantom reads.
  // All inventory docs are also read in this transaction, so stock changes retry.
  const control = shop.collection('inventoryControl').doc('online');
  const lock = await tx.get(control);
  const state = await readState(shop, ref => tx.get(ref));
  const request = requirements(items, state.products, state.groups);
  for (const type of ['products','ingredients']) for (const [id, qty] of Object.entries(request[type])) {
    if (available(state[type][id]?.stock) - (state.held[type][id] || 0) + 1e-9 < qty)
      throw Error('สินค้า/วัตถุดิบไม่พอ กรุณาปรับตะกร้าหรือติดต่อร้าน');
  }
  const totals={};
  for(const type of ['products','ingredients']) {
    totals[type]={...state.held[type]};
    for(const [id,qty] of Object.entries(request[type]))totals[type][id]=(totals[type][id]||0)+qty;
  }
  return {reservation: request, write: () => tx.set(control,{revision:Number(lock.data()?.revision || 0)+1,
    products:totals.products,ingredients:totals.ingredients})};
}
async function prepareRelease(tx,shop,order) {
  if(!order.inventoryReservation)return ()=>{};
  const ref=shop.collection('inventoryControl').doc('online'),old=(await tx.get(ref)).data();
  if(!old)return ()=>{};
  const data={revision:Number(old.revision||0)+1};
  for(const type of ['products','ingredients']) {
    data[type]={...(old[type]||{})};
    for(const [id,qty] of Object.entries(order.inventoryReservation[type]||{}))data[type][id]=Math.max(0,(data[type][id]||0)-qty);
  }
  return ()=>tx.set(ref,data);
}
module.exports = {readState, menuStock, reserve, requirements, prepareRelease};
