class_name ItemIcon
extends Control
## An item's picture, wherever items appear (slots, build cards, recipes, the pickup feed). Uses the baked icon
## when one exists (ItemInfo.icon), otherwise a stand-in glyph that still tells things apart at a glance:
##   materials  - a faceted chunk in the item's own colour (iron grey, copper brown ...), ingots as a bar
##   everything else - a category-coloured frame with the item's initials
## A count sits bottom-right, outlined. Never takes mouse input: the slot or card around it does.

var item_id := "":
	set(v):
		item_id = v
		queue_redraw()
var count := 0:
	set(v):
		count = v
		queue_redraw()

func _init(id: String = "", n: int = 0) -> void:
	item_id = id
	count = n
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	if item_id == "":
		return
	var r := Rect2(Vector2.ZERO, size).grow(-4.0)
	var tex := ItemInfo.icon(item_id)
	if tex != null:
		draw_texture_rect(tex, r, false)
	else:
		_glyph(r)
	if count > 1:
		var font := get_theme_font("font", "HudLabel")
		var fs := 13
		var t := str(count)
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := Vector2(size.x - w - 5, size.y - 5)
		draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
		draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTokens.TEXT)

func _glyph(r: Rect2) -> void:
	var col := ItemInfo.color(item_id)
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y) * 0.5
	if ItemInfo.category(item_id) == "material":
		var refined := item_id.begins_with("refined") or item_id in ["copper_casing", "piercing_core"]
		if refined:
			# ingot: a trapezoid bar, lit top face
			var top := PackedVector2Array([c + Vector2(-s * 0.55, -s * 0.25), c + Vector2(s * 0.55, -s * 0.25), c + Vector2(s * 0.75, s * 0.1), c + Vector2(-s * 0.75, s * 0.1)])
			var front := PackedVector2Array([c + Vector2(-s * 0.75, s * 0.1), c + Vector2(s * 0.75, s * 0.1), c + Vector2(s * 0.75, s * 0.4), c + Vector2(-s * 0.75, s * 0.4)])
			draw_colored_polygon(front, col.darkened(0.35))
			draw_colored_polygon(top, col.lightened(0.15))
		else:
			# ore chunk: an irregular faceted lump, three shades for painted light
			var pts := PackedVector2Array([c + Vector2(-s * 0.7, s * 0.1), c + Vector2(-s * 0.35, -s * 0.55), c + Vector2(s * 0.3, -s * 0.6), c + Vector2(s * 0.72, -s * 0.05), c + Vector2(s * 0.45, s * 0.55), c + Vector2(-s * 0.3, s * 0.6)])
			draw_colored_polygon(pts, col.darkened(0.25))
			draw_colored_polygon(PackedVector2Array([pts[1], pts[2], pts[3], c]), col.lightened(0.1))
			draw_colored_polygon(PackedVector2Array([pts[0], pts[1], c, pts[5]]), col)
		return
	# frame + initials
	var box := Rect2(c - Vector2(s, s) * 0.8, Vector2(s, s) * 1.6)
	draw_rect(box, Color(col, 0.14))
	draw_rect(box, col, false, 2.0)
	var item := Inventory.get_item_def(item_id)
	var words := (item.display_name if item != null else item_id).split(" ", false)
	var initials := ""
	for w in words:
		if w.length() > 0 and (w[0] >= "A" and w[0] <= "Z" or w[0] >= "0" and w[0] <= "9"):
			initials += w[0]
		if initials.length() == 2:
			break
	if initials == "":
		initials = (item.display_name if item != null else item_id).substr(0, 2).to_upper()
	var font := get_theme_font("font", "TitleLabel")
	var fs := int(s * 0.7)
	if fs < 1:                                          # not sized yet
		return
	var w := font.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
