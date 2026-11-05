extends Node

## The whole save system: slot management on disk, plus the orchestration that
## gathers state out of the running game and puts it back.
##
## Two storage layers, deliberately separate:
##
##   state.json    - everything authored by the player as discrete objects:
##                   inventory, quests, placed buildings, ships, where the
##                   player is standing. Small, human-readable, diffable.
##   terrain_*.sqlite - one VoxelStreamSQLite per celestial body, holding ONLY
##                   edited voxel blocks (save_generator_output = false). The
##                   planet itself is reproduced by the generator from its
##                   seed and baked heightmap, so a save never stores terrain
##                   the player didn't touch.
##
## SaveManager never reaches into another system's internals. Each participating
## system implements `save_state() -> Dictionary` / `load_state(Dictionary)` and
## this only decides WHEN and in what order - so adding a system to the save
## means adding two methods to it, not editing a central serializer.

const SAVES_DIR := "user://saves"
const STATE_FILE := "state.json"
## Bumped whenever the state.json layout changes incompatibly. Loading a slot
## from a newer version is refused rather than half-applied.
const FORMAT_VERSION := 2

## Migrations, one per version step: MIGRATIONS[n] turns a version-n state into version n+1. Old saves are
## upgraded on open, never refused, so changing the layout means adding a step here (design M34).
## 1 -> 2: player vitals/suit O2 and building health/jobs were added. Every reader has defaults, so the step
##         only stamps the version - it exists so the chain is unbroken from the first format.
const MIGRATIONS := {
	1: "_migrate_1_to_2",
}

func migrate(state: Dictionary) -> Dictionary:
	var v := int(state.get("version", 1))
	if v < 1:
		v = 1
	while v < FORMAT_VERSION:
		var step: String = MIGRATIONS.get(v, "")
		if step == "":
			push_error("SaveManager: no migration from version %d." % v)
			break
		state = call(step, state)
		v += 1
		state["version"] = v
	return state

func _migrate_1_to_2(state: Dictionary) -> Dictionary:
	return state

## Slot currently being played, "" when in the menu. Also what Planet reads to
## decide which terrain database to attach.
var current_slot: String = ""
## Parsed state waiting to be applied once the world scene finishes loading.
## Empty for a brand-new game, which is exactly what "new game" means here -
## there is no separate code path for it.
var pending_state: Dictionary = {}

var _playtime_base: float = 0.0
var _session_start_ms: int = 0

# ---------------------------------------------------------------- slot files

func slot_dir(slot_id: String) -> String:
	return "%s/%s" % [SAVES_DIR, slot_id]

func state_path(slot_id: String) -> String:
	return "%s/%s" % [slot_dir(slot_id), STATE_FILE]

## Per-body edit database. Keyed on the CelestialBody resource's filename,
## which is stable across sessions and unique per body without needing a new
## id field on the resource.
func terrain_db_path(slot_id: String, body_key: String) -> String:
	return "%s/terrain_%s.sqlite" % [slot_dir(slot_id), body_key]

func _ensure_saves_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVES_DIR))

## Every slot on disk, newest first. Header fields only - the full state is not
## parsed here, so listing stays cheap no matter how large a save gets.
func list_slots() -> Array:
	_ensure_saves_dir()
	var out: Array = []
	var dir := DirAccess.open(SAVES_DIR)
	if dir == null:
		return out
	for name in dir.get_directories():
		var data := read_state(name)
		if data.is_empty():
			continue
		out.append({
			"id": name,
			"name": String(data.get("name", name)),
			"updated_unix": int(data.get("updated_unix", 0)),
			"playtime_sec": float(data.get("playtime_sec", 0.0)),
			"version": int(data.get("version", 0)),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.updated_unix > b.updated_unix)
	return out

## Parsed state.json for a slot, or an empty dictionary if it is missing or
## unreadable. Public because the menu needs a slot header before deciding to
## open it.
func read_state(slot_id: String) -> Dictionary:
	var f := FileAccess.open(state_path(slot_id), FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

## Creates an empty slot and returns its id, or "" if it could not be written.
## The id is derived from the display name but stays filesystem-safe; a numeric
## suffix keeps two saves called "Home" from colliding.
func create_slot(display_name: String) -> String:
	_ensure_saves_dir()
	var base := _slugify(display_name)
	var id := base
	var n := 2
	while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(slot_dir(id))):
		id = "%s_%d" % [base, n]
		n += 1
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slot_dir(id))) != OK:
		push_error("SaveManager: could not create slot directory for '%s'." % id)
		return ""
	var now := int(Time.get_unix_time_from_system())
	var header := {
		"version": FORMAT_VERSION,
		"name": display_name.strip_edges(),
		"created_unix": now,
		"updated_unix": now,
		"playtime_sec": 0.0,
	}
	if not _write_state(id, header):
		return ""
	return id

