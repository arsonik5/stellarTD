class_name PlanetAtmosphere
extends Resource

## Everything needed to make one planet's sky/sun/fog look different from
## another's, without touching shader code. World.gd reads one of these
## (its exported `atmosphere` field) and pushes the values into a shared
## ShaderMaterial + Environment + the DirectionalLight3D at _ready() - a new
## planet is just a new .tres of this resource with different numbers, not a
## new shader or scene.

@export_group("Sky gradient")
@export var zenith_color: Color = Color(0.1, 0.28, 0.65)
@export var horizon_color: Color = Color(0.68, 0.78, 0.88)
@export var ground_color: Color = Color(0.14, 0.12, 0.11)
## Higher = sharper transition from horizon to zenith/ground; lower = a more
## gradual, hazier blend (thicker-feeling atmosphere).
@export_range(0.2, 8.0) var horizon_curve: float = 2.0

@export_group("Sun disc + glow")
@export var sun_color: Color = Color(1.0, 0.95, 0.85)
## Angular radius of the sharp sun disc, in radians.
@export_range(0.001, 0.2) var sun_angular_size: float = 0.03
@export var sun_glow_color: Color = Color(1.0, 0.7, 0.4)
@export_range(0.0, 6.0) var sun_glow_intensity: float = 1.8
## Higher = tighter/more concentrated glow around the sun disc; lower = a
## broader wash of color across more of the sky.
@export_range(1.0, 128.0) var sun_glow_exponent: float = 10.0
@export_range(0.0, 3.0) var atmosphere_energy: float = 1.0

@export_group("Directional light")
@export var sun_light_color: Color = Color(1.0, 0.97, 0.92)
@export_range(0.0, 4.0) var sun_light_energy: float = 1.2

@export_group("Fog")
@export var fog_enabled: bool = true
@export var fog_color: Color = Color(0.68, 0.78, 0.88)
## Kept low by default - this needs to read as atmospheric haze, not fog that
## hides terrain at normal dig/build ranges.
@export_range(0.0, 0.05) var fog_density: float = 0.003

@export_group("Physics")
## kg/m^3, drives projectile aerodynamic drag (see PlanetPhysics/projectile.gd)
## - Earth sea-level is 1.225. A thinner/thicker atmosphere on another planet
## changes how much drag bullets/shells feel, purely by changing this number.
@export_range(0.0, 5.0) var air_density: float = 1.225
