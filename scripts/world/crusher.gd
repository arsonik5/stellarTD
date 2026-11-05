class_name Crusher
extends Building
## Crusher (design M1): the stone sink. Stone in, gravel out; gravel becomes concrete in the constructor.
## Single recipe, so it runs on its own from the moment it is placed (no auto toggle to find).

const CrushStone: Recipe = preload("res://data/recipes/crush_stone.tres")

var _drum: Node3D

func _ready() -> void:
	recipes = [CrushStone]
	inventory_slots = 8
	inventory_capacity = 200
	if get_node_or_null("Model") == null:
		_build_blockout()
	power_draw = 10.0
	super._ready()
	set_auto(0, true)

func _process(delta: float) -> void:
	super._process(delta)
	if _drum != null and get_active_recipe_index() != -1:
		_drum.rotate_object_local(Vector3.RIGHT, delta * 4.0)

## Blockout (no Blender model yet). Every part has a job:
func _build_blockout() -> void:
	var m := Blockout.root(self)
	# base frame bolted to the ground plate: carries the crushing housing and the motor
	Blockout.box(m, Vector3(1.9, 0.2, 1.6), Vector3(0, 0.1, 0), Blockout.DARK)
	# crushing housing: the drum turns inside it
	Blockout.box(m, Vector3(1.2, 0.9, 1.2), Vector3(-0.15, 0.65, 0), Blockout.PAINT)
	Blockout.bolts(m, Vector3(-0.15, 1.1, 0), 0.5)
	# hopper on top of the housing: stone is dropped in here
	Blockout.box(m, Vector3(1.0, 0.5, 1.0), Vector3(-0.15, 1.35, 0), Blockout.STEEL)
	# drum axle sticks out of the housing side; the drum turns on it (hazard: moving)
	_drum = Node3D.new()
	_drum.name = "Drum"
	_drum.position = Vector3(-0.15, 0.65, 0.65)
	m.add_child(_drum)
	Blockout.cyl(_drum, 0.28, 0.1, Vector3.ZERO, Blockout.HAZARD, "z")
	# motor on its own pad, belt guard to the drum axle
	Blockout.cyl(m, 0.22, 0.55, Vector3(-0.15, 0.42, -0.75), Blockout.DARK, "z")
	Blockout.box(m, Vector3(0.12, 0.6, 0.12), Vector3(-0.15, 0.55, 0.72), Blockout.STEEL)
	# gravel chute from the housing bottom to the output port on the +X edge
	Blockout.box(m, Vector3(0.55, 0.3, 0.5), Vector3(0.62, 0.45, 0), Blockout.STEEL)
	Blockout.port(m, 0.45)