func _slugify(text: String) -> String:
	var out := ""
	for c in text.strip_edges().to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	out = out.lstrip("_").rstrip("_")
	return out if out != "" else "save"

## Removes a slot and everything in it, terrain databases included. Irreversible
## by design - there is no trash folder and the caller is expected to confirm.
func delete_slot(slot_id: String) -> bool:
	var abs_dir := ProjectSettings.globalize_path(slot_dir(slot_id))
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return false
	for file in dir.get_files():
		dir.remove(file)
	return DirAccess.remove_absolute(abs_dir) == OK

func _write_state(slot_id: String, data: Dictionary) -> bool:
	var f := FileAccess.open(state_path(slot_id), FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot write %s" % state_path(slot_id))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

# ------------------------------------------------------------- session flow

## Called by the menu before switching to the world scene. Loading a slot and
## starting a new one differ ONLY in whether pending_state has anything in it.
func begin_session(slot_id: String, state: Dictionary) -> void:
	current_slot = slot_id
	pending_state = state
	_playtime_base = float(state.get("playtime_sec", 0.0))
	_session_start_ms = Time.get_ticks_msec()

func end_session() -> void:
	current_slot = ""
	pending_state = {}

func open_slot(slot_id: String) -> bool:
	var state := read_state(slot_id)
	if state.is_empty():
		push_error("SaveManager: slot '%s' has no readable state." % slot_id)
		return false
	if int(state.get("version", 0)) > FORMAT_VERSION:
		push_error("SaveManager: slot '%s' was written by a newer version." % slot_id)
		return false
	state = migrate(state)
	begin_session(slot_id, state)
	return true

func playtime_seconds() -> float:
	if _session_start_ms == 0:
		return _playtime_base
	return _playtime_base + float(Time.get_ticks_msec() - _session_start_ms) / 1000.0

func format_playtime(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 3600, (total % 3600) / 60]

# ------------------------------------------------- gathering / applying state

## Group every player-placed world object joins, and the metadata key holding
## the Item id it was built from. Both are set once at placement time (see
## player.gd's _register_placed) so respawning an object on load is "look up
## the item, instance its scene, restore its transform" for every type - no
## per-building save code and nothing to forget when a new building is added.
const SAVEABLE_GROUP := "saveable"
const ITEM_ID_META := "save_item_id"

func save_now() -> bool:
	if current_slot == "":
		return false
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return false

	var state := read_state(current_slot)
	state["version"] = FORMAT_VERSION
	state["updated_unix"] = int(Time.get_unix_time_from_system())
	state["playtime_sec"] = playtime_seconds()
	state["inventory"] = Inventory.save_state()
	state["quests"] = QuestManager.save_state()
	state["placed"] = _collect_placed(tree)
	state["ships"] = _collect_ships(tree)

	var player := tree.get_first_node_in_group("player")
	if player != null and player.has_method("save_state"):
		state["player"] = player.save_state()

	# Terrain edits go to their own databases, not into state.json. Kicked off
	# here and polled by the caller: godot_voxel writes blocks on worker
	# threads, so a save is not finished the moment this returns.
	_trackers.clear()
	for node in tree.get_nodes_in_group("planet"):
		var planet := node as Planet
		if planet == null:
			continue
		var tracker: VoxelSaveCompletionTracker = planet.save_terrain_edits()
		if tracker != null:
			_trackers.append(tracker)

	return _write_state(current_slot, state)

var _trackers: Array = []

## True once every terrain database has finished writing. Callers that quit
## after saving MUST wait for this - VoxelStreamSQLite writes asynchronously,
## and quitting first silently loses the edits.
func terrain_save_complete() -> bool:
	for t: VoxelSaveCompletionTracker in _trackers:
		if not (t.is_complete() or t.is_aborted()):
			return false
	return true

func _collect_placed(tree: SceneTree) -> Array:
	var out: Array = []
	for node in tree.get_nodes_in_group(SAVEABLE_GROUP):
		var n := node as Node3D
		if n == null or not n.has_meta(ITEM_ID_META):
			continue
		var entry := {
			"item_id": String(n.get_meta(ITEM_ID_META)),
			"transform": transform_to_array(n.global_transform),
		}
		if n.has_method("save_state"):
			entry["state"] = n.save_state()
		out.append(entry)
	return out

func _collect_ships(tree: SceneTree) -> Array:
	var out: Array = []
	for node in tree.current_scene.get_children():
		var ship := node as Ship
		# Enemy ships are spawned by ThreatDirector and are not the player's
		# property; saving them would resurrect a fight the player already won.
		if ship == null or not ship.is_player_ship:
			continue
		out.append(ship.save_state())
	return out

## Restores everything in `pending_state` into the freshly loaded world.
## Deliberately does nothing at all when the state is empty, which is what a
## new game is.
func apply_pending(tree: SceneTree) -> void:
	if pending_state.is_empty():
		return
	if pending_state.has("inventory"):
		Inventory.load_state(pending_state["inventory"])
	if pending_state.has("quests"):
		QuestManager.load_state(pending_state["quests"])
	if pending_state.has("placed"):
		_restore_placed(tree, pending_state["placed"])
		# pipe chains are derived from geometry, not saved: rebuild them once every pipe is back
		PipeSegment.relink_all.call_deferred(tree)
	if pending_state.has("ships"):
		_restore_ships(tree, pending_state["ships"])

	var player := tree.get_first_node_in_group("player")
	if player != null and player.has_method("load_state") and pending_state.has("player"):
		player.load_state(pending_state["player"])

func _restore_placed(tree: SceneTree, entries: Array) -> void:
	for e: Dictionary in entries:
		var item: Item = Inventory.get_item_def(String(e.get("item_id", "")))
		if item == null or item.building_scene == null:
			push_warning("SaveManager: cannot restore '%s' - no item or scene." % e.get("item_id", "?"))
			continue
		var instance: Node3D = item.building_scene.instantiate()
		tree.current_scene.add_child(instance)
		instance.global_transform = array_to_transform(e.get("transform", []))
		mark_placed(instance, item.id)
		if instance.has_method("load_state") and e.has("state"):
			instance.load_state(e["state"])

func _restore_ships(tree: SceneTree, entries: Array) -> void:
	for e: Dictionary in entries:
		var ship := Ship.new()
		ship.is_player_ship = true
		tree.current_scene.add_child(ship)
		ship.load_state(e)

## Tags a newly placed object so it survives a save/load round trip, and wires
## it into the grid registry. One call at every placement site, so there is a
## single place that can be got wrong rather than one per building type.
func mark_placed(instance: Node3D, item_id: String) -> void:
	instance.set_meta(ITEM_ID_META, item_id)
	if not instance.is_in_group(SAVEABLE_GROUP):
		instance.add_to_group(SAVEABLE_GROUP)

# --------------------------------------------------------------- serializers

## Transform3D as 12 floats (basis rows then origin). JSON has no vector type
## and Godot's str()/str_to_var round trip is lossy on floats, so these go
## through plain numbers.
func transform_to_array(t: Transform3D) -> Array:
	return [
		t.basis.x.x, t.basis.x.y, t.basis.x.z,
		t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z,
		t.origin.x, t.origin.y, t.origin.z,
	]

func array_to_transform(a: Variant) -> Transform3D:
	if not (a is Array) or (a as Array).size() != 12:
		return Transform3D.IDENTITY
	var v: Array = a
	return Transform3D(
		Basis(
			Vector3(v[0], v[1], v[2]),
			Vector3(v[3], v[4], v[5]),
			Vector3(v[6], v[7], v[8])),
		Vector3(v[9], v[10], v[11]))

func vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func array_to_vec3(a: Variant) -> Vector3:
	if not (a is Array) or (a as Array).size() != 3:
		return Vector3.ZERO
	var v: Array = a
	return Vector3(v[0], v[1], v[2])

func array_to_vec3i(a: Variant) -> Vector3i:
	var v := array_to_vec3(a)
	return Vector3i(roundi(v.x), roundi(v.y), roundi(v.z))
