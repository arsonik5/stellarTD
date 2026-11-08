# Current scope

Slice 1: prove the repeatable feel loop on a spherical voxel planet: dig/place, five ores, processing, and one ore→refined→placeable chain.

Deferred: power, combat, UI polish, advanced automation/logistics.

Built past this line and now in scope to maintain: ships, and save/load
(main menu, slots, terrain edit deltas, world state - see
`architecture/gameplay-systems.md`).

Foundation placement follows local surface orientation. Pipes, mergers and splitters connect by matching their ports in 3D (2026-11-08; checked upright, on its side and tilted by `scenes/dev/junction_test.tscn`), so they work anywhere on the planet.
