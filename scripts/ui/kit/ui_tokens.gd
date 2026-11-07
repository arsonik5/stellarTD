class_name UiTokens
## The one source of every UI colour, size and font in the game (docs/game/ux-bible.md, "Look").
## Nothing in a UI script picks its own colour or font size: it asks for a theme type variation (UiKit / the
## generated ui/stellar_theme.tres) or, for the few things a theme can't express, reads a constant here.
## Change a value here, then regenerate the theme:
##   godot --headless --path . --script res://scripts/dev/build_theme.gd
##
## Direction (2026-11-07, Michael: the 11-04 look was "very AI-ish"; wants minimal, modern, glass, Warframe elements):
## frosted glass. Panels are light translucent sheets over the blurred world with a soft shadow and a faint rim;
## corners are asymmetric (two big, two nearly square) like Warframe's cut panels; ice-blue accent instead of
## gold; short accent bars instead of ornaments (no diamonds, no gradient rules, no "SUIT /" breadcrumbs);
## titles are light capitals with modest tracking. The selected thing becomes a solid light plate.

# --- surfaces: translucent, never opaque grey boxes ---------------------------------------------------------
const INK := Color("04070a")                     # loading screen, behind the menus
const PANEL := Color(0.78, 0.88, 0.95, 0.10)  # the rare real panel (detail panes, dropdowns)
const STRIP := Color(0.85, 0.93, 1.0, 0.075)       # a row: settings line, recipe, save card
const STRIP_HI := Color(0.85, 0.93, 1.0, 0.16)     # hovered row
const WELL := Color(0.02, 0.05, 0.08, 0.38)         # slots
const LINE := Color(0.85, 0.94, 1.0, 0.16)   # hairlines
const LINE_HI := Color(0.85, 0.94, 1.0, 0.50)
const SHADE := Color(0.03, 0.06, 0.09, 0.42)  # tint laid over the blurred world behind a screen

# --- text: warm off-white, never pure white ------------------------------------------------------------------
const TEXT := Color("eef4f8")
const TEXT_DIM := Color("9fb0ba")
const TEXT_FAINT := Color("65767f")

# --- signal ---------------------------------------------------------------------------------------------------
const ACCENT := Color("8fdcf2")                  # ice blue: selection, focus, values, progress, the crosshair ticks
const ACCENT_DIM := Color("6fb4c8")              # accent captions
const ACCENT_DEEP := Color(0.56, 0.86, 0.95, 0.16)   # accent wash behind selected/primary things
const ACCENT_INK := Color("0a1116")              # text on an accent or light plate
const PLATE := TEXT                              # the solid light plate a selected item turns into
const GOOD := Color("8fe0a8")                    # working / refilling / done (green, never the blue accent)
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
const CORNER_BIG := 10      # glass panels: top-left and bottom-right radius
const CORNER_SMALL := 2      # the other two corners
const CHAMFER := 0           # kept for old callers
const CHAMFER_S := 0
const SLOT := 64
const BUTTON_H := 36
