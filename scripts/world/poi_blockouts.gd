class_name PoiBlockouts
extends RefCounted
## Blockout scenes for points of interest, built in code until Blender models exist (BLOCKOUT stage of the model
## workflow). Michael's rule holds even here: every part has a job and is mounted to something - the comment on
## each piece says what it does and what it is fastened to. Each returns a Node3D whose origin is the point that
## sits on the ground and whose +Y is local up.
##
##   probe         Continuance survey probe: landed on three legs, mast with a dish pointed at the sky, a beacon
##                 light that blinks (it is still transmitting - that is why you can find it).
##   crash_site    A cargo pod that came down hard: half-buried, tilted, scorched ground, torn panels scattered
##                 downrange of the impact.
##   crystal_spire A cluster of radioactive crystal prisms pushed up through the crust, glowing faintly.

const STEEL := Color(0.45, 0.47, 0.5)
const DARK := Color(0.16, 0.17, 0.18)
const PAINT := Color(0.78, 0.74, 0.62)         # Continuance survey livery: faded sand
const SCORCH := Color(0.07, 0.065, 0.06)
const CRYSTAL := Color(0.42, 0.95, 0.82)

static func build(poi_type: String) -> Node3D:
	match poi_type:
		"probe":
			return _probe()
		"crash_site":
			return _crash_site()
		"crystal_spire":
			return _crystal_spire()
	var n := Node3D.new()
	n.name = "POI_" + poi_type
	return n

