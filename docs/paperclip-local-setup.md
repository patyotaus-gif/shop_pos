# Paperclip for Pokpok

Setup date: 2026-11-15. Local operator tooling, separate from the Pokpok app.

## Target environment

| Item | Local setup |
| --- | --- |
| Upstream | https://github.com/paperclipai/paperclip |
| Package | `paperclipai@2026.1106.0` (pinned) |
| Installation | `D:\PokpokTools\paperclip` |
| Runtime | Portable Node v24.22.3, SHA256 verified against nodejs.org |
| Project checkout | `C:\Users\Dav\shop_pos` |
| Project repository | https://github.com/patyotaus-gif/shop_pos |
| Dashboard | http://127.0.0.1:3100 |
| Data home | `D:\PokpokTools\paperclip\data` |
| Company / project | `Pokpok` / `Pokpok POS` |

The global Node v22.18.0 used by Pokpok is not replaced. Paperclip does not use
Pokpok's Firebase database, payment environment, hosting or production keys.

## Installation and verification

- Owner confirmed a new installation of `paperclipai/paperclip` for Pokpok.
- Portable Node downloaded and checksum checked.
- Initial npm installation on C: stopped with `ENOSPC` (insufficient disk space).
  Only the new Paperclip folder was moved to D:, which had over 220 GB free.
  Its partial dependency tree is retained as `incomplete-node_modules`; the
  replacement installation uses its own npm cache and temp directory on D:.
- Local data-folder ACL allows the current Windows user, SYSTEM and Administrators.
- Replacement npm installation completed; the CLI reports `2026.1106.0`.
- Initial doctor passed all 11 critical checks. Its Unix file-mode warning was
  checked against the actual Windows ACL on the generated local encryption key.
- UI HTML, JavaScript and CSS returned HTTP 200. API health reported `ok` and
  startup recovery `ready`. Actual listeners were `127.0.0.1:3100` for HTTP and
  loopback only for PostgreSQL on 54329.
- The company/project and exact checkout/repository mapping were verified through
  the API, including after restarting. Agent count was zero at installation.
- Start/stop scripts passed local execution. Shutdown invokes Paperclip's own
  SIGINT handler through `shutdown-bridge.mjs`, using a PID-bound request in the
  restricted data directory. HTTP and PostgreSQL ports closed after stopping.
  Do not use `Stop-Process` as the normal shutdown method.
- Browser screenshot capture was rejected by automatic approval review with
  `blocked by policy`. The owner's subsequent screenshot shows the dashboard
  rendering; an actual AI task has not been verified.
- The initial installation did not run an AI agent, make a provider API request,
  write to GitHub, or deploy production. The later login repair below contacts
  OpenAI only for unauthorised device sign-in prompts.

## Open and close

1. Open **Paperclip - Pokpok** on the Desktop, or double-click
   `D:\PokpokTools\paperclip\Open-Paperclip.cmd`. It starts the local server and
   opens http://127.0.0.1:3100. Startup can take several minutes on this drive.
2. Select company **Pokpok** and project **Pokpok POS**. Its primary workspace is
   the existing `shop_pos` checkout on `master`, not a separate copy of the code.
3. Close the server with **Stop Paperclip - Pokpok** on the Desktop or
   `D:\PokpokTools\paperclip\Stop-Paperclip.cmd`.

The server does not start automatically when Windows starts. Closing the browser
does not stop it. Start/stop logs are in `D:\PokpokTools\paperclip\logs`.

The running helper scripts, runtime, package lock and application data stay
outside the Pokpok repository. Reproducible Windows login repair/check scripts
are kept under `scripts/paperclip/`. The launcher changes environment variables
only for its own process and does not replace the system-wide Node executable.

## Operating model

The initial setup is loopback-only `local_trusted`. It is for this Windows user
on this machine; it is not a public/team server. No router port or tunnel is
opened. Adding remote teammates requires a separately configured authenticated
deployment.

Provider credentials are not copied from Pokpok or from the connected ChatGPT
GitHub plugin. A repository URL/workspace link is different from authorizing
Paperclip's GitHub connector or signing in to an AI provider. Those connections
must be configured explicitly when needed.

