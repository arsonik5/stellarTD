class_name Quest
extends Resource

## COLLECT_ITEM: complete once Inventory.get_count(target_id) >= target_amount.
## PLACE_BUILDING: complete once `target_amount` buildings/pipes with item id
## target_id have been placed (see QuestManager.notify_building_placed).
## ACTION: complete once a one-off gameplay action (target_id is an action
## key like "open_inventory", not an item id) has fired `target_amount`
## times - see QuestManager.notify_action.
enum ObjectiveType { COLLECT_ITEM, PLACE_BUILDING, ACTION }

@export var id: String
@export var title: String
@export var description: String
@export var hint: String
## Quest ids that must be complete before this one activates. Empty = a root
## quest, active from the start.
@export var prerequisite_ids: Array[String] = []
@export var objective_type: ObjectiveType = ObjectiveType.COLLECT_ITEM
@export var target_id: String = ""
@export var target_amount: int = 1
