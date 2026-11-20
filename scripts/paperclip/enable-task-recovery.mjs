// Enable Paperclip's queue/retry recovery. Individual agent timers are separate.
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';

const root = path.resolve(process.argv[2] ?? 'D:/PokpokTools/paperclip');
const pkg = JSON.parse(await readFile(path.join(root, 'node_modules/@paperclipai/server/package.json'), 'utf8'));
assert.equal(pkg.version, '2026.1106.0', 'Review scheduler behavior before updating another version');
const file = path.join(root, 'Start-Paperclip.ps1');
const original = await readFile(file, 'utf8');
const before = "$env:HEARTBEAT_SCHEDULER_ENABLED = 'false'";
const after = "$env:HEARTBEAT_SCHEDULER_ENABLED = 'true'";
if (original.includes(after)) {
  console.log('Task recovery scheduler already enabled in launcher');
} else {
  assert.equal(original.split(before).length - 1, 1, 'Expected one scheduler setting');
  const backupDir = path.join(root, 'local-fixes/autonomy-20261120');
  await mkdir(backupDir, { recursive: true });
  const backup = path.join(backupDir, 'Start-Paperclip.ps1.before-recovery');
  try {
    await writeFile(backup, original, { flag: 'wx' });
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
    assert.equal(await readFile(backup, 'utf8'), original, 'Existing launcher backup differs');
  }
  await writeFile(file, original.replace(before, after));
  console.log('Task recovery scheduler enabled in launcher. Restart Paperclip to load it.');
}
