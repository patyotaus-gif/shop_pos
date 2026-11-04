import {initializeApp} from 'https://www.gstatic.com/firebasejs/10.12.5/firebase-app.js';
import {getAuth, signInWithEmailAndPassword, signInWithPopup, GoogleAuthProvider, onAuthStateChanged, signOut}
  from 'https://www.gstatic.com/firebasejs/10.12.5/firebase-auth.js';
import {getFunctions, httpsCallable} from 'https://www.gstatic.com/firebasejs/10.12.5/firebase-functions.js';
import {setupAppCheck} from '/appcheck.js';
const app = initializeApp({apiKey:'AIzaSyDfkL865SPzygJ0Kcqb4l0UaoXaSuz63F0',
  authDomain:'shop-pos-89294.firebaseapp.com',projectId:'shop-pos-89294',appId:'1:1010156115465:web:01f80dfe21f2767ea68ad8'});
setupAppCheck(app);
const auth = getAuth(app), functions = getFunctions(app,'asia-southeast1');
const call = async (name,data={}) => (await httpsCallable(functions,name)(data)).data;
const $ = id => document.getElementById(id);
const labels = {bot:'บอทตอบอยู่',waiting:'รอเจ้าหน้าที่ · บอทหยุดแล้ว',human:'เจ้าหน้าที่ดูแล · บอทหยุดแล้ว'};
let rows=[], next=null, busy=false, session=0, authorized=false;
function showError(e) {
  if(e.code?.includes('permission-denied')||e.code?.includes('unauthenticated')){
    authorized=false;rows=[];next=null;$('chats').replaceChildren();$('workspace').hidden=true;
  }
  $('status').textContent = e.code?.includes('permission-denied') ? 'บัญชีนี้ไม่มีสิทธิ์ดูแลแชท กรุณาใช้บัญชีผู้ดูแล Pokpok'
    : e.code?.includes('failed-precondition') ? 'สถานะแชทเปลี่ยนแล้ว กรุณารีเฟรชก่อนทำรายการอีกครั้ง'
    : 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่ ยังไม่ควรเริ่มตอบใน LINE OA จนกว่าจะยืนยันว่าบอทหยุดแล้ว';
}
async function run(action) {
  if(busy)return;busy=true;
  document.querySelectorAll('button').forEach(b=>b.disabled=true);
  try{await action();}catch(e){showError(e);}finally{busy=false;document.querySelectorAll('button').forEach(b=>b.disabled=false);}
}
function el(tag,text,cls){const e=document.createElement(tag);e.textContent=text;if(cls)e.className=cls;return e;}
function render(){
  const q=$('search').value.trim().toLowerCase(), filter=$('filter').value;
  const shown=rows.filter(r=>(filter==='all'||r.mode===filter)&&`${r.displayName} ${r.userId} ${r.preview}`.toLowerCase().includes(q));
  $('chats').replaceChildren();
  for(const row of shown){
    const card=el('article',''),head=el('div','','row between');
    head.append(el('h2',row.displayName||'ผู้ใช้ LINE'),el('span',labels[row.mode]||row.mode,`badge ${row.mode}`));card.append(head);
    card.append(el('p',row.userId,'id'),el('p',row.preview,'preview'));
    card.append(el('p',`ข้อความ/สถานะล่าสุด ${new Date(row.updatedAt).toLocaleString('th-TH')}`,'meta'));
    if(row.sendingUntil>Date.now())card.append(el('p','บอทอาจมีข้อความที่ส่งออกไปแล้วหนึ่งข้อความ กรุณารอประมาณ 20 วินาทีและตรวจแชทก่อนตอบ','warning'));
    const actions=el('div','','row actions');
    const mode=row.mode==='human'?'bot':'human',button=el('button',mode==='human'?'รับช่วงแชท':'จบการดูแล / เปิดบอท');
    button.className=mode==='human'?'primary':'';
    button.onclick=()=>run(async()=>{
      if(mode==='bot'&&!confirm('จบการดูแลแล้วใช่ไหม? บอทจะตอบข้อความใหม่หลังจากนี้'))return;
      const epoch=session;
      const result=await call('adminLineChatMode',{userId:row.userId,mode,expectedMode:row.mode});
      if(epoch!==session)return;
      $('status').textContent=mode==='human'
        ? 'รับช่วงแชทแล้ว บอทหยุดตอบจนกว่าจะกดเปิดอีกครั้ง'+(result.sendingUntil>Date.now()?'\nมีข้อความที่อาจกำลังส่งอยู่ กรุณารอประมาณ 20 วินาทีและตรวจแชทก่อนตอบ':'')
        : 'เปิดบอทแล้ว จะเริ่มตอบเมื่อมีข้อความใหม่ ไม่ตอบข้อความเก่าย้อนหลัง';
      await refresh(false);
    });
    actions.append(button);
    if(row.mode==='waiting'){
      const resume=el('button','เปิดบอทอีกครั้ง');resume.onclick=()=>run(async()=>{
        if(!confirm('เปิดบอทอีกครั้งสำหรับแชทนี้ใช่ไหม?'))return;
        const epoch=session;
        await call('adminLineChatMode',{userId:row.userId,mode:'bot',expectedMode:row.mode});
        if(epoch!==session)return;
        $('status').textContent='เปิดบอทแล้ว จะตอบเฉพาะข้อความใหม่';await refresh(false);
      });actions.append(resume);
    }
    card.append(actions);$('chats').append(card);
  }
  if(!shown.length)$('chats').append(el('p','ยังไม่มีแชทตรงกับรายการที่เลือก'));
  $('more').hidden=!next;
}
async function refresh(append=false){
  const epoch=session;
  const data=await call('adminLineChats',append&&next?{after:next}:{});
  if(epoch!==session)return;
  authorized=true;$('workspace').hidden=false;
  rows=append?[...new Map([...rows,...data.chats].map(r=>[r.userId,r])).values()]:data.chats;
  next=data.next;render();
}
$('loginForm').onsubmit=e=>{e.preventDefault();run(async()=>{try{await signInWithEmailAndPassword(auth,$('email').value.trim(),$('password').value);}finally{$('password').value='';}});};
$('googleLogin').onclick=()=>run(()=>signInWithPopup(auth,new GoogleAuthProvider()));
$('logout').onclick=()=>run(()=>signOut(auth));
$('refresh').onclick=()=>run(()=>refresh(false));$('more').onclick=()=>run(()=>refresh(true));
$('search').oninput=render;$('filter').onchange=render;
onAuthStateChanged(auth,async user=>{
  session++;authorized=false;rows=[];next=null;$('chats').replaceChildren();$('workspace').hidden=true;
  $('login').hidden=!!user;$('logout').hidden=!user;$('status').textContent='';
  if(user){try{await refresh();}catch(e){showError(e);}}
});
// Keep older pages available for operators browsing history; use Refresh to return to the latest page.
setInterval(()=>{if(authorized&&!busy&&!document.hidden&&rows.length<=50)run(()=>refresh(false));},15000);