No AI agents or routine jobs were enabled during installation. Automatic heartbeat
scheduling is disabled in the local launcher. A zero budget field means unlimited,
not a spending block.
New agents require board approval. Creating this workspace does not authorize
an AI to deploy Pokpok or change production/payment settings.

The bundled GitHub Copilot runtime installer reports `unsupported-platform
(win32-x64)` in this version. Do not assume every AI adapter works on native
Windows; provider login and a separately authorized agent run need their own test.

## First-use check (2026-11-15)

The owner subsequently created a `CEO` agent. A read-only API check found:

- Adapter `codex_local`, status `paused`; no explicit adapter model or directory.
  Assign a first task to `Pokpok POS` to identify its project workspace.
- Timer heartbeat disabled; on-demand wake enabled. Maximum concurrent runs is
  currently 20; start with one run at a time for the first trial.
- `dangerouslyBypassApprovalsAndSandbox` is enabled in this agent's configuration.
  Review execution permissions before assigning tasks against the real checkout.
- No saved Paperclip AI connections were returned. The host Codex CLI reports
  `Logged in using ChatGPT`; this is not proof of a successful Paperclip run.

Open **CEO** -> **Harness / Runtime** (or **Configure** in the Overview runtime
card). Under **Adapter**, open **Connection** -> **Choose a connection** ->
**Connect an account...**. The installed account chooser identifies the OpenAI
subscription option as **ChatGPT subscription**. Complete sign-in in the provider
window, select the saved connection and use **Save changes**. Review the agent's
execution settings. If Overview shows **Finish setup** next to **Run now**,
click it and complete the existing agent's setup wizard, ending with
**Finish setup**. This button replaces Resume when `pauseReason` is `setup`;
Run now cannot invoke the agent in that state. For a normally paused agent
after setup, use **Resume** when ready. Create a **New Task**, select
**Pokpok POS**, and assign **CEO**.
For an initial task, request a read-only summary of `AGENTS.md`, `docs/HANDOFF.md`
and the project structure; explicitly exclude code changes, commits, pushes,
deployments and production-data access. Check the task's run result before
assigning implementation work. These are operator steps, not actions performed
by the setup assistant. No agent was resumed or task launched during this check.

Codex authentication reference: https://learn.chatgpt.com/docs/auth?surface=cli

### CEO role plan (2026-11-15)

A later read-only API check found CEO `ready` / `idle` with no pause reason, so
setup is complete. Its managed instructions file still holds only the default
one-line text. The proposed role, authority limits, phased agent team, first
three tasks and the Instructions text to paste are in
[paperclip-ceo-role.md](paperclip-ceo-role.md). Nothing was written to
Paperclip by that plan.

### Owner connection follow-up

After the Windows repair, the owner's screenshot shows **Connection successful**
and **You have unsaved changes**. A read-only API check now lists one saved AI
connection; CEO remains paused with pause reason `setup`. Save the runtime form
and complete **Finish setup** before starting a task, as described above.
The successful runtime check verifies
connection readiness; a completed task against Pokpok POS is still untested.

## Windows Codex login repair (2026-11-15)

The disabled Connect button was accompanied by an actual launcher failure.
Desktop-launched Paperclip did not inherit VS Code's Codex PATH. After resolving
Codex, the installed login driver still tried to run Python's POSIX PTY bridge,
which does not work on native Windows.

The pinned external install now has these local compatibility changes:

- `Start-Paperclip.ps1` discovers native `codex.exe` from PATH, or the installed
  `openai.chatgpt-*-win32-x64` VS Code extension. Its directory is added only to
  Paperclip's process PATH, including when opened from the Desktop.
- Windows OpenAI login starts the native executable directly with pipes, without
  a shell or Python. It preserves Paperclip's isolated `CODEX_HOME`; the existing
  VS Code account/credential file is not copied. Provider stdout/stderr go only
  to Paperclip's bounded in-memory device-prompt parser.
- Temporary login cleanup retries transient filesystem locks for a bounded
  period. The child does not use its temporary login home as its working
  directory, avoiding a Windows directory lock during cancellation.

To reconnect: refresh the page, open **CEO -> Harness / Runtime -> Connection
-> Connect an account...**, choose **OpenAI Subscription**, and follow the
displayed OpenAI sign-in link/code. Complete authorization yourself. Then use
**Connect** and **Save changes**. If an old attempt is shown, use **Start sign-in
again**. Connect remains disabled until account authorization is ready.

