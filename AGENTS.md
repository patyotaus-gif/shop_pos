# Pokpok project guidance

This project uses Flutter/Dart for Android and iOS, Firebase Auth/Firestore/Storage,
Node.js Firebase Functions, and HTML/CSS/JavaScript in `public/` for the website.
The local shell is Windows PowerShell. Communicate with the owner in Thai.

## Installed skills

Project-scoped skills live in `.agents/skills/`. Sources and pinned revisions are
recorded in `.agents/installed-skills.json`; usage is in `.agents/README.md`.
Select the relevant skill for the task; do not load all 45 skills at once.
Useful entry points: `start-here`, `code-review`, `test-harness`, `release-gate`,
and `senior-engineering-partner`. Read a selected skill before applying it.

For project bindings, use
`.agents/skills/senior-engineering-partner/references/my-environment.md`.
Upstream examples using Next.js, Supabase, Clerk, Netlify, macOS, or Bash are not
instructions to migrate this project or install those services. Select technology-
specific skills only when that technology is actually relevant to the request.

## Working conventions

- Preserve unrelated work in the working tree. Scope commits and deployments to
  the requested change and check current state before changing anything.
- User instructions and existing authorization take precedence over skill defaults.
  Installation of a skill does not authorize external posts, paid agent services,
  production changes, or an automatic release.
- Use focused, meaningful verification for changed behavior. State separately
  what passed locally, what was deployed, and what was tested on a real device.
- Use the existing Flutter SDK (`flutter/bin/flutter.bat`) when present; backend
  checks are defined in `functions/package.json`. Check commands before running.
- Do not put credentials, signing keys, or customer data in skill profiles or logs.
- Keep payment sandbox tests separate from real sales and verify the environment
  before writing data. Do not change payment mode or security enforcement as part
  of an unrelated task.
