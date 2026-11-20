// Codex can complete its turn with exit 0 after the Windows launcher fails.
// Only inspect actual command results, never prose or quoted historical logs.
export const MXC_ERROR = 'MXC launcher: native MXC is unavailable on this Windows build';

export function normalizeMxcAttempt(attempt) {
  if (attempt.proc.exitCode !== 0 || attempt.proc.timedOut || attempt.proc.signal || attempt.monitor?.fired) {
    return attempt;
  }
  let unavailable = false;
  for (const line of attempt.proc.stdout.split(/\r?\n/)) {
    let event;
    try { event = JSON.parse(line); } catch { continue; }
    const item = event?.item;
    if (event?.type !== 'item.completed' || item?.type !== 'command_execution') continue;
    if (item.status === 'completed' && item.exit_code === 0) {
      // The agent recovered in this turn; do not replay already finished work.
      unavailable = false;
    } else if (item.status === 'failed' && item.exit_code === 1 &&
        typeof item.aggregated_output === 'string' && item.aggregated_output.trim() === MXC_ERROR) {
      unavailable = true;
    }
  }
  if (!unavailable) return attempt;
  return {
    ...attempt,
    proc: {...attempt.proc, exitCode: 1, errorCode: 'codex_transient_upstream'},
    parsed: {...attempt.parsed, errorMessage: `${MXC_ERROR}. The agent turn ended but command execution did not recover. Resume from saved work in a new Codex process; keep sandbox permissions unchanged.`},
  };
}

export function patchMxcRecovery(source) {
  const marker = '// PAPERCLIP_LOCAL_FIX_MXC_RECOVERY';
  if (source.includes(marker)) return source;
  const sites = [
    ['import { createHash } from "node:crypto";', `${marker}\nimport { normalizeMxcAttempt } from "./codex-mxc-recovery.mjs";\nimport { createHash } from "node:crypto";`],
    ['const toResult = (attempt, clearSessionOnMissingSession = false, isRetry = false) => {',
      'const toResult = (attempt, clearSessionOnMissingSession = false, isRetry = false) => {\n            attempt = normalizeMxcAttempt(attempt);'],
    ['isCodexTransientUpstreamError({\n                    stdout: attempt.proc.stdout,\n                    stderr: attempt.proc.stderr,\n                    errorMessage: fallbackErrorMessage,\n                });',
      '(attempt.proc.errorCode === "codex_transient_upstream" || isCodexTransientUpstreamError({\n                    stdout: attempt.proc.stdout,\n                    stderr: attempt.proc.stderr,\n                    errorMessage: fallbackErrorMessage,\n                }));'],
  ];
  let next = source;
  for (const [from, to] of sites) {
    if (next.split(from).length !== 2) throw new Error(`Unexpected adapter patch site: ${from.slice(0, 70)}`);
    next = next.replace(from, () => to);
  }
  return next;
}
