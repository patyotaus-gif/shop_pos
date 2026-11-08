const test=require('node:test'),assert=require('node:assert/strict');
const {fixture}=require('./accounting_fixture.cjs');
const {handlers,wantsHuman}=require('./line_handover');
class HttpsError extends Error{constructor(code,message){super(message);this.code=code;}}
const uid='U'+'a'.repeat(32),other='U'+'b'.repeat(32);
function setup(){
  const f=fixture();let time=100000,seq=0;
  const api=handlers({db:f.db,HttpsError,now:()=>time,assertFounder:r=>{
    if(r.auth?.token?.founder!==true||r.auth.token.staffRole)throw new HttpsError('permission-denied','Founder only');
  }});
  return {...f,api,advance:n=>time+=n,event:(text,userId=uid)=>({webhookEventId:String(++seq),timestamp:time,
    source:{type:'user',userId},message:{type:'text',text}}),
    request:(mode,expectedMode,userId=uid)=>({auth:{uid:'founder',token:{founder:true}},data:{userId,mode,expectedMode}})};
}

// Exercise the production webhook routing as well as the pause state machine.
// All sends, Gemini calls and account links are local spies; no LINE traffic.
function webhookFixture() {
  const f=setup(), sent=[], ai=[], links=[];
  const fs=require('node:fs'),vm=require('node:vm');
  const source=fs.readFileSync(require.resolve('./index.js'),'utf8');
  const start=source.indexOf('exports.lineWebhook = onRequest(');
  const end=source.indexOf('exports.sendLineMessage = onCall(',start);
  assert.ok(start>=0&&end>start);
  const secret={value:()=> 'test-only'};
  const ctx={exports:{},onRequest:(_options,handler)=>handler,
    lineChannelAccessToken:secret,lineChannelSecret:secret,geminiApiKey:secret,
    _verifyLineSignature:()=>true,lineHandover:f.api,
    _lineReply:async(_token,_replyToken,messages)=>{sent.push(...messages);return true;},
    _lineAiReply:async(_key,_user,text)=>{ai.push(text);return 'test reply';},
    lineLink:{consume:async data=>{links.push(data);return true;}}};
  vm.runInNewContext(source.slice(start,end),ctx);
  return {...f,sent,ai,links,dispatch:async(events)=>{
    await ctx.exports.lineWebhook({headers:{'x-line-signature':'test'},rawBody:Buffer.alloc(0),
      body:{events:events.map(e=>({type:'message',replyToken:'test-reply',...e}))}},
      {json:body=>assert.equal(body.status,'ok')});
  }};
}

test('webhook: follow and unblock never greet or create a conversation before the customer speaks',async()=>{
  const f=webhookFixture();
  for(const isUnblocked of [false,true]){
    await f.dispatch([{...f.event(''),type:'follow',follow:{isUnblocked}}]);
  }
  assert.equal(f.sent.length,0);assert.equal(f.ai.length,0);
  assert.equal(f.docs.has('lineSupportChats/'+uid),false);
  await f.dispatch([f.event('hello')]);
  assert.equal(f.sent.length,1);assert.equal(f.ai.length,1);
});

