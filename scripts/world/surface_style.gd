class_name SurfaceStyle
extends Resource

## How one material looks on the ground: which baked texture set it uses, and
## how that set is tinted and responds to light.
##
## Detail comes from TEXTURES now, not procedural noise. The previous version
## described a surface entirely in noise parameters - bump scale, fracture
## strength, dust gain - which cost seven fbm fields per fragment (~300 hash
## operations per pixel, and 20-30 fps near the ground) and still could not make
## a rock. A baked map is both cheaper and better; those are the same fact.
##
## What remains here is everything that should differ between two planets using
## the SAME texture set: tint, roughness response, tile size. That is what lets a
## generated world reuse one rock set and still look like its own place, which
## is the whole reason a palette exists rather than a hardcoded shader branch.

@export var display_name: String = "Surface"

## Base name of the baked set in `data/textures/surfaces/`, without the `_alb` /
## `_nrm` suffix. Empty falls back to a flat grey layer, so a material with no
## texture authored is visibly unfinished rather than silently borrowing another
## material's rock.
@export var texture_name: String = ""

@export_group("Colour")
## Multiplied over the baked albedo. Keep near white unless the intent really is
## different mineralogy - the texture already carries the rock's own colour, and
## a strong tint reads as coloured light rather than as different stone.
@export var albedo_tint: Color = Color(1.0, 1.0, 1.0)
## Scales the roughness baked into the albedo map's alpha. Below 1 is glossier.
## Natural rock essentially never wants to go below ~0.6 overall; smoother than
## that reads as wet.
@export_range(0.1, 1.5, 0.01) var roughness_scale: float = 1.0

@export_group("Response")
## 0 for every natural rock and mineral. A metal reflects its own colour and has
## NO diffuse term at all, which is a big enough change that a wrong value reads
## as a bug rather than as a tint.
@export_range(0.0, 1.0, 0.01) var metallic: float = 0.0
## Dielectric reflectance at normal incidence, Godot's 0..1 scale. Dry dust sits
## low; ice and fresh crystal faces sit high.
@export_range(0.0, 1.0, 0.01) var specular: float = 0.3
## How strongly the baked normal map perturbs the surface.
@export_range(0.0, 2.0, 0.01) var normal_strength: float = 1.0

@export_group("Scale")
## World size of one texture tile, in metres.
##
## The single most important value for whether a surface reads at the right
## scale: too small and it shimmers into noise at distance, too large and the
## player walks across a single pebble. In METRES, so it is independent of
## planet radius - a constant that only works at one body size is the bug this
## project keeps re-learning.
@export_range(0.25, 64.0, 0.05) var texture_scale_m: float = 4.0

## Packed for the shader: rgb = albedo tint, a = roughness scale.
func tint_roughness() -> Plane:
	return Plane(albedo_tint.r, albedo_tint.g, albedo_tint.b, roughness_scale)

## Packed for the shader: normal strength, metallic, specular, tile size.
func extra_params() -> Plane:
	return Plane(normal_strength, metallic, specular, texture_scale_m)
