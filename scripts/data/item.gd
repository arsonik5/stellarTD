class_name Item
extends Resource

@export var id: String
@export var display_name: String
## Matches VoxelMaterials indices; -1 means this item has no terrain material (e.g. refined goods, tools).
@export var material_index: int = -1
@export var debug_color: Color = Color.WHITE
@export var is_tool: bool = false
@export var max_stack: int = 100
## True for a placeable building (e.g. a crafter). When true, building_scene
## is instanced into the world by the build tool instead of the item being
## added to inventory.
@export var is_building: bool = false
@export var building_scene: PackedScene
## Build-mode ghost preview box size for this building.
@export var ghost_size: Vector3 = Vector3(1.5, 1.5, 1.5)
## Forces grid-aligned placement regardless of the player's free-placement
## toggle. Required for anything the pipe network needs to find by exact
## integer grid cell (all buildings, plus pipes/mergers/splitters).
@export var force_grid_snap: bool = false
## True only for Foundation-type items. Foundations get their own bespoke
## placement rules (snap flush to an existing foundation's edge, inheriting
## its exact orientation, to build a locally-flat grid on a curved planet)
## instead of force_grid_snap's flat voxel-cell snapping. See player.gd's
## _resolve_build_placement().
@export var is_foundation: bool = false
## True for Ship Core - placing it spawns a brand new Ship, not a block on
## an existing one. Mutually exclusive with is_ship_block in practice.
@export var is_ship_core: bool = false
## True for a block placeable onto an existing Ship's local grid (hull,
## thruster, gyroscope, cockpit, ...). Uses `block_scene`, not
## `building_scene` - ship blocks are never placed through the planetary
## build-mode/foundation system, see player.gd's ship placement functions.
@export var is_ship_block: bool = false
@export var block_scene: PackedScene
