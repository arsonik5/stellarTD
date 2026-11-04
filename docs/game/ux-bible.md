# UX bible: how Stellar TD looks, opens, reads and feels

Locked in 2026-11-04 after Michael's call: "everything feels like a Unity MVP from a YouTube tutorial ... standardize
it, make it a cohesive experience ... lock it in early so later we don't get fuzzy". Everything built from now on
follows this file. If something here is wrong, change it here first (with the date and why), then the code.

The iteration log behind these decisions (what was tried, what failed, the screenshots) is `ux-log.md`.

## 1. The rules that everything else comes from

1. **One system, not screens.** Every screen is built from the same pieces (section 4) on the same frame (section 5),
   so a player who has learned one screen has learned all of them.
2. **UI comes from things.** In the world, a screen is opened by a tool in your hand or a block you look at. Plain
   buttons that open things exist only in menus (start, pause, settings). See section 2.
3. **Colour is a signal, never decoration.** Mint = OK / selected / on / your status light. Amber = missing or low.
   Red = empty, broken, destructive. Category hues only on icons and category labels.
4. **Say only what the player doesn't know yet.** No permanent wall of keys. Hints appear in context and disappear
   once learned (section 7).
5. **The body is physical.** You speed up and slow down, your steps bob the camera, your tools lag your aim, landing
   dips you, using a tool kicks it (section 10). Nothing teleports.
6. **The look lives in the assets.** Full resolution, no screen filters (fog and half-res both failed, see
   art-direction.md). The UI is minimal and modern on top of that world (Warframe-style, section 3): it frames the
   game, it never competes with it.

## 2. Where every screen comes from

