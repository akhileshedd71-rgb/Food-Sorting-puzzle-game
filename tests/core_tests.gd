extends SceneTree
## Run: godot --headless --path . --script tests/core_tests.gd

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/appendix_e.json"))
	_test_appendix_replays(fixture)
	_test_invalid_moves(fixture)
	_test_partial_rows_and_storage()
	_test_cascades_and_order()
	_test_recipes_before_board_and_two_active()
	_test_history_and_hashes(fixture)
	_test_recorded_hashes(fixture)
	_test_validator(fixture)
	_test_resources(fixture)
	_test_solver(fixture)
	if failures.is_empty():
		print("CORE PASS: %d assertions; both Appendix E replays, cascades, buffered orders, undo, conservation, validator and solver." % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("CORE FAIL: %d / %d assertions" % [failures.size(), checks])
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _apply(model: BoardModel, command: Array, label: String) -> void:
	var before_total: int = model.remaining_tokens() + int(model.state.batches) * 3
	_check(model.apply_move(int(command[0]), int(command[1]), int(command[2]), int(command[3])), label + ": command accepted")
	_check(model.remaining_tokens() + int(model.state.batches) * 3 == before_total, label + ": food conserved")
	var seen: Dictionary = {}
	for event in model.last_events:
		if event.type == "cleared":
			_check(not seen.has(event.event_id), label + ": unique event IDs")
			seen[event.event_id] = true

func _fresh(fixture: Dictionary) -> BoardModel:
	var model := BoardModel.new()
	model.setup(fixture)
	return model

func _test_appendix_replays(fixture: Dictionary) -> void:
	_check(LevelValidator.validate(fixture).is_empty(), "Appendix E validates")
	var model: BoardModel = _fresh(fixture)
	_check(model.state.initial_total == 9, "Appendix E begins with exactly nine tokens")
	_apply(model, fixture.solution[0], "E canonical 1")
	_check(model.state.trays[0].front == ["bell_pepper_ring", "bell_pepper_ring", null], "Corn clear reveals entire pepper row")
	_check(model.state.tickets[0].credits.corn_cob == 1, "One triple credits one batch")
	var after_one: String = model.state_hash()
	_apply(model, fixture.solution[1], "E canonical 2")
	_check(model.state.tickets[0].served and not model.state.tickets[1].served, "First ticket serves only after mushroom")
	_check(model.undo(), "Undo canonical second move")
	_check(model.state_hash() == after_one, "Undo restores tickets, queues and counters together")
	_apply(model, fixture.solution[1], "E canonical 2 replay")
	_apply(model, fixture.solution[2], "E canonical 3")
	_check(model.is_won() and model.remaining_tokens() == 0, "Canonical replay wins on cleared board")
	_check(model.state.moves == 3 and model.state.batches == 3, "Canonical totals are three moves and three batches")
	_check(model.state.tickets.all(func(ticket: Dictionary) -> bool: return ticket.served), "Both canonical tickets served")
	_check(model.last_events.filter(func(event: Dictionary) -> bool: return event.type == "won").size() == 1, "Win emitted once")
	var canonical_final: Dictionary = model.snapshot()
	model = _fresh(fixture)
	for index in range(fixture.alternate_solution.size()):
		var previous: String = model.state_hash()
		_apply(model, fixture.alternate_solution[index], "E alternative %d" % (index + 1))
		if index == 3:
			_check(model.state.tickets[1].credits.bell_pepper_ring == 1, "Future ticket receives prepared pepper")
			_check(not model.state.tickets[0].served and not model.state.tickets[1].served, "Prepared future ticket waits behind active ticket")
			_check(model.last_events.any(func(event: Dictionary) -> bool: return event.type == "allocated" and event.prepared), "Prepared event visible to UI")
			_check(model.undo(), "Undo prepared match")
			_check(model.state_hash() == previous, "Undo early pepper match restores prepared credits")
			_apply(model, fixture.alternate_solution[index], "E alternative prepared replay")
	_check(model.is_won() and model.state.moves == 5, "Alternative wins in five accepted moves")
	_check(model.state.batches == canonical_final.batches and model.state.tickets == canonical_final.tickets, "Both paths yield identical served recipes and inventory")
	_check(model.last_events.filter(func(event: Dictionary) -> bool: return event.type == "served").size() == 2, "Prepared future ticket serves atomically after first")

func _test_invalid_moves(fixture: Dictionary) -> void:
	var model: BoardModel = _fresh(fixture)
	for command in [[0, 0, 1, 0], [0, 0, 0, 2], [2, 0, 0, 2], [-1, 0, 0, 2], [0, 3, 1, 1], [0, 0, 99, 2]]:
		var before: String = model.state_hash()
		var history_size: int = model.history.size()
		_check(not model.apply_move(command[0], command[1], command[2], command[3]), "Invalid command rejected: " + str(command))
		_check(before == model.state_hash() and history_size == model.history.size(), "Invalid command changes neither board nor undo")
	for command in fixture.solution:
		var before: String = model.state_hash()
		_check(not model.apply_move(0, 0, 0, 1), "Same-tray command rejected during replay")
		_check(model.state_hash() == before, "Rejected inserted command leaves checksum unchanged")
		_apply(model, command, "Invalid-insertion replay")
	var won_hash: String = model.state_hash()
	_check(not model.apply_move(0, 0, 1, 1) and model.state_hash() == won_hash, "No commands after win")

func _test_partial_rows_and_storage() -> void:
	var fixture: Dictionary = {
		"schema_version": 1, "content_version": 1, "level_id": "partial", "mode": "campaign",
		"trays": [
			{"id": "a", "front": ["tomato", "corn_cob", null], "queue": [["tomato", "tomato", null]]},
			{"id": "b", "front": ["corn_cob", null, null], "queue": []},
			{"id": "c", "front": ["corn_cob", null, null], "queue": []}
		], "tickets": []}
	var model: BoardModel = _fresh(fixture)
	_apply(model, [0, 0, 1, 1], "Temporary mixed storage")
	_check(model.state.trays[0].front == [null, "corn_cob", null], "Individual gaps stay empty")
	_check(model.state.trays[0].queue.size() == 1, "Partial row does not draw from hidden positions")
	_check(model.state.trays[1].front == ["corn_cob", "tomato", null], "Different foods may share a tray")
	_apply(model, [0, 1, 2, 1], "Last token moved from source")
	_check(model.state.trays[0].front == ["tomato", "tomato", null], "Moving last token promotes whole queued row")
	_check(model.state.trays[0].queue.is_empty(), "Only one queued row promoted")

func _test_cascades_and_order() -> void:
	var fixture: Dictionary = {
		"schema_version": 1, "content_version": 1, "level_id": "cascade", "mode": "campaign",
		"trays": [
			{"id": "z", "front": ["tomato", "tomato", null], "queue": [["corn_cob", "corn_cob", "corn_cob"], ["button_mushroom", "button_mushroom", "button_mushroom"]]},
			{"id": "a", "front": ["tomato", null, null], "queue": [["bell_pepper_ring", "bell_pepper_ring", "bell_pepper_ring"]]}
		], "tickets": []}
	_check(LevelValidator.validate(fixture).is_empty(), "Queued prematched rows validate")
	var model: BoardModel = _fresh(fixture)
	_apply(model, [1, 0, 0, 2], "Automatic cascade")
	_check(model.is_won() and model.state.batches == 4, "Four batches resolve in one accepted command")
	var clear_foods: Array = []
	var clear_ids: Array = []
	for event in model.last_events:
		if event.type == "cleared":
			clear_foods.append(event.food)
			clear_ids.append(event.event_id)
	_check(clear_foods == ["tomato", "bell_pepper_ring", "corn_cob", "button_mushroom"], "Simultaneous cascades resolve in stable tray-ID order")
	_check(clear_ids == ["cascade:batch:1", "cascade:batch:2", "cascade:batch:3", "cascade:batch:4"], "Batch event IDs increase deterministically")
	_check(model.state.moves == 1, "Cascades do not spend additional player moves")
	_check(model.undo() and model.remaining_tokens() == 12, "Undo restores entire multi-row cascade")

func _test_history_and_hashes(fixture: Dictionary) -> void:
	# Repeat a harmless legal cycle; position-equivalent search states must not
	# multiply just because a player has spent more moves.
	var shallow: Dictionary = fixture.duplicate(true)
	for tray in shallow.trays:
		tray.queue = []
	shallow.tickets = []
	shallow.mode = "campaign"
	var model: BoardModel = _fresh(shallow)
	var original: String = model.state_hash()
	var original_key: String = model.search_key()
	for index in range(25):
		_check(model.apply_move(2, 1, 0, 2), "Cycle outward accepted")
		_check(model.apply_move(0, 2, 2, 1), "Cycle inward accepted")
	_check(model.history.size() >= 20 and model.history.size() == model.undo_capacity, "At least twenty undo transactions retained with bounded memory")
	_check(model.search_key() == original_key and model.state_hash() != original, "Search excludes move counters while replay hash includes them")
	var expected: Dictionary = model.snapshot()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(expected))
	var restored := BoardModel.new()
	restored.restore(parsed)
	_check(restored.state_hash() == model.state_hash(), "Disk JSON round trip preserves stable checksum")
	var independent: Dictionary = model.snapshot()
	independent.trays[0].front[0] = null
	_check(model.state_hash() == restored.state_hash(), "Snapshot is a deep copy")
	var before_undo: int = int(model.state.moves)
	for index in range(20):
		_check(model.undo(), "Twenty-step undo %d" % index)
	_check(model.state.moves == before_undo - 20, "Twenty undos restore exact move count")

