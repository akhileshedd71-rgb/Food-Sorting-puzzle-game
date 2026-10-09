class_name BoardView
extends GridContainer

var trays: Array[TrayView] = []
var state: Dictionary = {}
var finish: Dictionary = {}

func _ready() -> void:
	columns = 2
	add_theme_constant_override("h_separation", 24)
	add_theme_constant_override("v_separation", 36)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func bind(board_state: Dictionary, selected: Vector2i = Vector2i(-1, -1), hint: Vector2i = Vector2i(-1, -1), readable: bool = false) -> void:
	state = board_state
	add_theme_constant_override("v_separation", 6 if state.trays.size() > 6 else 36)
	if trays.size() != state.trays.size():
		for child in get_children():
			remove_child(child)
			child.queue_free()
		trays.clear()
		for i in range(state.trays.size()):
			var tray := TrayView.new()
			tray.custom_minimum_size = Vector2(0, 204)
			tray.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			add_child(tray)
			trays.append(tray)
	for i in range(trays.size()):
		trays[i].rim_color = finish.get("rim", Color("24637b"))
		trays[i].accent_color = finish.get("accent", Color("d3d9d5"))
		trays[i].bind(i, state.trays[i], selected, hint, readable)

func hit_test(point: Vector2) -> Vector2i:
	for i in range(trays.size()):
		var slot := trays[i].hit_slot(point)
		if slot >= 0:
			return Vector2i(i, slot)
	return Vector2i(-1, -1)

func center_of(cell: Vector2i) -> Vector2:
	return trays[cell.x].slot_center(cell.y)
