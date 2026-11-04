# Agent context map

Read this file first. Load only the smallest relevant reference:

- `slice.md` — current milestone and scope boundary
- `main-design.md` — architecture, implementation patterns, risks, and detailed design
- `art-direction-brief.md` — asset/art source of truth
- `docs/reference/claude-notes.md` — retained historical status and working notes; use only when the task needs dated context
- `architecture-status-slice.md` / `status.md` — cheap indexes

Do not read all Markdown by default. `addons/` Markdown is third-party/legal material, not project guidance.

## Rules

- Use minimum-token responses: no filler, restatement, or recap unless requested.
- Preserve behavior unless the task explicitly changes it.
- Reuse existing capabilities; do not create parallel implementations.
- Keep radial/spherical-world assumptions explicit; avoid hidden world-Y-only logic.
- Do not build deferred systems speculatively; confirm scope first.
- Validate with the smallest relevant test or headless check.
- Update the applicable source of truth in place; do not create v2/v3 copies.

When sources conflict, prefer the newer dated decision in `docs/reference/claude-notes.md`, then update the canonical reference so the conflict does not persist.

## Notes/memory protocol

- Save only durable, reusable deltas: decisions, invariants, recurring failures, commands, and user preferences. Do not save ordinary progress, chat summaries, or facts already in tracked docs/code.
- Prefer one dense record per topic: `fact -> consequence -> pointer`. Use exact paths/symbols; omit prose, chronology, and obvious rationale.
- Keep the always-loaded index to short pointers; put detail in on-demand topic files. Never paste a full design/doc into memory.
- On contradiction, replace the stale note; do not append another version. Add `YYYY-MM-DD` only when time changes meaning.
- Use plain English + compact ASCII notation (`=>`, `!=`, `+`, `-`, `?`, `TODO`, `why:`). Claude-specific verdict: do not assume Mandarin, emoji, or Unicode symbols save tokens; Anthropic documents token counts as model/content dependent and provides `count_tokens` as the authority. Use Mandarin only when it is clearer for a human reader or genuinely shorter in a measured Claude sample. Avoid decorative Unicode.
- At session end, write nothing unless a future session would otherwise repeat real work. If writing, update the relevant topic/index only.
