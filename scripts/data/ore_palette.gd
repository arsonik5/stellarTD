class_name OrePalette
extends RefCounted

## One colour per resource family, so a raw ore, the ingot smelted from it, the ore voxels in the ground and the
## scanner trace all read as the same thing:
##   iron   = steel grey-blue  (ore is the dull dark slate, ingot is bright steel)
##   copper = orange           (ore is burnt orange, ingot is bright copper)
##   coal   = black / graphite (ore is black, carbon is graphite)
##   silica = sand -> glass    (ore is sand, glass is pale cyan)
##   sulfur = yellow
##   crystal = green
## The item `debug_color`s in data/items and the surfaces in data/surfaces/ore_*.tres use these values: change one,
## change all. `hud` is the lighter variant used on dark UI.
const FAMILIES := {
	"iron": {"ore": Color(0.40, 0.45, 0.52), "ingot": Color(0.80, 0.84, 0.90), "hud": Color(0.66, 0.76, 0.90)},
	"copper": {"ore": Color(0.66, 0.40, 0.22), "ingot": Color(0.95, 0.58, 0.30), "hud": Color(0.95, 0.58, 0.30)},
	"coal": {"ore": Color(0.10, 0.10, 0.11), "ingot": Color(0.28, 0.28, 0.31), "hud": Color(0.62, 0.64, 0.70)},
	"silica": {"ore": Color(0.80, 0.76, 0.64), "ingot": Color(0.75, 0.92, 0.97), "hud": Color(0.78, 0.90, 0.96)},
	"sulfur": {"ore": Color(0.90, 0.80, 0.20), "ingot": Color(0.90, 0.80, 0.20), "hud": Color(0.95, 0.87, 0.35)},
	"crystal": {"ore": Color(0.30, 0.85, 0.30), "ingot": Color(0.30, 0.85, 0.30), "hud": Color(0.45, 0.95, 0.45)},
}

static func hud(id: String, fallback: Color = Color(0.55, 0.85, 0.75)) -> Color:
	return FAMILIES[id]["hud"] if FAMILIES.has(id) else fallback
