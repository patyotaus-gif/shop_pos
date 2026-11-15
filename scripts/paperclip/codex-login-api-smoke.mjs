// Local API + real Codex prompt check. Explicitly replaces a stuck local login,
// cancels only its own attempt, never completes authorization or runs an agent.
// Usage: node codex-login-api-smoke.mjs <company UUID> --restart-pending-sign-in
import assert from 'node:assert/strict';

assert.ok(process.argv.includes('--restart-pending-sign-in'),
  'Explicit flag required: this check replaces the pending local sign-in');
const companyId = process.argv[2];
assert.match(companyId ?? '', /^[a-f0-9-]{36}$/i, 'Company UUID required');
const base = `http://127.0.0.1:3100/api/companies/${companyId}/ai-connections`;
const intent = { provider: 'openai', method: 'subscription',
  name: 'Windows login compatibility check', ownership: 'personal',
  agentIds: [], allAgents: false };
async function request(url, method = 'GET', body) {
  const response = await fetch(url, { method,
    headers: { 'Content-Type': 'application/json', Origin: 'http://127.0.0.1:3100' },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(10_000) });
  assert.ok(response.ok, `Local API HTTP ${response.status}`);
  return response.json();
}
const before = await request(base);
let attempt;
try {
  attempt = await request(`${base}/local/attempts`, 'POST', { ...intent, restart: true });
  let result;
  const deadline = Date.now() + 25_000;
  do {
    result = await request(`${base}/local/check`, 'POST', {
      ...intent, localSessionId: attempt.sessionId });
    if ((result.authorizationUrl && result.code) || result.error) break;
    await new Promise(resolve => setTimeout(resolve, 250));
  } while (Date.now() < deadline);
  const hasPrompt = Boolean(result.authorizationUrl && result.code);
  console.log(JSON.stringify({ status: result.status, hasPrompt,
    hasError: Boolean(result.error) }));
  assert.equal(result.status, 'sign_in_required');
  assert.equal(hasPrompt, true, 'Running server must return the device login prompt');
  assert.equal(Boolean(result.error), false);
  assert.equal((await request(base)).connections.length, before.connections.length,
    'Check must not create an AI connection');
} finally {
  if (attempt) {
    await request(`${base}/local/attempts/${attempt.sessionId}`, 'DELETE');
    const cancelled = await request(`${base}/local/check`, 'POST', {
      ...intent, localSessionId: attempt.sessionId });
    assert.equal(cancelled.status, 'expired', 'Cancelled attempt must not remain usable');
    console.log('Check sign-in cancelled; no authorization or agent run performed.');
  }
}
