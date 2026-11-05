class_name ItemInfo
## Player-facing text and grouping for every item, in one place (docs/game/ux-bible.md, "Words"): the category that
## sorts it in menus and colours its icon, and one plain sentence saying what it is FOR - not how it works inside.
## Icons: ItemInfo.icon(id) returns data/icons/<id>.png when the icon baker has made one (see ux-bible "Icons"),
## otherwise null and the UI draws the category glyph.

const CATEGORIES := ["structure", "production", "logistics", "defense", "vehicles", "material", "tool"]
const CATEGORY_NAMES := {
	"structure": "Structure", "production": "Production", "logistics": "Logistics", "defense": "Defense",
	"vehicles": "Vehicles", "material": "Materials", "tool": "Tools",
}

const INFO := {
	# structure
	"metal_foundation": ["structure", "Flat 2 x 2 m floor plate. Machines on it sit level and line up on the grid."],
	"foundation_1m": ["structure", "1 m thick foundation block. Builds up terraces and platforms."],
	"foundation_2m": ["structure", "2 m thick foundation block for tall platforms."],
	"frame_2m": ["structure", "Open steel frame, 2 m. Light and see-through; holds floors up."],
	"ramp_1m": ["structure", "Slope that climbs 1 m over 2 m. Walk and drive up to the next level."],
	"stairs_1m": ["structure", "Steps up 1 m. Steeper than a ramp, takes less room."],
	"placeable_block": ["structure", "A block of terrain you can put back."],
	# production
	"basic_crafter": ["production", "Hand-fed workbench. Turns ore into the first parts."],
	"smelter": ["production", "Melts ore into ingots. Needs a steady feed of ore."],
	"constructor": ["production", "Builds parts from ingots - ammo, casings, ship parts."],
	# logistics
	"chest": ["logistics", "Storage box. Pipes can fill it and empty it."],
	"vacuum_pipe": ["logistics", "Carries items between machines. Lay it in straight runs; it bends itself at corners."],
	"merger": ["logistics", "Joins up to three pipes into one."],
	"splitter": ["logistics", "Splits one pipe into up to three, taking turns."],
	# defense
	"turret_gun": ["defense", "Fast-firing turret. Good against light, quick targets."],
	"turret_cannon": ["defense", "Slow, heavy cannon. Good against armour."],
	# vehicles
	"ship_garage": ["vehicles", "Base life support and ship yard: refills your suit, builds and repairs ships."],
	"ship_core": ["vehicles", "Heart of a ship. Every block must connect back to one."],
	"vehicle_core": ["vehicles", "Small core for buggies and light builds."],
	"ship_cockpit": ["vehicles", "Sealed cockpit: you breathe the ship's air from its oxygen tanks."],
	"driver_seat": ["vehicles", "Open seat. Light and cheap, but you live on your suit."],
	"o2_tank": ["vehicles", "Air for the sealed cockpits on the same ship."],
	"battery": ["vehicles", "Stores power for the ship."],
	"engine": ["vehicles", "Drives the wheels. No engine, and wheels only roll."],
	"wheel_small": ["vehicles", "1 m wheel with real suspension. Steers if it sits ahead of the centre."],
	"wheel_large": ["vehicles", "2 m wheel for heavy builds and rough ground."],
	"landing_gear": ["vehicles", "Sprung leg for landing. Grips hard when parked; G folds it away."],
	"ship_thruster": ["vehicles", "Main thruster. Pushes along its nozzle."],
	"rcs": ["vehicles", "Small thruster that pushes any way it is asked to. Fine control."],
	"ship_gyroscope": ["vehicles", "Turns the ship."],
	"ship_hull": ["vehicles", "2 m armour block."],
	"hull_small": ["vehicles", "0.5 m armour block."],
	"wedge": ["vehicles", "Sloped 1 m armour."],
	"plate": ["vehicles", "Thin 1 x 1 m plate: floor, wall or armour on a frame."],
	"beam_1": ["vehicles", "0.5 m frame beam. Bolts to anything."],
	"beam_2": ["vehicles", "1 m frame beam."],
	"beam_4": ["vehicles", "2 m frame beam."],
	"frame_cube": ["vehicles", "Open tube cube. Light filler in a frame."],
	"frame_corner": ["vehicles", "Frame joint with a bolting face on every side."],
	# materials
	"ore_a": ["material", "Iron ore. Smelts into iron ingots."],
	"ore_b": ["material", "Copper ore. Smelts into copper ingots."],
	"ore_coal": ["material", "Coal. Smelts into carbon."],
	"ore_silica": ["material", "Silica sand. Smelts into glass."],
	"sulfur": ["material", "Sulfur. Goes into gunpowder."],
	"ore_crystal": ["material", "Radioactive crystal. Handle with care: it draws attention."],
	"stone": ["material", "Plain rock from digging. A crusher turns it into gravel."],
	"refined_material": ["material", "Iron ingot. The base of most builds."],
	"refined_copper_ingot": ["material", "Copper ingot."],
	"refined_carbon": ["material", "Carbon ingot."],
	"refined_silica": ["material", "Silica glass. Circuits, concrete and crystal cells need it."],
	"copper_casing": ["material", "Shell casing for ammunition."],
	"gunpowder": ["material", "Propellant for ammunition."],
	"piercing_core": ["material", "Hardened core for piercing rounds."],
	"iron_piercing_ammo": ["material", "Gun turret ammunition."],
	"he_shell": ["material", "Cannon shell."],
	"copper_wire": ["material", "Copper wire. Goes into circuits and anything electric."],
	"steel_ingot": ["material", "Steel: iron hardened with carbon. Heavy machines and armour."],
	"circuit": ["material", "Circuit board. Machines that think: uplinks, sensors, robots."],
	"gravel": ["material", "Crushed stone. Mixed into concrete."],
	"concrete": ["material", "Concrete. Heavy foundations and the Continuance's colony orders."],
	"crystal_cell": ["material", "Sealed crystal power cell. Earth wants these more than anything - and so do others."],
	# tools
	"mining_tool": ["tool", "Drill. Hold the trigger to cut the ground and collect ore."],
	"building_tool": ["tool", "Places buildings. In hand: C opens the build menu."],
	"scanner_tool": ["tool", "Pings the ground for ore and marks it on screen."],
}

static func category(id: String) -> String:
	return String(INFO[id][0]) if INFO.has(id) else "material"

static func description(id: String) -> String:
	return String(INFO[id][1]) if INFO.has(id) else ""

static func color(id: String) -> Color:
	var c := category(id)
	if UiTokens.CAT.has(c):
		return UiTokens.CAT[c]
	var item := Inventory.get_item_def(id)
	return item.debug_color if item != null and c == "material" else UiTokens.TEXT_DIM

static var _icon_cache := {}

static func icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var path := "res://data/icons/%s.png" % id
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_icon_cache[id] = tex
	return tex
