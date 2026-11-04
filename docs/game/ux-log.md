# UX iteration log

Each round = a full `ux_tour` (screenshots in `art_src/ingame/ux/<round>_*.png`, one sheet per round). Newest last.
The rules that came out of this are in `ux-bible.md`; this file is the evidence and the dead ends.

## 2026-11-04, r0: baseline (before)

What a player saw:
- Main menu: a flat list of save rows and four buttons on black.
- HUD: a permanent "MODE: PLAYER" line plus every key in the game at the bottom; an empty quest box top-left;
  "SUIT O2 4:41" floating mid-left; no crosshair.
- Building: two key legends drawn over each other (my first-person change had kept both).
- Inventory: text-only slots ("Scann x1" cut off); orange titles, cyan headings, teal panels - three colour schemes.
- Build menu: one long text list of "Name / 2x Iron Ore (have 0)" running off the bottom of the screen.
- Machine panel: two unrelated panels, eight colours of label, "Smelter | Inventory 0/100 | Input 0 | Output 0".
- World: spawn is 36 deg past sunset, so every new game started in near darkness; tools were black shapes.
- Feel: velocity set instantly (no momentum), no head bob, tools fixed to the camera.

## r1: theme, kit, menus, settings, saves, pause

Changed: UiTokens + generated theme (project-wide), UiKit builders, SettingsPanel from one SPEC table, SavesPanel
cards, new start menu (nav + content + 3D backdrop), pause menu on the same layout, pause actually pauses.

Worked: Bahnschrift + chamfered corners + one mint accent turned the menus into "a game" in one step. Settings rows
from a table are tidy and consistent.
Didn't: backdrop model lit by the mint rim light looked murky green - the accent colour must never be used as a light
on models. Content panel overlapped the nav on a 1152 px window.
Also hit: autoload named `Settings` broke terrain (ErosionBaker has an inner class `Settings`) -> renamed
`GameSettings`. New `class_name`s need `godot --import` before scenes see them.

## r2: HUD, interact prompt, build menu, inventory, machine panel, journal, loading

Changed: HUD rebuilt with fixed places (objective, O2 bar, hands, feed, context hints, crosshair); interact prompt as a
key cap + verb + real item name; build menu with category tabs, cards and a detail pane; inventory and machine panel
on the standard frame with SlotButtons; journal with state colours and schematic connectors; loading screen in the
menus' corner layout.

Worked: the frame (header bar flush, choose / things / detail) makes every screen read the same. Amber "from 1 Iron
Ore" on recipes you can't run says why without words.
Didn't: initials as icons ("F1", "FF") read as placeholders; the green box ghost; key hints collided with the hand
cards on small windows; settings rows overflowed the narrower panel.

## r3: baked icons, hologram ghost, layout fixes

Changed: icon baker (41 icons from the real models, one camera, one light rig); ghost = the building's real meshes in
a mint hologram (ModelMeshes); settings rows narrowed; content panel sized to the window.
Worked: icons are the biggest single jump in "finished" feel - the build menu now looks like a catalogue. The hologram
ramp shows exactly what lands where.
Feel probe numbers (walk 6.00 m/s, ~2 cm camera bob; sprint 9.50 m/s, 4 steps / 0.8 s, FOV 80.9) - as designed.
Didn't: tools still read as huge black stumps (we saw their back ends, too close, at night).

## r4: daylight spawn, tool framing, lamp, compact hands

Changed: Star moved along its orbit (same 176 km distance) so it stands ~40 deg above the spawn horizon in the same
quarter of the sky - light only, no terrain change. Tools pulled back to z -0.46, scale 0.95, turned 7.5 deg inward.
Chest fill light + F helmet lamp. Hands readout as one `[L]/[R]` panel. Starter hint "WASD" as one key cap; the
hint row lifted above the O2 bar.
Worked: daylight changed the first impression completely: terrain, rocks and mountains read; tools read as a drill
and a build tool held in two hands. The sprint pose visibly swings the tools.

## Open from these rounds

- Main menu backdrop: one turret on a disc is fine but plain; a small base scene (foundation, smelter, pipe, turret)
  would sell the game better.
- The world sky at spawn is now a bright day; check the moon and other bodies still get night where they should.
- Machine panel at 1152 px is dense; at 1080p it breathes. Retest at 1920x1080 when the tour can set the window size.

## Polish pass, 2026-11-04 (Michael: "UI needs one more refresh pass - quality and animations ... the general
## graphical interface is also plain and grey (literally) ... feels like generic unity")

