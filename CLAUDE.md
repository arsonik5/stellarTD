# Stellar TD agent rules

Scope now: the design pass in `docs/game/design/` (2026-11-04) - build in the order of `design/07-roadmap.md`. Do not build a mechanic that is not in the design docs; add it there first. Ships and persistence are already built - maintain them, don't re-implement.

Always:
- Preserve behavior unless asked to change it; validate with the smallest relevant test.
- Reuse existing capabilities; no parallel inventory/UI/gravity/etc. implementations.
- Systems must support radial gravity and multiple bodies; never assume world Y-up unless explicitly local-only.
- Be concise; no filler/status recap unless requested.
- Workflow: targeted inspect -> change -> smallest validation -> result/files/test. Read paths/ranges, never whole trees/docs/logs without a task reason.
- Context isolation: use built-in Explore only for reconnaissance likely to read many files; give one question and return decisions + paths. Do not use agent teams for routine work.

Read only one needed reference:
- `docs/game/README.md` — game-doc router
- `docs/game/design/README.md` — whole-game design (vision, mechanics, planets, architecture, roadmap)
- `docs/game/current-scope.md` — milestone boundary
- `docs/game/art-direction.md` — assets/art
- `docs/game/ux-bible.md` — ANY UI, HUD, menu, input or first-person feel work (locked rules; evidence in `ux-log.md`)
- `docs/game/architecture/*.md` — implementation/design by topic
- `docs/agent/README.md` — agent-memory policy
- `docs/agent/workflow.md` — on-demand workflow detail

Archives are history only: do not load them unless tracing a dated decision. Update the smallest canonical source; replace stale notes instead of appending versions.
