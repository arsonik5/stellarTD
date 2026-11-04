# 04 - Small things (layer 3)

Polish, feedback and quality-of-life. Individually tiny, together they decide whether the game feels finished.
Rule from pillar 5: **a mechanic is not done until its small things are done.** Each core/minor mechanic ticket
should pull the matching rows from here rather than leaving them for a "polish pass" that never comes.

## Feedback per action (visible + audible, see `ux-bible.md` 3a/3b)

| Action | Visible | Audible | Status |
|---|---|---|---|
| Drill start / bite / stop | spin-up kick, dust tinted by material, sparks on ore, hole grows | motor spin-up/loop/down, grind pitched by hardness | partial (bore built; no particles/audio) |
| Item gained | "+3 Iron" stacking popup near crosshair; slot pulse | pickup tick, pitch rises with stack | partial (popup in HUD) |
| Inventory full | red flash on HUD bag, popup "Full" | buzz | missing |
| Place building | ghost snaps (tick), place thunk + dust ring | snap tick, thunk by size | partial |
| Invalid place | ghost red + reason text ("Needs foundation", "Blocked", "Missing 2 Iron Ingot") | dull error | partial (red, no reason) |
| Machine starts / finishes craft | work anim + light; output slot pop | start hum, finish clunk | partial (anim) |
| Machine idle with reason | icon over machine (no input / full / no power) visible at range | none (visual only, avoids noise) | missing |
| Pipe carries item | items visible moving in glass pipe | soft whoosh at inlets | partial |
| Turret fires / hits | muzzle flash, tracer, impact spark, hit marker on enemy | report by calibre, distance-attenuated | partial |
| Enemy warning | edge-of-screen bearing marker, uplink banner | klaxon + uplink voice/blip | missing |
| Take damage | directional red vignette, camera kick | suit alarm, impact | missing |
| O2 low | HUD bar pulses amber then red; breathing gets louder | breathing, low-O2 beep | partial (bar) |
| Directive complete | uplink banner, credit counter rolls | chime | missing |
| Research unlock | node lights, toast with icon | chime | partial (quest toast) |

## Quality-of-life

- Hotbar 1-9 for buildings and tools; middle-click "pick what I look at" (copies building type + rotation).
- Hold-to-dismantle with full refund; undo last placement (Ctrl+Z, 30 s window).
- Shift-click to move stacks between inventory and machine; ctrl-click to move all of a kind.
- Auto-sort button on inventory and chests.
- Recipe lookup: hover any item -> "made in / used in".
- Craft queue on hand-crafting with cancel; machines show the next 3 crafts.
- Ore magnet: nearby dropped items fly to the player (radial-gravity aware).
- Compass strip on the HUD (planet-local north from the body's spin axis, not world Y).
- Pings: middle-mouse in the world marks a spot for 30 s (also future co-op).
- Photo mode (hide HUD, free cam within 20 m).
- Rebindable keys; hold-vs-toggle for sprint, crouch, scanner.
- Tooltips everywhere with key hints in the same words (`ux-bible.md` 7, 8).

## World feel details

- Footstep sounds by surface material; landing dust; suit visor fog in cold biomes.
- Boot prints and drill scars persist (scars are the voxel edits - already free).
- Dust kicked by wheels/thrusters along radial gravity; thruster scorch on ground.
- Distant base lights visible from orbit (night side).
- Machines have idle micro-motion so a base reads alive from far away.
- Wrecks smoke for a few minutes after they fall.

## Numbers and tuning hygiene

- Every tunable in a `Resource` or `const` with a comment saying the unit and why (house style already).
- One balance sheet (`docs/game/design/economy.csv` when the economy lands) generated from `data/recipes` so
  docs never drift from data.
