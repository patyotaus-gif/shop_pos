# Project-local development skills

Installed for Codex in `shop_pos` on 2026-11-07. The application and its customers
do not load these files. No global skill or Claude Code installation was changed.

## Sources

- [Product Engineering](https://github.com/phuryn/product-engineering): all 44 skills
  from six packs, pinned in `installed-skills.json`. MIT license is retained in
  `vendor/product-engineering/LICENSE.md`.
- [Senior Engineering Partner](https://github.com/bjgreenberg/senior-engineering-partner):
  one skill with references, scripts, original LICENSE and NOTICE, pinned in the same
  manifest. Apache-2.0. Project bindings are in its `references/my-environment.md`.
  That profile is intentionally ignored by the upstream `.gitignore`; recreate it
  from `AGENTS.md` and the supplied template on another checkout.

## Use in Codex

Skills are in `.agents/skills/`, the repository-scoped skill location. They should
be available on the next turn; if the editor has not refreshed its skill list,
start a new Codex conversation in this project.

Because these are skill-folder installs rather than marketplace plugin installs,
use the unprefixed skill names, for example:

- `$start-here` — identify the next step from the current issue or proposal.
- `$code-review` — review a selected change for actionable defects.
- `$senior-engineering-partner DEBUG: ...` — investigate and fix a specified bug.
- `$release-gate` — check evidence before an authorized release.

Installing the collections does not run their helper scripts, enable hooks,
start additional agents, install cloud services, or grant deployment access.
Choose skills relevant to the task and keep the existing Flutter/Firebase stack.

## Updates and verification

No automatic upstream updates are enabled. To update, review the upstream change,
install the desired revision in a separate staging directory with the system
skill-installer, verify it, then replace the selected skill folders while retaining
the local environment profile and updating the manifest. Do not install another
copy globally or via a plugin over the same skills without checking duplication.

Installation validation checks the 45 skill entrypoints, unique metadata names,
and every installed upstream file against its Git blob hash. This verifies the
download, not the effectiveness of every workflow or the compatibility of every
optional helper. Python helpers can use the available uv-managed Python runtime;
Bash, third-party agent CLIs, and other optional dependencies are checked when used.
