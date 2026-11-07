---
name: release-gate
description: "Before 'push it', 'ship it', a deploy, release or go-live, or calling a stage done: the gate, the owner's preview, go/no-go, promote, prove it serves, roll back."
---

This skill lives at `.agents/skills/release-gate/` (vendored; source and pinned commit in `.agents/installed-skills.json`).

Read `.agents/skills/release-gate/SKILL.md` in full and follow it. Resolve any relative paths it mentions (references/, scripts/, docs/) against `.agents/skills/release-gate/`.

Project bindings: `.agents/skills/senior-engineering-partner/references/my-environment.md`. User instructions and `AGENTS.md` take precedence over the skill; it never authorizes deploys, releases, or external posts on its own.