test('webhook: repeated messages, photos and unblock stay silent until an operator explicitly resumes',async()=>{
  const f=webhookFixture(),request=f.event('ติดต่อเจ้าหน้าที่');
  await f.dispatch([request]);
  assert.equal(f.sent.length,1);
  await f.dispatch([request]); // LINE webhook redelivery
  f.advance(7*86400000);
  await f.dispatch([
    f.event('ติดต่อเจ้าหน้าที่'),f.event('ยังอยู่ไหม'),f.event('ID'),
    f.event('connect:test:123'),{...f.event(''),message:{type:'image',id:'image-1'}},
    {...f.event(''),type:'follow',follow:{isUnblocked:true}},f.event('สวัสดี'),
  ]);
  assert.equal(f.docs.get('lineSupportChats/'+uid).mode,'waiting');
  assert.equal(f.sent.length,1);assert.equal(f.ai.length,0);assert.equal(f.links.length,0);
  await f.api.setMode(f.request('human','waiting'));
  await f.dispatch([f.event('ขอบคุณค่ะ'),f.event('ติดต่อเจ้าหน้าที่')]);
  assert.equal(f.sent.length,1);assert.equal(f.ai.length,0);
  await f.api.setMode(f.request('bot','human'));f.advance(1);
  await f.dispatch([f.event('สอบถามการใช้งานต่อ')]);
  assert.equal(f.sent.length,2);assert.equal(f.ai.length,1);
});
test('explicit human requests supported; unrelated and negated questions remain bot questions',()=>{
  for(const s of ['ขอคุยกับเจ้าหน้าที่ค่ะ','อยากคุยกับคนจริง','ขอคุยกับคน ไม่เอาบอท','ไม่อยากคุยกับบอท','คุยกับคนได้ไหม','ไม่เอาบอต','เจ้าหน้าที่','human'])assert.equal(wantsHuman(s),true,s);
  for(const s of ['พนักงานเพิ่มยังไง','บอททำอะไรได้บ้าง','ไม่ต้องการคุยกับเจ้าหน้าที่','hello'])assert.equal(wantsHuman(s),false,s);
});
test('human request pauses persistently; duplicate webhook has no second acknowledgement; independent chats unaffected',async()=>{
  const f=setup(),event=f.event('ขอคุยกับคน'),t=await f.api.receive(event);let sent=0;
  assert.equal(t.action,'ack');await f.api.replyIfCurrent(t,async()=>{sent++;return true});
  assert.equal((await f.api.receive(event)).action,'ignore');
  f.advance(86400000);assert.equal((await f.api.receive(f.event('ยังอยู่ไหม'))).action,'ignore');
  assert.equal((await f.api.receive(f.event('hello',other))).action,'bot');assert.equal(sent,1);
  assert.equal(f.docs.get('lineSupportChats/'+uid).mode,'waiting');
});
test('takeover during Gemini generation cancels reply; finish resumes only new events and never replays old tickets',async()=>{
  const f=setup(),event=f.event('hello'),ticket=await f.api.receive(event);let sent=0;
  await f.api.setMode(f.request('human','bot'));
  assert.equal(await f.api.replyIfCurrent(ticket,async()=>{sent++;return true}),false);
  assert.equal((await f.api.receive(f.event('ID'))).action,'ignore');
  await f.api.setMode(f.request('bot','human'));f.advance(1);
  assert.equal((await f.api.receive(event)).action,'ignore');
  assert.equal(await f.api.replyIfCurrent(ticket,async()=>{sent++}),false);
  await f.api.replyIfCurrent(await f.api.receive(f.event('hello again')),async()=>{sent++;return true});
  assert.equal(sent,1);
});
test('concurrent human requests produce one acknowledgement ticket and pause AI already pending',async()=>{
  const f=setup(),old=await f.api.receive(f.event('hello'));
  const tickets=await Promise.all([f.api.receive(f.event('เจ้าหน้าที่')),f.api.receive(f.event('เจ้าหน้าที่'))]);
  assert.equal(tickets.filter(t=>t.action==='ack').length,1);
  assert.equal(await f.api.replyIfCurrent(old,async()=>assert.fail('must not send')),false);
});
test('takeover reports an already submitted reply and keeps pause after the send completes',async()=>{
  const f=setup(),ticket=await f.api.receive(f.event('hello'));let release,started;
  const ready=new Promise(r=>started=r),pending=new Promise(r=>release=r);
  const sending=f.api.replyIfCurrent(ticket,async()=>{started();await pending;return true});await ready;
  const result=await f.api.setMode(f.request('human','bot'));assert.ok(result.sendingUntil>100000);
  release();await sending;
  const d=f.docs.get('lineSupportChats/'+uid);assert.equal(d.mode,'human');assert.equal(d.sendingUntil,0);
});
test('unauthorized list/mutations and stale operator actions cannot change a chat',async()=>{
  const f=setup();await f.api.receive(f.event('hello'));
  for(const auth of [null,{uid:'shop',token:{}},{uid:'staff',token:{founder:true,staffRole:'cashier'}}]){
    await assert.rejects(f.api.list({auth}),{code:'permission-denied'});
    await assert.rejects(f.api.setMode({...f.request('human','bot'),auth}),{code:'permission-denied'});
  }
  await f.api.setMode(f.request('human','bot'));
  await assert.rejects(f.api.setMode(f.request('bot','bot')),{code:'failed-precondition'});
  await assert.rejects(f.api.setMode(f.request('delete','human')),{code:'invalid-argument'});
  await assert.rejects(f.api.setMode(f.request('bot','human','../shops/x')),{code:'invalid-argument'});
});
test('connection tokens are redacted; groups ignored; failed sending releases in-flight marker',async()=>{
  const f=setup();const ticket=await f.api.receive(f.event('connect:secret:123'));
  assert.equal(f.docs.get('lineSupportChats/'+uid).preview,'[เชื่อมบัญชีร้าน]');
  assert.equal((await f.api.receive({...f.event('human'),source:{type:'group',userId:uid}})).action,'ignore');
  await assert.rejects(f.api.replyIfCurrent(ticket,async()=>{throw Error('timeout')}));
  assert.equal(f.docs.get('lineSupportChats/'+uid).sendingUntil,0);
});
