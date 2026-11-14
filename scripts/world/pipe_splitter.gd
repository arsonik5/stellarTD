extends PipeSegment

var _last_output_index := 0
## The distributor drive (coupling under the gear motor) turns while an item is passing through.
var _rotor_player: AnimationPlayer
var _rotor_anim := ""

func _process(_delta: float) -> void:
	if _rotor_player == null:
		var players := find_children("*", "AnimationPlayer", true, false)
		if players.is_empty():
			set_process(false)
			return
		_rotor_player = players[0]
		for anim_name in _rotor_player.get_animation_list():
			if String(anim_name).begins_with("Working"):
				_rotor_anim = anim_name
				_rotor_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	if _rotor_anim == "":
		return
	var busy := _held_item_id != ""
	if busy and not _rotor_player.is_playing():
		_rotor_player.play(_rotor_anim)
	elif not busy and _rotor_player.is_playing():
		_rotor_player.pause()

func get_connection_points() -> Array[Vector3]:
	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x
	return [
		global_position - fwd * 0.5,
		global_position + fwd * 0.5,
		global_position + right * 0.5,
		global_position - right * 0.5,
	]

## Ports in 3D: one inlet (back) and three outlets (front, left, right). get_connection_points() order is
## [back, front, right, left].
func input_ports() -> Array[Vector3]:
	return [get_connection_points()[0]]

func output_ports() -> Array[Vector3]:
	var c := get_connection_points()
	return [c[1], c[3], c[2]]

func _try_advance() -> void:
	var ports := output_ports()
	for offset in ports.size():
		var index := (_last_output_index + offset) % ports.size()
		var target := _receiver_at(ports[index], _outward(ports[index]))
		if target == null:
			continue
		var moved := false
		if target is PipeSegment:
			moved = target.pipe_accept(_held_item_id, grid_pos)
		elif target is Building:
			moved = target.add_input(_held_item_id, 1) > 0
		if moved:
			_last_output_index = (index + 1) % ports.size()
			_held_item_id = ""
			_progress = 0.0
			_item_cube.visible = false
			return