func _test_recipes_before_board_and_two_active() -> void:
	var fixture: Dictionary = {
		"schema_version": 1, "content_version": 1, "level_id": "orders_first", "mode": "campaign_orders", "active_ticket_limit": 1,
		"trays": [
			{"id": "a", "front": ["tomato", "tomato", null], "queue": []},
			{"id": "b", "front": ["tomato", "corn_cob", null], "queue": []},
			{"id": "c", "front": ["corn_cob", "corn_cob", null], "queue": []}
		], "tickets": [{"id": "first", "requirements": {"tomato": 1}}]}
	var model: BoardModel = _fresh(fixture)
	_apply(model, [1, 0, 0, 2], "Order before board")
	_check(model.state.tickets[0].served and not model.is_won(), "Served order does not skip remaining food")
	_apply(model, [1, 1, 2, 2], "Clear remaining board")
	_check(model.is_won(), "Surplus batch clears remaining board without duplicate ticket credit")
	_check(model.state.tickets[0].credits.tomato == 1, "Recipe receives one credit only")
	fixture.tickets = [
		{"id": "first", "requirements": {"corn_cob": 1}},
		{"id": "second", "requirements": {"tomato": 1}}]
	fixture.active_ticket_limit = 2
	model = _fresh(fixture)
	_apply(model, [1, 0, 0, 2], "Two active tickets")
	_check(not model.state.tickets[0].served and model.state.tickets[1].served, "Complete second active ticket may serve while first waits")
	_check(model.last_events.any(func(event: Dictionary) -> bool: return event.type == "allocated" and not event.prepared), "Second active ticket credit is active, not prepared")
	_apply(model, [1, 1, 2, 2], "Two active tickets finish")
	_check(model.is_won(), "Two-active-ticket recipe board completes")