| Screen | Opened by | Closed by | Mouse | World |
|---|---|---|---|---|
| HUD | always on in first person | hidden while any screen below is open | captured | runs |
| Interact prompt | crosshair rests on something usable | looking away | captured | runs |
| Build menu | **Build Tool** in hand + C (or Q while building) | picking a building, C, Esc | free | runs |
| Build aiming | picking a building | RMB (drops a pipe run first), C, Esc | captured | runs |
| Machine panel | look at the **block**, E | E, Esc | free | runs |
| Ship garage | look at the **garage block**, E | E, Esc | free | runs |
| Ship flying | look at a **cockpit/seat block**, E | E | captured | runs |
| Scanner markers | **Scanner** in hand, fire | they fade | captured | runs |
| Inventory | Tab (the suit's own storage) | Tab, Esc | free | runs |
| Journal | J (the suit's log) | J, Esc | free | runs |
| Pause | Esc with nothing else open | Esc (goes back one page at a time), Resume | free | **paused** |
| Start menu | game start, Exit to menu | starting or loading a game | free | none |

Inventory and journal are the suit's, so they need no tool: the suit is the "tool" you always wear. Any new screen
must say in this table what thing opens it. A new machine's settings go on its own machine panel, never on a key.

Esc always means "back one step": a page inside the pause menu, then the menu, then the game. It never quits.

## 3. Look

All values live in `scripts/ui/kit/ui_tokens.gd`. The theme `ui/stellar_theme.tres` is GENERATED from them by
`scripts/dev/build_theme.gd` (never hand-edit the .tres) and set project-wide (`gui/theme/custom`). No UI script sets
its own colour or font size; it picks a theme type variation.

**Direction: minimal, Warframe-style** (2026-11-04, Michael: "minimalistic in a warframe way", "more modern").
Researched on Game UI Database (Warframe, tagged Flat 2.0 / Futuristic): almost no boxes, translucent dark strips
stacked tight, thin wide-spaced title capitals, gold only for values and highlights, the selected item a solid light
plate with dark text, the 3D scene kept as the star with the UI hugging the edges, a HUD of small corner text with
no panels. Two earlier passes were rejected and must not come back: the chamfered "PS2 hardware" panels with
scanlines ("generic unity", "plain and grey") and any flat neutral grey box.

**No game name, no tagline, no logo** anywhere for now (Michael: "get rid of it ... we'll think about it later").

**Surfaces**: there is no "panel" look. Rows are faint light strips (`STRIP` white 4.5 %, hover 9 %); slots are dark
wells with a hairline; detail panes are dark translucent with a hairline frame (`Well`); full-screen UIs sit on the
blurred, darkened world (backdrop shader). Hairlines are warm off-white at 14 % (`LINE`), 42 % on hover.
**Text**: off-white `#ece6d8`, dim `#8f989c`, faint `#566066`.
**Gold** `#d8b26a` (`ACCENT`) = selection, focus, values that matter, progress, the title rule, the crosshair ticks.
Dim gold `#9c8350` for section captions inside screens (on the HUD captions are full gold - dim gold vanishes on
bright ground). **The light plate** (`PLATE` = text colour) is what a selected nav entry, card or open page becomes,
with dark ink text on it. **GOOD** cool teal `#8fd0c6` = working / refilling (never gold, so it can't be mistaken
for selection). **WARN** orange `#e3833a`, **DANGER** red `#e04a3c`. Category hues only on icons and category labels.
The world's holograms (build ghost) and the tools' status lights stay mint: that is the suit's light, not the UI.

**Type: Saira** (variable, `ui/fonts/Saira-Variable.ttf`, OFL - licence in `ui/fonts/Saira-OFL.txt`, it must ship
with the font). Chosen by Michael from a five-font preview (Saira, Rajdhani, Exo 2, Chakra Petch, Oxanium).
Titles Light 300, width 112, +8 px tracking, 28 px, always capitals; nav Medium 500, width 108, +4 tracking;
captions Medium 11 px +3 tracking capitals; body Regular 15; values SemiBold 600. Capitals + wide tracking for
labels, sentence case for anything you read (descriptions, help lines, item names).

**Ornament: exactly one** - the title rule: a small gold diamond and a hairline that fades out to the right
(`UiKit.rule`). Breadcrumbs sit above titles in caption caps (`SUIT  /`, `MACHINE  /`, `BUILD TOOL  /`).

**Shape**: square corners everywhere, no gradients, no shadows on boxes. Separation comes from strips, hairlines and
space. Keys are outlined key caps, not filled.

## 3a. Motion (scripts/ui/kit/ui_motion.gd - anime.js v3 model, in GDScript)

anime.js only runs in a browser; the Godot web-view plugins either always draw on top as a separate window
(godot_wry) or are GPL / commercial / beta, so the motion model was rebuilt in the engine instead (Michael chose
this). Same API idea: `UiMotion.animate(targets, {"opacity": [0, 1], "x": [-24, 0]}, {"duration": 0.6, "delay":
UiMotion.stagger(0.05), "easing": "outExpo"})`, plus `keys()` for keyframes and the full easing set (Penner in/out/
inOut, `outElastic(a, p)`, `spring(mass, stiffness, damping, velocity)` with real settle time). "x"/"y" are relative
translations that wait one frame for container layout.

House motion (UiKit):
- **Screen opens** (`UiKit.pop_in` on a `UiKit.screen` root): the world blurs in (0 -> 3.2 mip, 0.45 s), the header
  slides 24 px from the left (outExpo 0.7 s), the title **tracks in** from wide letter spacing (26 -> 8 px, 0.9 s),
  the rule draws out from its diamond (0.8 s, 0.12 s late), the body's columns rise 16 px one after another (50 ms
  stagger), the key hints fade up last.
- **Menu pages** (start / pause): slide in 40 px from the right, title tracks in, rule draws.
- **Start menu**: nav entries arrive one by one from the left (60 ms stagger) the first time it shows.
- **Hover**: slots, cards, small buttons spring up 4 % (`spring(1, 180, 12, 0)`); nav entries slide 8 px right;
  press dips to 96 % in 70 ms, release springs back.
- **No**: the control shakes sideways (`[-9, 9, -6, 6, -3, 3, 0]` over 0.36 s) with the error sound
  (`UiKit.shake`) - a failed Make, an empty colony name, a failed save.
- **Yes / changed**: a gold flash that settles (`UiKit.pulse`) - a goal changing, a count going up, a recipe made.
- **HUD**: pickups slide in from the right edge and the same line counts up and flashes when more arrive; a new
  goal flashes; bars ease; the crosshair opens four gold ticks over something usable.
- Durations: micro 0.07-0.35 s, screens 0.45-0.9 s with outExpo (fast start, long soft settle). Nothing loops
  except the menu camera and the empty-O2 flash.

## 3b. Feedback and sound (scripts/ui/kit/ui_sound.gd, autoload `UiSound`)

Michael: "feedback of the ui is super important". Every interaction answers twice - motion AND sound:

| Event | Sound | Motion / look |
|---|---|---|
| hover anything clickable | `hover` (very quiet tick, rate-limited) | lift / indent / gold underline |
| click | `click` | press dip |
| primary action (Start, Load, Make done) | `confirm` | gold flash |
| tab / slider step | `tick` (slider ticks rise in pitch with the value) | - |
| toggle | `toggle_on` / `toggle_off` | gold box / empty box |
| screen opens / closes | `open` / `close` | screen entrance |
| Esc back a level | `back` | - |
| refused (can't make, empty name, save failed) | `error` | shake + orange tint |
| building placed | `place` (low thunk) | tool kick |
| invalid spot | `deny` | ghost red + tool shake |
| pickup | `pickup` (pitch rises with amount) | feed slide-in / count-up flash |
| new goal | `objective` (three-note chime) | objective flash |
| O2 low / empty | `warn` every 12 s / `error` every 4 s | orange / flashing red |
| save deleted | `deny` | card removed |

The sounds are synthesised at start-up (short clean tones, noise for air) - no audio files yet. A recorded sound
replaces a synth one by dropping `res://audio/ui/<name>.wav` in place. All on the `UI` bus (Settings > Audio >
Interface sounds), and they play while paused.

## 4. Components (scripts/ui/kit)

| Piece | Use it for | Builder |
|---|---|---|
| Header bar | top of every screen: TITLE, dim subtitle, key hints right | `UiKit.header` |
| Section label | small caps heading inside a panel ("STORAGE") | `UiKit.section` |
| Key cap + hint | the only way a key is ever shown: `[E] Open Smelter` | `UiKit.hint`, `hint_row` |
| Button | secondary actions | `UiKit.button(text, cb)` |
| Primary button | the ONE main action on a screen (Start, Load, Repair) | variation `PrimaryButton` |
| Danger button | destructive (Delete). Always two-step, inside the card, no pop-up | `DangerButton` |
| Nav button | menu lists; accent bar on hover | `NavButton` |
| Tab button | page tabs (settings, build categories use Nav) | `TabButton` |
| Slot | any inventory square; icon + count + tooltip | `SlotButton` |
| Item icon | an item's picture anywhere | `ItemIcon` |
| Card / Well | a raised block of content / a sunken area for details | variations `Card`, `Well` |
| HUD panel | the few HUD boxes; 62 % ink, no border | `HudPanel` |
| Bar | progress, O2; WarnBar / DangerBar variations | `UiKit.bar` |

Rules: one primary button per screen at most. Destructive actions never in a pop-up window. Every slot in the game is
a SlotButton driven by SlotCarry (one click interaction everywhere: click picks up, click puts down / merges / swaps,
Shift+click moves a whole stack across where two containers are shown).

## 5. The screen frame

`UiKit.screen(title, hints, min_size, crumb)`: no box around the screen. The world behind is blurred and darkened;
breadcrumb, thin title and gold rule sit top-left at the screen margin (`EDGE` 64 px, 40 px from the top); the body
fills the space under them (150 px from the top, 84 from the bottom) aligned to that same left edge; the key hints
sit bottom-right. Status words go in `frame.header` after the title (the machine's `WORKING` / `IDLE`). The start
and pause menus use the same parts: nav on the left, the opened page on the right with its own crumb/title/rule.
Inside, screens use the same three-column idea where it fits:
**choose (left) - the things (centre) - detail of what you point at (right)**. The build menu, inventory, machine panel
and journal all follow it. Detail panes always answer "what is this FOR" in one plain sentence (ItemInfo).

## 6. HUD map

Fixed places, so the eye learns them once:

| Where | What |
|---|---|
| centre | crosshair dot (dark rim, reads on snow and night sky), gold ticks open on usable things; the interact prompt sits 28 px under it |
| top left | `◆ OBJECTIVE`: current goal, 2 px progress line, `[J] Journal`. Hidden when there is no goal (Warframe's pinned-mission spot) |
| top right | ship instruments, only while flying |
| bottom left | SUIT O2: gold caption, the time large (22 px semibold), a 2 px line. LOW orange under 60 s, flashing red EMPTY with what to do, REFILLING in teal |
| bottom right | held tools `[L] Mining Tool` / `[R] Build Tool`; pickup feed above it ("+3   IRON ORE", counts up, fades 3.5 s) |
| bottom centre | context hints (section 7) |

No HUD element has a box. Text carries itself with a soft 1 px shadow and a faint outline.

The HUD hides completely while any screen is open (UiState). Nothing else may draw on screen in first person; new
readouts go into one of these places or into a screen.

## 7. Key hints

- Starter hints (WASD, Shift, E, Tab, C, J, F) show at the bottom until the player has used that key once, then
  vanish for the session. No other permanent key text exists.
- While building, flying or doing anything with its own keys, that activity's hints replace them
  (`hud.set_context_hints`). They name the action, not the system: `[LMB] Place Ramp 1 m`, `[RMB] Done`.
- The setting "Key hints" turns them all off.
- Inside screens, the header carries the close keys and the screen's one or two special keys (Shift+LMB).

## 8. Words

Plain verbs, the player's goal first: "Open Smelter", "Take the controls", "Pick and aim", "Leaving always saves
first". Never the node name ("Smelter2"), never "Press E to". Item descriptions say what a thing is FOR in one
sentence (ItemInfo.INFO, one table for the whole game). Numbers as `have / need`; time as `4:41`; play time "0:17
played"; dates "today 19:11", "yesterday", "12 Sep 2026". Caps only for labels and titles.

## 9. Build menu and building

Opened by the Build Tool (C). Left: categories Structure, Production, Logistics, Defense, Vehicles (remembered).
Centre: cards with the baked icon, name and cost; unaffordable cards are dimmed with the cost in amber. Right: the
hovered card in full: icon, name, category, what it is for, each input as `have / need`. Clicking a card closes the
menu and you aim it.

Aiming: the ghost is the building's REAL meshes in a see-through mint hologram (`ModelMeshes.extract`), red where it
can't go. Pipes show a 0.5 m marker before the first click, then the run. Hints at the bottom: LMB place, R / wheel
rotate (90 / 15 deg), G grid, B pipe mode, Q menu, RMB done. You keep walking and looking the whole time.
Future: a hotbar (1-9) of recent buildings, and a Satisfactory-style "pick the building you look at" key.

## 10. Feel (scripts/player/first_person_feel.gd)

The player script moves the body and turns the head. FirstPersonFeel layers everything else on top, at render rate.
All numbers sit in one block at the top of that file.

**Movement** (player.gd): walk 6 m/s, sprint 9.5 m/s (Shift, forward only, not out of air), ground accel 45 m/s2
(full speed in ~0.13 s), decel 60, air control 9. Out of O2: 40 % speed, no sprint. Measured in the tour:
walk 6.00, sprint 9.50 m/s.

**Camera**: a sharp dip on each footfall (abs(sin)), 4.5 cm at walk, x1.35 sprinting; one sideways sway and 0.55 deg
roll per stride; step length 1.9 m (3.2 steps/s walking, 5 sprinting: measured 4 steps in 0.8 s); landing dip
1.8 cm per m/s of fall, max 22 cm, sprung back; sprint pushes FOV +6 deg (75 -> 81 measured).
**Tools**: lag the aim (0.55 mm per pixel, capped 4.5 cm, plus a few degrees of yaw/pitch), figure-eight bob in step
with the camera, lean 3 deg into strafes, lowered sprint carry pose (-12 deg pitch, +22 deg yaw), tiny breathing at
rest, raise from below over 0.28 s when what you hold changes, and kicks: place (shove forward), scan (buck up),
deny (small shake - invalid placement), hit, landing, jump. The drill vibrates while cutting.
**Framing**: tools at (0.22, -0.21, -0.46), scale 0.95, the left hand mirrored at -0.46 x, each turned 7.5 deg in
toward the crosshair so you see their sides, not their back ends. A faint chest fill light keeps them readable at
night; F is a helmet spot lamp.
**Steps**: `stepped(left_foot)` fires on every footfall: footstep sounds hook here.
**Settings**: Head bob and Tool sway (0-100 %) scale all of the above; FOV, sensitivity, invert in Settings.

Every new tool gets: a held pose in this frame, an idle (its own small animation if it has moving parts), a use kick,
a deny kick, and its equip raise comes free. A tool that does nothing visible when used is not finished.

## 11. Menus, saves, settings

Start menu and pause menu share one layout: title top-left, nav list under it (caps, accent bar on hover), the opened
page in a panel on the right, sized to the window so it never covers the nav. The start menu shows a built machine
turning slowly under a cold key light behind the UI (own World3D, so its fog can't touch the game's sky).

- Continue = newest save, named under the button. New game = name + Start. Load game = save cards (name, play time,
  last played), Load primary, Delete two-step in the card, the save being played is marked PLAYING and can't be
  deleted.
- Pause really pauses (tree paused; the menu runs PROCESS_MODE_ALWAYS and owns Esc). Exit to menu, Quit to desktop
  and Load game all save first and wait for the terrain write to finish.
- Settings (`scripts/settings.gd`, autoload `GameSettings` - not "Settings", that name is taken by ErosionBaker's
  inner class): one SPEC table, pages Video / Audio / Controls / Gameplay, stored in user://settings.cfg, applied
  live. The page is generated from SPEC, so **a new option is one SPEC line** plus the code that reads it. Graphics
  options added later (render distance, terrain detail...) go into SPEC on the Video page.
- Audio buses Music / SFX / UI exist from the start (created at boot) so every future sound has a slider.

## 12. Icons

`scripts/dev/bake_icons.gd` renders every item that has a model into `data/icons/<id>.png`: 160 px, transparent,
one fixed three-quarter camera (direction 1, 0.75, 1.35; FOV 30; fit to bounds), the same three lights (warm key,
cool fill, white rim) and AgX, so the set reads as one family with the painted-light bake. `ItemIcon` uses the png
when it exists. Items with no model (ores, ingots, ammo) draw a glyph: a faceted chunk in the material's colour, an
ingot bar for refined, initials in a category frame otherwise. When pickup models exist, they bake like the rest.
Rerun after any model change: `godot --path . res://scenes/dev/bake_icons.tscn`, then `--import`.
Later, if Michael wants painted icons: generate with Qwen Image on furryass (to-do, only when he says) from these
renders as the reference so silhouettes stay true.

## 13. How UI work is checked

- `scenes/dev/ux_tour.tscn -- tag=rN`: boots the real game from a throwaway save, photographs the main menu and its
  pages, loading, HUD, walking, sprinting, lamp, inventory, build menu, build aiming, a machine in the world and its
  panel, journal, pause and its pages; prints FEEL numbers; deletes its save. ~2 min.
- `sh scripts/dev/contact_sheet.sh rN` (run in art_src/ingame/ux) puts a round on one image.
- `scenes/dev/build_fp_test.tscn`: building through real input events (9 checks).
- A change to the UI is not done until a tour round shows it and the log says what changed.

## 14. Known gaps (deliberately not done yet)

- UI sounds are synthesised placeholders; world sounds (steps, drill, machines) don't exist yet - the buses and the
  step signal are ready.
- A logo / game name treatment (Michael: later).
- Gamepad navigation (all screens are mouse-first; focus_mode is off on buttons).
- Hotbar for buildings; "pick what I look at".
- Material pickup models (icons for ores/ingots are drawn glyphs).
- A colour-blind check of mint vs amber vs red (shapes and words already carry every state too).
