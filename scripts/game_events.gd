extends Node
## GameEvents - the one signal bus (design/06-architecture.md A2).
##
## Producers emit here and never call consumers directly; quests, directives, research, statistics, audio and HUD
## subscribe. Adding a consumer must never require editing a producer. Autoloaded FIRST so every other autoload
## can connect in its _ready().
##
## Conventions: ids are item ids / action keys (strings), `source` is the node that caused it (may be null).

## A one-off gameplay action ("open_inventory", "toggle_autocraft", "place_block", "scan"...).
signal action(action_id: String, amount: int)
## The player's inventory gained / lost items (any cause: drill, pickup, take from machine, craft).
signal item_added(item_id: String, amount: int)
signal item_removed(item_id: String, amount: int)
## A building, pipe or foundation was put into / taken out of the world by the player.
signal building_placed(item_id: String, node: Node)
signal building_removed(item_id: String, node: Node)
## A machine finished a recipe.
signal item_crafted(item_id: String, amount: int, building: Node)
## Damage and destruction of anything carrying a Health component.
signal damaged(target: Node, amount: float, damage_type: String, source: Node)
signal destroyed(target: Node, source: Node)
## Player life cycle.
signal player_died(cause: String)
signal player_respawned
## Scanner pinged; `ore_ids` = distinct ore types it found.
signal scanned(ore_ids: Array)

## Shorthand for the commonest emit.
func act(action_id: String, amount: int = 1) -> void:
	action.emit(action_id, amount)
