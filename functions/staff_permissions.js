'use strict';
const positions=['cashier','waiter','kitchen','manager'];
const permissions=['discount','cancel','refund','cashSession','reports','cost','stock','stockReceive','stockWaste','stockHistory'];
async function authorize(request,db,HttpsError,permission=null){
  const auth=request.auth,shopId=request.data?.shopId;
  const deny=()=>{throw new HttpsError('permission-denied','ไม่มีสิทธิ์ทำรายการนี้ กรุณาติดต่อเจ้าของร้าน');};
  if(!auth||typeof shopId!=='string'||!shopId||shopId.includes('/'))deny();
  if(!auth.token?.staffRole){if(auth.uid!==shopId)deny();return {shopId,actor:auth.uid,name:auth.token?.name||'เจ้าของร้าน'};}
  const t=auth.token;
  if(t.staffRole!=='cashier'||t.staffShopId!==shopId||typeof t.staffId!=='string'||!t.staffId||t.staffId.includes('/'))deny();
  const shop=db.collection('shops').doc(shopId);
  const [s,m]=await Promise.all([shop.get(),shop.collection('staff').doc(t.staffId).get()]);
  const member=m.data();
  if(!s.exists||!m.exists||member.active===false||Number(member.sessionVersion||0)!==t.staffVersion)deny();
  const data=s.data(),until=data.subscriptionStatus==='active'?data.subscriptionEndsAt:data.subscriptionStatus==='trial'?data.trialEndsAt:null;
  if(!until?.toDate||until.toDate()<=new Date()||!['full','restaurant'].includes(data.tier||'full'))deny();
  if(permission&&member.permissions?.[permission]!==true)deny();
  return {shopId,actor:auth.uid,staffId:t.staffId,name:member.name,permissions:member.permissions||{},position:member.position||'cashier'};
}
async function recheck(tx,shop,request,HttpsError){
 if(!request.auth?.token?.staffRole)return;
 const token=request.auth.token;
 const [member,store]=await Promise.all([tx.get(shop.collection('staff').doc(token.staffId)),tx.get(shop)]);
 const m=member.data(),s=store.data();
 const until=s?.subscriptionStatus==='active'?s.subscriptionEndsAt:s?.subscriptionStatus==='trial'?s.trialEndsAt:null;
 if(!m||m.active===false||Number(m.sessionVersion||0)!==token.staffVersion||!until?.toDate||until.toDate()<=new Date()||!['full','restaurant'].includes(s?.tier||'full'))
  throw new HttpsError('permission-denied','สิทธิ์เปลี่ยนแล้ว กรุณาเข้าสู่ระบบใหม่');
}
module.exports={positions,permissions,authorize,recheck};
