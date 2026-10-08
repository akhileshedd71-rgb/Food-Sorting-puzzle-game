class_name LevelValidator
extends RefCounted
## Reject malformed or unsupported content before constructing typed Resources.

const FOOD_CATALOG = preload("res://core/food_catalog.gd")

static func validate(level: Dictionary) -> Array:
	var errors: Array = []
	if level.get("schema_version") != 1:
		errors.append("schema_version must be 1")
	if not _positive_integer(level.get("content_version")):
		errors.append("content_version must be a positive integer")
	if not _identifier(level.get("level_id")):
		errors.append("level_id must be a nonempty stable string")
	if level.get("mode") not in ["campaign", "campaign_orders"]:
		errors.append("Unsupported mode: only untimed campaign and campaign_orders are implemented")
	if level.get("timer_seconds", 0) != 0:
		errors.append("timer_seconds is unsupported in the untimed campaign")
	if not _positive_integer(level.get("active_ticket_limit", 1)) or int(level.get("active_ticket_limit", 1)) < 1 or int(level.get("active_ticket_limit", 1)) > 2:
		errors.append("active_ticket_limit must be 1 or 2")
	for key in ["constraints", "locks", "move_limit", "generator", "covered_previews", "blockers"]:
		if _nonempty(level.get(key)):
			errors.append("Unsupported level mechanic: " + key)
	var tray_data: Variant = level.get("trays")
	if not tray_data is Array:
		errors.append("trays must be an array")
		return errors
	if tray_data.size() < 2 or tray_data.size() > 8:
		errors.append("Campaign levels need 2 to 8 trays")
	var tray_ids: Dictionary = {}
	var inventory: Dictionary = {}
	var free_count: int = 0
	for index in range(tray_data.size()):
		var tray: Variant = tray_data[index]
		var location: String = "trays[%d]" % index
		if not tray is Dictionary:
			errors.append(location + " must be a dictionary")
			continue
		var id: Variant = tray.get("id")
		if not _identifier(id):
			errors.append(location + ".id must be a stable string")
		elif tray_ids.has(id):
			errors.append("Duplicate tray ID: " + str(id))
		else:
			tray_ids[id] = true
		for key in ["allowed_food_tags", "tray_identity_tags", "initial_seal", "seal", "lock", "locks", "covered", "hot", "frozen", "blocker"]:
			if _nonempty(tray.get(key)):
				errors.append(location + ": unsupported tray mechanic " + key)
		var front_valid: bool = _validate_row(tray.get("front"), location + ".front", inventory, errors)
		if front_valid:
			var front: Array = tray.front
			free_count += front.count(null)
			if front[0] != null and front[0] == front[1] and front[1] == front[2]:
				errors.append(location + ".front starts with an automatic triple; initial board must be stable")
		var queue: Variant = tray.get("queue")
		if not queue is Array:
			errors.append(location + ".queue must be an array of three-position rows")
			continue
		if queue.size() > 20:
			errors.append(location + ".queue exceeds the supported authoring depth (20)")
		if front_valid and tray.front.count(null) == 3 and not queue.is_empty():
			errors.append(location + ": empty front with a queue is not a stable starting state")
		for row_index in range(queue.size()):
			var row_location: String = location + ".queue[%d]" % row_index
			if _validate_row(queue[row_index], row_location, inventory, errors):
				if queue[row_index].count(null) == 3:
					errors.append(row_location + " cannot be wholly empty")
	var total: int = 0
	for food in inventory:
		var count: int = inventory[food]
		total += count
		if count % 3 != 0:
			errors.append("Food %s has %d tokens; totals must be divisible by three" % [food, count])
	if total == 0:
		errors.append("Level contains no food")
	if total > 0 and free_count == 0:
		errors.append("Starting board has no empty active slot")
	var ticket_data: Variant = level.get("tickets", [])
	if not ticket_data is Array:
		errors.append("tickets must be an array")
		return errors
	if level.get("mode") == "campaign_orders" and ticket_data.is_empty():
		errors.append("campaign_orders requires a finite nonempty ticket queue")
	if level.get("mode") == "campaign" and not ticket_data.is_empty():
		errors.append("Levels containing tickets must use campaign_orders mode")
	var ticket_ids: Dictionary = {}
	var demand: Dictionary = {}
	for index in range(ticket_data.size()):
		var ticket: Variant = ticket_data[index]
		var location: String = "tickets[%d]" % index
		if not ticket is Dictionary:
			errors.append(location + " must be a dictionary")
			continue
		var id: Variant = ticket.get("id")
		if not _identifier(id):
			errors.append(location + ".id must be a stable string")
		elif ticket_ids.has(id):
			errors.append("Duplicate ticket ID: " + str(id))
		else:
			ticket_ids[id] = true
		var requirements: Variant = ticket.get("requirements")
		if not requirements is Dictionary or requirements.is_empty():
			errors.append(location + ".requirements must be a nonempty food-to-batches dictionary")
			continue
		for food in requirements:
			if not food is String or not FOOD_CATALOG.has_food(food):
				errors.append(location + ": unknown recipe food " + str(food))
			if not _positive_integer(requirements[food]):
				errors.append(location + ": recipe batch quantities must be positive integers")
			else:
				demand[food] = int(demand.get(food, 0)) + int(requirements[food])
		for key in ["tray_tag", "deadline", "random", "credits", "served"]:
			if _nonempty(ticket.get(key)):
				errors.append(location + ": unsupported authored ticket field " + key)
	for food in demand:
		if int(demand[food]) * 3 > int(inventory.get(food, 0)):
			errors.append("Insufficient inventory for all recipe demand: " + str(food))
	var solution: Variant = level.get("solution", [])
	if not solution is Array:
		errors.append("solution must be an array of commands")
	else:
		for command in solution:
			if not command is Array or command.size() != 4:
				errors.append("Solution commands must be four-integer arrays")
				continue
			for value in command:
				if not _nonnegative_integer(value):
					errors.append("Solution command coordinates must be nonnegative integers")
	return errors

static func _validate_row(row: Variant, location: String, inventory: Dictionary, errors: Array) -> bool:
	if not row is Array or row.size() != 3:
		errors.append(location + " must contain exactly three nullable food IDs")
		return false
	for food in row:
		if food == null:
			continue
		if not food is String or not FOOD_CATALOG.has_food(food):
			errors.append(location + ": unknown or unsupported token " + str(food))
			continue
		inventory[food] = int(inventory.get(food, 0)) + 1
	return true

static func _identifier(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _nonnegative_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) == floor(float(value))

static func _positive_integer(value: Variant) -> bool:
	return _nonnegative_integer(value) and float(value) > 0

static func _nonempty(value: Variant) -> bool:
	if value == null:
		return false
	if value is Array or value is Dictionary or value is String:
		return not value.is_empty()
	return bool(value)
