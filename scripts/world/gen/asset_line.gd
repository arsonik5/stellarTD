class_name AssetLine
extends Resource

## One line of ground content: a kind of thing that lies on a planet for a reason (boulder fields, talus aprons,
## pebbles, regolith clods...). A trait lists the lines it brings (PlanetTrait.asset_lines); ScatterEngine turns each
## line into VoxelInstancer items whose placement follows the same physical signals as the ground materials, so the
## rocks lie where the ground says rocks would be. reports/AAA voxel terrain fidelity.md, "The catalogue".

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("What")
## Rock model folders under data/models/rocks (each split into data/models/rocks/<id>/game/*.glb by
## tools/decimate_rocks.py). Every mesh in them becomes a variant.
@export var models: Array[String] = []
## Size range in metres (largest dimension of the placed rock) and how strongly small sizes dominate. Real debris
## follows a steep power law (Ruesch; Pajola: index ~ -4 at fresh craters): many pebbles, few boulders.
@export var size_min_m: float = 0.3
@export var size_max_m: float = 1.0
@export_enum("linear", "quadratic", "cubic", "quintic") var size_skew := "cubic"

@export_group("Where")
## Instances per square metre at full signal (before the signal, clumping and rest masks thin it).
@export var density: float = 0.01
## The erosion signal it follows: talus (debris below slopes), deposition (where fines settle), wear (scoured,
## stripped ground), flow (drainage lines), none (everywhere the ground allows).
@export_enum("none", "talus", "deposition", "wear", "flow") var signal_mask := "none"
@export var signal_low: float = 0.1
@export var signal_high: float = 0.5
## true = the line avoids the signal instead (pebbles thin out where fine dust settled).
@export var signal_invert: bool = false
@export var slope_min_deg: float = 0.0
@export var slope_max_deg: float = 40.0
## Ground roles it may sit on (palette slots): fine, worked, scree, secondary, cliff. Empty = any.
@export var on_ground: Array[String] = []
## Clumping: rocks come in groups. Size of a clump region (m) and how much of the ground is in clumps (0..1).
@export var clump_m: float = 40.0
@export_range(0.0, 1.0) var clump_cover: float = 0.5
## The "rest" mask: low-frequency bare stretches between busy patches, so the busy parts read as composed.
@export var rest_m: float = 260.0
@export_range(0.0, 1.0) var rest_share: float = 0.35

@export_group("How it sits")
## Sunk into the ground by this fraction of its size: a rock set exactly on the surface reads as a sticker.
@export_range(0.0, 0.8) var burial: float = 0.25
## Terrain LOD the instances live at (0 = finest, nearest the camera). Bigger things live further out.
@export_range(0, 4) var lod: int = 0
@export var shadows: bool = true
## How far into its terrain LOD's range the line stays visible (0..1); beyond it the instances are hidden. Pebbles
## you can't see past a few metres must not be drawn at a hundred.
@export_range(0.05, 1.0) var view_ratio: float = 1.0
## Use the light mesh (LOD1, ~30% triangles) as the main mesh: for pebble-sized lines drawn in the thousands.
@export var low_poly: bool = false
## Near-field line (pebbles, gravel, clods): placed at real density only around the viewer by NearScatter, instead of
## across the whole terrain LOD by the instancer. Signal masks don't apply; the ground roles and clumping do.
@export var near_field: bool = false
@export var collision: bool = false
## How much the rock's colour is pulled toward the ground it lies on (same geology, same dust).
@export_range(0.0, 1.0) var colour_match: float = 0.55
## Dust settled on up-facing surfaces, in the ground's colour.
@export_range(0.0, 1.0) var dust: float = 0.35
