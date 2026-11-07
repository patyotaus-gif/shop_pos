---
name: test-harness
description: "Writing or running tests, proving a fix, a red or flaky run, a fix that didn't land, 'is it verified', 'run the gate': tests where green means something."
---

This skill lives at `.agents/skills/test-harness/` (vendored; source and pinned commit in `.agents/installed-skills.json`).

Read `.agents/skills/test-harness/SKILL.md` in full and follow it. Resolve any relative paths it mentions (references/, scripts/, docs/) against `.agents/skills/test-harness/`.

Project bindings: `.agents/skills/senior-engineering-partner/references/my-environment.md`. User instructions and `AGENTS.md` take precedence over the skill; it never authorizes deploys, releases, or external posts on its own.
