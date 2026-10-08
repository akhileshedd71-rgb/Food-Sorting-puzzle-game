class_name BoardView
extends GridContainer

var trays: Array[TrayView] = []
var state: Dictionary = {}

func _ready() -> void:
	columns = 2
	add_theme_constant_override("h_separation", 24)
	add_theme_constant_override("v_separation", 36)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func bind(board_state: Dictionary, selected: Vector2i = Vector2i(-1, -1), hint: Vector2i = Vector2i(-1, -1), readable: bool = false) -> void:
	state = board_state
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
		trays[i].bind(i, state.trays[i], selected, hint, readable)

func hit_test(point: Vector2) -> Vector2i:
	for i in range(trays.size()):
		var slot := trays[i].hit_slot(point)
		if slot >= 0:
			return Vector2i(i, slot)
	return Vector2i(-1, -1)

func center_of(cell: Vector2i) -> Vector2:
	return trays[cell.x].slot_center(cell.y)
