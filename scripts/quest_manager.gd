extends Node

## Starting/tutorial questline: guides a new player through mining ->
## crafting -> automating. Deliberately generic (id/prerequisite/objective
## data, not per-quest code) so it composes cleanly with whatever later
## quest content shows up (e.g. the corporate "contracts" system sketched in
## radiation-threat-design.md) rather than needing a second bespoke tracker.
signal changed

const QUEST_LIST := [
	preload("res://data/quests/mine_iron.tres"),
	preload("res://data/quests/open_inventory.tres"),
	preload("res://data/quests/place_processor.tres"),
	preload("res://data/quests/refine_iron.tres"),
	preload("res://data/quests/build_block.tres"),
	preload("res://data/quests/autocraft.tres"),
	preload("res://data/quests/conveyor.tres"),
]

var _defs: Dictionary = {}
var _state: Dictionary = {} # id -> "locked" | "active" | "complete"
var _progress: Dictionary = {} # id -> int, only used by PLACE_BUILDING/ACTION objectives

func _ready() -> void:
	for quest: Quest in QUEST_LIST:
		_defs[quest.id] = quest
		_state[quest.id] = "locked"
		_progress[quest.id] = 0
	Inventory.changed.connect(_recompute)
	GameEvents.action.connect(notify_action)
	GameEvents.building_placed.connect(func(item_id: String, _node: Node) -> void: notify_building_placed(item_id))
	_recompute()

func get_all_ids() -> Array:
	return _defs.keys()

func get_def(id: String) -> Quest:
	return _defs.get(id)

func get_state(id: String) -> String:
	return _state.get(id, "locked")

func get_active_ids() -> Array:
	return _state.keys().filter(func(id: String) -> bool: return _state[id] == "active")

func get_progress_current(id: String) -> int:
	var quest: Quest = _defs.get(id)
	if quest == null:
		return 0
	if quest.objective_type == Quest.ObjectiveType.COLLECT_ITEM:
		return mini(Inventory.get_count(quest.target_id), quest.target_amount)
	return mini(_progress.get(id, 0), quest.target_amount)

## Longest prerequisite chain from any root quest - used only by the
## Journal's tech-tree layout (column = depth), not by completion logic.
func get_depth(id: String) -> int:
	var quest: Quest = _defs.get(id)
	if quest == null or quest.prerequisite_ids.is_empty():
		return 0
	var deepest := 0
	for prereq_id: String in quest.prerequisite_ids:
		deepest = maxi(deepest, get_depth(prereq_id) + 1)
	return deepest

func notify_action(action_id: String, amount: int = 1) -> void:
	_accumulate(Quest.ObjectiveType.ACTION, action_id, amount)

func notify_building_placed(item_id: String, amount: int = 1) -> void:
	_accumulate(Quest.ObjectiveType.PLACE_BUILDING, item_id, amount)

## Accumulates against EVERY matching quest, not just currently-active ones -
## a player can do the thing a later quest asks for before that quest
## actually unlocks (e.g. place a second building type early, or satisfy a
## collect-based prerequisite one action after the placement it gates). Since
## progress is harmless to track early and _recompute() re-checks completion
## on every unlock, this makes the whole chain robust to real play order
## instead of only the exact order the quest chain was authored assuming.
func _accumulate(objective_type: Quest.ObjectiveType, target_id: String, amount: int) -> void:
	for id: String in _defs:
		var quest: Quest = _defs[id]
		if quest.objective_type == objective_type and quest.target_id == target_id:
			_progress[id] += amount
	_recompute()

## Fixed-point pass: unlock any quest whose prerequisites just completed,
## complete any active quest whose objective is now met, repeat until
## nothing changes, emit once. Avoids the mutual-recursion bookkeeping a
## naive "unlock then separately check completions" split would need.
func _recompute() -> void:
	var changed_this_pass := true
	while changed_this_pass:
		changed_this_pass = false
		for id: String in _defs:
			if _state[id] == "locked" and _prereqs_met(id):
				_state[id] = "active"
				changed_this_pass = true
			elif _state[id] == "active" and _objective_met(id):
				_state[id] = "complete"
				changed_this_pass = true
	changed.emit()

func _prereqs_met(id: String) -> bool:
	for prereq_id: String in _defs[id].prerequisite_ids:
		if _state.get(prereq_id) != "complete":
			return false
	return true

func _objective_met(id: String) -> bool:
	var quest: Quest = _defs[id]
	if quest.objective_type == Quest.ObjectiveType.COLLECT_ITEM:
		return Inventory.get_count(quest.target_id) >= quest.target_amount
	return _progress.get(id, 0) >= quest.target_amount

## --- Persistence (see scripts/save/save_manager.gd) ---
##
## Quests not present in the save stay at their freshly-initialised "locked"
## and are then re-derived by _recompute(), so adding new quests to QUEST_LIST
## does not invalidate existing saves - a returning player simply finds the new
## quest unlocked if they already meet its prerequisites.

func save_state() -> Dictionary:
	return {"state": _state.duplicate(), "progress": _progress.duplicate()}

func load_state(data: Dictionary) -> void:
	var saved_state: Dictionary = data.get("state", {})
	var saved_progress: Dictionary = data.get("progress", {})
	for id: String in _defs:
		if saved_state.has(id):
			_state[id] = String(saved_state[id])
		if saved_progress.has(id):
			_progress[id] = int(saved_progress[id])
	_recompute()
