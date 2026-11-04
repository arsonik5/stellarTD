---
name: stellar-td-ui-todo
description: Stellar TD UX overhaul (2026-11-04) is locked in docs/game/ux-bible.md; parked to-do to install Qwen Image 2.1 Q8 on furryass only when Michael says
metadata:
  node_type: memory
  type: project
  originSessionId: 06af6e59-c7aa-4c8d-ac14-b8023a2089f8
  modified: 2026-11-04T09:23:54.445Z
---

2026-11-04 Michael: "we need better ui for everything ... design a scheme" and then "everything feels like a Unity
MVP from a YouTube tutorial ... standardize it, cohesive experience ... UIs opened by tools and blocks, not buttons,
except menus ... first person tools are static, view bob, walking ... saves menu, start menu, settings ... iterate as
many times as possible, notes very in depth, lock it in early".

Done the same day, all in the repo:
- `docs/game/ux-bible.md` = the locked rules (look tokens, where every screen comes from, components, HUD map, key
  hints, words, build menu, feel numbers, menus/settings, icons, how to test). `docs/game/ux-log.md` = rounds r0-r4.
- Code: scripts/ui/kit (UiTokens, UiKit, SlotButton, ItemIcon, ModelMeshes), generated theme
  (scripts/dev/build_theme.gd -> ui/stellar_theme.tres), GameSettings autoload, start/pause/saves/settings, HUD,
  build menu, inventory, machine panel, journal, FirstPersonFeel, icon baker, ux_tour.

**Why:** Michael wants the experience nailed early so later work builds on one system.

**How to apply:**
- Any UI/HUD/menu/feel work: read docs/game/ux-bible.md first and follow it; run `scenes/dev/ux_tour.tscn -- tag=rN`
  and add a round to ux-log.md.
- Autoload is `GameSettings`, never `Settings` (ErosionBaker has an inner class Settings; the clash broke terrain).
- Qwen Image 2.1, Q8, on furryass: still a TO-DO. Do NOT install until Michael says. Mind furryass disk (~27 GB free
  on C: as of 2026-10-11) and 12 GB VRAM. Intended use: painted icons/UI art using the baked icon renders as reference.
- Look since the 2026-11-04 Warframe pass (Michael: "minimalistic in a warframe way", "more modern", "feedback of
  the ui is super important"): frameless screens over a blurred world, translucent strips, hairlines, Saira
  (ui/fonts, OFL, his pick) thin wide-tracked caps titles with one gold diamond rule, Warframe gold accent, selected =
  solid light plate with dark text, HUD with no boxes. Motion = UiMotion (anime.js v3 model in GDScript - he chose
  this over a web view), sound = UiSound (synthesised). NO game name, tagline or logo until he decides.
- Rejected and must not return: the chamfered "PS2 hardware" panels with scanlines/hatching and any flat neutral
  grey box ("generic unity").

Related: [[stellar-td-ps2-look]], [[stellar-td-fp-building]].
