'use strict';
const {minor}=require('./money_ledger');

// Read source documents while closing, then freeze report evidence with the round.
async function buildCashReport(tx,shop,rows){
  const source=rows.filter(r=>r.kind==='sale'||r.kind==='refund');
  const ids=[...new Set(source.map(r=>r.saleId).filter(id=>typeof id==='string'&&!id.includes('/')))];
  const snaps=await Promise.all(ids.map(id=>tx.get(shop.collection('sales').doc(id))));
  const sales=new Map(snaps.filter(s=>s.exists).map(s=>[s.id,s.data()]));
  let before=0,discount=0,service=0,adjustment=0,returns=0,refundBills=0,complete=true;
  const staff=new Map(),items=new Map(),channels={};
  for(const r of source){
    const s=sales.get(r.saleId);
    if(!s){complete=false;continue;}
    if(r.kind==='sale'){
      const cut=minor(s.discount||0),fee=minor(s.serviceCharge||0),adj=minor(s.paymentAdjustment||0);
      before+=r.salesMinor+cut-fee-adj;discount+=cut;service+=fee;adjustment+=adj;
      const key=s.staffId||s.staffName||r.actor||'unknown';
      staff.set(key,{name:s.staffName||'ไม่บันทึกชื่อแคชเชียร์',id:s.staffId||null});
      const channel=s.salesChannel||'unspecified';
      channels[channel]=(channels[channel]||0)+(r.salesMinor||0)/100;
    }else{
      refundBills++;returns-=r.salesMinor||0;
      for(const item of s.items||[]){
        const name=item.name||item.productName||'ไม่ระบุชื่อสินค้า';
        const key=String(item.productId||name)+'|'+String(item.unit||'');
        const old=items.get(key)||{name,quantity:0,unit:item.unit||''};
        old.quantity=Math.round((old.quantity+Number(item.quantity||0))*1000)/1000;items.set(key,old);
      }
    }
  }
  return {version:1,complete,salesBeforeDiscount:before/100,discountTotal:discount/100,
    serviceCharge:service/100,paymentAdjustment:adjustment/100,returnedSales:returns/100,
    refundBillCount:refundBills,returnedItems:[...items.values()].slice(0,100),
    returnedItemsTruncated:items.size>100,cashiers:[...staff.values()].slice(0,100),
    cashiersTruncated:staff.size>100,byChannel:channels,cancelledBills:null};
}
module.exports={buildCashReport};
