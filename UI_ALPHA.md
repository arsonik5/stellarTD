# StellarTD Alpha UI

This file is the source of truth for the alpha interface. Godot scenes should use `res://ui/alpha_theme.tres` and preserve these layout rules.

## Direction

Industrial field-console UI: deep blue-black surfaces, warm amber actions, teal system information, and orange warnings. The world remains visible behind the interface through a restrained dimmer. UI is dense, readable, and built for repeated inventory and production work.

## Layout rules

- Full-screen overlays use a 24 px outer margin and a 16 px gap between columns.
- A building screen has two columns: player inventory on the left, active building on the right.
- Player inventory is a 288 px rail; the building workspace takes the remaining width.
- Building inventory is a compact 5-column grid. Capacity is shown as units, not slot count.
- Recipes are a vertical list of full-width actions so adding recipes never causes horizontal overflow.
- Every clickable slot is at least 44 px tall and has a clear hover/pressed state.
- Content may scroll inside its column; panels never grow beyond the viewport.

## Tokens

- Base: `#08131c`
- Surface: `#10232e`
- Raised surface: `#173542`
- Line: `#2c5360`
- Text: `#e9f1ed`
- Muted text: `#91a9aa`
- Teal status: `#4ecdc4`
- Amber action: `#f2a65a`
- Warning: `#e76f51`
- Success: `#78c091`

## Motion

Use short, functional transitions only: 120-220 ms for hover and state changes, 300-450 ms for opening panels. Prefer Godot Tween with ease-out. Reduced-motion support is a later alpha task.

## Surfaces

- Inventory slots are quiet raised tiles; item names are primary and counts are secondary.
- Recipe actions use amber only for the actionable state. Disabled or blocked actions use muted red text and never rely on color alone.
- Modifiers are four equal slots with explicit empty state.
- Avoid full-screen grey panels, floating cards inside cards, and unbounded fixed pixel layouts.
