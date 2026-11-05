extends Node
## Progression - Directives, research and Continuance credit (design/02-core-mechanics.md C7, M26-M28).
##
## Three currencies, on purpose:
##   credit   - "Earth is pleased": paid for Directives, spent on supply drops.
##   research - "you learned something": data points in three categories, earned by doing things for the FIRST
##              time (first ore of a type mined or scanned, first time a material is made, first alien killed...),
##              spent on ResearchNodes that unlock buildings.
##   signature- not here: RadiationSignature (Uplink launches report to it through GameEvents).
##
## Directives: the tutorial quests (QuestManager) come first; once its last quest is done the milestone chain in
## data/directives/ starts, one at a time. After the first milestone the Continuance also keeps up to
## STANDING_SLOTS generated standing orders open forever, sized to what the player actually produces.
## Everything listens to GameEvents; nothing calls in here except the Uplink (deliver) and UI (buy).

signal changed
signal directive_completed(id: String, title: String)
signal research_unlocked(id: String)
signal points_awarded(category: String, amount: int, reason: String)

const DIRECTIVE_DIR := "res://data/directives"
const RESEARCH_DIR := "res://data/research"
const CATEGORIES := ["geology", "engineering", "xeno"]
const STANDING_SLOTS := 2
## Tutorial quest whose completion opens the directive chain (the last one in QuestManager's diamond).
const TUTORIAL_FINAL := "conveyor"
## Value per item in credit, by how far up the chain it is. Unlisted = 1.
const ITEM_VALUE := {
	"refined_material": 1, "refined_copper_ingot": 1, "refined_carbon": 1, "refined_silica": 1, "gravel": 1,
	"copper_wire": 1, "steel_ingot": 3, "concrete": 2, "circuit": 4, "crystal_cell": 12, "alien_alloy": 8,
}
## Materials the generator may ask for in standing orders (raw ore is never ordered: Earth wants work done).
const ORDERABLE := ["refined_material", "refined_copper_ingot", "refined_carbon", "refined_silica", "copper_wire",
	"steel_ingot", "concrete", "circuit", "crystal_cell", "gravel"]
const STANDING_MESSAGES := [
	"Standing order from the Continuance. Steady supply saves more lives than heroics.",
	"The coastal shelters ran short this week. Anything you can spare.",
	"Reconstruction Board request. Same as last time, Voyager - Earth is counting.",
	"A ration cut was avoided because of your last shipment. Here is the next one.",
]

var credit := 0
var points := {"geology": 0, "engineering": 0, "xeno": 0}
var bought: Dictionary = {}          # research id -> true
var completed: Dictionary = {}       # directive id -> true (milestones and standing)
var delivered: Dictionary = {}       # directive id -> {item_id: n}
var placed_counts: Dictionary = {}   # item_id -> n (for PLACE directives)
var firsts: Dictionary = {}          # "mined:ore_a" -> true
var produced: Dictionary = {}        # item_id -> total made or mined (standing-order sizing, statistics)
var standing: Array = []             # generated directives (Dictionaries with Directive's fields + "standing": true)
var _standing_serial := 0

var _milestones: Array[Directive] = []
var _research: Array[ResearchNode] = []
var _locked_by: Dictionary = {}      # item_id -> research id that unlocks it

func _ready() -> void:
	for f in ResourceLoader.list_directory(DIRECTIVE_DIR):
		if f.ends_with(".tres"):
			var d := load(DIRECTIVE_DIR + "/" + f) as Directive
			if d != null:
				_milestones.append(d)
	_milestones.sort_custom(func(a: Directive, b: Directive) -> bool: return a.id < b.id)
	for f in ResourceLoader.list_directory(RESEARCH_DIR):
		if f.ends_with(".tres"):
			var r := load(RESEARCH_DIR + "/" + f) as ResearchNode
			if r != null:
				_research.append(r)
				for item_id in r.unlocks:
					_locked_by[item_id] = r.id
	_research.sort_custom(func(a: ResearchNode, b: ResearchNode) -> bool: return _cost_total(a) < _cost_total(b))
	GameEvents.item_mined.connect(_on_mined)
	GameEvents.item_crafted.connect(_on_crafted)
	GameEvents.building_placed.connect(_on_placed)
	GameEvents.scanned.connect(_on_scanned)
	GameEvents.destroyed.connect(_on_destroyed)
	QuestManager.changed.connect(_refill_standing)

