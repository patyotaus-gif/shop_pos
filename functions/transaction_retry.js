'use strict';
const {setTimeout: delay}=require('node:timers/promises');

// Firestore normally retries contention itself, but an invalidated transaction
// can surface as code 3 with this exact message (also seen in the emulator).
// Only use with idempotent, database-only callbacks. Never reuse its transaction
// object or retry a validation/permission error or an arbitrary network failure.
async function runTransaction(db, action) {
  for (let attempt=0; ; attempt++) {
    try { return await db.runTransaction(action); }
    catch (error) {
      const message=error?.details || error?.message || '';
      const closed=error?.code===3 && /^(?:3 INVALID_ARGUMENT: )?Transaction is invalid or closed\.$/.test(message);
      if (!closed || attempt>=2) throw error;
      await delay(50*(attempt+1)+Math.floor(Math.random()*50));
    }
  }
}
module.exports={runTransaction};
