class_name PipeSegment
extends StaticBody3D

const ITEMS_PER_SECOND := 6.0
const _CUBE_START := Vector3(0.0, 0.45, 0.45)
const _CUBE_END := Vector3(0.0, 0.45, -0.45)

var grid_pos: Vector3i
var _held_item_id: String = ""
var _progress: float = 0.0
var _item_cube_material: StandardMaterial3D

@onready var _item_cube: MeshInstance3D = $ItemCube

func _ready() -> void:
	add_to_group("pipe")
	_item_cube_material = StandardMaterial3D.new()
	_item_cube_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_item_cube.material_override = _item_cube_material
	_item_cube.visible = false

## Local -Z is this segment's forward/output direction, matching Godot's
## default "objects look along local -Z" convention (same one player.gd's own
## camera-forward raycast uses) - rotation.y is always a multiple of 90 deg
## since build placement only rotates in fixed steps, so rounding is exact.
func forward() -> Vector3i:
	var dir := -global_transform.basis.z
	return Vector3i(roundi(dir.x), 0, roundi(dir.z))

func has_ready_item() -> bool:
	return _held_item_id != "" and _progress >= 1.0

func pipe_accept(item_id: String, _from_grid_pos: Vector3i = Vector3i.ZERO) -> bool:
	if _held_item_id != "":
		return false
	_held_item_id = item_id
	_progress = 0.0
	_item_cube.position = _CUBE_START
	_item_cube.visible = true
	var item := Inventory.get_item_def(item_id)
	_item_cube_material.albedo_color = item.debug_color if item != null else Color.WHITE
	return true

func _physics_process(delta: float) -> void:
	if _held_item_id == "":
		_try_pull_from_input_side()
		return
	_progress = min(_progress + ITEMS_PER_SECOND * delta, 1.0)
	_item_cube.position = _CUBE_START.lerp(_CUBE_END, _progress)
	if _progress >= 1.0:
		_try_advance()

func _try_advance() -> void:
	var target := PipeNetwork.get_node_at(grid_pos + forward())
	if target == null:
		return
	var moved := false
	if target is PipeSegment:
		moved = target.pipe_accept(_held_item_id, grid_pos)
	elif target is Building:
		moved = target.add_input(_held_item_id, 1) > 0
	if moved:
		_held_item_id = ""
		_progress = 0.0
		_item_cube.visible = false

func _try_pull_from_input_side() -> void:
	var source := PipeNetwork.get_node_at(grid_pos - forward())
	if source == null or not (source is Building):
		return
	var building: Building = source
	for recipe in building.recipes:
		var output_id: String = recipe.output_id
		if building.get_inventory_count(output_id) > 0 and building.remove_item(output_id, 1):
			pipe_accept(output_id, grid_pos - forward())
			return
