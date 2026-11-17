// Local compatibility fix for the pinned external Paperclip install (2026.1106.0).
//
// Problem: managed AI runs create a per-run Codex home under the process TEMP.
// With TEMP = D:\PokpokTools\paperclip\temp, Codex's observability state folder
// (`...\provider\paperclip-observability\<agent id>\<hash>`) is 258 characters,
// so its SQLite file passes Windows MAX_PATH (260) while LongPathsEnabled = 0.
// The first real run (POK-1, 2026-11-17) failed with
// "failed to initialize sqlite state runtime" (acpx_session_init_failed).
//
// Fix: point Paperclip's TEMP/TMP at the short folder D:\pt (saves 24
// characters; the longest path becomes ~253). No Administrator rights needed and
// no machine-wide setting changes; only the launcher's own process env changes.
//
// Usage: node repair-windows-short-temp.mjs <Paperclip install root>
// Restart Paperclip afterwards (Stop-Paperclip, then Open-Paperclip).
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import path from 'node:path';

assert.equal(process.platform, 'win32', 'This fix is for native Windows only');
const root = path.resolve(process.argv[2] ?? 'D:/PokpokTools/paperclip');
const pkg = JSON.parse(await readFile(path.join(root, 'node_modules/@paperclipai/server/package.json'), 'utf8'));
assert.equal(pkg.version, '2026.1106.0', 'Review newer Paperclip versions before patching');

const file = path.join(root, 'Start-Paperclip.ps1');
const MARKER = 'PAPERCLIP_LOCAL_FIX_SHORT_TEMP';
const from = "$env:TEMP = Join-Path $installRoot 'temp'";
const to = `# ${MARKER}: Codex run state under TEMP must stay below Windows MAX_PATH (260).
$env:TEMP = 'D:\\pt'`;

const raw = await readFile(file, 'utf8');
if (raw.includes(MARKER)) {
  console.log('already applied:', path.relative(root, file));
  process.exit(0);
}
const count = raw.split(from).length - 1;
assert.equal(count, 1, `expected one patch site, found ${count}`);

const backupDir = path.join(root, 'local-fixes/windows-short-temp-20261117');
await mkdir(backupDir, { recursive: true });
const backup = path.join(backupDir, 'Start-Paperclip.ps1.original');
try { await access(backup); } catch { await writeFile(backup, raw); }
await mkdir('D:/pt', { recursive: true });
await writeFile(file, raw.replace(from, () => to));
console.log('patched:', path.relative(root, file), '| TEMP -> D:\\pt | original saved to', path.relative(root, backup));
