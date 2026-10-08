class_name BoardModel
extends RefCounted
## The single authoritative, deterministic rule engine. UI consumes its events.
## Stable snapshots own every value; no animation, clock or Node affects rules.

const RULES_VERSION := 1
const DEFAULT_TUNING = preload("res://data/tuning/default.tres")

var state: Dictionary = {}
var history: Array = []
var last_events: Array = []
var undo_capacity: int = DEFAULT_TUNING.undo_capacity

func setup(level: Dictionary) -> void:
	history.clear()
	last_events.clear()
	state = {
		"schema_version": int(level.get("schema_version", 1)),
		"content_version": int(level.get("content_version", 1)),
		"rules_version": RULES_VERSION,
		"level_id": str(level.get("level_id", "")),
		"mode": str(level.get("mode", "campaign")),
		"trays": level.get("trays", []).duplicate(true),
		"tickets": [], "moves": 0, "batches": 0, "sequence": 0,
		"initial_total": 0, "outcome": "ready",
		"active_ticket_limit": int(level.get("active_ticket_limit", 1)),
	}
	for ticket_data in level.get("tickets", []):
		var ticket: Dictionary = ticket_data.duplicate(true)
		ticket["name"] = str(ticket.get("name", ticket.get("id", "Recipe")))
		ticket["credits"] = {}
		for food in ticket.get("requirements", {}):
			ticket.credits[food] = 0
		ticket["served"] = false
		state.tickets.append(ticket)
	state.initial_total = remaining_tokens()
	_evaluate_outcome()
	last_events.clear()

func apply_move(source_tray: int, source_slot: int, target_tray: int, target_slot: int) -> bool:
	if not _is_legal(source_tray, source_slot, target_tray, target_slot):
		return false
	var previous: Dictionary = snapshot()
	last_events = []
	var food: String = state.trays[source_tray].front[source_slot]
	state.trays[source_tray].front[source_slot] = null
	state.trays[target_tray].front[target_slot] = food
	state.moves = int(state.moves) + 1
	last_events.append({"type": "moved", "food": food,
		"source_tray": source_tray, "source_slot": source_slot,
		"target_tray": target_tray, "target_slot": target_slot, "tray": target_tray})
	if not _resolve():
		state = previous
		last_events = [{"type": "content_error", "message": "Resolution bound exceeded"}]
		push_error("Food board resolution exceeded its finite content bound")
		return false
	history.append(previous)
	while history.size() > undo_capacity:
		history.pop_front()
	_evaluate_outcome()
	return true

func undo() -> bool:
	if history.is_empty():
		return false
	state = history.pop_back().duplicate(true)
	last_events = []
	return true

func snapshot() -> Dictionary:
	return state.duplicate(true)

func restore(saved: Dictionary) -> void:
	state = saved.duplicate(true)
	history = []
	last_events = []

func state_hash() -> String:
	return canonical_json(state).sha256_text()

func search_key() -> String:
	var logical: Dictionary = snapshot()
	for counter in ["moves", "batches", "sequence", "initial_total", "outcome"]:
		logical.erase(counter)
	# Slots have no identities/restrictions in rules v1. Canonicalize equivalent
	# slot arrangements; tray identities and queue order remain significant.
	for tray in logical.trays:
		var slots: Array = tray.front.duplicate()
		slots.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		tray.front = slots
	return canonical_json(logical).sha256_text()

func is_won() -> bool:
	return state.get("outcome", "") == "won"

func remaining_tokens() -> int:
	var count: int = 0
	for tray in state.get("trays", []):
		for food in tray.front:
			if food != null:
				count += 1
		for row in tray.queue:
			for food in row:
				if food != null:
					count += 1
	return count

func legal_moves() -> Array:
	var result: Array = []
	if state.get("outcome", "") == "won":
		return result
	for source_tray in range(state.get("trays", []).size()):
		for source_slot in range(3):
			if state.trays[source_tray].front[source_slot] == null:
				continue
			for target_tray in range(state.trays.size()):
				if source_tray == target_tray:
					continue
				for target_slot in range(3):
					if state.trays[target_tray].front[target_slot] == null:
						result.append([source_tray, source_slot, target_tray, target_slot])
	return result

