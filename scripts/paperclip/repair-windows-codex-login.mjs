// Local compatibility fix for the pinned external Paperclip install. Does not
// touch accounts, credentials, agent permissions, or the Pokpok application.
// Usage: node repair-windows-codex-login.mjs <Paperclip install root>
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';

assert.equal(process.platform, 'win32', 'This fix is for native Windows only');
const root = path.resolve(process.argv[2] ?? 'D:/PokpokTools/paperclip');
const serverRoot = path.join(root, 'node_modules/@paperclipai/server');
const pkg = JSON.parse(await readFile(path.join(serverRoot, 'package.json'), 'utf8'));
assert.equal(pkg.version, '2026.1106.0', 'Review newer Paperclip versions before patching');

const edits = [
  {
    file: path.join(root, 'Start-Paperclip.ps1'),
    replacements: [[
      '$env:Path = "$nodeDir;$env:Path"',
      String.raw`# Desktop launches do not inherit VS Code's extension-specific PATH.
# Discover the installed native Codex binary each start, including after an
# extension update. Never copy its credentials or change machine-wide PATH.
$codexCommand = Get-Command codex.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$codexDir = $null
if ($codexCommand) {
  $codexDir = Split-Path -Parent $codexCommand.Source
} else {
  $extensionsDir = Join-Path $env:USERPROFILE '.vscode\extensions'
  if (Test-Path -LiteralPath $extensionsDir) {
    $codexExtensions = Get-ChildItem -LiteralPath $extensionsDir -Directory -Filter 'openai.chatgpt-*-win32-x64' | Sort-Object LastWriteTime -Descending
    foreach ($extension in $codexExtensions) {
      $candidate = Join-Path $extension.FullName 'bin\windows-x86_64\codex.exe'
      if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $codexDir = Split-Path -Parent $candidate
        break
      }
    }
  }
}
$env:Path = (@($nodeDir, $codexDir, $env:Path) | Where-Object { $_ }) -join ';'`,
    ]],
  },
  {
    file: path.join(serverRoot, 'dist/services/local-ai-browser-login.js'),
    replacements: [
      [
        'child = spawn("python3", ["-u", "-c", PYTHON_PTY_BRIDGE, executable, ...args], { env, stdio: ["pipe", "pipe", "pipe"] });',
        `// Codex device auth supports pipes. Python's POSIX pty bridge does
                // not run on Windows; use the resolved native .exe without a shell.
                const nativeCodex = process.platform === "win32" && provider === "openai";
                child = nativeCodex
                    ? spawn(executable, args, { env, windowsHide: true, shell: false, stdio: ["pipe", "pipe", "pipe"] })
                    : spawn("python3", ["-u", "-c", PYTHON_PTY_BRIDGE, executable, ...args], { env, stdio: ["pipe", "pipe", "pipe"] });`,
      ],
      [
        '// Provider output may contain secrets. Never log or retain stderr.\n                child.stderr.resume();',
        `// Native Codex may emit the device prompt on stderr. Feed it only
                // to the bounded in-memory login parser; never log provider output.
                if (nativeCodex) child.stderr.on("data", (bytes) => onData(bytes.toString("utf8")));
                else child.stderr.resume();`,
      ],
      [
        'state.error = "Browser sign-in requires Python 3 and a working local terminal. Install Python 3 on this execution host, then start sign-in again.";',
        `state.error = nativeCodex
                        ? "Codex could not start on Windows. Check the installed Codex executable and restart sign-in."
                        : "Browser sign-in requires Python 3 and a working local terminal. Install Python 3 on this execution host, then start sign-in again.";`,
      ],
    ],
  },
  {
    file: path.join(serverRoot, 'dist/services/local-ai-login.js'),
    // Windows can retain file handles briefly after cancellation kills the CLI.
    // Keep cleanup bounded and retry only Node's documented transient fs errors.
    replacements: [
      ['await rm(loginHome(row.id), { recursive: true, force: true });',
       'await rm(loginHome(row.id), { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });'],
      ['await rm(loginHome(existing.id), { recursive: true, force: true });',
       'await rm(loginHome(existing.id), { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });'],
      ['await rm(directory, { recursive: true, force: true });',
       'await rm(directory, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });'],
      ['await rm(loginHome(id), { recursive: true, force: true });',
       'await rm(loginHome(id), { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });', 2],
    ],
  },
];

// Validate every replacement before changing any file. Unknown/upgraded sources
// stop here instead of overwriting them with the pinned compatibility patch.
const prepared = [];
for (const edit of edits) {
  const original = await readFile(edit.file);
  let updated = original.toString('utf8').replaceAll('\r\n', '\n');
  let changed = false;
  for (const [before, after, count = 1] of edit.replacements) {
    if (updated.split(after).length === count + 1 && !updated.includes(before)) continue;
    assert.equal(updated.split(before).length, count + 1,
      `Unexpected number of matching patch sites: ${path.basename(edit.file)}`);
    updated = updated.replaceAll(before, after);
    changed = true;
  }
  if (changed) prepared.push({ ...edit, original, updated });
}
const backupRoot = path.join(root, 'local-fixes/windows-codex-login-20261115');
await mkdir(backupRoot, { recursive: true });
for (const edit of prepared) {
  const backup = path.join(backupRoot, `${path.basename(edit.file)}.original`);
  try {
    await writeFile(backup, edit.original, { flag: 'wx' });
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
    assert.ok((await readFile(backup)).equals(edit.original),
      'Existing backup differs; review before changing this install');
  }
}
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
for (const edit of prepared) {
  await writeFile(edit.file, edit.updated, 'utf8');
  console.log(JSON.stringify({ file: path.relative(root, edit.file),
    beforeSha256: sha256(edit.original), afterSha256: sha256(edit.updated) }));
}
console.log(prepared.length
  ? `Patched ${prepared.length} files. Restart Paperclip gracefully to load changes.`
  : 'Patched 0 files. The compatibility fix is already present.');
