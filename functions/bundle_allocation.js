// Integer satang: bundle savings affect only participating units. Remaining
// bill discounts are allocated over those units' net values afterwards.
function cutsForBundles(items,bundles,allocate) {
  const cuts=items.map(()=>0),left=items.map(i=>i.isGift?0:i.quantity);
  for(const b of bundles||[]) {
    const weights=items.map(()=>0);
    for(const c of b.components) {
      let needed=c.quantity*b.sets;
      items.forEach((i,n)=>{
        if(i.productId!==c.productId||i.isGift||i.modifiers?.length)return;
        const take=Math.min(needed,left[n]);needed-=take;left[n]-=take;
        weights[n]+=take*c.unitPriceMinor;
      });
    }
    const part=allocate(b.discountMinor,weights);
    part.forEach((v,n)=>cuts[n]+=v);
  }
  return cuts;
}
module.exports={cutsForBundles};
