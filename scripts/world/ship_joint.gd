class_name ShipJoint
extends ShipBlock
## Moving joints (design/02-core-mechanics.md C5, roadmap G5): the first step of the Scrap Mechanic layer.
## A joint part on a ship spawns a SUB-GRID - a second Ship body - on its head face, joined to the parent by a
## real Jolt constraint with a motor. You build onto the sub-grid like any ship; the pilot drives every joint on
## the ship with Z / C (and joints on sub-grids of sub-grids too). The parent saves the whole tree.
##
##   bearing - spins freely around the part's local +Y, motor-driven, no limits (turntables, wheels, rotors)
##   hinge   - rotates around local X, limited to +-90 degrees (doors, arms, landing legs, ramps)
##   piston  - slides along local +Y, 0 .. PISTON_STROKE metres (lifts, presses, extending booms)
##
## The joint head (a "rotor_head" plate) is the sub-grid's root block at cell 0; Ship treats a sub-grid's cell 0
## as its core, so the usual connectivity rules hold on the moving part too.

@export_enum("bearing", "hinge", "piston") var joint_type := "bearing"
const MAX_SPEED := 1.5            # rad/s (bearing, hinge) or m/s (piston) at full input
const MAX_IMPULSE := 4000.0
const HINGE_LIMIT := PI / 2.0
const PISTON_STROKE := 1.5
const HEAD_ID := "rotor_head"

var child: Ship
var joint: Joint3D
## -1..1 from the pilot (Z / C); 0 = hold position.
var input := 0.0

func _ready() -> void:
	super._ready()
	if get_node_or_null("Model") == null:
		_build_blockout()

## Called by Ship.add_block once this part is registered. Spawns a fresh sub-grid unless the ship is loading
## (then Ship.load_state restores the saved one through restore_child).
func on_added(ship: Ship) -> void:
	if ship.loading:
		return
	create_child.call_deferred({})

## World transform of the head face where the sub-grid's root sits.
func head_transform() -> Transform3D:
	var t := global_transform
	var up := t.basis.y.normalized()
	return Transform3D(t.basis.orthonormalized(), t.origin + up * (float(size_cells.y) * Ship.CELL_SIZE * 0.5 + Ship.CELL_SIZE * 0.5))

## Build (or restore from `state`) the sub-grid and the constraint.
func create_child(state: Dictionary) -> Ship:
	var ship := get_parent() as Ship
	if ship == null or not is_inside_tree():
		return null
	child = Ship.new()
	child.is_player_ship = ship.is_player_ship
	child.is_subgrid = true
	child.joint_parent = ship
	child.loading = not state.is_empty()
	ship.get_parent().add_child(child)
	if state.is_empty():
		child.global_transform = head_transform()
		var head_item := Inventory.get_item_def(HEAD_ID)
		var head: ShipBlock = head_item.block_scene.instantiate()
		child.try_add_block(Vector3i(-1, 0, -1), head)
	else:
		child.load_state(state)
	child.loading = false
	_make_joint(ship)
	return child

func _make_joint(ship: Ship) -> void:
	if joint != null and is_instance_valid(joint):
		joint.queue_free()
	var head := head_transform()
	match joint_type:
		"piston":
			var g := Generic6DOFJoint3D.new()
			# the slide axis is the part's +Y; 6DOF's linear axes are its own X/Y/Z, so align its basis to ours
			g.transform = Transform3D(head.basis, global_position)
			for ax in ["x", "y", "z"]:
				g.set("angular_limit_%s/enabled" % ax, true)
				g.set("angular_limit_%s/upper_angle" % ax, 0.0)
				g.set("angular_limit_%s/lower_angle" % ax, 0.0)
			for ax in ["x", "z"]:
				g.set("linear_limit_%s/enabled" % ax, true)
				g.set("linear_limit_%s/upper_distance" % ax, 0.0)
				g.set("linear_limit_%s/lower_distance" % ax, 0.0)
			g.set("linear_limit_y/enabled", true)
			g.set("linear_limit_y/lower_distance", 0.0)
			g.set("linear_limit_y/upper_distance", PISTON_STROKE)
			g.set("linear_motor_y/enabled", true)
			g.set("linear_motor_y/force_limit", MAX_IMPULSE * 20.0)
			g.set("linear_motor_y/target_velocity", 0.0)
			joint = g
		_:
			var h := HingeJoint3D.new()
			# HingeJoint3D turns around its own Z: point Z along the bearing's +Y or the hinge's +X
			var axis := head.basis.y if joint_type == "bearing" else head.basis.x
			var z := axis.normalized()
			var x := (head.basis.z if joint_type == "bearing" else head.basis.y).normalized()
			h.transform = Transform3D(Basis(x, z.cross(x), z).orthonormalized(), head.origin - head.basis.y * Ship.CELL_SIZE * 0.5)
			h.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
			h.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
			h.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, MAX_IMPULSE)
			if joint_type == "hinge":
				h.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
				h.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -HINGE_LIMIT)
				h.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, HINGE_LIMIT)
			joint = h
	joint.name = "Joint_%s" % joint_type
	joint.exclude_nodes_from_collision = true
	ship.get_parent().add_child(joint)
	joint.node_a = joint.get_path_to(ship)
	joint.node_b = joint.get_path_to(child)

func _physics_process(_delta: float) -> void:
	if joint == null or not is_instance_valid(joint):
		return
	var v := clampf(input, -1.0, 1.0) * MAX_SPEED
	if joint is HingeJoint3D:
		# Jolt's hinge motor turns node_b relative to node_a; sign chosen so C (+1) turns counter-clockwise
		# looking down the axis
		(joint as HingeJoint3D).set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, -v)
	else:
		joint.set("linear_motor_y/target_velocity", v)

## Current angle (bearing/hinge, radians) or extension (piston, metres) of the sub-grid relative to the part.
func position_value() -> float:
	if child == null or not is_instance_valid(child):
		return 0.0
	var rel := global_transform.affine_inverse() * child.global_transform
	if joint_type == "piston":
		var base := global_transform.affine_inverse() * head_transform()
		return (rel.origin - base.origin).dot(Vector3.UP)
	var axis := Vector3.UP if joint_type == "bearing" else Vector3.RIGHT
	var ref := Vector3.FORWARD if joint_type == "bearing" else Vector3.UP
	var v := rel.basis * ref
	v -= axis * v.dot(axis)
	return ref.signed_angle_to(v.normalized(), axis)

## The joint part is leaving its ship: the sub-grid becomes free-floating debris (it keeps its blocks).
func _exit_tree() -> void:
	if joint != null and is_instance_valid(joint):
		joint.queue_free()
	if child != null and is_instance_valid(child):
		child.joint_parent = null

func _build_blockout() -> void:
	var m := Blockout.root(self)
	var s := Vector3(size_cells) * Ship.CELL_SIZE
	# housing bolted to the parent grid face
	Blockout.box(m, Vector3(s.x * 0.95, s.y * 0.5, s.z * 0.95), Vector3(0, -s.y * 0.25, 0), Blockout.STEEL)
	match joint_type:
		"bearing":
			Blockout.cyl(m, s.x * 0.4, s.y * 0.45, Vector3(0, s.y * 0.22, 0), Blockout.HAZARD)   # the turning race
		"hinge":
			Blockout.cyl(m, s.y * 0.2, s.x * 0.95, Vector3(0, s.y * 0.15, 0), Blockout.HAZARD, "x")  # hinge pin
		"piston":
			Blockout.cyl(m, s.x * 0.25, s.y * 0.5, Vector3(0, s.y * 0.25, 0), Blockout.HAZARD)   # the ram
