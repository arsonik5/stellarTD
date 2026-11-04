extends Node

## Dev tool: boots the world, waits for real ground, parks the sun at a fixed
## raking angle, then captures a fixed set of framings.
##
##     godot --path . res://scenes/dev/terrain_look.tscn -- --tag=<name>
##     godot --path . res://scenes/dev/terrain_look.tscn -- --tag=<name> --terrain-log
##
## Writes user://look_<tag>_<framing>.png. Tag every run, then compare tags -
## that is the whole point: terrain and material changes can only be judged
## against a previous capture of the SAME framing under the SAME light.
##
## Not a test - it asserts nothing. It exists because judging a look change from
## memory does not work, and because two of this session's wrong conclusions came
## from comparing captures that differed in camera placement or sun angle as well
## as in the thing being tested.
##
## Framings are FIXED on purpose. Judging a material or a landform change from
## differently-placed cameras compares two things at once, and the camera
## usually wins.

var _world: Node
var _planet: Planet
var _player: Node3D
var _cam: Camera3D
var _t := 0.0
var _settle := 0.0
var _stage := 0
var _frame_samples: Array[float] = []
var _tag := "x"

# alt = metres above the player's own surface height; pitch in radians.
var _shots := [
	{"name": "eye", "alt": 1.7, "pitch": -0.06, "fov": 70.0},
	{"name": "raking", "alt": 4.0, "pitch": -0.20, "fov": 55.0},
	{"name": "closeup", "alt": 1.0, "pitch": -0.70, "fov": 60.0},
	{"name": "ridge", "alt": 120.0, "pitch": -0.35, "fov": 65.0},
	{"name": "air1km", "alt": 1000.0, "pitch": -0.55, "fov": 70.0},
	{"name": "orbit12km", "alt": 12000.0, "pitch": -0.95, "fov": 60.0},
	# The NIGHT limb. Every other framing looks at lit ground, because the sun is
	# parked relative to the camera - which means none of them can see an
	# artifact that only appears where the atmosphere is unlit. A dither-speckle
	# problem on the dark side went unmeasured through two capture rounds for
	# exactly that reason: the numbers came back unchanged because the region
	# being measured was the wrong one.
	{"name": "nightlimb", "alt": 9000.0, "pitch": -0.62, "fov": 65.0, "night": true},
	# High night view, roughly where a ship sits. The 9 km framing above did not
	# reproduce a reported "atmosphere disappears" - span/shell ratios differ a
	# lot with altitude, so the sample-count behaviour has to be checked from
	# further out too.
	{"name": "nightorbit", "alt": 55000.0, "pitch": -0.30, "fov": 60.0, "night": true},
]

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			_tag = a.substr(6)
	_world = preload("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await get_tree().process_frame
	_world.get_node("LoadingScreen").queue_free()
	_planet = _world.get_node("HomePlanet")
	_player = _world.get_node("Player")

func _process(delta: float) -> void:
	_t += delta
	if _player == null:
		return
	if not _player.is_spawn_resolved():
		if _t > 180.0:
			print("RESULT: FAIL - no walkable ground after 180 s")
			get_tree().quit()
		return
	if _cam == null:
		_park_sun()
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--debug-view="):
				var mode := int(a.substr(13))
				var t := _planet.terrain as VoxelLodTerrain
				if t != null and t.material is ShaderMaterial:
					var sm := t.material as ShaderMaterial
					sm.set_shader_parameter("debug_view", mode)
					print("debug_view = ", mode,
						"  readback=", sm.get_shader_parameter("debug_view"),
						"  mat=", sm.get_instance_id(),
						"  shader=", sm.shader.resource_path if sm.shader != null else "<none>",
						"  mesher_mat=", t.mesher.get("material") if t.mesher != null else "<no mesher>")
			if a == "--no-rock":
				# A/B: is the wavy pattern on flat ground the rock band, or the
				# erosion map's own channels? They look alike and guessing has
				# been wrong before.
				_planet.profile.rock_amplitude = 0.0
				_planet.terrain.generator = _planet._make_generator()
				print("rock band disabled")
			if a == "--no-shadow":
				var sun := _world.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
				if sun != null:
					sun.shadow_enabled = false
					print("shadows disabled")
			if a == "--no-atmo":
				_world.get_node("AtmosphereRenderer").enabled = false
				print("atmosphere disabled")
		_cam = Camera3D.new()
		_cam.far = 300000.0
		_cam.near = 0.05
		add_child(_cam)
		_cam.make_current()
		print("playable at %.1f s, landed r=%.1f" % [
			_t, _player.global_position.distance_to(_planet.global_position)])
		_print_spawn_evidence()
		_place()
		return
	_settle += delta
	# Long settle: LOD keeps streaming after the player can walk, and a shot
	# taken early shows holes that are not really there.
	# 10 s, not 3. Distant LOD levels are still meshing well after the player can
	# walk, and a short settle captures half-streamed geometry as scattered holes
	# along every far ridge - which looks exactly like a shading artifact and
	# cost several wrong diagnoses before a no-atmosphere capture showed the
	# speckle was SPACE visible through the mesh.
	# Frame times are sampled over the back half of the settle window, once
	# streaming has quietened. Measuring while blocks are still meshing reports
	# the loader, not the renderer.
	if _settle > 6.0:
		_frame_samples.append(delta)
	if _settle < 10.0:
		return
	if not _frame_samples.is_empty():
		var total := 0.0
		var worst := 0.0
		for d: float in _frame_samples:
			total += d
			worst = maxf(worst, d)
		var avg: float = total / float(_frame_samples.size())
		print("  fps %s: avg %.1f (%.2f ms)  worst %.1f (%.2f ms)  n=%d" % [
			_shots[_stage]["name"], 1.0 / maxf(avg, 0.0001), avg * 1000.0,
			1.0 / maxf(worst, 0.0001), worst * 1000.0, _frame_samples.size()])
		_frame_samples.clear()
	get_viewport().get_texture().get_image().save_png(
		"user://look_%s_%s.png" % [_tag, _shots[_stage]["name"]])
	print("shot ", _shots[_stage]["name"])
	_stage += 1
	# Re-park per shot: the night framing needs the sun BELOW the horizon, and
	# parking once at setup would light every shot the same way.
	if _stage < _shots.size():
		_park_sun()
	if _stage >= _shots.size():
		get_tree().quit()
		return
	_settle = 0.0
	_place()

## Moves the STAR so the sun sits at a fixed low elevation over the player.
##
## Without this every capture has a different, arbitrary sun angle - one run
## looked at ground in full shadow and read as "the material does nothing".
## Relief only reads under raking light, which is exactly the condition the
## reference photography is shot in, so the light has to be controlled or the
## captures are not comparable to each other OR to the references.
##
## Moving the star rather than the player: Star.gd re-aims the DirectionalLight
## from the star's real position every frame, and the player is also the
## VoxelViewer, so relocating them would move which terrain is streamed.
func _park_sun() -> void:
	var star := _world.get_node_or_null("Star") as Node3D
	if star == null:
		return
	var up := (_player.global_position - _planet.global_position).normalized()
	var east := up.cross(Vector3.UP).normalized()
	if east.length_squared() < 0.1:
		east = up.cross(Vector3.RIGHT).normalized()
	# 18 degrees above the local horizon, off to one side of the view direction
	# so slopes facing the camera are lit across rather than flat-on.
	# Below the horizon for a night shot, so the camera looks across a limb the
	# sun is behind.
	var elevation := deg_to_rad(-22.0 if _shots[_stage].get("night", false) else 18.0)
	var sun_dir := (up * sin(elevation) + east.rotated(up, -0.9) * cos(elevation)).normalized()
	var dist: float = star.global_position.distance_to(_planet.global_position)
	star.global_position = _player.global_position + sun_dir * dist
	print("sun parked at %.0f deg elevation" % rad_to_deg(elevation))

func _place() -> void:
	var shot: Dictionary = _shots[_stage]
	var up := (_player.global_position - _planet.global_position).normalized()
	var r: float = _player.global_position.distance_to(_planet.global_position)
	var pos: Vector3 = _planet.global_position + up * (r + float(shot["alt"]))
	var east := up.cross(Vector3.UP).normalized()
	if east.length_squared() < 0.1:
		east = up.cross(Vector3.RIGHT).normalized()
	_cam.fov = float(shot["fov"])
	_cam.global_position = pos
	_cam.look_at(pos + east.rotated(up, 0.6).normalized(), up)
	_cam.rotate_object_local(Vector3.RIGHT, float(shot["pitch"]))

## What the player is actually standing on at the moment the harness declares
## the world playable.
##
## Exists because "playable" once fired at 0.5 s on a world that takes 11 s to
## stream, and the first capture then showed boulders floating over no terrain.
## A spawn gate that passes early makes every frame after it untrustworthy, and
## the spawn code has several paths to "resolved" - this says which one fired and
## what the ground under the player really is, instead of guessing.
func _print_spawn_evidence() -> void:
	var up := (_player.global_position - _planet.global_position).normalized()
	var q := PhysicsRayQueryParameters3D.create(
		_player.global_position + up * 2.0, _player.global_position - up * 50.0)
	q.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(q)
	var what := "nothing"
	if not hit.is_empty():
		var col: Object = hit.get("collider")
		what = "%s (%s)" % [col.get_class() if col != null else "?",
			(col as Node).name if col is Node else "-"]
	var t := _planet.terrain as VoxelLodTerrain
	print("spawn evidence: wait_frames=%s from_save=%s ground_hit=%s data_blocks=%d" % [
		str(_player.get("_spawn_wait_frames")), str(_player.get("_spawn_from_save")),
		what, t.debug_get_data_block_count() if t != null else -1])
