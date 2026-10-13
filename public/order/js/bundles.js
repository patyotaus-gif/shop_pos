import {addLine,getQty,items,onCartChange} from './cart.js?v=20261013stock';
import {fmtBaht} from './util.js?v=20261013stock';
export function initBundles(bundles,products) {
  const root=document.getElementById('bundleChoices');
  const byId=new Map(products.map(p=>[p.id,p]));
  const valid=(bundles||[]).filter(b=>b.components.every(c=>byId.has(c.productId)&&!(byId.get(c.productId).modifierGroups||[]).length));
  if(!valid.length)return;
  root.hidden=false;
  const heading=document.createElement('h2');heading.textContent='ชุดสินค้าราคาพิเศษ';root.append(heading);
  const help=document.createElement('p');help.textContent='เพิ่มสินค้าครบชุดแล้ว ระบบคิดส่วนลดให้ก่อนชำระเงิน หากแก้จำนวนจะคำนวณชุดใหม่';root.append(help);
  const grid=document.createElement('div');grid.className='bundle-grid';root.append(grid);
  for(const b of valid) {
    const card=document.createElement('div');card.className='bundle-card';
    const title=document.createElement('strong');title.textContent=b.name;
    const detail=document.createElement('p');detail.textContent=b.components.map(c=>`${byId.get(c.productId).name} × ${c.quantity}`).join(' + ');
    const price=document.createElement('p');price.textContent=`${fmtBaht(b.priceMinor/100)} ต่อชุด • สูงสุด ${b.maxSets} ชุดต่อบิล`;
    const button=document.createElement('button');button.type='button';button.textContent='เพิ่มชุดลงตะกร้า';
    const check=()=>{
      const complete=Math.min(...b.components.map(c=>Math.floor(items().filter(i=>i.id===c.productId&&!i.optionIds?.length).reduce((s,i)=>s+i.quantity,0)/c.quantity)));
      const enough=b.components.every(c=>getQty(c.productId)+c.quantity<=Math.min(99,byId.get(c.productId).stock));
      button.disabled=!enough||complete>=b.maxSets;
      button.textContent=!enough?'สินค้าไม่พอ':complete>=b.maxSets?'ครบจำนวนชุดที่รับสิทธิ์':'เพิ่มชุดลงตะกร้า';
    };
    button.addEventListener('click',()=>{
      check();if(button.disabled)return;
      for(const c of b.components)addLine(byId.get(c.productId),c.quantity);
    });
    onCartChange(check);check();card.append(title,detail,price,button);grid.append(card);
  }
}
