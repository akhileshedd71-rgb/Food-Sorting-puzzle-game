extends SceneTree
## Offline bounded candidate authoring, exact production solving and fresh replay.
## Accepted JSON is frozen. No generation executes in the running game.

const Model = preload("res://core/board_model.gd")
const Solver = preload("res://core/solver.gd")
const Validator = preload("res://core/level_validator.gd")
const Definition = preload("res://core/resources/level_definition.gd")
const Catalog = preload("res://core/level_catalog.gd")
const MAX_CANDIDATES: int = 96
const SEARCH_BUDGET_MS: int = 1500
var signatures: Dictionary = {}
var recipes: Dictionary = {}
var errors: Array[String] = []


func _initialize() -> void:
	var manifest: Dictionary = read_json("res://data/levels/legacy_manifest.json")
	for path in manifest.files:
		if FileAccess.get_sha256("res://" + path) != manifest.files[path]:
			push_error("Refusing to proceed: a preserved level changed: " + path)
			quit(1)
			return
	if FileAccess.get_sha256("res://" + manifest.report_file) != manifest.report_sha256:
		push_error("Refusing to proceed: original replay certificates changed")
		quit(1)
		return
	var legacy: Dictionary = read_json("res://data/levels/legacy_replay_report.json")
	var reports: Array = legacy.levels.duplicate(true)
	for number in range(1, 31):
		var level := read_json(Catalog.level_path(number))
		signatures[canonical_layout(level)] = level.level_id
	for recipe in Catalog.load_recipes():
		recipes[recipe.id] = recipe
	var plan: Dictionary = read_json("res://data/levels/expansion_plan.json")
	for spec in plan.levels:
		var result := author(spec)
		if result.is_empty():
			errors.append("No acceptable certified candidate for " + str(spec.level_id))
			print("FAILED ", spec.level_id)
			continue
		reports.append(result)
		print("CERTIFIED %s | %s | %d moves | %d tokens | candidate %d" % [
			result.level_id, spec.rhythm, result.moves, result.initial_tokens, result.candidate])
	var summary := legacy.duplicate(true)
	summary.generator = "tools/author_expansion.gd"
	summary.scope = "150 frozen campaign levels: 30 original authored boards and 120 offline generated, curated and machine-certified additions; no boosters"
	summary.levels = reports
	summary.passed = errors.is_empty() and reports.size() == 150
	summary.errors = errors
	summary["legacy_manifest"] = "data/levels/legacy_manifest.json"
	summary["candidate_search_budget_ms"] = SEARCH_BUDGET_MS
	summary["generated_content_human_review"] = "pending"
	write_json("res://data/levels/replay_report.json", summary)
	print("EXPANSION: %d certified levels, %d errors" % [reports.size(), errors.size()])
	quit(0 if errors.is_empty() else 1)


func author(spec: Dictionary) -> Dictionary:
	var path: String = Catalog.level_path(int(spec.number))
	var plan_hash: String = Model.canonical_json(spec).sha256_text()
	# An interrupted authoring run can safely reuse accepted frozen candidates.
	if FileAccess.file_exists(path):
		var existing := read_json(path)
		if existing.get("authoring", {}).get("plan_hash", "") == plan_hash:
			var key := canonical_layout(existing)
			if not signatures.has(key):
				var reused := replay(existing)
				if not reused.is_empty():
					signatures[key] = existing.level_id
					return reused
	for attempt in range(MAX_CANDIDATES):
		var level := candidate(spec, attempt)
		if level.is_empty() or not Validator.validate(level).is_empty():
			continue
		var signature := canonical_layout(level)
		if signatures.has(signature):
			continue
		var runtime_level: Dictionary = Definition.from_dictionary(level).to_dictionary()
		var model = Model.new()
		model.setup(runtime_level)
		var solved: Dictionary = Solver.solve(model, SEARCH_BUDGET_MS)
		if solved.get("status", "") != "SOLVED":
			continue
		var count: int = solved.moves.size()
		if count < int(spec.min_solution_moves) or count > int(spec.max_solution_moves):
			continue
		level.solution = solved.moves
		level.authoring["plan_hash"] = plan_hash
		level.authoring["solver_states"] = int(solved.get("states", 0))
		level.authoring["structural_signature"] = signature.sha256_text()
		level["content_hash"] = Model.canonical_json(level).sha256_text()
		var proof := replay(level)
		if proof.is_empty():
			continue
		write_json(path, level)
		signatures[signature] = level.level_id
		return proof
	return {}


