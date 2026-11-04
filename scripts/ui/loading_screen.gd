extends CanvasLayer

## Covers world generation on entry and hides itself the moment the player
## actually has ground under them.
##
## Gated on Player.is_spawn_resolved() rather than a timer or a frame count:
## that flag already means "terrain data exists here AND a collider was found",
## which is the only definition of ready that matters. A timed screen would
## either uncover an unfinished world or sit there after it was done.

var _label: Label
var _detail: Label
var _elapsed := 0.0

## Set by Planet during the erosion bake. Without it a first-time bake is ~56 s
## of an apparently frozen window - the bake yields between batches so this
## screen can actually draw, and this is what it draws.
var _fraction := 0.0
var _stage := ""
var _bar: ProgressBar

func set_progress(fraction: float, label: String) -> void:
	_fraction = clampf(fraction, 0.0, 1.0)
	_stage = label

const TIPS := [
	"Your suit holds five minutes of air. A Ship Garage refills it.",
	"Hold the drill's trigger: it spins up, then cuts.",
	"Foundations snap to each other. Build on them and machines line up.",
	"Pipes bend themselves at corners. Press B for free angles.",
	"F switches your helmet lamp on and off.",
	"Shift+click moves a whole stack between a machine and your storage.",
	"A sealed cockpit breathes from the ship's oxygen tanks. An open seat doesn't.",
]

func _ready() -> void:
	add_to_group("loading_screen")
	layer = 100
	var bg := ColorRect.new()
	bg.color = UiTokens.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# no name, no logo (decided later): the job bottom-left, one useful tip bottom-right, nothing else
	var tip_box := UiKit.vbox(4)
	tip_box.anchor_left = 1.0
	tip_box.anchor_right = 1.0
	tip_box.anchor_top = 1.0
	tip_box.anchor_bottom = 1.0
	tip_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tip_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tip_box.offset_right = -UiTokens.EDGE
	tip_box.offset_bottom = -56
	add_child(tip_box)
	var tip_cap := UiKit.label("TIP", "SectionLabel")
	tip_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tip_box.add_child(tip_cap)
	var tip := UiKit.label(TIPS[randi() % TIPS.size()], "DimLabel")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size.x = 440
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tip_box.add_child(tip)
	var box := UiKit.vbox(6)
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_left = UiTokens.EDGE
	box.offset_bottom = -56
	box.offset_right = 560
	add_child(box)

	box.add_child(UiKit.label("COLONY  /", "CrumbLabel"))
	_label = UiKit.title("Landing")
	box.add_child(_label)
	box.add_child(UiKit.rule())

	_detail = UiKit.label("", "CrumbLabel")
	box.add_child(_detail)

	_bar = UiKit.bar("", 2)
	_bar.custom_minimum_size = Vector2(420, 2)
	# Hidden until there is something to report: a cached load takes 0.45 s and
	# a bar that flashes on and off is worse than none.
	_bar.visible = false
	box.add_child(_bar)

func _process(delta: float) -> void:
	_elapsed += delta
	if _fraction > 0.0:
		_bar.visible = true
		_bar.value = _fraction
	_detail.text = "GENERATING THE PLANET   ·   %.0f S" % _elapsed if _stage.is_empty() 		else "%s   %.0f%%   ·   %.0f S" % [_stage.to_upper(), _fraction * 100.0, _elapsed]
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("is_spawn_resolved") and player.is_spawn_resolved():
		TerrainLog.write("load", "TIME TO PLAYABLE: %.2f s" % _elapsed)
		TerrainLog.close()
		queue_free()
