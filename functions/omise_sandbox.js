'use strict';
// Founder-only gateway rehearsal. Never writes shops, sales, stock or moneyMovements.
const {HttpsError} = require('firebase-functions/v2/https');
const AMOUNT = 10000; // 100 THB, always set by the server.
const PUBLIC_KEY = 'pkey_test_64n6n1ijr0hyb2sawod';
const RETURN_URL = 'https://pok-pok.app/payment-test/';
const WEBHOOK_URL = 'https://asia-southeast1-shop-pos-89294.cloudfunctions.net/omiseSandboxWebhook';
const uuid = value => typeof value === 'string' && /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(value);
const chargeIdOk = value => typeof value === 'string' && /^chrg_test_[a-z0-9]+$/.test(value);
const fail = (code, message) => { throw new HttpsError(code, message); };

function client({secret, fetchImpl = fetch}) {
  return async (path, form) => {
    const key = secret();
    if (typeof key !== 'string' || !/^skey_test_[a-z0-9]+$/.test(key)) {
      fail('failed-precondition', 'ต้องใช้ Omise Test Secret Key เท่านั้น');
    }
    if (!/^\/(?:charges(?:\/chrg_test_[a-z0-9]+)?|sources\/src_test_[a-z0-9]+|tokens\/tokn_test_[a-z0-9]+)$/.test(path)) {
      fail('invalid-argument', 'เส้นทางทดสอบไม่ถูกต้อง');
    }
    // Do not log the key, request body, provider response or underlying exception.
    let response, result;
    try {
      const tokenRequest = path.startsWith('/tokens/');
      response = await fetchImpl(`https://${tokenRequest ? 'vault' : 'api'}.omise.co${path}`, {
        method: form ? 'POST' : 'GET', redirect: 'error', signal: AbortSignal.timeout(15000),
        headers: {Authorization: `Basic ${Buffer.from(`${tokenRequest ? PUBLIC_KEY : key}:`).toString('base64')}`,
          'Omise-Version': '2019-05-29', ...(form ? {'Content-Type':'application/x-www-form-urlencoded'} : {})},
        ...(form ? {body:new URLSearchParams(form).toString()} : {}),
      });
      result = await response.json();
    } catch (_) { fail('unavailable', 'ยังยืนยันผลไม่ได้ กรุณาตรวจรายการเดิมก่อนเริ่มใหม่'); }
    if (!response.ok) {
      // A timeout/5xx may have happened AFTER charge creation. Never retry POST automatically.
      const uncertain = response.status >= 500 || response.status === 408 || response.status === 429;
      fail(uncertain ? 'unavailable' : 'failed-precondition',
        uncertain ? 'ยังยืนยันผลไม่ได้ กรุณาตรวจรายการเดิมก่อนเริ่มใหม่'
          : 'Omise ไม่รับคำขอนี้ กรุณาตรวจคีย์ทดลองและการเปิดช่องทางชำระในบัญชี');
    }
    return result;
  };
}

function view(id, data) {
  return {attemptId:id, amount:AMOUNT, currency:'THB', testMode:true,
    status:data.status, chargeId:data.chargeId || null, authorizeUri:data.authorizeUri || null};
}
function validateCharge(charge, attempt, id) {
  if (!charge || charge.object !== 'charge' || charge.livemode !== false || !chargeIdOk(charge.id) ||
      charge.amount !== AMOUNT || String(charge.currency).toUpperCase() !== 'THB' ||
      charge.metadata?.pokpokSandboxAttempt !== id || charge.metadata?.actor !== attempt.actor ||
      (attempt.chargeId && attempt.chargeId !== charge.id) ||
      (attempt.method === 'card' ? charge.card?.id !== attempt.instrumentId : charge.source?.id !== attempt.instrumentId)) {
    fail('failed-precondition', 'ข้อมูลการชำระไม่ตรงกับรายการทดลอง');
  }
  let status = 'pending';
  if (charge.status === 'successful' && charge.paid === true && charge.captured === true) status = 'successful';
  else if (['failed','expired','reversed'].includes(charge.status)) status = charge.status;
  if (status === 'successful' && charge.refunded_amount > 0) status = 'refunded';
  let authorizeUri = null;
  if (status === 'pending' && charge.authorize_uri) {
    const url = new URL(charge.authorize_uri);
    if (url.protocol !== 'https:' || url.username || url.password ||
        !(url.hostname === 'omise.co' || url.hostname.endsWith('.omise.co'))) {
      fail('failed-precondition', 'ลิงก์ยืนยันการชำระไม่ถูกต้อง');
    }
    authorizeUri = url.href;
  }
  return {chargeId:charge.id, status, authorizeUri};
}

