class_name ShipWeaponControl
extends Node

## The ship's weapon control system, War Thunder style:
## - Weapons are grouped by name ("ROCKETS"); every fitted pod of that name belongs to one group.
## - Two triggers. PRIMARY (guns) fires every primary weapon while held. SECONDARY fires the SELECTED secondary group.
## - A selector steps through the secondary groups; a salvo setting per group says how many rounds one trigger pull
##   releases (1, 2, 4, 8, 16) or RIPPLE (keeps firing while held). Rounds alternate between the group's weapons.
## - A CCIP solution (continuously computed impact point) for the selected group, for the HUD pipper.
## Any controller can drive it (player input, AI): it only exposes pull/release and state. One per Ship, created on
## demand by ShipWeaponControl.of(ship). Input mapping lives in PlayerShipController, not here.

const SALVOS := [1, 2, 4, 8, 16, 0]           # 0 = ripple
const RIPPLE_INTERVAL := 0.07                  # s between rounds inside a salvo / ripple
const CCIP_HZ := 15.0

var ship: Ship
var groups: Array = []                         # [{name, trigger, weapons: Array[ShipWeapon]}]
var selected := 0                              # index into secondary_groups()
var salvo_index := {}                          # group name -> index into SALVOS
var ccip := {}                                 # {"hit", "position", "time"} for the selected group

var _primary_held := false
var _secondary_held := false
var _queued := 0                               # rounds left in the current salvo
var _ripple_timer := 0.0
var _next_weapon := {}                         # group name -> round-robin index
var _ccip_timer := 0.0

static func of(s: Ship) -> ShipWeaponControl:
	var c := s.get_node_or_null("WeaponControl") as ShipWeaponControl
	if c == null:
		c = ShipWeaponControl.new()
		c.name = "WeaponControl"
		c.ship = s
		s.add_child(c)
	return c

func _ready() -> void:
	refresh()

## Rebuild the groups from the ship's operational weapons (call after the ship's blocks change).
func refresh() -> void:
	var by_name := {}
	groups.clear()
	for b in ship._gather_blocks():
		var w := b as ShipWeapon
		if w == null or not w.is_operational():
			continue
		if not by_name.has(w.weapon_name):
			by_name[w.weapon_name] = {"name": w.weapon_name, "trigger": w.trigger, "weapons": []}
			groups.append(by_name[w.weapon_name])
		by_name[w.weapon_name]["weapons"].append(w)
	selected = clampi(selected, 0, maxi(secondary_groups().size() - 1, 0))

func secondary_groups() -> Array:
	return groups.filter(func(g): return g["trigger"] == "secondary")

func selected_group() -> Dictionary:
	var s := secondary_groups()
	return s[selected] if selected < s.size() else {}

func has_weapons() -> bool:
	return not groups.is_empty()

func ammo_of(group: Dictionary) -> Vector2i:
	var have := 0
	var cap := 0
	for w: ShipWeapon in group.get("weapons", []):
		have += w.ammo
		cap += w.ammo_max
	return Vector2i(have, cap)

func salvo_of(group: Dictionary) -> int:
	return SALVOS[salvo_index.get(group.get("name", ""), 2)]          # default 4

func salvo_label(group: Dictionary) -> String:
	var n := salvo_of(group)
	return "RIPPLE" if n == 0 else "SALVO %d" % n

# --- switches -----------------------------------------------------------------------------------------------
func select_next(step := 1) -> void:
	var n := secondary_groups().size()
	if n > 0:
		selected = posmod(selected + step, n)
		_queued = 0

func cycle_salvo() -> void:
	var g := selected_group()
	if g.is_empty():
		return
	salvo_index[g["name"]] = (int(salvo_index.get(g["name"], 2)) + 1) % SALVOS.size()

func set_primary(held: bool) -> void:
	_primary_held = held

func set_secondary(held: bool) -> void:
	if held and not _secondary_held:
		var g := selected_group()
		if not g.is_empty():
			var n := salvo_of(g)
			_queued = n if n > 0 else 0
			_ripple_timer = 0.0
	_secondary_held = held

# --- firing -------------------------------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if ship == null or not is_instance_valid(ship) or not ship.is_operational():
		return
	if _primary_held:
		for g in groups:
			if g["trigger"] == "primary":
				_fire_round(g)
	var g := selected_group()
	if not g.is_empty():
		var ripple := salvo_of(g) == 0
		if _queued > 0 or (ripple and _secondary_held):
			_ripple_timer -= delta
			if _ripple_timer <= 0.0:
				if _fire_round(g):
					_queued = maxi(_queued - 1, 0)
					_ripple_timer = RIPPLE_INTERVAL
				elif ammo_of(g).x == 0:
					_queued = 0
	_ccip_timer -= delta
	if _ccip_timer <= 0.0:
		_ccip_timer = 1.0 / CCIP_HZ
		_update_ccip()

## One round from the group's next ready weapon (round robin across pods). False if none could fire.
func _fire_round(g: Dictionary) -> bool:
	var ws: Array = g["weapons"]
	if ws.is_empty():
		return false
	var start: int = _next_weapon.get(g["name"], 0)
	for i in ws.size():
		var w: ShipWeapon = ws[(start + i) % ws.size()]
		if is_instance_valid(w) and w.fire_one(ship):
			_next_weapon[g["name"]] = (start + i + 1) % ws.size()
			return true
	return false

func _update_ccip() -> void:
	var g := selected_group()
	if g.is_empty() or (g["weapons"] as Array).is_empty():
		ccip = {}
		return
	var w: ShipWeapon = g["weapons"][0]
	if not is_instance_valid(w) or not (w is ShipRocketPod):
		ccip = {}
		return
	var mt := w.global_transform
	var exclude: Array[RID] = [ship.get_rid()]
	ccip = Rocket.predict(ship.get_world_3d(), mt.origin, ship.linear_velocity, -mt.basis.z, exclude)
