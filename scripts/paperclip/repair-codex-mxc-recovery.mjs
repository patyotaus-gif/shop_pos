// Opt-in fix for the pinned external installation. Preview unless --apply.
// Recognizes the observed launcher fault as a bounded retryable failure, while
// retaining the same session, permissions, model and original artifacts.
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import path from 'node:path';
import {patchMxcRecovery} from './codex-mxc-recovery.mjs';

const root = path.resolve(process.argv.slice(2).find(x => !x.startsWith('--')) ?? 'D:/PokpokTools/paperclip');
const adapter = path.join(root, 'node_modules/@paperclipai/adapter-codex-local');
assert.equal(JSON.parse(await readFile(path.join(adapter, 'package.json'), 'utf8')).version, '2026.1106.0');
const target = path.join(adapter, 'dist/server/execute.js');
const original = await readFile(target, 'utf8');
const next = patchMxcRecovery(original);
const helper = await readFile(new URL('./codex-mxc-recovery.mjs', import.meta.url), 'utf8');
if (!process.argv.includes('--apply')) {
  console.log(next === original ? 'Adapter recovery patch is installed.' : 'Adapter recovery patch is ready; use --apply while all agents are idle.');
  process.exit(0);
}
const response = await fetch('http://127.0.0.1:3100/api/companies/696941b8-3918-40a1-868e-f81178444a60/agents');
assert.ok(response.ok, 'Cannot verify agent state');
const agents = await response.json();
assert.ok(agents.length === 13 && agents.every(a => a.status === 'idle'), 'All agents must be idle before applying');
const backupDir = path.join(root, 'local-fixes/mxc-recovery-20261121');
await mkdir(backupDir, {recursive: true});
if (next !== original) {
  await writeFile(path.join(backupDir, 'execute.js.original'), original, {flag: 'wx'});
}
await writeFile(path.join(adapter, 'dist/server/codex-mxc-recovery.mjs'), helper);
await writeFile(target, next);
assert.equal(await readFile(target, 'utf8'), next);
console.log('Installed and verified. Restart Paperclip gracefully to load the adapter.');
