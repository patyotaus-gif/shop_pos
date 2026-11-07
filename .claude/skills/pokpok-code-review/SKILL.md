---
name: pokpok-code-review
description: "'Review this', 'find bugs', 'is this fix safe': review code for defects that matter, correctness first, each finding refuted before it's reported."
---

This skill lives at `.agents/skills/code-review/` (vendored; source and pinned commit in `.agents/installed-skills.json`).

Read `.agents/skills/code-review/SKILL.md` in full and follow it. Resolve any relative paths it mentions (references/, scripts/, docs/) against `.agents/skills/code-review/`.

Project bindings: `.agents/skills/senior-engineering-partner/references/my-environment.md`. User instructions and `AGENTS.md` take precedence over the skill; it never authorizes deploys, releases, or external posts on its own.