func candidate(spec: Dictionary, attempt: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.seed) + attempt * 7919
	var palette: Array = spec.palette
	var batches: Dictionary = {}
	var total_batches: int = 0
	for food in palette:
		batches[food] = maxi(1, int(spec.required_batches.get(food, 0)))
		total_batches += int(batches[food])
	while total_batches < int(spec.batch_count):
		var food: String = palette[rng.randi_range(0, palette.size() - 1)]
		batches[food] = int(batches[food]) + 1
		total_batches += 1
	var tokens: Array = []
	for food in palette:
		for _piece in range(int(batches[food]) * 3):
			tokens.append(food)
	shuffle(tokens, rng)
	var trays: Array = []
	for index in range(int(spec.trays)):
		trays.append({"id": "tray_%d" % (index + 1), "front": [null, null, null], "queue": []})
	var positions: Array = range(trays.size() * 3)
	shuffle(positions, rng)
	for index in range(int(spec.free_slots), positions.size()):
		var position: int = int(positions[index])
		trays[position / 3].front[position % 3] = tokens.pop_back()
	for tray in trays:
		if is_triple(tray.front):
			return {}
	var eligible: Array = []
	for index in range(trays.size()):
		if trays[index].front.count(null) < 3:
			eligible.append(index)
	if not tokens.is_empty():
		var anchor: int = eligible[rng.randi_range(0, eligible.size() - 1)]
		for _depth in range(int(spec.max_rows) - 1):
			trays[anchor].queue.append([tokens.pop_back(), tokens.pop_back(), tokens.pop_back()])
	while not tokens.is_empty():
		var targets: Array = []
		for index in eligible:
			if trays[index].queue.size() < int(spec.max_rows) - 1:
				targets.append(index)
		if targets.is_empty():
			return {}
		var target: int = targets[rng.randi_range(0, targets.size() - 1)]
		trays[target].queue.append([tokens.pop_back(), tokens.pop_back(), tokens.pop_back()])
	if not spec.allow_cascade:
		for tray in trays:
			for row in tray.queue:
				if is_triple(row):
					return {}
	var tickets: Array = []
	for recipe_id in spec.recipe_ids:
		var recipe: Dictionary = recipes[recipe_id]
		tickets.append({"id": "ticket_%d" % (tickets.size() + 1), "recipe_id": recipe_id,
			"name": recipe.name, "requirements": recipe.requirements.duplicate(true)})
	return {
		"schema_version": 1, "content_version": 1, "level_id": spec.level_id,
		"number": int(spec.number), "chapter": int(spec.chapter), "title": spec.title,
		"title_key": "level.%s.title" % spec.level_id, "lesson": spec.lesson,
		"lesson_key": "level.%s.lesson" % spec.level_id,
		"mode": "campaign_orders" if not tickets.is_empty() else "campaign",
		"active_ticket_limit": 1, "timer_seconds": 0, "trays": trays, "tickets": tickets,
		"solution": [],
		"authoring": {
			"source": "Seeded offline candidate generation with an explicit chapter curriculum and production-resolver certification",
			"generator_version": 1, "seed": int(spec.seed), "candidate": attempt,
			"rhythm": spec.rhythm, "challenge": spec.rhythm == "challenge", "relief": spec.rhythm == "relief",
			"expected_trays": int(spec.trays), "expected_foods": palette.size(),
			"expected_max_rows": int(spec.max_rows), "expected_free_slots": int(spec.free_slots),
			"max_solution_moves": int(spec.max_solution_moves), "new_food": spec.new_food,
			"new_recipe": spec.new_recipe, "human_playtest_status": "pending",
		},
	}


