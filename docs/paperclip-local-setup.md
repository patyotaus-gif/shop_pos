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
  the API, including after restarting. Agent count remained zero.
- Start/stop scripts passed local execution. Shutdown invokes Paperclip's own
  SIGINT handler through `shutdown-bridge.mjs`, using a PID-bound request in the
  restricted data directory. HTTP and PostgreSQL ports closed after stopping.
  Do not use `Stop-Process` as the normal shutdown method.
- Browser screenshot capture was rejected by automatic approval review with
  `blocked by policy`. Rendered UI and an actual AI task have not been verified.
- No AI agent run, provider API request, GitHub write or production deploy has
  been performed by this setup.

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

The helper scripts, runtime, package lock and application data stay outside the
Pokpok repository. The launcher changes environment variables only for its own
process and does not replace the system-wide Node executable.

## Operating model

The initial setup is loopback-only `local_trusted`. It is for this Windows user
on this machine; it is not a public/team server. No router port or tunnel is
opened. Adding remote teammates requires a separately configured authenticated
deployment.

Provider credentials are not copied from Pokpok or from the connected ChatGPT
GitHub plugin. A repository URL/workspace link is different from authorizing
Paperclip's GitHub connector or signing in to an AI provider. Those connections
must be configured explicitly when needed.

No AI agents or routine jobs are enabled during installation. Automatic heartbeat
scheduling is disabled in the local launcher. A zero budget field must not be
treated as a spending block: no provider/agent is configured at this stage.
New agents require board approval. Creating this workspace does not authorize
an AI to deploy Pokpok or change production/payment settings.

The bundled GitHub Copilot runtime installer reports `unsupported-platform
(win32-x64)` in this version. Do not assume every AI adapter works on native
Windows; provider login and a separately authorized agent run need their own test.

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