## Fresh game (tests and New Game call this through load_state({})).
func reset() -> void:
	credit = 0
	points = {"geology": 0, "engineering": 0, "xeno": 0}
	bought.clear()
	completed.clear()
	delivered.clear()
	placed_counts.clear()
	firsts.clear()
	produced.clear()
	standing.clear()
	_standing_serial = 0
	changed.emit()

# --------------------------------------------------------------------------------------------- research

func research_nodes() -> Array[ResearchNode]:
	return _research

func get_research(id: String) -> ResearchNode:
	for r in _research:
		if r.id == id:
			return r
	return null

## False only for items a not-yet-bought research node unlocks.
func is_buildable(item_id: String) -> bool:
	return not _locked_by.has(item_id) or bought.has(_locked_by[item_id])

## Research node that gates `item_id`, or null if it is free.
func gate_of(item_id: String) -> ResearchNode:
	return get_research(_locked_by[item_id]) if _locked_by.has(item_id) and not bought.has(_locked_by[item_id]) else null

func can_buy(id: String) -> bool:
	var r := get_research(id)
	if r == null or bought.has(id):
		return false
	for p in r.prerequisite_ids:
		if not bought.has(p):
			return false
	for c: String in r.cost:
		if int(points.get(c, 0)) < int(r.cost[c]):
			return false
	return true

func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var r := get_research(id)
	for c: String in r.cost:
		points[c] = int(points[c]) - int(r.cost[c])
	bought[id] = true
	research_unlocked.emit(id)
	GameEvents.act("research_" + id)
	changed.emit()
	return true

func award(category: String, amount: int, reason: String) -> void:
	if amount <= 0 or not points.has(category):
		return
	points[category] = int(points[category]) + amount
	points_awarded.emit(category, amount, reason)
	changed.emit()

## Award once per key, ever (saved). Returns true when it was new.
func award_first(key: String, category: String, amount: int, reason: String) -> bool:
	if firsts.has(key):
		return false
	firsts[key] = true
	award(category, amount, reason)
	return true

func _on_mined(item_id: String, amount: int, _src: Node) -> void:
	produced[item_id] = int(produced.get(item_id, 0)) + amount
	if item_id != "stone":
		award_first("mined:" + item_id, "geology", 1, "first " + _name(item_id))

func _on_crafted(item_id: String, amount: int, _b: Node) -> void:
	produced[item_id] = int(produced.get(item_id, 0)) + amount
	if ItemInfo.category(item_id) == "material":
		award_first("crafted:" + item_id, "engineering", 1, "first " + _name(item_id))

func _on_placed(item_id: String, _node: Node) -> void:
	placed_counts[item_id] = int(placed_counts.get(item_id, 0)) + 1
	if ItemInfo.category(item_id) == "production":
		award_first("placed:" + item_id, "engineering", 1, "first " + _name(item_id))
	_check_milestone()

func _on_scanned(ore_ids: Array) -> void:
	for id in ore_ids:
		award_first("scanned:" + String(id), "geology", 1, "found " + _name(String(id)))

func _on_destroyed(target: Node, _source: Node) -> void:
	if target == null or not target.is_in_group("enemy"):
		return
	var kind := String(target.get_meta("enemy_kind", target.get_class()))
	award_first("killed:" + kind, "xeno", 2, "first kill: " + kind.capitalize())

# ------------------------------------------------------------------------------------------- directives

func tutorial_done() -> bool:
	return QuestManager.get_state(TUTORIAL_FINAL) == "complete"

