import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {MXC_ERROR, normalizeMxcAttempt, patchMxcRecovery} from './codex-mxc-recovery.mjs';

const command = (output, exit = 1) => JSON.stringify({type: 'item.completed', item: {
  type: 'command_execution', status: exit === 0 ? 'completed' : 'failed', exit_code: exit, aggregated_output: output,
}});
const attempt = stdout => ({proc: {exitCode: 0, stdout, stderr: '', signal: null, timedOut: false},
  parsed: {sessionId: 'existing-session', summary: 'The turn finished', usageComplete: true}, monitor: {fired: false}});

test('launcher failure inside a successful turn becomes retryable without losing state', () => {
  const original = attempt(command(MXC_ERROR + '\n'));
  const result = normalizeMxcAttempt(original);
  assert.equal(result.proc.exitCode, 1);
  assert.equal(result.proc.errorCode, 'codex_transient_upstream');
  assert.equal(result.parsed.sessionId, 'existing-session');
  assert.equal(result.proc.stdout, original.proc.stdout);
  assert.equal(original.proc.exitCode, 0);
});

test('ordinary failures, quotes and historical text never trigger automatic replay', () => {
  for (const stdout of [command('Access denied'), command('prefix: ' + MXC_ERROR),
    JSON.stringify({type: 'item.completed', item: {type: 'agent_message', text: MXC_ERROR}}),
    command(JSON.stringify({aggregated_output: MXC_ERROR}), 0), MXC_ERROR, 'null\n{}']) {
    const original = attempt(stdout);
    assert.equal(normalizeMxcAttempt(original), original);
  }
});

test('recovered commands clear the fault; a later recurrence is still detected', () => {
  const recovered = attempt(command(MXC_ERROR) + '\n' + command('ok', 0));
  assert.equal(normalizeMxcAttempt(recovered), recovered);
  assert.equal(normalizeMxcAttempt(attempt(recovered.proc.stdout + '\n' + command(MXC_ERROR))).proc.exitCode, 1);
});

test('cancellation, timeout, monitor termination and pre-existing process errors keep their meaning', () => {
  for (const update of [{signal: 'SIGTERM'}, {timedOut: true}, {exitCode: 2}]) {
    const original = attempt(command(MXC_ERROR)); Object.assign(original.proc, update);
    assert.equal(normalizeMxcAttempt(original), original);
  }
  const original = attempt(command(MXC_ERROR)); original.monitor.fired = true;
  assert.equal(normalizeMxcAttempt(original), original);
});

// Exercise the installed adapter's real result builder, with only its surrounding
// invocation context supplied. This catches returning success/errorFamily=null.
export function resultBuilder(source) {
  const start = source.indexOf('const toResult = (attempt, clearSessionOnMissingSession');
  const end = source.indexOf('\n        let executionError = null;', start);
  assert.ok(start >= 0 && end > start);
  const context = {normalizeMxcAttempt, forceFreshSession: false, runtimeSessionId: null, runtime: {},
    effectiveExecutionCwd: 'D:/fixture', executionTargetIsRemote: false, workspaceId: null,
    workspaceRepoUrl: null, workspaceRepoRef: null, model: 'unchanged', biller: 'openai', billingType: 'subscription_included',
    firstMeaningfulStderrLine: () => '', extractCodexRetryNotBefore: () => null,
    classifyCodexAuthRefreshFailure: () => null, isCodexProviderQuotaError: () => false,
    isCodexTransientUpstreamError: () => false, isCodexHarnessCrash: () => false};
  return vm.runInNewContext(source.slice(start, end) + '\ntoResult;', context);
}

test('pinned adapter passes the infrastructure failure to its bounded retry scheduler', async () => {
  const source = await readFile('D:/PokpokTools/paperclip/node_modules/@paperclipai/adapter-codex-local/dist/server/execute.js', 'utf8');
  const candidate = process.env.PAPERCLIP_TEST_UNPATCHED === '1' ? source : patchMxcRecovery(source);
  const result = resultBuilder(candidate)(attempt(command(MXC_ERROR)));
  assert.equal(result.exitCode, 1);
  assert.equal(result.errorCode, 'codex_transient_upstream');
  assert.equal(result.errorFamily, 'transient_upstream');
  assert.equal(result.resultJson.errorFamily, 'transient_upstream');
  assert.equal(result.sessionId, 'existing-session');
  assert.equal(result.clearSession, false);
  assert.equal(patchMxcRecovery(candidate), candidate);
});
