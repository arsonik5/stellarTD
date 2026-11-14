class_name BuildGrid2D
extends Node2D

## Everything built on the 2D tile grid (pivot-2d.md C4): which tile holds what, the placement rules, paying for a
## placement (a carried copy first, else the build recipe's materials - same rule as the 3D build UI), dismantling
## with a full refund (cost + contents), output dumping onto belts, and save/load of buildings and belts.

const MACHINES := {
	"smelter": preload("res://scripts/world2d/machines/smelter_2d.gd"),
	"chest": preload("res://scripts/world2d/machines/chest_2d.gd"),
	"constructor": preload("res://scripts/world2d/machines/constructor_2d.gd"),
	"deposit_drill": preload("res://scripts/world2d/machines/deposit_drill_2d.gd"),
}
const BELT := "conveyor_belt"
const DIRS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]   ## rot 0..3

var grid: WorldGrid
var view: WorldView
var belts: BeltSystem2D
var _at := {}                ## Vector2i -> Building2D
var _sizes := {}             ## item_id -> Vector2i (cached from a throwaway instance)

func setup(g: WorldGrid, v: WorldView) -> void:
	grid = g
	view = v
	belts = BeltSystem2D.new()
	belts.grid = g
	belts.view = v
	belts.build = self
	add_child(belts)
	FactoryClock.tick.connect(_dump_outputs)

static func buildable_ids() -> Array:
	return [BELT, "deposit_drill", "smelter", "constructor", "chest"]

func size_of(id: String) -> Vector2i:
	if id == BELT:
		return Vector2i.ONE
	if not _sizes.has(id):
		var b: Building2D = MACHINES[id].new()
		_sizes[id] = b.size
		b.free()
	return _sizes[id]

func footprint(id: String, rot: int) -> Vector2i:
	var s := size_of(id)
	return Vector2i(s.y, s.x) if rot % 2 == 1 else s

func building_at(t: Vector2i) -> Building2D:
	return _at.get(t)

func all_buildings() -> Array:
	var seen := {}
	for b: Building2D in _at.values():
		seen[b] = true
	return seen.keys()

## Why `id` can't go at `tile` (top-left) with rotation `rot`, "" if it can.
func can_place(id: String, tile: Vector2i, rot: int) -> String:
	if id != BELT and not MACHINES.has(id):
		return "Not buildable"
	var f := footprint(id, rot)
	var lv := grid.level_at(tile.x, tile.y)
	var any_ore := false
	for y in f.y:
		for x in f.x:
			var t := tile + Vector2i(x, y)
			if not grid.in_bounds(t.x, t.y):
				return "Edge of the map"
			if grid.level_at(t.x, t.y) != lv:
				return "Needs flat ground"
			if grid.is_ramp(t.x, t.y) and id != BELT:
				return "Not on a slope"
			if _at.has(t) or belts.has_belt(t):
				return "Something is in the way"
			if grid.ore_at(t.x, t.y) > 0:
				any_ore = true
	if id == "deposit_drill" and not any_ore:
		return "Needs ore under it"
	return ""

func build_recipe(id: String) -> Recipe:
	var p := "res://data/recipes/build_%s.tres" % id
	return load(p) if ResourceLoader.exists(p) else null

## Can the player pay for one `id` right now (a carried copy, or the materials)?
func can_pay(id: String) -> bool:
	if Inventory.get_count(id) > 0:
		return true
	var r := build_recipe(id)
	if r == null:
		return false
	for k in r.input_ids.size():
		if Inventory.get_count(r.input_ids[k]) < r.input_amounts[k]:
			return false
	return true

## Takes the price of one `id` from the inventory (a carried copy first). The recipe may make several (belts come
## in pairs): the rest go into the inventory as carried copies.
func pay(id: String) -> bool:
	if Inventory.get_count(id) > 0:
		return Inventory.try_remove(id, 1)
	var r := build_recipe(id)
	if r == null or not can_pay(id):
		return false
	for k in r.input_ids.size():
		Inventory.try_remove(r.input_ids[k], r.input_amounts[k])
	if r.output_amount > 1:
		Inventory.add(id, r.output_amount - 1)
	return true

