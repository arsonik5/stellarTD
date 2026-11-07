# Tools: the whole flow (2026-11-07)

One rule: **the left mouse button uses the tool in the left hand, the right mouse button uses the tool in the right
hand.** Both hands are always live. What a press does depends only on what that hand holds. The HUD (bottom right)
shows `LMB <tool>` and `RMB <tool>`. Code: `Player._on_hand_button()` in `scripts/player/player.gd`.

## What was wrong (before)
- LMB did "the scanner if one is in any hand, else the drill". Put the scanner in the right hand and the drill in the
  left stopped working, with no hint why.
- RMB did "ship part, else lay a block with the drill". The Building Tool had nothing to do with either mouse button:
  it only worked through the C key, so a tool in your hand did nothing when you clicked.
- The HUD said `L` / `R`, which read as keys, not mouse buttons.
- A drill whose release the game never saw (menu opened mid-hold) kept running; a scanner pulse outlived the scanner.

## Flow
```
start:  left hand Mining Tool, right hand Building Tool, Scanner in the suit storage (Tab)

Tab -> inventory: drag a tool into a hand slot (hands take tools and ship parts only)

mouse press (mouse captured, not in a menu)
  hand = left for LMB, right for RMB
  hand holds ...
    Mining Tool    hold: wind-up (0.35 s: pose, rattle, whine) -> bites every 0.05 s, shove + dust + thud per bite
                   release: spin-down. Taking the drill out of the hand stops it.
    Scanner        press: ping + radar minigame (B-scope, sweep bar, traces). Wheel / 1-6 tune the ore, press again
                   with a trace on the centre line = LOCK; then a marker + distance guide you. X closes the radar,
                   X again drops the lock. Code: scripts/ui/scanner_hud.gd, scripts/world/ore_scanner.gd
    Building Tool  opens build mode (same as C): menu -> pick a building -> aim ->
                     LMB places (pipe: LMB start, LMB end), R / wheel rotate, G grid, B pipe angle,
                     Q menu, RMB leave (first RMB drops a started pipe)
                   Taking the tool out of the hand leaves build mode.
    Ship part      places it (ship core / blocks)
    nothing        small deny shake. Exception: RMB with a Mining Tool in the other hand lays a terrain block
                   (costs ore; the "Lay a Block" quest)
other keys: C build mode (needs the Building Tool in any hand), E use, F lamp, Tab inventory, J journal
```

## Rules for new tools
A new tool is an Item with `is_tool = true` plus one branch in `_on_hand_button`, a held model (viewmodel), a use kick,
a deny kick and a HUD name. Never read "is the tool somewhere in a hand" to decide a mouse action: ask the hand that
owns the button. Test: `scenes/dev/tool_flow_test.tscn` (headless).

## Console (` or /)
Empty input lists every command; typing narrows the list (items, hands, amounts too). Up/Down pick, Tab or click fills,
PageUp/PageDown = history. `give`/`spawn`, `tools`, `ores`, `hand`, `clear`, `tp`, `o2`, `save`, `reload`.