func _test_recorded_hashes(fixture: Dictionary) -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/appendix_e_hashes.json"))
	for replay_name in ["solution", "alternate_solution"]:
		var model: BoardModel = _fresh(fixture)
		_check(model.state_hash() == reference.replays[replay_name][0], "Fixture initial recorded checksum: " + replay_name)
		for index in range(fixture[replay_name].size()):
			var command: Array = fixture[replay_name][index]
			_check(model.apply_move(command[0], command[1], command[2], command[3]), "Recorded command accepted")
			_check(model.state_hash() == reference.replays[replay_name][index + 1], "Frozen replay checksum %s step %d" % [replay_name, index + 1])

func _test_validator(fixture: Dictionary) -> void:
	var cases: Array = []
	var malformed: Dictionary = fixture.duplicate(true)
	malformed.trays[0].queue.append([null, null, null])
	cases.append(malformed)
	malformed = fixture.duplicate(true)
	malformed.trays[0].front = ["tomato", null]
	cases.append(malformed)
	malformed = fixture.duplicate(true)
	malformed.tickets[1].requirements.bell_pepper_ring = 2
	cases.append(malformed)
	malformed = fixture.duplicate(true)
	malformed.tickets[1].requirements.bell_pepper_ring = 0.5
	cases.append(malformed)
	malformed = fixture.duplicate(true)
	malformed.trays[0].front[0] = "unregistered_food"
	cases.append(malformed)
	malformed = fixture.duplicate(true)
	malformed.trays[0].front[0] = null
	cases.append(malformed)
	malformed = fixture.duplicate(true)
	malformed.trays[0].initial_seal = 2
	cases.append(malformed)
	malformed = fixture.duplicate(true)
	malformed.trays[0].allowed_food_tags = ["grilled"]
	cases.append(malformed)
	malformed = fixture.duplicate(true)
	malformed.mode = "rush"
	cases.append(malformed)
	malformed = fixture.duplicate(true)
	malformed.trays[1].id = malformed.trays[0].id
	cases.append(malformed)
	malformed = fixture.duplicate(true)
	malformed.tickets = "wrong"
	cases.append(malformed)
	for index in range(cases.size()):
		_check(not LevelValidator.validate(cases[index]).is_empty(), "Malformed content rejected %d" % index)

