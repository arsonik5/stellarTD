class_name Directive
extends Resource
## A Continuance contract (design/02-core-mechanics.md C7). Milestone directives are authored here as .tres in
## data/directives/ and form the spine after the tutorial quests; standing directives are generated at runtime by
## Progression with the same fields (as Dictionaries - see Progression._standing).
##
## DELIVER: complete once every item in `item_ids` has been delivered through an Uplink in `amounts`.
## PLACE:   complete once `amounts[0]` buildings of `item_ids[0]` have been placed.

enum Kind { DELIVER, PLACE }

@export var id: String
@export var title: String
## What the Continuance says when it issues this. Earnest, rationed, a little desperate (design/01-vision.md).
@export_multiline var message: String
@export var kind: Kind = Kind.DELIVER
@export var item_ids: Array[String] = []
@export var amounts: Array[int] = []
## Directive ids that must be complete first. Empty = available once the tutorial quest chain is done.
@export var prerequisite_ids: Array[String] = []
@export var reward_credit: int = 0
## e.g. {"engineering": 2}
@export var reward_research: Dictionary = {}
