class_name ShipWeapon
extends ShipBlock

## Base for every ship-mounted weapon. The weapon only knows how to fire ONE shot and how much ammo it has; WHEN it
## fires (trigger, selected weapon, salvo size, alternating between pods) is the ShipWeaponControl's job, the same
## split as War Thunder: weapons are hardware, the control system is the pilot's switches.
## Local -Z is the bore axis, like every other block.

## Which trigger fires it: "primary" (guns, LMB) or "secondary" (rockets, bombs: selected and fired as a group).
@export var trigger := "secondary"
## Weapons with the same name form one group in the selector and on the HUD ("ROCKETS"), however many are fitted.
@export var weapon_name := "WEAPON"
@export var ammo_max := 1
## Fastest this one weapon can fire again (s).
@export var fire_interval := 0.1

var ammo := 0
var _cooldown := 0.0

func _ready() -> void:
	super._ready()
	ammo = ammo_max

func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)

func ready_to_fire() -> bool:
	return ammo > 0 and _cooldown <= 0.0 and is_operational()

## Fire one shot. Returns true if it fired.
func fire_one(ship: Ship) -> bool:
	if not ready_to_fire():
		return false
	if not _shoot(ship):
		return false
	ammo -= 1
	_cooldown = fire_interval
	return true

## Subclasses spawn the projectile here.
func _shoot(_ship: Ship) -> bool:
	return false

## Where the next shot leaves from (global), for aiming aids.
func muzzle_transform() -> Transform3D:
	return global_transform

func rearm() -> void:
	ammo = ammo_max

## Saved per block by Ship.save_state() under "extra".
func save_extra() -> Dictionary:
	return {"ammo": ammo}

func load_extra(data: Dictionary) -> void:
	ammo = clampi(int(data.get("ammo", ammo_max)), 0, ammo_max)
