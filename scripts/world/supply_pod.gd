class_name SupplyPod
extends Building
## Supply drop (design M29): bought with Continuance credit in the Journal, it falls from orbit along the body's
## radial down - a real fall, it can land on a slope or a roof - and opens like any storage. The credit sink.

const FALL_SPEED := 60.0
const START_ALT := 300.0
var _landing := Vector3.ZERO
var _falling := false

## Packs the Journal offers: id -> [title, credit cost, {item: count}]
const PACKS := {
	"ingots": ["Ingot crate", 60, {"refined_material": 40, "refined_copper_ingot": 20}],
	"electronics": ["Electronics crate", 140, {"circuit": 8, "copper_wire": 30}],
	"munitions": ["Munitions crate", 120, {"iron_piercing_ammo": 200, "he_shell": 20}],
	"steel": ["Steel crate", 160, {"steel_ingot": 40}],
}

func _ready() -> void:
	recipes = []
	accepts_any_item = true
	inventory_slots = 8
	inventory_capacity = 400
	max_health = 250.0
	if get_node_or_null("Model") == null:
		_build_blockout()
	super._ready()

## Buy `pack` with credit and drop it beside `near`. Returns the pod or null if unaffordable / unknown.
static func order(pack: String, near: Node3D) -> SupplyPod:
	if not PACKS.has(pack) or Progression.credit < int(PACKS[pack][1]) or near == null:
		return null
	Progression.credit -= int(PACKS[pack][1])
	Progression.changed.emit()
	var pod: SupplyPod = load("res://scenes/supply_pod.tscn").instantiate()
	near.get_tree().current_scene.add_child(pod)
	var up := PlanetPhysics.get_up(near.global_position)
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized().rotated(up, randf() * TAU)
	var target := near.global_position + side * 8.0
	var q := PhysicsRayQueryParameters3D.create(target + up * 40.0, target - up * 80.0)
	var hit := near.get_world_3d().direct_space_state.intersect_ray(q)
	pod._landing = hit.position if not hit.is_empty() else target
	pod.global_transform = Transform3D(Basis.looking_at(side, up), pod._landing + up * START_ALT)
	pod._falling = true
	var items: Dictionary = PACKS[pack][2]
	for id: String in items:
		pod.add_input(id, int(items[id]))
	SaveManager.mark_placed(pod, "supply_pod")
	GameEvents.act("supply_drop")
	return pod

func _process(delta: float) -> void:
	super._process(delta)
	if not _falling:
		return
	var to := _landing - global_position
	var step := FALL_SPEED * delta
	if to.length() <= step:
		global_position = _landing
		_falling = false
		UiSound.play("place")
	else:
		global_position += to.normalized() * step

func is_landed() -> bool:
	return not _falling

func status_text() -> String:
	return "INBOUND" if _falling else "SUPPLY DROP  ·  %d ITEMS" % get_total_count()

func idle_reason() -> String:
	return ""

func save_state() -> Dictionary:
	var d := super.save_state()
	if _falling:
		d["landing"] = SaveManager.transform_to_array(Transform3D(Basis(), _landing))
	return d

func load_state(data: Dictionary) -> void:
	super.load_state(data)
	var l: Array = data.get("landing", [])
	if l.size() == 12:
		_landing = SaveManager.array_to_transform(l).origin
		_falling = true

func _build_blockout() -> void:
	var m := Blockout.root(self)
	# drop capsule: a hardened crate in a frame, braking fins on top, a beacon light
	Blockout.box(m, Vector3(1.4, 1.2, 1.4), Vector3(0, 0.7, 0), Blockout.PAINT)
	Blockout.box(m, Vector3(1.5, 0.12, 1.5), Vector3(0, 0.06, 0), Blockout.DARK)
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		Blockout.box(m, Vector3(0.06 + absf(d.y) * 0.5, 0.5, 0.06 + absf(d.x) * 0.5), Vector3(d.x * 0.5, 1.55, d.y * 0.5), Blockout.HAZARD)
	Blockout.cyl(m, 0.08, 0.12, Vector3(0, 1.4, 0), UiTokens.ACCENT, "y", "Light", true)
