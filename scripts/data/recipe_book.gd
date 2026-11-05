class_name RecipeBook
extends RefCounted
## Every Recipe in data/recipes, indexed by output - the one lookup for "what does X cost", "what makes X" and
## "what uses X" (dismantle refunds, recipe lookup tooltips, the economy sheet).

const DIR := "res://data/recipes"

static var _all: Array[Recipe] = []
static var _by_output: Dictionary = {}

static func all() -> Array[Recipe]:
	_load()
	return _all

## The recipe that produces `item_id` (build_* recipes for buildings), or null.
static func for_output(item_id: String) -> Recipe:
	_load()
	return _by_output.get(item_id)

## Recipes that consume `item_id`.
static func uses_of(item_id: String) -> Array[Recipe]:
	_load()
	var out: Array[Recipe] = []
	for r in _all:
		if r.input_ids.has(item_id):
			out.append(r)
	return out

static func _load() -> void:
	if not _all.is_empty():
		return
	# list_directory handles exported builds (.remap files) where DirAccess listing would not
	for f in ResourceLoader.list_directory(DIR):
		if not f.ends_with(".tres"):
			continue
		var r := load(DIR + "/" + f) as Recipe
		if r == null:
			continue
		_all.append(r)
		# build_* recipes win over craft_* for the same output: the build recipe is what placement spends
		if not _by_output.has(r.output_id) or f.begins_with("build_"):
			_by_output[r.output_id] = r