function handlers({db, FieldValue, assertFounder, api}) {
  const refFor = id => db.collection('omiseSandboxAttempts').doc(id);
  function signed(request) {
    assertFounder(request);
    if (request.auth?.token?.staffRole) fail('permission-denied', 'เฉพาะผู้ดูแลระบบ');
  }
  async function owned(request) {
    signed(request);
    const id = request.data?.attemptId;
    if (!uuid(id)) fail('invalid-argument', 'รหัสรายการทดลองไม่ถูกต้อง');
    const ref = refFor(id), data = (await ref.get()).data();
    if (!data || data.actor !== request.auth.uid) fail('not-found', 'ไม่พบรายการทดลองของบัญชีนี้');
    return {id, ref, data};
  }
  async function record(id, charge) {
    return db.runTransaction(async tx => {
      const ref = refFor(id), data = (await tx.get(ref)).data();
      if (!data) fail('not-found', 'ไม่พบรายการทดลอง');
      const update = validateCharge(charge, data, id);
      // Concurrent status/webhook responses must not undo a verified terminal result.
      if (['successful','refunded','reversed','failed','expired'].includes(data.status) && update.status === 'pending' ||
          data.status === 'refunded' && update.status === 'successful') return view(id, data);
      tx.update(ref, {...update, checkedAt:FieldValue.serverTimestamp()});
      return view(id, {...data,...update});
    });
  }
  async function create(request) {
    signed(request);
    const {attemptId:id, method, nonce} = request.data || {};
    if (!uuid(id) || !['card','truemoney'].includes(method) || typeof nonce !== 'string' ||
        !(method === 'card' ? /^tokn_test_[a-z0-9]+$/ : /^src_test_[a-z0-9]+$/).test(nonce)) {
      fail('invalid-argument', 'ต้องใช้ข้อมูลบัตรหรือ TrueMoney ในโหมดทดลอง');
    }
    const ref = refFor(id);
    // Persist the claim BEFORE contacting Omise. Concurrent calls and lost responses
    // return the same attempt without issuing another charge.
    const existing = await db.runTransaction(async tx => {
      const prior = (await tx.get(ref)).data();
      if (prior) {
        if (prior.actor !== request.auth.uid || prior.method !== method || prior.nonce !== nonce) {
          fail('already-exists', 'รหัสคำขอนี้ถูกใช้แล้ว');
        }
        return prior;
      }
      tx.create(ref, {actor:request.auth.uid, method, nonce, status:'creating', testMode:true,
        amount:AMOUNT, currency:'THB', createdAt:FieldValue.serverTimestamp()});
      return null;
    });
    if (existing) return view(id, existing);
    let instrument;
    try {
      instrument = await api(`/${method === 'card' ? 'tokens' : 'sources'}/${nonce}`);
      if (instrument.id !== nonce || instrument.livemode !== false ||
          (method === 'card' ? instrument.object !== 'token' || instrument.used !== false || !instrument.card?.id
            : instrument.object !== 'source' || instrument.type !== 'truemoney' || instrument.amount !== AMOUNT ||
              String(instrument.currency).toUpperCase() !== 'THB')) {
        fail('failed-precondition', 'ข้อมูลทดสอบหรือยอดเงินไม่ถูกต้อง');
      }
    } catch (e) {
      await ref.update({status:'rejected'}); // no POST attempted
      throw e;
    }
    await ref.update({instrumentId:method === 'card' ? instrument.card.id : nonce});
    let charge;
    try {
      charge = await api('/charges', {amount:String(AMOUNT), currency:'THB', capture:'true',
        [method === 'card' ? 'card' : 'source']:nonce,
        description:'Pokpok gateway test only - no sale',
        return_uri:`${RETURN_URL}?attempt=${id}`, 'metadata[pokpokSandboxAttempt]':id,
        'metadata[actor]':request.auth.uid, 'webhook_endpoints[]':`${WEBHOOK_URL}?attempt=${id}`});
    } catch (e) {
      // Do not overwrite a webhook which already verified the charge.
      await db.runTransaction(async tx => {
        const current = (await tx.get(ref)).data();
        if (current.status === 'creating') tx.update(ref, {status:e.code === 'failed-precondition' ? 'rejected' : 'unknown'});
      });
      throw e;
    }
    return record(id, charge);
  }
  async function status(request) {
    const {id, data} = await owned(request);
    const chargeId = data.chargeId || request.data.chargeId;
    if (!chargeId) return view(id, data);
    if (!chargeIdOk(chargeId)) fail('invalid-argument', 'ต้องใช้รหัสการชำระทดลอง');
    return record(id, await api(`/charges/${chargeId}`));
  }
  async function webhook(req, res) {
    res.set('Cache-Control', 'no-store');
    if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');
    const id = req.query?.attempt, chargeId = req.body?.data?.id;
    if (!uuid(id) || !chargeIdOk(chargeId) || (req.rawBody?.length || 0) > 65536) return res.status(400).send('Invalid event');
    try {
      if (!(await refFor(id).get()).exists) return res.status(404).send('Not found');
      // Event verification: ignore posted status/amount; retrieve the charge via
      // our secret, then bind account, test mode, amount, actor and instrument.
      await record(id, await api(`/charges/${chargeId}`));
      return res.status(200).json({received:true});
    } catch (e) { return res.status(e.code === 'unavailable' ? 503 : 400).send('Unable to verify event'); }
  }
  async function config(request) {
    signed(request);
    return {publicKey:PUBLIC_KEY, amount:AMOUNT, currency:'THB', testMode:true};
  }
  return {config, create, status, webhook};
}
module.exports = {client, handlers, validateCharge, AMOUNT, PUBLIC_KEY};
