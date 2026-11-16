// Local compatibility fix for the pinned external Paperclip install (2026.1106.0).
//
// Problem: managed AI connections write a fresh per-run Codex home whose
// config.toml contains only `cli_auth_credentials_store = "file"`. With no
// Windows sandbox mode, Codex falls back to the legacy "elevated" sandbox,
// which needs an Administrator (UAC) prompt to launch its setup helper. Agent
// runs are unattended, so every sandboxed command fails with error 1223 and
// Paperclip's lifecycle check reports `harness_test_failed`.
//
// Fix: on Windows, append `[windows] sandbox = "mxc"` to that config. MXC is
// OpenAI's recommended Windows sandbox (Windows 11 24H2/25H2 build x.9278+),
// needs no Administrator setup, and was verified on this machine to run
// workspace commands and block writes outside the workspace.
//
// Does not touch accounts, credentials, agent permissions, or the Pokpok app.
// Usage: node repair-windows-codex-sandbox.mjs <Paperclip install root>
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import path from 'node:path';

assert.equal(process.platform, 'win32', 'This fix is for native Windows only');
const root = path.resolve(process.argv[2] ?? 'D:/PokpokTools/paperclip');
const serverRoot = path.join(root, 'node_modules/@paperclipai/server');
const pkg = JSON.parse(await readFile(path.join(serverRoot, 'package.json'), 'utf8'));
assert.equal(pkg.version, '2026.1106.0', 'Review newer Paperclip versions before patching');

const file = path.join(serverRoot, 'dist/services/ai-connection-runtime.js');
const MARKER = 'PAPERCLIP_LOCAL_FIX_CODEX_WINDOWS_SANDBOX';
const constant = `// ${MARKER}: unattended runs cannot answer the legacy elevated sandbox's
// Administrator prompt; select the MXC sandbox, which needs no setup.
const CODEX_WINDOWS_SANDBOX_TOML = process.platform === "win32" ? '\\n[windows]\\nsandbox = "mxc"\\n' : "";
`;
const replacements = [
  ['import path from "node:path";\n', 'import path from "node:path";\n' + constant],
  [
    `await writeFile(path.join(providerHome, "config.toml"), 'cli_auth_credentials_store = "file"\\n', { mode: 0o600 });`,
    `await writeFile(path.join(providerHome, "config.toml"), 'cli_auth_credentials_store = "file"\\n' + CODEX_WINDOWS_SANDBOX_TOML, { mode: 0o600 });`,
  ],
  [
    `await writeFile(path.join(providerHome, "config.toml"), 'cli_auth_credentials_store = "file"\\n' + projected.codexConfig, { mode: 0o600 });`,
    `await writeFile(path.join(providerHome, "config.toml"), 'cli_auth_credentials_store = "file"\\n' + projected.codexConfig + CODEX_WINDOWS_SANDBOX_TOML, { mode: 0o600 });`,
  ],
];

const original = await readFile(file, 'utf8');
if (original.includes(MARKER)) {
  console.log('already applied:', path.relative(root, file));
  process.exit(0);
}
let next = original;
for (const [from, to] of replacements) {
  const count = next.split(from).length - 1;
  assert.equal(count, 1, `expected one patch site, found ${count}: ${from.slice(0, 80)}`);
  next = next.replace(from, () => to);
}

const backupDir = path.join(root, 'local-fixes/windows-codex-sandbox-20261117');
await mkdir(backupDir, { recursive: true });
const backup = path.join(backupDir, 'ai-connection-runtime.js.original');
try { await access(backup); } catch { await writeFile(backup, original); }
await writeFile(file, next);
console.log('patched:', path.relative(root, file), '| original saved to', path.relative(root, backup));
console.log('Restart Paperclip gracefully (Stop-Paperclip, then Open-Paperclip) to load the change.');
