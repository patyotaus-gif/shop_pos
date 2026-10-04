'use strict';
async function deduct({db,shop,saleRef,usage,FieldValue}) {
  return db.runTransaction(async tx=>{
    const sale=await tx.get(saleRef);
    if(!sale.exists||sale.data().ingredientsDeducted)return false;
    const live={};
    for(const [id,qty] of Object.entries(usage)){
      if((await tx.get(shop.collection('ingredients').doc(id))).exists)live[id]=qty;
    }
    const alreadyReturned=sale.data().isRefunded===true&&sale.data().returnToStock!==false;
    if(!alreadyReturned)for(const [id,qty] of Object.entries(live))tx.update(shop.collection('ingredients').doc(id),{stock:FieldValue.increment(-qty)});
    tx.update(saleRef,{ingredientsDeducted:true,ingredientUsage:live,...(alreadyReturned?{ingredientsRestored:true}:{})});
    return !alreadyReturned;
  });
}
async function restore({db,shop,saleRef,FieldValue}) {
  return db.runTransaction(async tx=>{
    const snap=await tx.get(saleRef), sale=snap.data();
    if(!sale||!sale.isRefunded||sale.returnToStock===false||sale.ingredientsRestored||!sale.ingredientUsage)return;
    const updates=[];
    for(const [id,qty] of Object.entries(sale.ingredientUsage)){
      const ref=shop.collection('ingredients').doc(id);
      if((await tx.get(ref)).exists)updates.push({ref,qty});
    }
    for(const u of updates)tx.update(u.ref,{stock:FieldValue.increment(u.qty)});
    tx.update(saleRef,{ingredientsRestored:true});
  });
}
module.exports={deduct,restore};
