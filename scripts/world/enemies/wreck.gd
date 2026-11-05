class_name Wreck
extends Building
## What a downed raider leaves (design M24): a hull on the ground holding alien alloy. Open it (E) and take the
## alloy like any machine's storage; the first look at each wreck yields xeno research data. Saved like any placed
## object, so a battlefield stays a battlefield. Not buildable; it never draws power or takes pipe input.

var source_kind := "raider"
var salvaged := false

func _ready() -> void:
	recipes = []
	inventory_slots = 6
	inventory_capacity = 200
	max_health = 2000.0
	marker_height = 2.0
	if get_node_or_null("Model") == null:
		_build_blockout()
	super._ready()

func can_accept_input(_id: String, _n: int) -> bool:
	return false

func output_ids() -> Array:
	return []

func idle_reason() -> String:
	return ""

func status_text() -> String:
	return "WRECK  ·  " + source_kind.to_upper() + ("" if get_total_count() > 0 else "  ·  STRIPPED")

func interact() -> void:
	if not salvaged:
		salvaged = true
		Progression.award("xeno", 2, "salvaged " + source_kind)
		GameEvents.act("salvage_wreck")
	super.interact()

func build_ui_extras(box: VBoxContainer, _refresh: Callable) -> void:
	box.add_child(UiKit.label("Alien hull. Take the alloy - the Continuance's labs will want every gram.", "DimLabel"))

func save_state() -> Dictionary:
	var d := super.save_state()
	d["wreck"] = {"kind": source_kind, "salvaged": salvaged}
	return d

func load_state(data: Dictionary) -> void:
	super.load_state(data)
	var w: Dictionary = data.get("wreck", {})
	source_kind = String(w.get("kind", "raider"))
	salvaged = bool(w.get("salvaged", false))

## Drop a wreck on the ground under `pos` (radial raycast), holding `alloy` alien alloy.
static func spawn_at(scene: Node, pos: Vector3, alloy: int, kind: String) -> Wreck:
	var w: Wreck = load("res://scenes/wreck.tscn").instantiate()
	scene.add_child(w)
	var up := PlanetPhysics.get_up(pos)
	var ground := pos
	var space := (scene as Node3D).get_world_3d().direct_space_state if scene is Node3D else w.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + up * 2.0, pos - up * 300.0)
	q.exclude = [w.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		ground = hit.position
	var fwd := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	w.global_transform = Transform3D(Basis.looking_at(fwd, up), ground)
	w.source_kind = kind
	w.add_output("alien_alloy", alloy)
	SaveManager.mark_placed(w, "wreck")
	return w

func can_add_output(item_id: String, amount: int) -> bool:
	return item_id == "alien_alloy" and get_total_count() + amount <= inventory_capacity

func _build_blockout() -> void:
	var m := Blockout.root(self)
	# broken hull half-buried, tilted: torn plates and a dead glow strip
	var hull := EnemyFlyer.part(m, EnemyFlyer.box_mesh(Vector3(2.6, 0.7, 3.4)), Vector3(0, 0.25, 0), false, Vector3(0.18, 0.4, 0.12))
	hull.name = "Hull"
	EnemyFlyer.part(m, EnemyFlyer.box_mesh(Vector3(0.9, 0.15, 1.6)), Vector3(1.3, 0.55, -0.4), false, Vector3(0.9, 0.2, 0.4))
	EnemyFlyer.part(m, EnemyFlyer.box_mesh(Vector3(0.12, 0.08, 2.4)), Vector3(-0.6, 0.62, 0), true, Vector3(0.18, 0.4, 0.12))
