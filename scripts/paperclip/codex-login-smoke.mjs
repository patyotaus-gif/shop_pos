// Opt-in local integration check: contacts OpenAI only to request a device-code
// prompt. Never authorizes it, copies credentials, or runs a model/agent task.
// Usage: node codex-login-smoke.mjs <Paperclip install root>
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, access } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = path.resolve(process.argv[2] ?? 'D:/PokpokTools/paperclip');
const loginHome = await mkdtemp(path.join(root, 'temp', 'login-smoke-'));
await writeFile(path.join(loginHome, 'config.toml'),
  'cli_auth_credentials_store = "file"\n', { mode: 0o600 });
// This fresh, empty login home is intentionally retained for inspection. No
// user can authorize the attempt: neither its code nor its URL is printed.
const { startLocalBrowserLogin } = await import(pathToFileURL(path.join(root,
  'node_modules/@paperclipai/server/dist/services/local-ai-browser-login.js')));
const state = startLocalBrowserLogin('openai', loginHome);
try {
  const deadline = Date.now() + 25_000;
  while (!state.authorizationUrl && !state.outcome && Date.now() < deadline) {
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  const hasPrompt = Boolean(state.authorizationUrl && state.code);
  const hasCredential = await access(path.join(loginHome, 'auth.json'))
    .then(() => true, () => false);
  console.log(JSON.stringify({ hasPrompt, hasCredential,
    outcome: state.outcome ?? 'pending', error: state.error ?? null }));
  assert.equal(hasPrompt, true, 'Paperclip must surface the device sign-in prompt');
  assert.equal(hasCredential, false, 'Check must not authorize an account');
} finally {
  state.abort();
  const deadline = Date.now() + 3_000;
  while (!state.outcome && Date.now() < deadline) {
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  assert.ok(state.outcome, 'Cancelled login must finish');
}
