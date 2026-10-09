'use strict';
function handler({db, Timestamp, FieldValue, HttpsError, now=()=>new Date()}) {
  return async request => {
    if (!request.auth) throw new HttpsError('unauthenticated','Login required');
    if (request.auth.token?.staffRole) throw new HttpsError('permission-denied','Owner only');
    const code=String(request.data?.code||'').trim().toUpperCase();
    if (!/^[A-Z0-9-]{3,40}$/.test(code)) throw new HttpsError('invalid-argument','Invalid referral code');
    const self=db.doc(`shops/${request.auth.uid}`), claim=db.doc(`referralClaims/${request.auth.uid}`);
    return db.runTransaction(async tx=>{
      const [selfSnap,prior,referrers]=await Promise.all([
        tx.get(self),tx.get(claim),tx.get(db.collection('shops').where('referralCode','==',code).limit(2)),
      ]);
      if (!selfSnap.exists) throw new HttpsError('not-found','Shop not found');
      if (prior.exists || selfSnap.data().referredBy) return {applied:false,reason:'already-referred'};
      if (selfSnap.data().referralCode===code) return {applied:false,reason:'self'};
      // Ambiguous legacy codes must be resolved by the owner, not chosen arbitrarily.
      if (referrers.size!==1) return {applied:false,reason:'code-not-found'};
      const referrer=referrers.docs[0];
      if (referrer.id===self.id) return {applied:false,reason:'self'};
      const date=now();
      const extend=s=>Timestamp.fromMillis(Math.max(s.data().trialEndsAt?.toMillis()||0,+date)+30*86400000);
      tx.update(self,{referredBy:code,trialEndsAt:extend(selfSnap)});
      tx.update(referrer.ref,{trialEndsAt:extend(referrer)});
      tx.create(claim,{shopId:self.id,referrerId:referrer.id,code,bonusDays:30,createdAt:FieldValue.serverTimestamp()});
      return {applied:true,bonusDays:30};
    });
  };
}
module.exports={handler};