The version-guarded repair is reproducible with:

```powershell
& 'D:\PokpokTools\paperclip\runtime\node-v24.22.3-win-x64\node.exe' scripts/paperclip/repair-windows-codex-login.mjs 'D:\PokpokTools\paperclip'
```

It validates known patch sites before writing, refuses different Paperclip
versions, and is idempotent. Original launcher and two service modules are under
`D:\PokpokTools\paperclip\local-fixes\windows-codex-login-20261115` as
`*.original`. Stop gracefully before restoring those exact files; restart after
applying/restoring. Reinstalling/upgrading Paperclip can replace the modified
service modules: review upstream Windows support before reapplying this fix.

Verification (local only):

- `codex-login-smoke.mjs` failed with the original Desktop PATH error and then
  the Python error; with the fix, the real CLI device prompt was parsed.
- Restarted Paperclip with only Machine + User PATH, matching a Desktop launch.
  Two `codex-login-api-smoke.mjs` start/prompt/cancel cycles passed through the
  running server. A cancelled attempt reports expired; no device-auth process
  remained. API sign-in responses contained a prompt and no error.
- Repair re-run changed zero files; runtime route returned HTTP 200; health was
  `ok` on `127.0.0.1:3100`; CEO stayed paused; saved AI connections stayed zero.
- These are opt-in local checks, outside app CI. They contact OpenAI for a device
  prompt but never authorize it, print its code, create a connection, or invoke
  a model. The API check requires a company UUID and the explicit
  `--restart-pending-sign-in` flag because it replaces a stuck sign-in attempt.
- Owner authorization, actual agent execution, and final UI interaction remain
  unverified. The CLI used was `0.164.0-alpha.11.1` bundled with VS Code.

## Windows Codex sandbox repair (2026-11-17)

New agents created with **Bypass sandbox** off failed Paperclip's lifecycle check
(`harness_test_failed`, "Codex hello probe failed"). With bypass on, the same probe
passed. Diagnosis on this machine (Windows 11 25H2, build 26200.9974, Codex CLI
0.169.0-alpha.11.1):

