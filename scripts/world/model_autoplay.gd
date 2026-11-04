extends Node3D
## Put on an instanced building model (.glb) whose machinery always runs (ship core rings, gyroscope gimbal,
## garage cranes): starts the model's "Working" animation looping. Machines that only run while crafting are
## driven by Building instead (see building.gd _update_work_anim).

func _ready() -> void:
	for player: AnimationPlayer in find_children("*", "AnimationPlayer", true, false):
		for anim_name in player.get_animation_list():
			if String(anim_name).begins_with("Working"):
				player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
				player.play(anim_name)
				return