## The milestone currently in force, or null (tutorial not done, or the chain is finished).
func active_milestone() -> Directive:
	if not tutorial_done():
		return null
	for d in _milestones:
		if completed.has(d.id):
			continue
		var ready := true
		for p in d.prerequisite_ids:
			if not completed.has(p):
				ready = false
		if ready:
			return d
	return null

func milestones() -> Array[Directive]:
	return _milestones

## Every open directive as a uniform Dictionary: {id, title, message, kind, item_ids, amounts, reward_credit,
## reward_research, standing}. Milestone first.
func open_directives() -> Array:
	var out := []
	var m := active_milestone()
	if m != null:
		out.append(_as_dict(m))
	out.append_array(standing)
	return out

func _as_dict(d: Directive) -> Dictionary:
	return {"id": d.id, "title": d.title, "message": d.message, "kind": d.kind, "item_ids": d.item_ids,
		"amounts": d.amounts, "reward_credit": d.reward_credit, "reward_research": d.reward_research,
		"standing": false}

## {item_id: delivered so far} for a directive (PLACE directives report placements).
func progress_of(d: Dictionary) -> Dictionary:
	if int(d.kind) == Directive.Kind.PLACE:
		var id: String = d.item_ids[0]
		return {id: mini(int(placed_counts.get(id, 0)), int(d.amounts[0]))}
	return delivered.get(d.id, {})

## 0..1 overall progress of a directive.
func fraction_of(d: Dictionary) -> float:
	var got := progress_of(d)
	var have := 0
	var need := 0
	for i in d.item_ids.size():
		need += int(d.amounts[i])
		have += mini(int(got.get(d.item_ids[i], 0)), int(d.amounts[i]))
	return float(have) / float(need) if need > 0 else 1.0

## True when some open DELIVER directive still needs this item (the Uplink only accepts those).
func wants(item_id: String) -> bool:
	return _need_of(item_id) > 0

func _need_of(item_id: String) -> int:
	var total := 0
	for d: Dictionary in open_directives():
		if int(d.kind) != Directive.Kind.DELIVER:
			continue
		var idx: int = (d.item_ids as Array).find(item_id)
		if idx >= 0:
			total += maxi(int(d.amounts[idx]) - int(progress_of(d).get(item_id, 0)), 0)
	return total

## The Uplink hands goods over here. Fills the milestone first, then standing orders in order. Returns how many
## were taken (the rest stays in the Uplink).
func deliver(item_id: String, amount: int) -> int:
	var left := amount
	for d: Dictionary in open_directives():
		if left <= 0:
			break
		if int(d.kind) != Directive.Kind.DELIVER:
			continue
		var idx: int = (d.item_ids as Array).find(item_id)
		if idx < 0:
			continue
		var got: Dictionary = delivered.get(d.id, {})
		var need := int(d.amounts[idx]) - int(got.get(item_id, 0))
		var take := mini(need, left)
		if take <= 0:
			continue
		got[item_id] = int(got.get(item_id, 0)) + take
		delivered[d.id] = got
		left -= take
	var taken := amount - left
	if taken > 0:
		_check_all()
		changed.emit()
	return taken

func _check_all() -> void:
	_check_milestone()
	for d: Dictionary in standing.duplicate():
		if fraction_of(d) >= 1.0:
			standing.erase(d)
			_complete(d)
	_refill_standing()

func _check_milestone() -> void:
	var guard := 0
	var m := active_milestone()
	while m != null and guard < 20:
		guard += 1
		var d := _as_dict(m)
		if fraction_of(d) < 1.0:
			break
		_complete(d)
		m = active_milestone()
	_refill_standing()

func _complete(d: Dictionary) -> void:
	completed[d.id] = true
	credit += int(d.reward_credit)
	for c: String in d.reward_research:
		award(c, int(d.reward_research[c]), d.title)
	directive_completed.emit(d.id, d.title)
	GameEvents.act("directive_complete")
	changed.emit()

