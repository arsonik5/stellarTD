class_name ResearchNode
extends Resource
## One unlock in the research tree (design C7 / M27). Bought with research data points earned by DOING things
## for the first time (Progression.award_first). Items listed in `unlocks` cannot be built until it is bought.

@export var id: String
@export var title: String
@export_multiline var description: String
## {"geology": n, "engineering": n, "xeno": n}
@export var cost: Dictionary = {}
@export var prerequisite_ids: Array[String] = []
## Building/item ids this makes buildable.
@export var unlocks: Array[String] = []
