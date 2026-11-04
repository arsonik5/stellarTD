class_name VoxelMaterials

const STONE := 0
const IRON_ORE := 1
const COPPER_ORE := 2
const CONSTRUCTION_BLOCK := 3
const SULFUR_ORE := 4
const COAL_ORE := 5
const SILICA_ORE := 6
const CRYSTAL_ORE := 7

# Per-biome "filler rock" indices - what shows where no ore vein wins.
# STONE (0) doubles as Regolith Plains' own filler, no separate index needed.
const STONE_FROZEN := 8
const STONE_SULFUR_FLATS := 9
const STONE_CRYSTAL_FIELDS := 10

# Applied by surface RULE rather than by biome (see ore_generator.gd):
# cliff rock on steep faces, bedrock below the topsoil layer. Both exist on
# every body regardless of which biomes it defines.
const CLIFF_ROCK := 11
const BEDROCK := 12

# TEXTURES_MIXEL4_S4 gives each of the four blended material slots only 4
# bits, so nothing here may exceed 15 - adding a 17th material needs a
# different texturing mode, not just another constant.
const MAX_INDEX := 15

# Legacy aliases kept for old save data and resource references.
const ORE_A := IRON_ORE
const ORE_B := COPPER_ORE
const BLOCK := CONSTRUCTION_BLOCK
const ORE_SULFUR := SULFUR_ORE

## How hard a material is to drill: bite strength is divided by this, so 2.0
## takes twice as long to cut as plain stone. First-pass values, tune by feel.
## BEDROCK is the host rock of the whole underground below a few metres of
## topsoil, not an unbreakable floor - keep it close to stone or every tunnel
## crawls.
static func hardness_for(index: int) -> float:
	var hardness := {
		STONE: 1.0, IRON_ORE: 1.5, COPPER_ORE: 1.3, CONSTRUCTION_BLOCK: 2.0,
		SULFUR_ORE: 0.7, COAL_ORE: 0.8, SILICA_ORE: 1.2, CRYSTAL_ORE: 2.5,
		STONE_FROZEN: 1.2, STONE_SULFUR_FLATS: 0.8, STONE_CRYSTAL_FIELDS: 1.4,
		CLIFF_ROCK: 1.6, BEDROCK: 1.2,
	}
	return hardness.get(index, 1.0)

## Human-readable name for a material index, for diagnostics only.
##
## Keyed off the constants above rather than repeating their raw values, so
## adding a material cannot drift out of sync with the index it names - only the
## label has to be supplied.
static func name_for(index: int) -> String:
	var names := {
		STONE: "stone", IRON_ORE: "iron", COPPER_ORE: "copper",
		CONSTRUCTION_BLOCK: "block", SULFUR_ORE: "sulfur", COAL_ORE: "coal",
		SILICA_ORE: "silica", CRYSTAL_ORE: "crystal",
		STONE_FROZEN: "frozen", STONE_SULFUR_FLATS: "sulfurflat",
		STONE_CRYSTAL_FIELDS: "crystalfld", CLIFF_ROCK: "cliffrock",
		BEDROCK: "bedrock",
	}
	return names.get(index, "idx%d" % index)
