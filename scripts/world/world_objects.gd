class_name WorldObjects
extends RefCounted
## Removing player-placed things from the world, in one place (design M13). Placement registers objects in
## several systems (SaveManager group, PipeNetwork, FoundationNetwork, pipe chains); removal must undo all of
## them, for dismantling and for destruction alike.

## The placed object (has SaveManager's item-id meta) that `collider` belongs to, or null.
static func placed_root(collider: Object) -> Node3D:
	var n := collider as Node
	var depth := 0
	while n != null and depth < 5:
		if n is Node3D and n.has_meta(SaveManager.ITEM_ID_META):
			return n
		n = n.get_parent()
		depth += 1
	return null

## Everything dismantling `node` gives back: the build cost plus whatever is stored inside it.
## Returns {item_id: count}.
static func refund_of(node: Node3D) -> Dictionary:
	var out := {}
	var item_id := String(node.get_meta(SaveManager.ITEM_ID_META, ""))
	var recipe := RecipeBook.for_output(item_id)
	if recipe != null:
		for i in recipe.input_ids.size():
			out[recipe.input_ids[i]] = int(out.get(recipe.input_ids[i], 0)) + recipe.input_amounts[i]
	if node is Building:
		var b := node as Building
		for slot in b._inventory:
			if slot.item_id != "" and slot.count > 0:
				out[slot.item_id] = int(out.get(slot.item_id, 0)) + int(slot.count)
	if "_held_item_id" in node and String(node.get("_held_item_id")) != "":
		var held := String(node.get("_held_item_id"))
		out[held] = int(out.get(held, 0)) + 1
	return out

## True when the player's inventory can take every item in `refund`. Checked before dismantling so nothing is
## ever destroyed for lack of space (the dismantle is refused instead, with a reason).
static func inventory_fits(refund: Dictionary) -> bool:
	var free_slots := 0
	var partial := {}
	for i in Inventory.GRID_SIZE:
		var slot: Dictionary = Inventory.get_slot({"kind": "grid", "index": i})
		if slot.item_id == "":
			free_slots += 1
		else:
			var def := Inventory.get_item_def(slot.item_id)
			var cap := def.max_stack if def != null else 100
			partial[slot.item_id] = int(partial.get(slot.item_id, 0)) + (cap - int(slot.count))
	for id: String in refund:
		var def := Inventory.get_item_def(id)
		var cap := def.max_stack if def != null else 100
		var left: int = maxi(int(refund[id]) - int(partial.get(id, 0)), 0)
		free_slots -= ceili(float(left) / float(cap))
	return free_slots >= 0

## Dismantle: refund into the inventory, unregister, free. Returns false (and changes nothing) if it won't fit.
static func dismantle(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var refund := refund_of(node)
	if not inventory_fits(refund):
		return false
	for id: String in refund:
		Inventory.add(id, int(refund[id]))
	remove(node)
	return true

## Take `node` out of the world and every registry (no refund). Used by dismantle and by destruction.
static func remove(node: Node3D) -> void:
	var item_id := String(node.get_meta(SaveManager.ITEM_ID_META, ""))
	var tree := node.get_tree()
	if node.is_in_group(SaveManager.SAVEABLE_GROUP):
		node.remove_from_group(SaveManager.SAVEABLE_GROUP)
	PipeNetwork.unregister_node(node)
	GameEvents.building_removed.emit(item_id, node)
	node.queue_free()
	# pipe chains are derived from geometry: rebuild once the node is really gone
	if tree != null and (node is PipeSegment or item_id in ["vacuum_pipe", "merger", "splitter"]):
		tree.process_frame.connect(func() -> void: PipeSegment.relink_all(tree), CONNECT_ONE_SHOT)
