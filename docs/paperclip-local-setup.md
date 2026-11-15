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
execution settings, then use **Resume**
when ready. Create a **New Task**, select **Pokpok POS**, and assign **CEO**.
For an initial task, request a read-only summary of `AGENTS.md`, `docs/HANDOFF.md`
and the project structure; explicitly exclude code changes, commits, pushes,
deployments and production-data access. Check the task's run result before
assigning implementation work. These are operator steps, not actions performed
by the setup assistant. No agent was resumed or task launched during this check.

Codex authentication reference: https://learn.chatgpt.com/docs/auth?surface=cli

### Owner connection follow-up

After the Windows repair, the owner's screenshot shows **Connection successful**
and **You have unsaved changes**. A read-only API check now lists one saved AI
connection; CEO remains paused. Save the runtime form before starting a task.
Then follow the first-task steps above. The successful runtime check verifies
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

## References

- [Installation](https://docs.paperclip.ing/reference/cli/installation/)
- [Setup commands](https://docs.paperclip.ing/reference/cli/setup-commands/)

## Environment log

| Date | Event | Verification |
| --- | --- | --- |
| 2026-11-15 | Isolated installation authorized; runtime prepared; C: disk shortage encountered | Official npm version/engine metadata, Node SHA256, local disk inventory |
| 2026-11-15 | Fresh D: installation; local company/project created; launchers and backup ready | Healthy API, UI assets, loopback binding, workspace mapping, restart persistence and graceful shutdown |
| 2026-11-15 | Repair native Windows Codex discovery, device login and cancellation | Original failures reproduced; real prompt check and two server API login/cancel cycles passed; owner sign-in pending |
