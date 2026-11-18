// Deterministic fixtures. All sales are in whole baht; refunded goods return to stock.
const products = [
  {name:'พาสต้ากุ้ง', price:180, cost:68}, {name:'ข้าวกะเพรา', price:90, cost:32},
  {name:'ชาไทย', price:60, cost:16}, {name:'กาแฟเย็น', price:75, cost:24},
  {name:'เครปเบอร์รี', price:120, cost:46}, {name:'ข้าวไก่ย่าง', price:110, cost:38}
];
const channels=['ทานที่ร้าน','กลับบ้าน','ออนไลน์'], payments=['เงินสด','เงินโอน'];
const staff=['มะลิ','ต้น','นุ่น','พลอย'], days=['จ.','อ.','พ.','พฤ.','ศ.','ส.','อา.'];
const periods=['26 ต.ค.–1 พ.ย.','2–8 พ.ย.','9–15 พ.ย.'];
const metrics=['ยอดขายสุทธิ','กำไรขั้นต้น','บิลขายสำเร็จ','เฉลี่ยต่อบิล'];
const element=id=>document.getElementById(id);
const fmt=v=>v.toLocaleString('th-TH',{maximumFractionDigits:2});
const baht=v=>'฿'+fmt(v);
const sum=(rows,field)=>rows.reduce((v,r)=>v+r[field],0);
const bills=[];
let seed=1986;
function random(limit){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return Math.floor(seed/4294967296*limit)}
for(let date=0;date<21;date++){
  for(let branch=0;branch<2;branch++){
    const volume=10+random(7)+Math.floor(date/7)*2+(date%7>3?7:0);
    for(let i=0;i<volume;i++){
      const sku=random(products.length), item=products[sku], qty=1+random(3);
      const gross=item.price*qty, discount=i%7===0?Math.round(gross*.1):0;
      const state=random(24), voided=state===0, refunded=state===1;
      const refund=refunded?gross-discount:0;
      const net=voided?0:gross-discount-refund;
      const hour=[8,9,10,11,12,12,12,13,14,15,16,17,18,18,19,20][random(16)];
      bills.push({date,branch,sku,qty,voided,refunded,refund,net,gross,discount,hour,
        cost:net?qty*item.cost:0,minute:random(60),channel:random(3),payment:random(2),
        cashier:branch*2+random(2),member:random(3)?null:random(80),
        id:'P'+String(date+1).padStart(2,'0')+'-'+(branch+1)+String(i+1).padStart(3,'0')});
    }
  }
}
let week=2, selectedDay=2, metric=0;
const branchMatches=b=>element('branch').value==='all'||b.branch===Number(element('branch').value);
const weekRows=w=>bills.filter(b=>Math.floor(b.date/7)===w&&branchMatches(b));
const success=b=>!b.voided&&!b.refunded;
function totals(rows){
  const net=sum(rows,'net'), count=rows.filter(success).length;
  return [net,net-sum(rows,'cost'),count,count?net/count:0];
}
function value(i,v){return i===2?fmt(v):baht(v)}
function delta(a,b){
  if(!b)return a?'ไม่มีฐานเปรียบเทียบ':'เท่าเดิม';
  const d=Math.round((a/b-1)*1000)/10;
  return d===0?'เท่าเดิม':(d>0?'↑ ':'↓ ')+fmt(Math.abs(d))+'%';
}
const dateLabel=d=>(week===2?9:2)+d+' พ.ย.';
const byDay=(rows,d)=>rows.filter(b=>b.date%7===d);
function pairs(entries){
  return entries.map(([label,val,cls=''])=>`<div class="data-row ${cls}"><span>${label}</span><b>${val}</b></div>`).join('');
}
function ranking(labels,values){
  const max=Math.max(1,...values);
  return labels.map((label,i)=>`<div class="ranking"><div class="row"><span>${label}</span><b>${baht(values[i])}</b></div><span class="meter"><i style="width:${100*values[i]/max}%"></i></span></div>`).join('');
}
function table(headers,rows){
  return '<table><thead><tr>'+headers.map(h=>'<th scope="col">'+h+'</th>').join('')+'</tr></thead><tbody>'+
    rows.map(row=>'<tr>'+row.map(v=>'<td>'+v+'</td>').join('')+'</tr>').join('')+'</tbody></table>';
}
function renderChart(){
  const chart=element('chart'), width=chart.clientWidth,height=chart.clientHeight;
  if(!width)return;
  const current=weekRows(week),prev=weekRows(week-1);
  const series=[prev,current].map(rows=>days.map((_,d)=>totals(byDay(rows,d))[metric]));
  const top=Math.max(1,...series.flat());
  const step=10**Math.floor(Math.log10(top));
  const ceiling=Math.ceil(top/step*2)*step/2;
  const left=46, bottom=height-8;
  const x=i=>left+(i+.5)*(width-left)/7, y=v=>bottom-v/ceiling*(bottom-16);
  const path=values=>values.map((v,i)=>(i?'L':'M')+x(i)+' '+y(v)).join(' ');
  const curve=path(series[1]),point=series[1][selectedDay];
  chart.setAttribute('viewBox',`0 0 ${width} ${height}`);
  chart.innerHTML=[0,.5,1].map(f=>`<line x1="${left}" x2="${width}" y1="${y(ceiling*f)}" y2="${y(ceiling*f)}" stroke="var(--line)"/><text class="axis" x="${left-5}" y="${y(ceiling*f)+4}" text-anchor="end">${fmt(ceiling*f)}</text>`).join('')+
    `<path d="${curve} L${x(6)} ${bottom} L${x(0)} ${bottom} Z" fill="var(--rose)" opacity=".65"/>
    <path d="${path(series[0])}" fill="none" stroke="var(--prior)" stroke-width="2" stroke-dasharray="5 5"/>
    <line x1="${x(selectedDay)}" x2="${x(selectedDay)}" y1="10" y2="${bottom}" stroke="var(--edge)" stroke-dasharray="2 4"/>
    <path d="${curve}" fill="none" stroke="var(--wine)" stroke-width="3" stroke-linejoin="round"/>
    <circle cx="${x(selectedDay)}" cy="${y(point)}" r="5" fill="var(--surface)" stroke="var(--wine)" stroke-width="3"/>`;
  element('dates').innerHTML=days.map((name,d)=>`<button data-day="${d}" aria-pressed="${d===selectedDay}" aria-label="${name} ${dateLabel(d)} ${metrics[metric]} ${value(metric,series[1][d])}"><span>${name}</span> ${parseInt(dateLabel(d))}</button>`).join('');
  element('day-summary').textContent=dateLabel(selectedDay)+' · '+metrics[metric]+' '+value(metric,point);
}
function render(){
  const rows=weekRows(week), active=rows.filter(success), posted=rows.filter(b=>!b.voided);
  const now=totals(rows), prev=totals(weekRows(week-1));
  element('metrics').innerHTML=metrics.map((m,i)=>`<button class="metric" data-metric="${i}" aria-pressed="${metric===i}">${m}<strong>${value(i,now[i])}</strong><small>${delta(now[i],prev[i])} จากสัปดาห์ก่อน</small></button>`).join('');
  element('chart-title').textContent=metrics[metric]+'รายวัน';
  element('compare').textContent=periods[week]+' เทียบกับ '+periods[week-1]+' 2569';
  renderChart();
  const subtract=v=>v?'−'+baht(v):baht(0);
  element('reconcile').innerHTML=pairs([
    ['ยอดสินค้าก่อนส่วนลด',baht(sum(posted,'gross'))],['ส่วนลด',subtract(sum(posted,'discount'))],
    ['คืนเงิน · '+posted.filter(b=>b.refunded).length+' บิล',subtract(sum(posted,'refund'))],
    ['ยอดขายสุทธิ',baht(now[0]),'sum'],['ต้นทุนสินค้าที่ขาย',baht(sum(rows,'cost'))],['กำไรขั้นต้น',baht(now[1]),'sum']
  ])+`<p class="note">ยกเลิกก่อนชำระ ${rows.length-posted.length} บิล · แยกออกจากยอดขาย</p>`;
  element('channels').innerHTML=ranking(channels,channels.map((_,i)=>sum(rows.filter(b=>b.channel===i),'net')));
  element('payments').innerHTML=pairs(payments.map((p,i)=>[p,baht(sum(rows.filter(b=>b.payment===i),'net'))]));
  const starts=[8,11,14,17,20];
  element('hours').innerHTML=ranking(starts.map(h=>h+':00–'+(h+2)+':59'),starts.map(h=>sum(rows.filter(b=>b.hour>=h&&b.hour<h+3),'net')));
  const ranked=products.map((p,i)=>{const part=active.filter(b=>b.sku===i);return {name:p.name,qty:sum(part,'qty'),net:sum(part,'net')}}).sort((a,b)=>b.net-a.net);
  element('product-list').innerHTML=table(['สินค้า','ชิ้น','ยอดสุทธิ'],ranked.map(r=>[r.name,fmt(r.qty),baht(r.net)]));
  const end=(week+1)*7, branches=element('branch').value==='all'?2:1;
  const sold=bills.filter(b=>branchMatches(b)&&success(b)&&b.date<end);
  element('stock-date').textContent='คงเหลือ ณ สิ้นวันที่ '+dateLabel(6)+' 2569';
  element('stock').innerHTML=pairs(products.map((p,i)=>[p.name,fmt((340+10*i)*branches-sum(sold.filter(b=>b.sku===i),'qty'))+' ชิ้น']));
  element('staff').innerHTML=table(['พนักงาน','บิล','ยอดสุทธิ'],staff.flatMap((s,i)=>{const part=active.filter(b=>b.cashier===i);return part.length?[[s,part.length,baht(sum(part,'net'))]]:[]}));
  const members=active.filter(b=>b.member!==null), memberCount=new Set(members.map(b=>b.member)).size;
  element('customers').innerHTML=pairs([['สมาชิกที่ซื้อ',fmt(memberCount)+' คน'],['บิลสมาชิก',members.length+' บิล'],['ยอดซื้อสมาชิก',baht(sum(members,'net'))],['เฉลี่ยต่อสมาชิก',baht(memberCount?sum(members,'net')/memberCount:0)],['ยอดขายลูกค้าทั่วไป',baht(now[0]-sum(members,'net'))]]);
}
function selectDay(i){selectedDay=i;renderChart();element('dates').querySelector('[aria-pressed=true]').focus({preventScroll:true})}
element('dates').onclick=e=>{const b=e.target.closest('button');if(b)selectDay(Number(b.dataset.day))};
element('chart').onclick=e=>{const rect=e.currentTarget.getBoundingClientRect();selectDay(Math.max(0,Math.min(6,Math.floor((e.clientX-rect.left-46)/(rect.width-46)*7))))};
element('metrics').onclick=e=>{const b=e.target.closest('button');if(b){metric=Number(b.dataset.metric);render();element('metrics').querySelector('[aria-pressed=true]').focus({preventScroll:true})}};
element('branch').onchange=render;
element('period').onchange=e=>{week=Number(e.target.value);render()};
element('tabs').onclick=e=>{
  const tab=e.target.closest('button');if(!tab)return;
  for(const b of element('tabs').children){const show=b===tab;element(b.dataset.tab).hidden=!show;b.setAttribute('aria-pressed',String(show))}
  if(tab.dataset.tab==='overview')renderChart();
};
element('open-bills').onclick=()=>{
  const rows=byDay(weekRows(week),selectedDay).sort((a,b)=>b.hour-a.hour||b.minute-a.minute);
  element('bill-title').textContent='บิลวันที่ '+dateLabel(selectedDay);
  element('bill-list').innerHTML='<p class="sub">'+totals(rows)[2]+' บิลขายสำเร็จ · ยอดสุทธิ '+baht(sum(rows,'net'))+'</p>'+rows.map(b=>{
    const status=b.voided?'ยกเลิก':b.refunded?'คืนเงิน':'ชำระแล้ว';
    return `<details><summary>${b.hour}:${String(b.minute).padStart(2,'0')} · ${b.id} · ${baht(b.net)} · ${status}</summary>${pairs([[products[b.sku].name+' × '+b.qty,baht(b.gross)],['ส่วนลด',baht(b.discount)],['ช่องทาง',channels[b.channel]],['ผู้ปิดบิล',staff[b.cashier]]])}</details>`;
  }).join('');
  element('drawer').showModal();
};
new ResizeObserver(renderChart).observe(element('chart'));
render();
