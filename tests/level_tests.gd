extends SceneTree
## Campaign content regression: schemas, inventory, diversity, saved replay proofs.

const Catalog = preload("res://core/level_catalog.gd")
const Model = preload("res://core/board_model.gd")
const Validator = preload("res://core/level_validator.gd")
var checks: int = 0
var failures: Array[String] = []
var layout_signatures: Dictionary = {}


func _initialize() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/replay_report.json"))
	check(report.get("passed", false), "Published replay report passed")
	check(report.get("levels", []).size() == 30, "Exactly thirty replay certificates")
	check(Catalog.load_recipes().size() == 4, "Exactly four recipe bundles")
	for number in range(1, 31):
		test_level(number, report.get("levels", [])[number - 1])
	check(report.levels[0].moves == 1, "First level teaches a single guided move")
	check(report.levels[4].temporary_placement_witness, "Level 5 stores food before its first clear")
	check(report.levels[8].automatic_cascade_witness, "Level 9 has an automatic hidden-row cascade")
	check(report.levels[11].temporary_placement_witness, "Level 12 prepares mixed storage")
	check(report.levels[17].orders_completed_before_board_clear, "Level 18 teaches the remaining-board objective")
	check(report.levels[18].simultaneous_reveal_and_clear, "Level 19 reveals and clears in one transaction")
	check(report.levels[22].temporary_placement_witness, "Level 23 prepares space before its first clear")
	check(report.levels[26].retrieval_witness, "Level 27 later retrieves temporarily placed food")
	for failure in failures:
		push_error(failure)
	print("LEVEL TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func test_level(number: int, certificate: Dictionary) -> void:
	var label := "Level %02d" % number
	var path := "res://data/levels/garden_%03d.json" % number
	var authored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(Validator.validate(authored).is_empty(), label + " validates")
	var expected_hash: String = authored.get("content_hash", "")
	var hash_source := authored.duplicate(true)
	hash_source.erase("content_hash")
	check(Model.canonical_json(hash_source).sha256_text() == expected_hash, label + " content SHA-256")
	check(certificate.get("content_hash", "") == expected_hash, label + " certificate matches content")
	check(certificate.get("status", "") == "PASS", label + " replay certificate passed")
	var level: Dictionary = Catalog.load_level(number)
	check(not level.is_empty(), label + " loads through Resources")
	if level.is_empty():
		return
	check(level.trays.size() == int(level.authoring.expected_trays), label + " exact authored tray count")
	check(level.trays.size() <= 6, label + " fits two columns with at most six trays")
	var free_slots: int = 0
	var deepest_row: int = 1
	var inventory: Dictionary = {}
	for tray in level.trays:
		free_slots += tray.front.count(null)
		deepest_row = maxi(deepest_row, 1 + tray.queue.size())
		for row in [tray.front] + tray.queue:
			for food in row:
				if food != null:
					inventory[food] = int(inventory.get(food, 0)) + 1
	check(free_slots == int(level.authoring.expected_free_slots), label + " exact initial free slots")
	check(deepest_row == int(level.authoring.expected_max_rows), label + " exact queue depth")
	check(inventory.size() == int(level.authoring.expected_foods), label + " exact food variety")
	var signature := canonical_layout(level)
	check(not layout_signatures.has(signature), label + " is not a food/slot/tray permutation of another board")
	layout_signatures[signature] = number
	var model = Model.new()
	model.setup(level)
	check(model.state_hash() == certificate.state_hashes[0], label + " initial replay checksum")
	var snapshots: Array = [model.snapshot()]
	for index in range(level.solution.size()):
		var command: Array = level.solution[index]
		var before_invalid: String = model.state_hash()
		check(not model.apply_move(command[0], command[1], command[0], command[1]), label + " rejects same-tray command")
		check(model.state_hash() == before_invalid, label + " rejected command leaves state unchanged")
		var legal: bool = model.apply_move(command[0], command[1], command[2], command[3])
		check(legal, label + " recorded command %d is legal" % (index + 1))
		if not legal:
			return
		check(model.state_hash() == certificate.state_hashes[index + 1], label + " command %d replay checksum" % (index + 1))
		snapshots.append(model.snapshot())
	check(model.is_won(), label + " replay wins without tools")
	check(model.remaining_tokens() == 0, label + " board including queues cleared")
	check(int(model.state.batches) * 3 == int(model.state.initial_total), label + " token conservation")
	for ticket in model.state.tickets:
		check(ticket.served, label + " all finite tickets served")
	# Undo must restore every intermediate queue, ticket and counter exactly.
	for index in range(level.solution.size() - 1, -1, -1):
		check(model.undo(), label + " undo recorded transaction")
		check(model.state_hash() == certificate.state_hashes[index], label + " undo restores complete state")
	# Independent level loads and model instances must never share mutable state.
	var other: Dictionary = Catalog.load_level(number)
	level.trays[0].front[0] = "test_mutation"
	check(other.trays[0].front[0] != "test_mutation", label + " Resource conversion returns independent copies")
	check(model.state.trays[0].front[0] != "test_mutation", label + " model owns its copied state")


func canonical_layout(level: Dictionary) -> String:
	# Food names, slot order and tray order cannot disguise a repeated puzzle.
	# Hidden row order remains significant. Recipes are deliberately excluded:
	# merely changing an order does not make a new board under these rules.
	var food_ids: Array = []
	for tray in level.trays:
		for row in [tray.front] + tray.queue:
			for food in row:
				if food != null and not food_ids.has(food):
					food_ids.append(food)
	var best: String = ""
	for ordering in permutations(food_ids):
		var mapping: Dictionary = {}
		for index in range(ordering.size()):
			mapping[ordering[index]] = str(index + 1)
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
		var remaining: Array = values.duplicate()
		var first: Variant = remaining.pop_at(index)
		for tail in permutations(remaining):
			result.append([first] + tail)
	return result


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
