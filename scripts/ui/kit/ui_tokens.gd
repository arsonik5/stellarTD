class_name UiTokens
## The one source of every UI colour, size and font in the game (docs/game/ux-bible.md, "Look").
## Nothing in a UI script picks its own colour or font size: it asks for a theme type variation (UiKit / the
## generated ui/stellar_theme.tres) or, for the few things a theme can't express, reads a constant here.
## Change a value here, then regenerate the theme:
##   godot --headless --path . --script res://scripts/dev/build_theme.gd
##
## Direction (2026-11-04, Michael: "minimalistic in a warframe way", "more modern"): almost no boxes. Content floats
## over a blurred, darkened world on faint translucent strips; thin light hairlines; Saira in thin, wide-spaced
## capitals for titles; gold for selection, focus and values; the selected thing becomes a solid light plate.

# --- surfaces: translucent, never opaque grey boxes ---------------------------------------------------------
const INK := Color("04070a")                     # loading screen, behind the menus
const PANEL := Color(0.016, 0.027, 0.039, 0.62)  # the rare real panel (detail panes, dropdowns)
const STRIP := Color(1.0, 1.0, 1.0, 0.045)       # a row: settings line, recipe, save card
const STRIP_HI := Color(1.0, 1.0, 1.0, 0.09)     # hovered row
const WELL := Color(0.0, 0.0, 0.0, 0.34)         # slots
const LINE := Color(0.925, 0.902, 0.847, 0.14)   # hairlines
const LINE_HI := Color(0.925, 0.902, 0.847, 0.42)
const SHADE := Color(0.016, 0.024, 0.035, 0.70)  # tint laid over the blurred world behind a screen

# --- text: warm off-white, never pure white ------------------------------------------------------------------
const TEXT := Color("ece6d8")
const TEXT_DIM := Color("8f989c")
const TEXT_FAINT := Color("566066")

# --- signal ---------------------------------------------------------------------------------------------------
const ACCENT := Color("d8b26a")                  # gold: selection, focus, values, progress, the crosshair ticks
const ACCENT_DIM := Color("9c8350")              # gold captions
const ACCENT_DEEP := Color(0.847, 0.698, 0.416, 0.16)   # gold wash behind selected/primary things
const ACCENT_INK := Color("0b0e11")              # text on a gold or light plate
const PLATE := TEXT                              # the solid light plate a selected item turns into
const GOOD := Color("8fd0c6")                    # working / refilling / done (cool, so it never reads as gold)
const WARN := Color("e3833a")                    # low, missing input
const DANGER := Color("e04a3c")                  # empty, destructive

# --- category hues (art-direction.md). Only on icons and category labels --------------------------------
const CAT := {
	"structure": Color("b9bec3"),
	"production": Color("f2a33a"),
	"logistics": Color("4fc3c0"),
	"defense": Color("e5533d"),
	"vehicles": Color("b49cf0"),
	"power": Color("6fa8ff"),           # reserved, not in use yet
}

# --- type: Saira (variable, ui/fonts/Saira-Variable.ttf, OFL) -----------------------------------------------
const FONT_FILE := "res://ui/fonts/Saira-Variable.ttf"
const W_LIGHT := 300                             # titles - thin, wide-spaced capitals
const W_REGULAR := 400                           # body
const W_MEDIUM := 500                            # labels, buttons, nav
const W_SEMI := 600                              # numbers that matter (O2 time, counts)
const FS_CAPTION := 11       # section labels (caps, +0.25em), key caps, small print
const FS_BODY := 15          # default
const FS_NAV := 16           # menu nav
const FS_TITLE := 28         # screen titles (light, +0.3em)
const FS_DISPLAY := 40       # reserved
const FS_HUD := 15

# --- spacing: 4 px grid -----------------------------------------------------------------------------------
const GAP_S := 4
const GAP := 8
const GAP_L := 16
const PAD := 16
const EDGE := 64             # screen margin: titles, nav and footer hints sit this far in from the edges
const CHAMFER := 0           # square corners everywhere (Warframe-flat); kept for old callers
const CHAMFER_S := 0
const SLOT := 64
const BUTTON_H := 36
