const test = require('node:test');
const assert = require('node:assert/strict');
const { fixture } = require('./accounting_fixture.cjs');
const { handlers } = require('./line_link');
class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
const request = { auth: { uid: 'owner', token: {} }, data: { shopId: 'owner' } };
const userId = 'U' + 'a'.repeat(32);
function setup() {
  const f = fixture({ 'shops/owner': {name: 'Shop'} }); let time = 100000;
  return { ...f, api: handlers({ db: f.db, HttpsError, now: () => time }), advance: ms => time += ms };
}
const textOf = response => decodeURIComponent(response.url.split('/?')[1]);
test('owner-only issue, rate limit, unguessable token and no raw token stored', async () => {
  const f = setup();
  for (const bad of [{}, {...request, auth: { uid: 'attacker' }}, {...request, auth: {uid: 'owner', token: {staffRole: 'cashier'}}}]) {
    await assert.rejects(f.api.start(bad), { code: 'permission-denied' });
    await assert.rejects(f.api.status(bad), { code: 'permission-denied' });
    await assert.rejects(f.api.cancel(bad), { code: 'permission-denied' });
  }
  const link = await f.api.start(request);
  assert.match(textOf(link), /^connect:owner:[0-9a-f]{64}$/);
  assert.ok(!JSON.stringify([...f.docs]).includes(textOf(link).split(':')[2]));
  await assert.rejects(f.api.start(request), {code: 'resource-exhausted'});
});
test('signed one-to-one recipient binds once atomically; replay and group fail', async () => {
  const f = setup(), text = textOf(await f.api.start(request));
  assert.equal(await f.api.consume({text, userId, sourceType:'group'}), false);
  assert.equal(await f.api.consume({text:text.replace(/.$/,'z'), userId, sourceType:'user'}), false);
  const results = await Promise.all([f.api.consume({text,userId,sourceType:'user'}), f.api.consume({text,userId:'U'+'b'.repeat(32),sourceType:'user'})]);
  assert.deepEqual(results, [true,false]);
  assert.equal(f.docs.get('shops/owner/settings/shop').lineUserId, userId);
  assert.deepEqual(await f.api.status(request), {status:'connected'});
});
test('expiry, replacement, cancellation and public shop ID cannot connect', async () => {
  const f=setup(); const first=textOf(await f.api.start(request));
  f.advance(600001);
  assert.equal(await f.api.consume({text:first,userId,sourceType:'user'}),false);
  const second=textOf(await f.api.start(request)); f.advance(30001);
  const third=textOf(await f.api.start(request));
  assert.equal(await f.api.consume({text:second,userId,sourceType:'user'}),false);
  await f.api.cancel(request);
  assert.equal(await f.api.consume({text:third,userId,sourceType:'user'}),false);
  assert.equal(await f.api.consume({text:'connect:owner',userId,sourceType:'user'}),false);
  assert.ok(!f.docs.has('shops/owner/settings/shop'));
});
