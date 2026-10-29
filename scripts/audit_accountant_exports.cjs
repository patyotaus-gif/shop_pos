'use strict';
// Regression entry point after the exploratory accountant audit was fixed.
// Executes production export builders with simulated data, no Firebase writes.
const {spawnSync} = require('node:child_process');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const windows = process.platform === 'win32';
const result = spawnSync(windows ? 'cmd.exe' : path.join(root, 'flutter/bin/flutter'),
  windows ? ['/d', '/c', 'flutter\\bin\\flutter.bat test --no-pub test/accounting_exports_test.dart']
    : ['test', '--no-pub', 'test/accounting_exports_test.dart'],
  {cwd: root, stdio: 'inherit'});
if (result.error) console.error(result.error.message);
process.exitCode = result.status ?? 1;