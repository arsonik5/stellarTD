extends Node

## Regression: rows animated in with "y" while their container had not laid them out yet used to remember y = 0 as
## their rest position, and later opens animated every row onto the top one ("rows spawn on each other").
func _ready() -> void:
	var holder := Control.new()
	holder.size = Vector2(400, 600)
	add_child(holder)
	var box := VBoxContainer.new()
	box.size = Vector2(300, 400)
	holder.add_child(box)
	var rows: Array = []
	for i in 5:
		var l := Label.new()
		l.text = "row %d" % i
		l.custom_minimum_size.y = 40
		box.add_child(l)
		rows.append(l)
	# first open: the control tree is hidden, so no layout has happened yet
	holder.visible = false
	UiMotion.animate(rows, {"opacity": [0.0, 1.0], "y": [16, 0]}, {"duration": 0.2})
	await get_tree().create_timer(0.6).timeout
	holder.visible = true
	await get_tree().create_timer(0.2).timeout
	# second open
	UiMotion.animate(rows, {"opacity": [0.0, 1.0], "y": [16, 0]}, {"duration": 0.2})
	await get_tree().create_timer(0.8).timeout
	var ys := []
	for r: Control in rows:
		ys.append(snappedf(r.position.y, 1.0))
	print("row y after second open: ", ys)
	var ok := true
	for i in rows.size():
		if absf((rows[i] as Control).position.y - 44.0 * i) > 1.0:
			ok = false
	print("MOTIONROWS ", "PASS" if ok else "FAIL")
	get_tree().quit()
