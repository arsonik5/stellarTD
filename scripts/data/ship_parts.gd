class_name ShipParts
extends RefCounted
## Every small ship / vehicle part on the shared 0.5 m grid (models: art_src/parts_lib.py, behaviour:
## scripts/world/ship_*.gd). The inventory registers ITEMS; the Constructor and the Ship Garage craft RECIPES.

const ITEMS := [
	preload("res://data/items/beam_1.tres"),
	preload("res://data/items/beam_2.tres"),
	preload("res://data/items/beam_4.tres"),
	preload("res://data/items/frame_cube.tres"),
	preload("res://data/items/frame_corner.tres"),
	preload("res://data/items/plate.tres"),
	preload("res://data/items/wedge.tres"),
	preload("res://data/items/hull_small.tres"),
	preload("res://data/items/driver_seat.tres"),
	preload("res://data/items/vehicle_core.tres"),
	preload("res://data/items/battery.tres"),
	preload("res://data/items/o2_tank.tres"),
	preload("res://data/items/engine.tres"),
	preload("res://data/items/rcs.tres"),
	preload("res://data/items/wheel_small.tres"),
	preload("res://data/items/wheel_large.tres"),
	preload("res://data/items/landing_gear.tres"),
	preload("res://data/items/bearing.tres"),
	preload("res://data/items/hinge.tres"),
	preload("res://data/items/piston.tres"),
	preload("res://data/items/rotor_head.tres"),
]

const RECIPES := [
	preload("res://data/recipes/craft_beam_1.tres"),
	preload("res://data/recipes/craft_beam_2.tres"),
	preload("res://data/recipes/craft_beam_4.tres"),
	preload("res://data/recipes/craft_frame_cube.tres"),
	preload("res://data/recipes/craft_frame_corner.tres"),
	preload("res://data/recipes/craft_plate.tres"),
	preload("res://data/recipes/craft_wedge.tres"),
	preload("res://data/recipes/craft_hull_small.tres"),
	preload("res://data/recipes/craft_driver_seat.tres"),
	preload("res://data/recipes/craft_vehicle_core.tres"),
	preload("res://data/recipes/craft_battery.tres"),
	preload("res://data/recipes/craft_o2_tank.tres"),
	preload("res://data/recipes/craft_engine.tres"),
	preload("res://data/recipes/craft_rcs.tres"),
	preload("res://data/recipes/craft_wheel_small.tres"),
	preload("res://data/recipes/craft_wheel_large.tres"),
	preload("res://data/recipes/craft_landing_gear.tres"),
	preload("res://data/recipes/craft_bearing.tres"),
	preload("res://data/recipes/craft_hinge.tres"),
	preload("res://data/recipes/craft_piston.tres"),
]
