class_name SolarPanel
extends Building
## Solar panel: RATED_KW at the home planet's distance with the star overhead. Output follows the star's angle
## above THIS panel's horizon (radial up - no world-Y), so it fades at dusk and is zero at night, and scales with
## irradiance, so panels are weaker on bodies further from the star.

const RATED_KW := 12.0

var _irr_ref := -1.0

func _ready() -> void:
	recipes = []
	inventory_slots = 0
	inventory_capacity = 0
	modifier_slots = 0
	max_health = 150.0
	if get_node_or_null("Model") == null:
		_build_blockout()
	super._ready()

func can_accept_input(_id: String, _n: int) -> bool:
	return false

## 0..1+ : sun elevation factor x irradiance relative to the home body.
func sun_factor() -> float:
	var star := get_tree().get_first_node_in_group("star") as Node3D
	if star == null or not star.has_method("irradiance_at"):
		return 0.0
	var up := PlanetPhysics.get_up(global_position)
	var to_star := (star.global_position - global_position).normalized()
	var elevation := up.dot(to_star)
	if elevation <= 0.0:
		return 0.0
	if _irr_ref < 0.0:
		# reference = irradiance at the centre of whatever body we stand on: same panel, same star, 1.0 there
		var body := PlanetPhysics.get_nearest_body(global_position) as Node3D
		_irr_ref = float(star.irradiance_at(body.global_position)) if body != null else float(star.irradiance_at(global_position))
	var irr := float(star.irradiance_at(global_position)) / maxf(_irr_ref, 1e-9)
	return elevation * clampf(irr, 0.0, 2.0)

func power_available() -> float:
	return RATED_KW * sun_factor()

func power_drawn(_kw: float, _dt: float) -> void:
	pass

func idle_reason() -> String:
	return "" if sun_factor() > 0.0 else "Night - no sun"

func status_text() -> String:
	var f := sun_factor()
	return "NIGHT" if f <= 0.0 else "%.1f kW  ·  SUN %d%%" % [RATED_KW * f, roundi(f * 100.0)]

func build_ui_extras(box: VBoxContainer, _refresh: Callable) -> void:
	PowerUi.grid_section(box, self)

func _build_blockout() -> void:
	var m := Blockout.root(self)
	# ground frame: four feet bolted down, holding the panel table
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		Blockout.box(m, Vector3(0.1, 0.9, 0.1), Vector3(d.x * 0.8, 0.45, d.y * 0.8), Blockout.STEEL)
	# panel: dark cells facing up
	Blockout.box(m, Vector3(1.9, 0.06, 1.9), Vector3(0, 0.93, 0), Color(0.08, 0.12, 0.22))
	# junction box under the panel where the cells' wiring meets the pole's wire
	Blockout.box(m, Vector3(0.3, 0.2, 0.3), Vector3(0.6, 0.78, 0), Blockout.DARK)