## Standing orders open after the first milestone, and are kept at STANDING_SLOTS. Sized to production: about
## eight minutes of what the base has made of that item so far (at least 10), so the ask grows with the factory.
func _refill_standing() -> void:
	if not completed.has("d01_uplink"):
		return
	var guard := 0
	while standing.size() < STANDING_SLOTS and guard < 4:
		guard += 1
		var d := _generate_standing()
		if d.is_empty():
			return
		standing.append(d)
		changed.emit()

func _generate_standing() -> Dictionary:
	var candidates := []
	for id in ORDERABLE:
		if int(produced.get(id, 0)) > 0:
			var taken := false
			for s: Dictionary in standing:
				if (s.item_ids as Array).has(id):
					taken = true
			if not taken:
				candidates.append(id)
	# nothing produced yet (or all of it already ordered): fall back to the basics every base can make
	if candidates.is_empty():
		for id in ["refined_material", "refined_copper_ingot", "copper_wire"]:
			var taken := false
			for s: Dictionary in standing:
				if (s.item_ids as Array).has(id):
					taken = true
			if not taken:
				candidates.append(id)
	if candidates.is_empty():
		return {}
	_standing_serial += 1
	# deterministic choice (saves and tests reproduce): rotate through what is produced
	var item: String = candidates[_standing_serial % candidates.size()]
	var minutes := maxf(FactoryClock.sim_time / 60.0, 5.0)
	var per_min := float(produced.get(item, 0)) / minutes
	var amount := clampi(int(round(per_min * 8.0 / 5.0)) * 5, 10, 400)
	var value: int = ITEM_VALUE.get(item, 1)
	return {"id": "standing_%d" % _standing_serial, "title": "Standing order: %s" % _name(item),
		"message": STANDING_MESSAGES[_standing_serial % STANDING_MESSAGES.size()], "kind": Directive.Kind.DELIVER,
		"item_ids": [item], "amounts": [amount], "reward_credit": amount * value,
		"reward_research": {"engineering": 1} if value >= 3 else {}, "standing": true}

func _name(item_id: String) -> String:
	var def := Inventory.get_item_def(item_id)
	return def.display_name if def != null else item_id

static func _cost_total(r: ResearchNode) -> int:
	var t := 0
	for c: String in r.cost:
		t += int(r.cost[c])
	return t

# -------------------------------------------------------------------------------------------- persistence

func save_state() -> Dictionary:
	return {"credit": credit, "points": points.duplicate(), "bought": bought.keys(), "completed": completed.keys(),
		"delivered": delivered.duplicate(true), "placed": placed_counts.duplicate(), "firsts": firsts.keys(),
		"produced": produced.duplicate(), "standing": standing.duplicate(true), "serial": _standing_serial}

func load_state(data: Dictionary) -> void:
	reset()
	credit = int(data.get("credit", 0))
	var p: Dictionary = data.get("points", {})
	for c in CATEGORIES:
		points[c] = int(p.get(c, 0))
	for id in data.get("bought", []):
		bought[String(id)] = true
	for id in data.get("completed", []):
		completed[String(id)] = true
	for k in data.get("firsts", []):
		firsts[String(k)] = true
	var dl: Dictionary = data.get("delivered", {})
	for id: String in dl:
		var inner := {}
		for item: String in dl[id]:
			inner[item] = int(dl[id][item])
		delivered[id] = inner
	var pc: Dictionary = data.get("placed", {})
	for id: String in pc:
		placed_counts[id] = int(pc[id])
	var pr: Dictionary = data.get("produced", {})
	for id: String in pr:
		produced[id] = int(pr[id])
	for s in data.get("standing", []):
		var d: Dictionary = s
		d["kind"] = int(d.get("kind", 0))
		var amounts := []
		for a in d.get("amounts", []):
			amounts.append(int(a))
		d["amounts"] = amounts
		standing.append(d)
	_standing_serial = int(data.get("serial", 0))
	changed.emit()
