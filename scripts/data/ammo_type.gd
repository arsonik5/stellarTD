class_name AmmoType
extends Resource

## A complete, self-contained "what does firing this round actually do"
## spec: real ballistics inputs (mass/velocity/caliber/drag) so
## projectile.gd can integrate a real trajectory, plus the combat stats
## (damage/splash) that trajectory resolves into on impact. Deliberately
## NOT split across (turret, ammo) - the same round behaves the same no
## matter which compatible turret fires it, which is what makes "only some
## turrets accept some ammo types" a meaningful choice rather than a
## reskinned duplicate (see Turret.compatible_ammo).

@export var item_id: String
@export var display_name: String

@export_group("Ballistics")
@export_range(0.001, 50.0) var mass_kg: float = 0.05
@export_range(1.0, 1000.0) var muzzle_velocity: float = 40.0
## Projectile diameter, in meters - drives both drag cross-section
## (pi * (caliber/2)^2) and the projectile's rendered size.
@export_range(0.001, 1.0) var caliber_m: float = 0.02
## Dimensionless quadratic-drag coefficient. ~0.2-0.5 for typical
## bullet/shell shapes; higher = loses velocity to air resistance faster.
@export_range(0.0, 2.0) var drag_coefficient: float = 0.3

@export_group("Impact")
@export var damage: float = 8.0
## >0 makes this a splash round: every other "enemy"-group node within this
## radius of the impact point also takes damage (scaled by the falloff).
@export_range(0.0, 20.0) var splash_radius: float = 0.0
@export_range(0.0, 1.0) var splash_damage_falloff: float = 0.5

@export_group("Visuals")
@export var projectile_color: Color = Color(1.0, 0.85, 0.3)
