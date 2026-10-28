# Repository notes for Claude

This repo holds two things:
- the original **godot-mcp** server (`src/`, `scripts/`, `package.json`) — upstream code, leave alone unless asked;
- **Rotten Crown**, the user's Godot game (`rotten-crown/`, see `rotten-crown/CLAUDE.md`) and its
  published web build (`docs/`, served by GitHub Pages at https://mahmoud70004-debug.github.io/godot-mcp/).

## Workflow rule (set by the user — applies to every session and every phase)
Use the **smart-task-router** skill (`.claude/skills/smart-task-router`) for all build/fix work:
recon into `.router/CONTEXT.md` (router-scout), plan into `.router/PLAN.md` (Tier H), get the user's
approval on the plan summary, build task by task with the router-* agents, verify every done-check
yourself, review the diff with router-reviewer, then report the tier mix.
`.router/` is committed (containers are ephemeral; it is how work resumes). To resume: read
`.router/PROGRESS.md` and continue from the first unfinished task.

The user writes in Arabic; reply in Arabic. Player-facing game text stays English until Phase 8.