- Managed AI connections write a fresh per-run Codex home whose `config.toml` holds
  only `cli_auth_credentials_store = "file"` (by design it never copies the
  operator's settings). With no Windows sandbox mode, Codex uses the legacy
  **elevated** sandbox.
- A headless sandboxed `codex exec` that runs a shell command failed under elevated
  with `ShellExecuteExW failed to launch setup helper: 1223`. The helper needs an
  Administrator/UAC prompt that unattended runs cannot answer.
- The **MXC** sandbox (OpenAI's recommended Windows mode; needs build x.9278+, no
  Administrator setup) passed the official probe (`MXC_OK`). Headless, it ran a
  workspace command (`SANDBOX_CMD_OK`, exit 0), still worked when the Codex home was
  inside TEMP, and blocked a write to `C:\Users\Dav\` (exit 1, no file created).
- Paperclip's "Refusing to create helper binaries under temporary dir" message is
  only the first stderr line that Paperclip shows. It is a warning, not the cause.

Fix: `scripts/paperclip/repair-windows-codex-sandbox.mjs` (version-guarded and
idempotent) appends `[windows] sandbox = "mxc"` on Windows at both places that write
the managed Codex `config.toml` in `server/dist/services/ai-connection-runtime.js`.
The original file is saved in
`D:\PokpokTools\paperclip\local-fixes\windows-codex-sandbox-20261117\`. Re-running
the script changes nothing; `node --check` passes. Restart Paperclip to load it.
Reinstalling or upgrading Paperclip removes the change; review upstream before
reapplying.

```powershell
& 'D:\PokpokTools\paperclip\runtime\node-v24.22.3-win-x64\node.exe' scripts/paperclip/repair-windows-codex-sandbox.mjs 'D:\PokpokTools\paperclip'
```

After the owner restarted Paperclip, the per-run config contained `[windows]
sandbox = "mxc"` (captured during a test; `auth.json` was not read), but the probe
still failed. Reproducing Paperclip's exact environment (`HOME`/`CODEX_HOME` under
TEMP, same config and flags, no credentials) showed the remaining error:
`Not inside a trusted directory and --skip-git-repo-check was not specified`.
The adapter check runs in `D:\PokpokTools\paperclip`, which is not a git repo, and
Paperclip adds that flag only for remote sandboxes. Real tasks run in git worktrees
that pass this check anyway. The 11 sandboxed agents now carry
`adapterConfig.extraArgs = ["--skip-git-repo-check"]` (other keys unchanged). The
sandbox-on adapter test passed (`hello`), and after a lifecycle retry all 12 agents
became `idle` / `ready`. Managed connections reject `-c` overrides in `extraArgs`
(HTTP 422), so the sandbox mode itself must come from the patch above.

### First real task run (POK-1, 2026-11-17)

- The run failed in 12 seconds with `acpx_session_init_failed`: "failed to initialize
  sqlite state runtime". Codex's state folder under the per-run home
  (`<TEMP>\paperclip-ai-…\provider\paperclip-observability\<agent>\<hash>`) is
  258 characters. With the SQLite file name it exceeds Windows MAX_PATH (260), and
  `LongPathsEnabled` is 0. Fix: `scripts/paperclip/repair-windows-short-temp.mjs`
  sets the launcher's TEMP/TMP to `D:\pt`, which brings the longest path to about
  253 characters. It changes only the Paperclip process environment and needs no
  Administrator rights. The original launcher is in
  `local-fixes\windows-short-temp-20261117\`. It is idempotent, and the PowerShell
  parse reports no errors. A restart is required.
- The run's execution workspace was `shared_workspace` in `C:\Users\Dav\shop_pos`,
  not a D: worktree, because the instance's experimental
  `enableIsolatedWorkspaces` setting was off, so the project's worktree policy was
  ignored. Enabled `enableIsolatedWorkspaces` and
  `enableIsolatedWorkspacesByDefault` through `PATCH /api/instance/settings/experimental`.
  POK-1 stays bound to the shared workspace, so it should be cancelled and a new
  task created. The owner's checkout stayed clean.

- After the restart, POK-2 ran in an isolated D: worktree as intended, but its
  runs still failed with the same SQLite error under `D:\pt`. The failing folder
  is built only by the default **ACP** engine
  (`prepareAcpxCodexObservabilityHome`: a per-agent Codex home containing an
  `auth.json` file symlink and `sessions`/`skills` directory symlinks). The
  adapter hello test uses the Codex **CLI** lane, which never builds it, so the
  test passed while real runs failed. All agents now use
  `adapterConfig.engine = "cli"`, and CLI-lane tests pass. The exact reason the ACP
  home's SQLite fails on Windows is not confirmed. Keep `engine = "cli"` until it
  is.

- On the CLI engine, the first CEO run succeeded but could not call the Paperclip
  API ("connect UNKNOWN") or start PowerShell (error 8009001d). Paperclip passes
  `shell_environment_policy.include_only` built from its own launch environment,
  which lacks Windows' core variables. Every agent now has `adapterConfig.env` with
  `SystemRoot`, `WINDIR`, `COMSPEC`, `PATHEXT`, `USERPROFILE`, `APPDATA`,
  `LOCALAPPDATA`, `ProgramData` and `ProgramFiles`. Saving an agent re-runs the AI
  connection check, which can fail transiently; retry after a short wait.
  Include these keys when creating new agents.

Separately, at the owner's approval, the owner's own `C:\Users\Dav\.codex\config.toml`
was changed from `sandbox = "elevated"` to `sandbox = "mxc"`. The backup is
`config.toml.bak-20261117-elevated`. This affects Codex in VS Code only. Paperclip
agents do not read this file, so it is not required for the fix above. Restore the
backup to undo it.

## Local backups

Created initial database backup
`data\instances\default\data\backups\paperclip-20261115-103953.sql.gz`.
The instance is configured for hourly local database backups with 30-day
retention while the server is running. This is not an off-device backup.
A restore into another database has not been tested.

Keep the complete `data` directory safe, including configuration, `.env` and the
encryption key under `secrets`, as well as database backups and local storage.
Do not commit these files or publish them in a shared repository. The data ACL
allows only the current Windows user, SYSTEM and Administrators.

## Continuing assigned work (2026-11-20)

The owner authorized agents to carry assigned work through completion, reuse
earlier approvals, make reversible implementation decisions within their brief,
and follow child tasks through to the parent deliverable. All 13 managed
instruction files carry this policy. Public posting requires Board approval of
the final content, account, destination and publication occurrence. A concept
selection or production brief alone does not authorize publication.

The source roles are in `docs/paperclip-agents/` and the CEO Instructions block
in `docs/paperclip-ceo-role.md`. From the repository root, preview or sync them
with the following commands. Sync checks the existing revision before writing
and reads each saved file back. Paperclip also retains instruction history.

```powershell
node scripts/paperclip/sync-agent-instructions.mjs
node scripts/paperclip/sync-agent-instructions.mjs --apply
```

CTO has two additional Codex workspace grants through `extraArgs` using
`--add-dir`. One covers `D:/PokpokWork/worktrees` so it can prepare and inspect
task workspaces. The other covers the exact retained POK-12 workspace returned
by `GET /api/issues/a4b766c3-b8d1-4acb-ba94-d29a3acb6811/workspace` at binding
revision 1. These grants permit filesystem writes as well as reads. Task
instructions restrict edits to the assigned work and require preserving other
agents' changes. CTO continues with sandbox bypass disabled.

The managed Codex home does not inherit the operator's Git configuration.
The retained POK-12 repository now has local `core.longpaths=true`, which applies
inside the agent's managed runtime. Ten agents also have
`GIT_CONFIG_COUNT=1`, `GIT_CONFIG_KEY_0=core.longpaths` and
`GIT_CONFIG_VALUE_0=true` in their runtime environments. Reviewer / QA,
Security & Data and COO / Field Ops still await this additional environment
setting because the provider hello validation timed out. Their updated
continuation/publication instructions are installed and verified. The launcher
uses the host Git setting when provisioning checkouts.
Review existing `GIT_CONFIG_*` overrides before adding more entries. Remove the
three environment keys, or unset the retained repository's local core.longpaths,
to restore the respective prior state.

Content Marketer's `POKPOK_IG_ACCESS_TOKEN` secret reference was removed from
its persistent environment. The stored secret remains available to the operator.
Before an approved publication, the operator verifies the exact Board approval
and final artifact, checks that other runs for this agent are idle, and assigns
the reference for that publication run. The operator removes it after the run
finishes, including failures. The agent checks the destination before retrying
an uncertain publication. This is an operator-controlled credential step. The
local trusted Paperclip installation is not a security boundary against the
Windows account owner.

Original instructions and changed-setting references are saved locally under
`D:/PokpokTools/paperclip/local-fixes/autonomy-20261120`. They contain secret IDs
only. To reverse these changes, restore the saved instruction revisions through
Paperclip and restore CTO's prior `extraArgs`. Reassign the publishing reference
only for a Board-approved publication. Timer heartbeats remain disabled and
on-demand assignment/follow-up wakes remain enabled, with one run per agent.

The launcher must enable `HEARTBEAT_SCHEDULER_ENABLED` for scheduled retries,
queued-run recovery and dependency reconciliation. Individual agent timer
heartbeats can stay disabled. The original launcher disabled this service-wide
scheduler, which left a due CEO retry queued until operator intervention.
`node scripts/paperclip/enable-task-recovery.mjs` changes the pinned launcher
and saves its original copy beside the autonomy backups. Restart gracefully to
load it. Review pending retries before enabling recovery. Obsolete retries for
the completed POK-2 and superseded POK-1 trial were cancelled, and POK-1 was
closed with links to its completed/replacement tasks.

Apply agent runtime config changes while the company has no active model runs.
Paperclip validates the shared AI account during these writes and can defer
other agents with `ai_connection_busy`. The scheduler resumes deferred work.

### Recovering a mid-run MXC launcher failure (2026-11-21)

POK-14 run `bc50607a-a98f-47ed-b874-97a08d4649df` ran shell commands, generated
an image, then failed two shell calls with
`MXC launcher: native MXC is unavailable on this Windows build`. Codex exited
0 after reporting the failure, so the adapter recorded success and no retry.
New-process probes using that same managed Codex home and workspace succeeded
with MXC unchanged. The underlying cause of the mid-run MXC failure is unknown.

The pinned `@paperclipai/adapter-codex-local` 2026.1106.0 has a scoped recovery
patch, maintained in `scripts/paperclip/codex-mxc-recovery.mjs`. It examines only
structured failed command results with the exact launcher output. An unrecovered
fault in an otherwise successful turn becomes `codex_transient_upstream`, retaining
the session/transcript for continuation. The existing scheduler allows two retry
attempts. A later successful command clears the fault; quotations, unrelated
failures, cancelled runs and timeouts preserve their original handling.

```powershell
node --test scripts/paperclip/codex-mxc-recovery.test.mjs
node scripts/paperclip/repair-codex-mxc-recovery.mjs
node scripts/paperclip/repair-codex-mxc-recovery.mjs --apply
```

Apply only while all agents are idle, then gracefully restart Paperclip. The
installer verifies the pinned version and patch sites and saves the original
`execute.js` under `D:/PokpokTools/paperclip/local-fixes/mxc-recovery-20261121`.
To roll back, restore that file to the adapter's `dist/server/execute.js` while
idle and restart. The helper can remain unused. Reassess the patch before a
Paperclip upgrade. It does not change sandbox mode, permissions or publication
approval. The [official Windows sandbox guide](https://learn.chatgpt.com/docs/windows/windows-sandbox)
documents the MXC compatibility probe; use a real command probe rather than
inferring permanent incompatibility from this intermittent error.

## Content Marketer video tools

The rendering host keeps its npm project at `D:\PokpokTools\marketing-video`.
It uses Remotion and @remotion/cli 4.0.545, React and React DOM 19.2.0, and
Chrome from Program Files. Copy `scripts/paperclip/render.cjs` beside its
package.json after updating the renderer. Set `POKPOK_RENDER_BROWSER` to use
another installed Chrome executable.

The two skills in the toolkit's `skills` directory come from
`remotion-dev/skills` at `6f55706d1069e512430582ad86e4e57dc07afe1b`.
The `ffmpeg/bin` directory contains the Gyan FFmpeg 9.0.2 essentials build.
To recreate `render-binaries`, copy the DLLs and `remotion.exe` from
`node_modules/@remotion/compositor-win32-x64-msvc`, then copy the standalone
`ffmpeg.exe` and `ffprobe.exe` from the Gyan 7.1.1 essentials build
(`ffmpeg7/bin`) into the same directory. Remotion 4.0.545 uses an audio
filter option removed in FFmpeg 9.
The live Content Marketer role points to these tools. Its local render command
and probe paths are in `docs/paperclip-agents/content-marketer.md`.

## Windows workspace setup

When provisioning the Windows user that runs Paperclip, enable long paths in Git
for Windows. Paperclip clones an isolated checkout before it starts the agent,
so the setting must also apply to newly created repositories.

```powershell
git config --global core.longpaths true
git config --get core.longpaths
git -C C:\Users\Dav\shop_pos config --get remote.origin.url
```

For this project, both the source checkout's origin and Paperclip's project
workspace repository URL are `https://github.com/patyotaus-gif/shop_pos`.
Paperclip 2026.1106.0 checks the URL saved with an execution workspace when a
second agent reuses it. A trailing `.git` on just one side can trigger
`source_repository_mismatch`. If this happens, verify the host, owner,
repository and linked checkout before aligning the URL with the saved one.
Keep worktrees containing agent commits. For a failed task, retry it once the
corresponding check passes and verify its run and output in the task activity.

## References

- [Installation](https://docs.paperclip.ing/reference/cli/installation/)
- [Setup commands](https://docs.paperclip.ing/reference/cli/setup-commands/)

## Environment log

| Date | Event | Verification |
| --- | --- | --- |
| 2026-11-15 | Isolated installation authorized; runtime prepared; C: disk shortage encountered | Official npm version/engine metadata, Node SHA256, local disk inventory |
| 2026-11-15 | Fresh D: installation; local company/project created; launchers and backup ready | Healthy API, UI assets, loopback binding, workspace mapping, restart persistence and graceful shutdown |
| 2026-11-15 | Repair native Windows Codex discovery, device login and cancellation | Original failures reproduced; real prompt check and two server API login/cancel cycles passed; owner sign-in pending |
