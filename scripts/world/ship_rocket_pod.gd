class_name ShipRocketPod
extends ShipWeapon

## A rocket pod: 160 unguided 70 mm rockets in a 16 x 10 honeycomb of tubes. Fires one tube per shot, in an order
## that walks around the face so a ripple doesn't pull the ship to one side. Rockets: Rocket (rocket.gd).

const COLS := 16
const ROWS := 10
const PITCH := 0.08                 # tube spacing (m), = parts_lib.RP_PITCH
const FACE_Z := -1.04               # tube mouths, block-local (pod is 1.5 x 1.0 x 2.5 m)
const ROW_Y := -0.04                # tube bank centre height, = parts_lib.RP_ZC

var _order: Array[int] = []

func _ready() -> void:
	super._ready()
	# interleaved order: alternate left/right half and top/bottom half every shot
	var quads: Array = [[], [], [], []]
	for r in ROWS:
		for c in COLS:
			var q := (1 if c >= COLS / 2 else 0) + (2 if r >= ROWS / 2 else 0)
			quads[q].append(r * COLS + c)
	for i in quads[0].size():
		for q in [0, 3, 1, 2]:
			if i < quads[q].size():
				_order.append(quads[q][i])

func _tube_local(index: int) -> Vector3:
	var r := index / COLS
	var c := index % COLS
	return Vector3((c - (COLS - 1) * 0.5) * PITCH, ROW_Y + (r - (ROWS - 1) * 0.5) * PITCH, FACE_Z)

func muzzle_transform() -> Transform3D:
	var used := ammo_max - ammo
	var idx: int = _order[clampi(used, 0, _order.size() - 1)]
	return global_transform * Transform3D(Basis(), _tube_local(idx))

func _shoot(ship: Ship) -> bool:
	var exclude: Array[RID] = [ship.get_rid()]
	var vel := ship.linear_velocity
	var mt := muzzle_transform()
	Rocket.launch(ship.get_parent(), mt, vel, exclude)
	_tube_fired(ammo_max - ammo)
	return true

## Hide the fired rocket's nose in the model if the model has per-tube rocket tips ("Tip_<n>").
func _tube_fired(n: int) -> void:
	var tip := find_child("Tip_%d" % _order[clampi(n, 0, _order.size() - 1)], true, false) as Node3D
	if tip != null:
		tip.visible = false

func rearm() -> void:
	super.rearm()
	for n in find_children("Tip_*", "Node3D", true, false):
		(n as Node3D).visible = true

func load_extra(data: Dictionary) -> void:
	super.load_extra(data)
	for i in ammo_max - ammo:
		_tube_fired(i)