static func _mat(c: Color, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.75
	m.metallic = 0.25
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = Color(c.r, c.g, c.b)
		m.emission_energy_multiplier = emission
	return m

static func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

static func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, c: Color,
		rot := Vector3.ZERO, emission := 0.0, sides := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = sides
	mi.mesh = cm
	mi.material_override = _mat(c, emission)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

## A static collider so the player stands on / bumps into the POI instead of walking through it.
static func _collider(parent: Node3D, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	body.rotation = rot
	parent.add_child(body)

static func _probe() -> Node3D:
	var root := Node3D.new()
	root.name = "POI_Probe"
	# Body: the instrument bus, carried on the three landing legs.
	_box(root, Vector3(1.4, 0.9, 1.4), Vector3(0, 1.45, 0), PAINT)
	_collider(root, Vector3(1.6, 2.0, 1.6), Vector3(0, 1.0, 0))
	for k in 3:
		var a := TAU * float(k) / 3.0
		var out := Vector3(cos(a), 0, sin(a))
		# Leg strut from the bus's lower corner down to the foot pad (the load path to the ground).
		var top := out * 0.55 + Vector3(0, 1.05, 0)
		var foot := out * 1.45 + Vector3(0, 0.08, 0)
		var mid := (top + foot) * 0.5
		var leg := _cyl(root, 0.06, 0.06, top.distance_to(foot), mid, STEEL)
		leg.look_at_from_position(mid, foot, Vector3.UP)
		leg.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		# Foot pad: spreads the load on loose regolith.
		_cyl(root, 0.28, 0.32, 0.08, foot - Vector3(0, 0.04, 0), DARK)
	# Mast bolted to the bus top, carrying the dish and the beacon.
	_cyl(root, 0.05, 0.07, 1.8, Vector3(0, 2.8, 0), STEEL)
	# Dish: the reason the probe exists - it talks to the Continuance relay. Tilted at the sky.
	_cyl(root, 0.75, 0.12, 0.25, Vector3(0.25, 3.6, 0), Color(0.85, 0.84, 0.8), Vector3(0, 0, -0.6), 0.0, 20)
	# Solar panel on a hinge arm off the bus side: powers the transmitter.
	_box(root, Vector3(1.6, 0.04, 0.9), Vector3(-1.45, 1.85, 0), Color(0.12, 0.16, 0.28), Vector3(0, 0, 0.25))
	_cyl(root, 0.03, 0.03, 0.6, Vector3(-0.85, 1.75, 0), STEEL, Vector3(0, 0, PI / 2.0))
	# Beacon light at the mast top: still transmitting, which is why the scanner and your eyes find it.
	var beacon := _cyl(root, 0.09, 0.09, 0.14, Vector3(0, 3.78, 0), Color(1.0, 0.55, 0.15), Vector3.ZERO, 6.0, 8)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.omni_range = 9.0
	light.light_energy = 1.2
	light.position = Vector3(0, 3.85, 0)
	root.add_child(light)
	var blink := Timer.new()
	blink.wait_time = 1.2
	blink.autostart = true
	root.add_child(blink)
	blink.timeout.connect(func() -> void:
		light.visible = not light.visible
		beacon.visible = light.visible)
	return root

static func _crash_site() -> Node3D:
	var root := Node3D.new()
	root.name = "POI_CrashSite"
	# Scorched ground disc where the pod hit (decal-like: a thin dark slab just under the surface).
	_cyl(root, 7.5, 7.5, 0.06, Vector3(0, 0.02, 0), SCORCH, Vector3.ZERO, 0.0, 24)
	# The cargo pod itself, nose-down and tilted, half in the ground.
	var pod := Node3D.new()
	pod.position = Vector3(0, 0.6, 0)
	pod.rotation = Vector3(0.55, 0.3, 0.18)
	root.add_child(pod)
	_cyl(pod, 1.3, 1.5, 4.8, Vector3.ZERO, PAINT, Vector3.ZERO, 0.0, 16)       # pressure hull
	_cyl(pod, 1.55, 1.55, 0.25, Vector3(0, 2.2, 0), STEEL, Vector3.ZERO, 0.0, 16) # docking collar at the top
	_cyl(pod, 0.5, 0.75, 0.6, Vector3(0, 2.65, 0), DARK)                        # spent retro motor bell
	_box(pod, Vector3(1.0, 1.4, 0.1), Vector3(0, 0.4, 1.38), DARK)             # cargo hatch, blown open
	_collider(root, Vector3(3.0, 4.5, 3.0), Vector3(0, 0.6, 0), Vector3(0.55, 0.3, 0.18))
	# Torn panels thrown downrange (+Z), each lying flat or wedged into the ground.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for k in 7:
		var d := 3.5 + rng.randf() * 9.0
		var side := rng.randf_range(-3.0, 3.0)
		_box(root, Vector3(rng.randf_range(0.6, 1.5), 0.06, rng.randf_range(0.5, 1.2)),
			Vector3(side, 0.05 + rng.randf() * 0.2, d), STEEL if k % 2 == 0 else PAINT,
			Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
	return root

static func _crystal_spire() -> Node3D:
	var root := Node3D.new()
	root.name = "POI_CrystalSpire"
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	# Prisms grow from one buried node, splaying outward - the way a crystal druse pushes up through rock.
	for k in 9:
		var h := rng.randf_range(2.5, 9.0) * (1.6 if k == 0 else 1.0)
		var r := rng.randf_range(0.35, 0.8) * (1.4 if k == 0 else 1.0)
		var tilt := Vector3(rng.randf_range(-0.45, 0.45), 0, rng.randf_range(-0.45, 0.45)) * (0.2 if k == 0 else 1.0)
		var base := Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5)) * (0.0 if k == 0 else 1.0)
		var b := Basis.from_euler(tilt)
		_cyl(root, r * 0.15, r, h, base + b.y * (h * 0.5 - 0.6), CRYSTAL, tilt, 1.4, 6)
	_collider(root, Vector3(3.5, 12.0, 3.5), Vector3(0, 5.5, 0))
	var glow := OmniLight3D.new()
	glow.light_color = CRYSTAL
	glow.omni_range = 14.0
	glow.light_energy = 1.5
	glow.position = Vector3(0, 3.0, 0)
	root.add_child(glow)
	# Ground stain around the base: crystal-bearing ground reads from the air (deposit surface expression).
	_cyl(root, 5.5, 5.5, 0.05, Vector3(0, 0.02, 0), Color(0.22, 0.42, 0.38), Vector3.ZERO, 0.4, 20)
	return root
