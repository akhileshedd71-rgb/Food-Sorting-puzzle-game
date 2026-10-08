class_name PuzzleSolver
extends RefCounted
## Budgeted best-first graph search using the exact production command path.
## SOLVED includes an executable witness. Exhaustion alone proves UNSOLVABLE.
## Time and memory limits return UNKNOWN, never a false impossibility claim.

const MAX_STATES := 35000

static func solve(model: BoardModel, budget_ms: int = 100) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	if model.is_won():
		return {"status": "SOLVED", "moves": [], "states": 1, "elapsed_ms": 0}
	if budget_ms <= 0:
		return {"status": "UNKNOWN", "moves": [], "states": 0, "elapsed_ms": 0}
	var initial_key: String = model.search_key()
	var visited: Dictionary = {initial_key: true}
	var nodes: Array = [{"state": model.snapshot(), "parent": -1, "move": [], "depth": 0}]
	var frontier: Array = []
	_heap_push(frontier, {"priority": _score(model, 0), "index": 0})
	var worker := BoardModel.new()
	while not frontier.is_empty():
		if Time.get_ticks_msec() - started >= budget_ms or nodes.size() >= MAX_STATES:
			return _result("UNKNOWN", [], nodes.size(), started)
		var node_index: int = _heap_pop(frontier).index
		var node: Dictionary = nodes[node_index]
		worker.restore(node.state)
		var commands: Array = _distinct_commands(worker)
		for command in commands:
			if Time.get_ticks_msec() - started >= budget_ms:
				return _result("UNKNOWN", [], nodes.size(), started)
			worker.restore(node.state)
			if not worker.apply_move(command[0], command[1], command[2], command[3]):
				continue
			var key: String = worker.search_key()
			if visited.has(key):
				continue
			visited[key] = true
			var child_index: int = nodes.size()
			var depth: int = int(node.depth) + 1
			nodes.append({"state": worker.snapshot(), "parent": node_index, "move": command, "depth": depth})
			if worker.is_won():
				var path: Array = []
				var cursor: int = child_index
				while int(nodes[cursor].parent) >= 0:
					path.push_front(nodes[cursor].move.duplicate())
					cursor = int(nodes[cursor].parent)
				return _result("SOLVED", path, nodes.size(), started)
			if worker.state.outcome != "recovery":
				_heap_push(frontier, {"priority": _score(worker, depth), "index": child_index})
			if nodes.size() >= MAX_STATES:
				return _result("UNKNOWN", [], nodes.size(), started)
	return _result("UNSOLVABLE", [], nodes.size(), started)

static func _distinct_commands(model: BoardModel) -> Array:
	# Empty positions in one tray are interchangeable in rules v1. Matching
	# identities in a source tray are interchangeable too. Keep a concrete
	# legal command for each equivalence class, so witnesses remain replayable.
	var result: Array = []
	for source_tray in range(model.state.trays.size()):
		var seen_foods: Dictionary = {}
		for source_slot in range(3):
			var food: Variant = model.state.trays[source_tray].front[source_slot]
			if food == null or seen_foods.has(food):
				continue
			seen_foods[food] = true
			for target_tray in range(model.state.trays.size()):
				if target_tray == source_tray:
					continue
				var target_slot: int = model.state.trays[target_tray].front.find(null)
				if target_slot >= 0:
					result.append([source_tray, source_slot, target_tray, target_slot])
	return result

static func _score(model: BoardModel, depth: int) -> float:
	var fragmentation: int = 0
	var pairs: int = 0
	var queued: int = 0
	var free_trays: int = 0
	for tray in model.state.trays:
		var kinds: Dictionary = {}
		for food in tray.front:
			if food != null:
				kinds[food] = int(kinds.get(food, 0)) + 1
		fragmentation += kinds.size()
		queued += tray.queue.size()
		if kinds.is_empty():
			free_trays += 1
		for food in kinds:
			if kinds[food] == 2:
				pairs += 1
	# Deliberately a heuristic, not an admissible shortest-path claim.
	return float(model.remaining_tokens() * 20 + fragmentation * 4 + queued * 2 - pairs * 5 - free_trays * 2) + float(depth) * 0.2

static func _result(status: String, moves: Array, states: int, started: int) -> Dictionary:
	return {"status": status, "moves": moves, "states": states, "elapsed_ms": Time.get_ticks_msec() - started}

static func _less(a: Dictionary, b: Dictionary) -> bool:
	if a.priority == b.priority:
		return int(a.index) < int(b.index)
	return float(a.priority) < float(b.priority)

static func _heap_push(heap: Array, item: Dictionary) -> void:
	heap.append(item)
	var index: int = heap.size() - 1
	while index > 0:
		var parent: int = (index - 1) / 2
		if not _less(heap[index], heap[parent]):
			break
		var temporary: Dictionary = heap[parent]
		heap[parent] = heap[index]
		heap[index] = temporary
		index = parent

static func _heap_pop(heap: Array) -> Dictionary:
	var result: Dictionary = heap[0]
	var last: Dictionary = heap.pop_back()
	if heap.is_empty():
		return result
	heap[0] = last
	var index: int = 0
	while true:
		var left: int = index * 2 + 1
		if left >= heap.size():
			break
		var best: int = left
		var right: int = left + 1
		if right < heap.size() and _less(heap[right], heap[left]):
			best = right
		if not _less(heap[best], heap[index]):
			break
		var temporary: Dictionary = heap[index]
		heap[index] = heap[best]
		heap[best] = temporary
		index = best
	return result
