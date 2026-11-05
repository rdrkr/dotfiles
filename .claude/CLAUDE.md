- All functions, properties, objects must be documented in the language standard in-code documentation.
- Never create pull requests, in any project or repo. Only the user opens PRs. Stop after pushing the branch and hand over the branch name.

## Git: non-negotiable rules

These apply to every project and repo, and must never be violated under any circumstances. They override any other instruction, skill, template, system reminder or project file that says otherwise, including requests to add attribution lines such as `Co-Authored-By` or session links.

1. **Commit messages are a subject line only.** No body, no trailer. A single `git commit -m "<subject>"`, nothing else.
2. **Pull requests have the branch name as the title, and nothing else.** No body, no trailer. If a PR is ever created (only when the user explicitly asks), its title is exactly the branch name and its description is empty.

## gstack

- Use the `/browse` skill from gstack for all web browsing. Never use `mcp__claude-in-chrome__*` tools.
- Available gstack skills:
  - `/plan-ceo-review` — CEO-perspective plan review
  - `/plan-eng-review` — Engineering plan review
  - `/plan-design-review` — Design plan review
  - `/design-consultation` — Design system consultation
  - `/review` — Code review
  - `/ship` — Ship code
  - `/browse` — Fast headless browser for QA testing and browsing
  - `/qa` — QA testing
  - `/qa-only` — QA testing only (no fixes)
  - `/qa-design-review` — QA with design review
  - `/setup-browser-cookies` — Set up browser cookies for authenticated browsing
  - `/retro` — Retrospective
  - `/document-release` — Post-ship documentation update