func _is_legal(source_tray: int, source_slot: int, target_tray: int, target_slot: int) -> bool:
	if state.is_empty() or is_won() or source_tray == target_tray:
		return false
	if source_tray < 0 or source_tray >= state.trays.size() or target_tray < 0 or target_tray >= state.trays.size():
		return false
	if source_slot < 0 or source_slot > 2 or target_slot < 0 or target_slot > 2:
		return false
	return state.trays[source_tray].front[source_slot] != null and state.trays[target_tray].front[target_slot] == null

func _resolve() -> bool:
	var queue_rows: int = 0
	for tray in state.trays:
		queue_rows += tray.queue.size()
	# Every changing pass consumes a triple, promotes a queued row, or both.
	var bound: int = remaining_tokens() / 3 + queue_rows + 2
	var tray_order: Array = range(state.trays.size())
	tray_order.sort_custom(func(a: int, b: int) -> bool: return str(state.trays[a].id) < str(state.trays[b].id))
	for _pass in range(bound):
		var changed: bool = false
		var batches: Array = []
		for tray_index in tray_order:
			var row: Array = state.trays[tray_index].front
			if row[0] != null and row[0] == row[1] and row[1] == row[2]:
				var food: String = row[0]
				state.trays[tray_index].front = [null, null, null]
				state.batches = int(state.batches) + 1
				state.sequence = int(state.sequence) + 1
				var batch: Dictionary = {"type": "cleared", "tray": tray_index,
					"food": food, "event_id": "%s:batch:%d" % [state.level_id, state.sequence]}
				last_events.append(batch)
				batches.append(batch)
				changed = true
		for batch in batches:
			_allocate_batch(batch)
		_serve_ready_tickets()
		for tray_index in tray_order:
			var tray: Dictionary = state.trays[tray_index]
			if _row_empty(tray.front) and not tray.queue.is_empty():
				tray.front = tray.queue.pop_front().duplicate(true)
				last_events.append({"type": "revealed", "tray": tray_index,
					"row": tray.front.duplicate(), "food": ""})
				changed = true
		if not changed:
			return true
	return false

func _allocate_batch(batch: Dictionary) -> void:
	var active_indices: Array = _active_ticket_indices()
	for ticket_index in range(state.tickets.size()):
		var ticket: Dictionary = state.tickets[ticket_index]
		var required: int = int(ticket.requirements.get(batch.food, 0))
		var credit: int = int(ticket.credits.get(batch.food, 0))
		if not ticket.served and credit < required:
			ticket.credits[batch.food] = credit + 1
			last_events.append({"type": "allocated", "ticket": ticket_index,
				"ticket_id": ticket.id, "food": batch.food, "event_id": batch.event_id,
				"prepared": not active_indices.has(ticket_index)})
			return

func _active_ticket_indices() -> Array:
	var active: Array = []
	for index in range(state.tickets.size()):
		if not state.tickets[index].served:
			active.append(index)
			if active.size() >= int(state.active_ticket_limit):
				break
	return active

func _serve_ready_tickets() -> void:
	# Serving opens an active slot. Repeat so a fully prepared future ticket
	# can serve in this same atomic command, never in an animation callback.
	for _pass in range(state.tickets.size() + 1):
		var served_any: bool = false
		for index in _active_ticket_indices():
			var ticket: Dictionary = state.tickets[index]
			var complete: bool = true
			for food in ticket.requirements:
				if int(ticket.credits.get(food, 0)) < int(ticket.requirements[food]):
					complete = false
					break
			if complete:
				ticket.served = true
				last_events.append({"type": "served", "ticket": index, "ticket_id": ticket.id})
				served_any = true
		if not served_any:
			return

func _evaluate_outcome() -> void:
	var complete: bool = remaining_tokens() == 0
	for ticket in state.get("tickets", []):
		if not ticket.served:
			complete = false
	if complete:
		if state.outcome != "won":
			last_events.append({"type": "won", "level_id": state.level_id})
		state.outcome = "won"
	else:
		state.outcome = "ready"
		if legal_moves().is_empty():
			state.outcome = "recovery"

static func _row_empty(row: Array) -> bool:
	return row[0] == null and row[1] == null and row[2] == null

static func canonical_json(value: Variant) -> String:
	# JSON decoding uses floats. Normalize integral numeric values before
	# encoding, then sort keys recursively for portable replay checksums.
	return JSON.stringify(_canonical_value(value), "", true, true)

static func _canonical_value(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_canonical_value(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = _canonical_value(value[key])
		return result
	return value