func replay(level: Dictionary) -> Dictionary:
	if not Validator.validate(level).is_empty() or level.get("solution", []).is_empty():
		return {}
	var hash_input: Dictionary = level.duplicate(true)
	hash_input.erase("content_hash")
	if Model.canonical_json(hash_input).sha256_text() != level.get("content_hash", ""):
		return {}
	var model = Model.new()
	model.setup(Definition.from_dictionary(level).to_dictionary())
	var hashes: Array = [model.state_hash()]
	var cleared: int = 0
	var revealed: int = 0
	var served: int = 0
	var first_clear: int = -1
	var retrieval: bool = false
	var simultaneous: bool = false
	var cascade: bool = false
	var early_orders: bool = false
	var moved_slots: Dictionary = {}
	for index in range(level.solution.size()):
		var command: Array = level.solution[index]
		var source := "%d:%d" % [command[0], command[1]]
		retrieval = retrieval or moved_slots.has(source)
		moved_slots.erase(source)
		if not model.apply_move(command[0], command[1], command[2], command[3]):
			return {}
		moved_slots["%d:%d" % [command[2], command[3]]] = true
		var local_clears: int = 0
		var local_reveals: int = 0
		for event in model.last_events:
			match event.type:
				"cleared":
					cleared += 1
					local_clears += 1
					if first_clear < 0:
						first_clear = index + 1
				"revealed":
					revealed += 1
					local_reveals += 1
				"served":
					served += 1
			if event.type in ["cleared", "revealed"]:
				for slot in range(3):
					moved_slots.erase("%d:%d" % [event.tray, slot])
		simultaneous = simultaneous or (local_clears > 0 and local_reveals > 0)
		cascade = cascade or local_clears > 1
		early_orders = early_orders or (served > 0 and served == level.tickets.size() and model.remaining_tokens() > 0)
		hashes.append(model.state_hash())
	if not model.is_won() or model.remaining_tokens() != 0:
		return {}
	return {
		"level_id": level.level_id, "status": "PASS", "content_hash": level.content_hash,
		"moves": level.solution.size(), "initial_tokens": int(model.state.initial_total), "remaining_tokens": 0,
		"cleared_batches": cleared, "revealed_rows": revealed, "served_tickets": served,
		"first_clear_move": first_clear, "temporary_placement_witness": first_clear > 1,
		"retrieval_witness": retrieval, "simultaneous_reveal_and_clear": simultaneous,
		"automatic_cascade_witness": cascade, "orders_completed_before_board_clear": early_orders,
		"state_hashes": hashes, "final_state_hash": model.state_hash(),
		"candidate": int(level.authoring.candidate), "seed": int(level.authoring.seed),
		"rhythm": level.authoring.rhythm, "human_playtest_status": "pending",
	}


func canonical_layout(level: Dictionary) -> String:
	var foods: Array = []
	for tray in level.trays:
		for row in [tray.front] + tray.queue:
			for food in row:
				if food != null and not foods.has(food):
					foods.append(food)
	var best: String = ""
	for order in permutations(foods):
		var mapping: Dictionary = {}
		for index in range(order.size()):
			mapping[order[index]] = str(index + 1)
		var trays: Array[String] = []
		for tray in level.trays:
			var rows: Array[String] = []
			for row in [tray.front] + tray.queue:
				var slots: Array[String] = []
				for food in row:
					slots.append("0" if food == null else mapping[food])
				slots.sort()
				rows.append("".join(slots))
			trays.append("/".join(rows))
		trays.sort()
		var encoded := "|".join(trays)
		if best.is_empty() or encoded < best:
			best = encoded
	return best


func permutations(values: Array) -> Array:
	if values.is_empty():
		return [[]]
	var result: Array = []
	for index in range(values.size()):
		var remainder: Array = values.duplicate()
		var first: Variant = remainder.pop_at(index)
		for tail in permutations(remainder):
			result.append([first] + tail)
	return result


func shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[other]
		values[other] = value


func is_triple(row: Array) -> bool:
	return row[0] != null and row[0] == row[1] and row[1] == row[2]


func read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(normalize_numbers(value), "  ") + "\n")


func normalize_numbers(value: Variant) -> Variant:
	# Keep human-readable JSON integral fields integral without depending on
	# private production-model helpers. Content hashes still use its public API.
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(normalize_numbers(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = normalize_numbers(value[key])
		return result
	return value
