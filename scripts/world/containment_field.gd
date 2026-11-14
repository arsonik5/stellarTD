class_name ContainmentField
extends Building
## Containment field (design M22, Scope 5): a powered damper that hides DAMPING signature while it runs - the
## "mine crystal but stay quiet" path. Needs power (it does nothing unplugged) and draws a lot of it, so a quiet
## crystal base needs a real grid behind it.

const DAMPING := 15.0

var _ring: MeshInstance3D

func _ready() -> void:
	recipes = []
	inventory_slots = 0
	inventory_capacity = 0
	modifier_slots = 0
	max_health = 400.0
	power_draw = 60.0
	needs_power = true
	marker_height = 3.4
	add_to_group("signature_damper")
	if get_node_or_null("Model") == null:
		_build_blockout()
	super._ready()

func can_accept_input(_id: String, _n: int) -> bool:
	return false

func damping() -> float:
	return DAMPING * clampf(work_speed, 0.0, 1.0)

func wants_power() -> bool:
	return true

func idle_reason() -> String:
	return "No power" if work_speed <= 0.0 else ""

func status_text() -> String:
	return "NO POWER  ·  NOT DAMPING" if work_speed <= 0.0 else "DAMPING  -%.0f SIGNATURE" % damping()

func get_active_recipe_index() -> int:
	return 0 if work_speed > 0.0 else -1

func _process(delta: float) -> void:
	super._process(delta)
	if _ring != null:
		_ring.visible = work_speed > 0.0
		_ring.rotate_object_local(Vector3.UP, delta * 0.8)

func build_ui_extras(box: VBoxContainer, _refresh: Callable) -> void:
	box.add_child(UiKit.label("Hides %d signature from the sky while powered. Draws %d kW." % [int(DAMPING), int(power_draw)], "DimLabel"))
	PowerUi.grid_section(box, self)

func _build_blockout() -> void:
	var m := Blockout.root(self)
	# base plinth with the field coil standing on it
	Blockout.box(m, Vector3(1.6, 0.3, 1.6), Vector3(0, 0.15, 0), Blockout.PAINT)
	Blockout.cyl(m, 0.25, 2.4, Vector3(0, 1.5, 0), Blockout.STEEL)                     # coil mast
	for h in [0.9, 1.5, 2.1]:
		Blockout.cyl(m, 0.42, 0.12, Vector3(0, h, 0), Color(0.75, 0.5, 0.25))           # copper windings
	# the field itself: a faint mint ring that only shows while powered
	var ring := TorusMesh.new()
	ring.inner_radius = 1.6
	ring.outer_radius = 1.7
	_ring = MeshInstance3D.new()
	_ring.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.95, 0.85, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = mat
	_ring.position = Vector3(0, 2.7, 0)
	m.add_child(_ring)
