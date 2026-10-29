const {test} = require('node:test');
const assert = require('node:assert/strict');
test('pickup dates and time choices stay separate without changing slot IDs', async()=>{
 const {pickupDescription,pickupDays,slotsForDate}=await import('../public/order/js/order-display.mjs');
 const slots=[{id:'1',label:'30/10/2026 09:00–09:15 น.'},
   {id:'2',label:'30/10/2026 10:00–10:15 น.'},{id:'3',label:'31/10/2026 09:00–09:15 น.'}];
 assert.deepEqual(pickupDays(slots),['30/10/2026','31/10/2026']);
 assert.deepEqual(slotsForDate(slots,'31/10/2026').map(s=>s.id),['3']);
 assert.deepEqual(slotsForDate(slots,'01/11/2026'),[]);
 assert.equal(pickupDescription(slots[0].label),'วันรับสินค้า: 30/10/2026\nเวลารับ: 09:00–09:15 น. (เวลาไทย)');
 assert.equal(pickupDescription(null),'');
});

test('real picker changes date, refreshes stale slots and blocks checkout after load failure', async()=>{
 const vm=require('node:vm'), fs=require('node:fs');
 const helpers=await import('../public/order/js/order-display.mjs');
 class Element {
  constructor(){this.options=[];this._value='';this.listeners={};}
  get value(){return this._value;}
  set value(v){this._value=String(v);}
  replaceChildren(){this.options=[];this._value='';}
  add(option){this.options.push(option);if(this.options.length===1)this._value=option.value;}
  addEventListener(event,fn){this.listeners[event]=fn;}
 }
 const elements=Object.fromEntries(['pickupFields','pickupMode','pickupDate','pickupSlot','pickupHint','pickupRefresh','pickupDateLabel','pickupTimeLabel'].map(k=>[k,new Element()]));
 elements.pickupMode.value='scheduled';
 let response={ok:true,json:async()=>({pickup:{enabled:true,slots:[
   {id:'a',label:'30/10/2026 09:00–09:15 น.'},{id:'b',label:'31/10/2026 10:00–10:15 น.'}]}})};
 const context=vm.createContext({...helpers,document:{getElementById:id=>elements[id]},
   Option:class {constructor(text,value){this.text=text;this.value=value;}},
   apiFetch:async()=>response,shopId:'test',orderContext:{}});
 const source=fs.readFileSync(require.resolve('../public/order/js/pickup.js'),'utf8').replace(/^import .*\n/gm,'').replace(/export /g,'');
 vm.runInContext(source,context);
 context.initPickup(); await context.refreshPickup();
 assert.equal(elements.pickupSlot.options[0].text,'09:00–09:15 น.');
 elements.pickupDate.value='31/10/2026'; elements.pickupDate.listeners.change();
 assert.equal(context.pickupPayload().pickupSlot,'b');
 response={ok:true,json:async()=>({pickup:{enabled:true,slots:[{id:'c',label:'31/10/2026 11:00–11:15 น.'}]}})};
 await context.refreshPickup();
 assert.equal(context.pickupPayload().pickupSlot,'c');
 elements.pickupMode.value='asap';elements.pickupMode.listeners.change();
 assert.equal(elements.pickupDate.disabled,true);
 assert.equal(context.pickupPayload().pickupSlot,'c');
 response={ok:false}; await context.refreshPickup();
 assert.throws(()=>context.pickupPayload());
});