func _test_resources(fixture: Dictionary) -> void:
	var definition := LevelDefinition.from_dictionary(fixture)
	_check(definition.trays[0] is TrayDefinition and definition.tickets[0] is RecipeTicket, "JSON authoring converts to explicit typed Resources")
	_check(definition.tickets[0].requirements[0] is RecipeRequirement, "Recipe requirements are typed")
	var data: Dictionary = definition.to_dictionary()
	_check(data.has("alternate_solution"), "Authoring metadata survives resource conversion")
	data.trays[0].front[0] = null
	_check(definition.trays[0].front[0] == "corn_cob", "Runtime dictionaries cannot mutate authored Resource")

func _test_solver(fixture: Dictionary) -> void:
	var model: BoardModel = _fresh(fixture)
	var original: String = model.state_hash()
	var result: Dictionary = PuzzleSolver.solve(model, 5000)
	_check(result.status == "SOLVED", "Solver certifies Appendix E")
	_check(model.state_hash() == original and model.history.is_empty(), "Hint solver never mutates live session")
	if result.status == "SOLVED":
		for command in result.moves:
			_apply(model, command, "Solver witness")
		_check(model.is_won(), "Solver witness replays through production resolver")
	model = _fresh(fixture)
	_check(PuzzleSolver.solve(model, 0).status == "UNKNOWN", "Zero search budget returns UNKNOWN")
	var impossible: Dictionary = {
		"schema_version": 1, "content_version": 1, "level_id": "exhaustion", "mode": "campaign", "tickets": [],
		"trays": [{"id": "a", "front": ["tomato", null, null], "queue": []}, {"id": "b", "front": [null, null, null], "queue": []}]}
	# Deliberately invalid inventory is a tiny exhaustive-search fixture.
	model = _fresh(impossible)
	_check(PuzzleSolver.solve(model, 2000).status == "UNSOLVABLE", "Finite graph exhaustion proves UNSOLVABLE")
