# Current scope

Since 2026-11-04 the game is planned by the design pass in `design/` (vision, core/minor/small mechanics,
planets, architecture, roadmap). Work follows `design/07-roadmap.md`: milestone G1 (foundations) first, World
track W1-W2 alongside.

Power, economy and threat waves came in with the design pass (G2-G5). Deferred: UI polish, advanced automation/logistics. Combat: ship weapons started 2026-11-08 at Michael's request (rocket pod + War Thunder-style weapon control, see architecture/gameplay-systems.md); everything else in combat stays deferred.

In progress, at Michael's direction (2026-11-08, "never lower the bar"): AAA planet surfaces on the way to a seeded
universe (traits, CC0 material library, rebuilt terrain shader, ground rules, scatter) - stages 0-4a done, see
`architecture/planet-surfaces.md` and `reports/AAA voxel terrain fidelity.md`. Fresh clone: `sh tools/setup_surfaces.sh`.

Built past this line and now in scope to maintain: ships, and save/load
(main menu, slots, terrain edit deltas, world state - see
`architecture/gameplay-systems.md`).

Foundation placement follows local surface orientation. Pipes, mergers and splitters connect by matching their ports in 3D (2026-11-08; checked upright, on its side and tilted by `scenes/dev/junction_test.tscn`), so they work anywhere on the planet. Pipe runs are planned whole (Straight / Curved, `PipeRoute`), join machines at their real ports, and anything built can be dismantled for a full refund (F in build mode).

Still true and maintained: ships/constructs, save/load, terrain generator, scanner, hand drill, factory chain.
