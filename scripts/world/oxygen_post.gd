class_name OxygenPost
extends Building

## Base oxygen supply. Press E on it to plug your suit in with a hose; while you stay within HOSE_LENGTH of the
## post your suit refills (Player._update_suit_o2 reads `Player.o2_hose`). Press E again to unplug. Walk too far and
## the hose pops out. No inventory, no recipe: it only breathes for you.
## The model is built from primitives (a tank on a slab with a hose reel) so it needs no art asset.

const HOSE_LENGTH := 20.0
const HOSE_SEGMENTS := 14

var connected := false
var _hose: MeshInstance3D
var _hose_mesh := ImmediateMesh.new()
var _ring_mat: StandardMaterial3D

func _ready() -> void:
	recipes = []
	inventory_slots = 0
	modifier_slots = 0
	input_capacity = 0
	output_capacity = 0
	_build_visuals()
	super._ready()
	add_to_group("oxygen_post")

func _material(c: Color, metal: float = 0.0, rough: float = 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m

func _add_mesh(mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _build_visuals() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.9, 1.0)
	shape.shape = box
	shape.position = Vector3(0, 0.95, 0)
	add_child(shape)

	var slab := BoxMesh.new()
	slab.size = Vector3(1.0, 0.16, 1.0)
	_add_mesh(slab, Vector3(0, 0.08, 0), _material(Color(0.30, 0.32, 0.35), 0.6, 0.5))

	var tank := CylinderMesh.new()
	tank.top_radius = 0.30
	tank.bottom_radius = 0.30
	tank.height = 1.5
	_add_mesh(tank, Vector3(0, 0.91, 0), _material(Color(0.80, 0.86, 0.92), 0.5, 0.35))

	var dome := SphereMesh.new()
	dome.radius = 0.30
	dome.height = 0.6
	_add_mesh(dome, Vector3(0, 1.66, 0), _material(Color(0.80, 0.86, 0.92), 0.5, 0.35))

	# glowing bands: cyan while idle, green while someone is plugged in
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.3, 0.8, 0.95)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(0.3, 0.8, 0.95)
	_ring_mat.emission_energy_multiplier = 1.6
	for y in [0.45, 1.35]:
		var ring := CylinderMesh.new()
		ring.top_radius = 0.315
		ring.bottom_radius = 0.315
		ring.height = 0.07
		_add_mesh(ring, Vector3(0, y, 0), _ring_mat)

	# valve and the hose reel on the side
	var reel := CylinderMesh.new()
	reel.top_radius = 0.17
	reel.bottom_radius = 0.17
	reel.height = 0.22
	var reel_mi := _add_mesh(reel, Vector3(0.42, 0.9, 0), _material(Color(0.20, 0.22, 0.25), 0.7, 0.45))
	reel_mi.rotation = Vector3(0, 0, PI * 0.5)
	var valve := BoxMesh.new()
	valve.size = Vector3(0.14, 0.14, 0.14)
	_add_mesh(valve, Vector3(0, 1.97, 0), _material(Color(0.9, 0.55, 0.2), 0.3, 0.5))

	_hose = MeshInstance3D.new()
	_hose.mesh = _hose_mesh
	_hose.top_level = true
	_hose.material_override = _material(Color(0.12, 0.13, 0.15), 0.0, 0.8)
	_hose.visible = false
	add_child(_hose)

## Where the hose leaves the post, in world space.
func hose_anchor() -> Vector3:
	return to_global(Vector3(0.52, 0.9, 0))

func set_connected(v: bool) -> void:
	connected = v
	var c := Color(0.35, 0.95, 0.45) if v else Color(0.3, 0.8, 0.95)
	_ring_mat.albedo_color = c
	_ring_mat.emission = c
	_hose.visible = v
	if not v:
		_hose_mesh.clear_surfaces()

func prompt_text() -> String:
	var p := get_tree().get_first_node_in_group("player")
	return "Unplug oxygen hose" if p != null and p.get("o2_hose") == self else "Plug in oxygen hose"

func interact() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	if p.get("o2_hose") == self:
		p.call("disconnect_hose")
	else:
		p.call("connect_hose", self)

func _process(delta: float) -> void:
	if not connected:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null or p.get("o2_hose") != self:
		set_connected(false)
		return
	var up := PlanetPhysics.get_up(p.global_position)
	var a := hose_anchor()
	var b := p.global_position + up * 0.9
	var slack := clampf(1.0 - a.distance_to(b) / HOSE_LENGTH, 0.0, 1.0)
	var mid := (a + b) * 0.5 - up * (0.15 + 1.6 * slack)
	_hose_mesh.clear_surfaces()
	_hose_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in HOSE_SEGMENTS + 1:
		var t := float(i) / HOSE_SEGMENTS
		_hose_mesh.surface_add_vertex(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	_hose_mesh.surface_end()