Direction set with the frontend-design skill: "field instrument" - industrial/utilitarian with PS2-era hardware
character. The read: an in-game UI a player lives in for hours, so motion stays short and functional and the
character comes from material (tinted gradient plates, machined lip, cut corners, brackets) and type (condensed
caps), not from decoration everywhere.

### p1: drawn box, tinted palette, condensed type, motion
Changed: UiBevelBox (a GDScript StyleBox: gradient plate, asymmetric cut corners, lip, brackets, hatching, rule);
palette re-tinted teal (no neutral grey left); Bahnschrift SemiBold Condensed for titles/nav/tabs; menu backdrop =
vignette + scanlines; hover lift / press dip on every button, slot and card; screens rise in, lists stagger; HUD
goal pulse, eased bars, pickup pop, crosshair ticks on usable things; numbered nav; start menu backdrop = an outpost
of real buildings at dusk with an orbiting camera.
Worked: the condensed headings and the cut-corner plates with mint brackets are what finally make it read as THIS
game's UI rather than an engine default. Header hatching is subtle and right.
Didn't: the backdrop ground plane's edge showed as a grey "room" behind the base, and the light was muddy brown.
Gotchas: a StyleBox subclass in the theme needs `--import` first (class_name), and the theme builder's helper
signatures must take `StyleBox`, not `StyleBoxFlat`. The first tour run after an import crashed once silently
(no script error) and ran clean on retry - rerun before debugging.

### p2: backdrop, loading, nav state
Changed: 900 m ground fading into horizon-coloured fog, brighter golden key, wider orbit; loading screen on the
shared backdrop with a tip line; the open page's nav entry stays lit.
Worked: the menu now reads as a dusk outpost on an endless plain. Settings page with VIDEO tab underlined, 04
SETTINGS lit - you always know where you are.
Open: the front faces of the base are backlit at some orbit angles (the key is low and behind for part of the turn);
fine as mood, revisit if it reads too dark on other monitors.

## Warframe pass, 2026-11-04 (Michael: "nah make the ui more modern. Use libraries like anime.js, research how to
## make a good game ui. Use a different font" / "minimalistic in a warframe way" / "feedback of the ui is super
## important" / Game UI Database link to Warframe / "saira defo", no name or tagline)

Research: Warframe on Game UI Database (title, options, arsenal, daily tribute, in-mission HUD screens read in the
built-in browser - the site 403s automated fetches). Web-UI-in-Godot plugins checked: godot_wry (4.7 fork, MIT, but a
native always-on-top window - can't sit under/between game UI), godotwebview (commercial beta, 4.5), ultralight-godot
(GPL, pre-1.0, 60 fps cap on free SDK), Godot-Webview-OSR (no release). Michael chose: Godot UI + an anime.js-style
motion system written in GDScript; Warframe gold; Saira (from a five-font preview rendered in the chat).

### w1: rebuild
Saira downloaded (483,700 bytes, OFL, licence kept beside it). UiMotion (anime.js v3 model: animate, stagger,
keyframes, Penner/elastic/spring easings). UiSound (15 synthesised UI sounds on the UI bus). New tokens and theme:
square, translucent strips, hairlines, gold, light plate for selection. UiKit.screen rebuilt as a frameless
full-screen layout over a blurred world (backdrop shader), title + gold diamond rule + breadcrumb, hints
bottom-right. Start / pause / loading rebuilt; name, tagline and numbering removed. HUD stripped of boxes,
objective moved top-left. Feedback wired everywhere (section 3b of the bible).
Didn't: the machine panel failed to open (its body variable was still typed PanelContainer - the frame body is a
MarginContainer now; one bad typed assignment aborted the whole _build); metadata keys can't contain "," or ":";
a `match` as the last statement of an inline lambda is a GDScript parse error ("Expected expression for match
pattern") - use if/elif there; HUD text with outline 3 + shadow outline 4 looked smeared; the selected build card's
name vanished (light text on the light plate); the journal's current goal was gold-on-light.

### w2: fixes
Panel type, meta keys, lambda match -> if, HUD text = 1 px faint outline + 1 px shadow, selected card text turns ink,
current goal = gold outline on a gold wash, toggle "On" no longer clipped, HUD captions full gold (dim gold
disappeared on bright ground). Build test 9/9, tour clean (0 script errors).
Worked: the frameless screens over the blurred world, the thin tracked titles with the one diamond rule, and the
light plate for "selected" are what make it read as Warframe-modern. The machine panel is the best single screen.