## Places `id`. `pay_for_it` false = free (loading a save, tests). Returns the building (or null for a belt / refusal).
func place(id: String, tile: Vector2i, rot: int, pay_for_it: bool = true) -> Variant:
	if can_place(id, tile, rot) != "":
		return null
	if pay_for_it and not pay(id):
		return null
	if id == BELT:
		belts.add_belt(tile, DIRS[rot % 4])
		GameEvents.building_placed.emit(id, null)
		return true
	var b: Building2D = MACHINES[id].new()
	b.tile = tile
	b.rot = rot
	b.level = grid.level_at(tile.x, tile.y)
	b.view = view
	if b.has_method("ore_under"):
		b.set("grid", grid)
	add_child(b)
	for t in b.tiles():
		_at[t] = b
	b.removed.connect(func() -> void: _forget(b), CONNECT_ONE_SHOT)
	GameEvents.building_placed.emit(id, b)
	return b

func _forget(b: Building2D) -> void:
	for t in b.tiles():
		if _at.get(t) == b:
			_at.erase(t)
	b.queue_free()

## Takes down whatever is at `t`, refunding its cost and contents. False if nothing is there or it won't fit.
func dismantle_at(t: Vector2i) -> bool:
	var refund := {}
	if belts.has_belt(t):
		refund = {BELT: 1}
		for id: String in (belts.belts[t] as BeltSystem2D.Belt).ids:
			refund[id] = int(refund.get(id, 0)) + 1
		if not Inventory.can_add_all(refund):
			return false
		belts.remove_belt(t)
	else:
		var b := building_at(t)
		if b == null:
			return false
		refund = b.contents_refund()
		refund[b.item_id] = int(refund.get(b.item_id, 0)) + 1     # the building comes back as a carried copy
		if not Inventory.can_add_all(refund):
			return false
		_forget(b)
	for id: String in refund:
		Inventory.add(id, int(refund[id]))
	return true

## Every tick each building pushes one output item onto a neighbouring belt that points away from it (Mindustry's
## dump rule), trying its sides in turn so outputs spread over several belts.
var _rr := 0
func _dump_outputs(_dt: float) -> void:
	_rr += 1
	for b: Building2D in all_buildings():
		if b.output_ids().is_empty():
			continue
		var edge := _edge_belts(b)
		if edge.is_empty():
			continue
		for k in edge.size():
			var e: Array = edge[(k + _rr) % edge.size()]
			if belts.has_room(e[0]):
				var id := b.take_one_output()
				if id != "":
					belts.insert(e[0], id)
				break

## Belts touching the building's outline that point away from it: [[tile, dir]...]
func _edge_belts(b: Building2D) -> Array:
	var out := []
	var cover := b.tiles()
	for t in cover:
		for d: Vector2i in DIRS:
			var n := t + d
			if cover.has(n) or not belts.has_belt(n):
				continue
			var belt: BeltSystem2D.Belt = belts.belts[n]
			if belt.dir == d and belt.level == b.level:
				out.append([n, d])
	return out

func save_state() -> Dictionary:
	var bs := []
	for b: Building2D in all_buildings():
		bs.append(b.save_state())
	return {"buildings": bs, "belts": belts.save_state()}

func load_state(data: Dictionary) -> void:
	for b: Building2D in all_buildings():
		_forget(b)
	_at.clear()
	for e: Dictionary in data.get("buildings", []):
		var b: Variant = place(String(e["item_id"]), Vector2i(int(e["tile"][0]), int(e["tile"][1])), int(e.get("rot", 0)), false)
		if b is Building2D:
			(b as Building2D).load_state(e)
	belts.load_state(data.get("belts", []))
