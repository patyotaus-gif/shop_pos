const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {ref, uploadBytes, getBytes, deleteObject} = require('firebase/storage');

(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-pokpok-storage',
    storage: {host: '127.0.0.1', port: 9299,
      rules: fs.readFileSync(path.join(__dirname, '../storage.rules'), 'utf8')},
  });
  try {
    const owner = env.authenticatedContext('shop-a').storage();
    const other = env.authenticatedContext('shop-b').storage();
    const staff = env.authenticatedContext('staff-a', {staffRole: 'cashier', staffShopId: 'shop-a'}).storage();
    const guest = env.unauthenticatedContext().storage();
    const logo = 'shops/shop-a/logo.jpg';
    const bytes = new Uint8Array([255, 216, 255, 217]);
    const image = {contentType: 'image/jpeg'};
    await assertSucceeds(uploadBytes(ref(owner, logo), bytes, image));
    await assertSucceeds(uploadBytes(ref(owner, logo), bytes, image));
    await assertSucceeds(getBytes(ref(guest, logo)));
    for (const actor of [other, staff, guest]) {
      await assertFails(uploadBytes(ref(actor, logo), bytes, image));
      await assertFails(deleteObject(ref(actor, logo)));
    }
    await assertFails(uploadBytes(ref(owner, logo), bytes, {contentType: 'text/html'}));
    await assertFails(uploadBytes(ref(owner, logo), new Uint8Array(5 * 1024 * 1024 + 1), image));
    await assertFails(uploadBytes(ref(owner, 'shops/shop-a/private.txt'), bytes, image));
    await assertSucceeds(uploadBytes(ref(owner, 'shops/shop-a/products/test.jpg'), bytes, image));
    await assertSucceeds(deleteObject(ref(owner, logo)));
    console.log('Storage rules passed: owner logo create/update/delete, public read, foreign/staff/anonymous denial, type/size/path limits, product compatibility.');
  } finally {
    await env.cleanup();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
