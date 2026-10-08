class_name TrayView
extends Control

var tray_index: int = 0
var tray_data: Dictionary = {}
var slot_rects: Array[Rect2] = []
var selected_slot: int = -1
var valid_targets: bool = false
var hint_slot: int = -1
var high_readability: bool = false
var food_nodes: Array[Control] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_layout()

func bind(index: int, data: Dictionary, selected: Vector2i, hint: Vector2i, readability: bool) -> void:
	tray_index = index
	tray_data = data
	selected_slot = selected.y if selected.x == index else -1
	valid_targets = selected.x >= 0 and selected.x != index
	hint_slot = hint.y if hint.x == index else -1
	high_readability = readability
	for c in get_children():
		remove_child(c)
		c.queue_free()
	food_nodes.clear()
	for i in range(3):
		var food: Variant = data.front[i]
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(holder)
		food_nodes.append(holder)
		if food != null:
			var icon := FoodArt.icon(str(food))
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon.custom_minimum_size = Vector2.ZERO
			icon.scale = Vector2(1.18, 1.18)
			icon.offset_left = -8
			icon.offset_top = -7
			holder.add_child(icon)
			if high_readability:
				var name_label := GardenUI.label(FoodArt.title(str(food)), 14, GardenUI.INK, true)
				name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
				name_label.offset_top = -22
				holder.add_child(name_label)
	if not data.queue.is_empty():
		for i in range(3):
			var food: Variant = data.queue[0][i]
			if food != null:
				var icon := FoodArt.icon(str(food), 34)
				icon.name = "Preview%d" % i
				icon.modulate = Color(1, 1, 1, 0.78)
				add_child(icon)
		var depth := GardenUI.label("+%d" % data.queue.size(), 18, GardenUI.CREAM, true)
		depth.name = "Depth"
		add_child(depth)
	_layout()

func _layout() -> void:
	if not is_inside_tree():
		return
	slot_rects.clear()
	var sw := (size.x - 24.0) / 3.0
	for i in range(3):
		var rect := Rect2(12 + i * sw, 12, sw, 108)
		slot_rects.append(rect)
		if i < food_nodes.size():
			food_nodes[i].position = rect.position + Vector2(0, -6 if selected_slot == i else 0)
			food_nodes[i].size = rect.size
		var preview := get_node_or_null("Preview%d" % i) as Control
		if preview:
			preview.position = Vector2(size.x * 0.24 + i * 40, 151)
			preview.size = Vector2(36, 36)
	var depth := get_node_or_null("Depth") as Control
	if depth:
		depth.position = Vector2(size.x * 0.76, 157)
	queue_redraw()

func _draw() -> void:
	if tray_data.is_empty():
		return
	var width := size.x
	# Ceramic foot, blue enamel rim and inset steel surface.
	draw_style_box(GardenUI.box(Color("493b30"), 13), Rect2(14, 112, width - 28, 32))
	draw_style_box(GardenUI.box(Color("24637b"), 17, Color("154256"), 2, 4), Rect2(0, 15, width, 125))
	draw_string(GardenUI.BODY, Vector2(17, 134), str(tray_index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("cde2e2"))
	draw_style_box(GardenUI.box(Color("d3d9d5"), 17, Color("fffbed"), 4), Rect2(0, 0, width, 123))
	draw_style_box(GardenUI.box(Color("a7b4b0"), 12, Color("899b97"), 2), Rect2(9, 9, width - 18, 105))
	for i in range(slot_rects.size()):
		var r := slot_rects[i].grow(-4)
		r.position.y = 14
		r.size.y = 94
		draw_style_box(GardenUI.box(Color("c9d1c9"), 10, Color("b3bdb5"), 1), r)
		if tray_data.front[i] == null:
			draw_circle(r.get_center(), 15, Color("b7c1b8"))
			draw_line(r.get_center() - Vector2(6, 0), r.get_center() + Vector2(6, 0), Color("99a99f"), 2, true)
			draw_line(r.get_center() - Vector2(0, 6), r.get_center() + Vector2(0, 6), Color("99a99f"), 2, true)
			if valid_targets:
				draw_style_box(GardenUI.box(Color(0.3, 0.65, 0.4, 0.14), 12, Color("e8ff9f"), 3), r)
		if selected_slot == i or hint_slot == i:
			draw_style_box(GardenUI.box(Color(1, 0.9, 0.4, 0.13), 12, GardenUI.GOLD, 4), r)
	if not tray_data.queue.is_empty():
		var preview_rect := Rect2(width * 0.21, 149, width * 0.54, 40)
		for n in range(mini(3, tray_data.queue.size()) - 1, -1, -1):
			draw_style_box(GardenUI.box(Color("f3eee0").darkened(n * 0.05), 5, Color("c9c2af"), 2), Rect2(preview_rect.position + Vector2(0, n * 5), preview_rect.size))

func hit_slot(global_point: Vector2) -> int:
	var local_point := get_global_transform_with_canvas().affine_inverse() * global_point
	for i in range(slot_rects.size()):
		if slot_rects[i].has_point(local_point):
			return i
	return -1

func slot_center(slot: int) -> Vector2:
	return get_global_transform_with_canvas() * slot_rects[slot].get_center()
