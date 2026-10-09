extends SceneTree
## Checked lessons use production rules and never mutate the inspected model.

const School = preload("res://services/tutorial_service.gd")
const Model = preload("res://core/board_model.gd")
const Validator = preload("res://core/level_validator.gd")
const Catalog = preload("res://core/level_catalog.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	check(School.lessons().size() == 3, "Exactly three practice lessons")
	check(School.lesson(-1).is_empty() and School.lesson(3).is_empty(), "Out-of-range lessons fail honestly")
	for index in range(3):
		test_guidance_and_replay(index)
	test_exploration()
	test_reveal_lesson()
	test_prepared_recipe()
	test_independent_campaign()
	for failure in failures:
		push_error(failure)
	print("TUTORIAL TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func test_guidance_and_replay(index: int) -> void:
	var level: Dictionary = School.lesson(index)
	check(not level.is_empty(), "Lesson %d loads with a verified content hash" % (index + 1))
	if level.is_empty():
		return
	check(Validator.validate(level).is_empty(), "Normal level schema validates")
	check(int(level.tutorial_step) == index + 1 and int(level.number) == index + 1, "One-based progress and number")
	check(str(level.level_id).begins_with("cooking_school_"), "Tutorial IDs cannot be campaign IDs")
	check(level.tutorial_guide.size() == level.solution.size(), "Each teaching move has its own useful instruction")
	var model = Model.new()
	model.setup(level)
	var snapshots: Array = [model.snapshot()]
	for step in range(level.solution.size()):
		var before: String = model.state_hash()
		var undo_count: int = model.history.size()
		var hint: Dictionary = School.instruction(index, model)
		check(hint.status == "guided" and hint.step == step, "Correct teaching step recognized")
		check(not hint.title.is_empty() and not hint.body.is_empty() and not hint.progress.is_empty(), "Guidance has visible text")
		check(model.state_hash() == before and model.history.size() == undo_count, "Guidance has no state or history side effects")
		var command: Array = level.solution[step]
		var proof = Model.new()
		proof.restore(model.snapshot())
		check(proof.apply_move(command[0], command[1], command[2], command[3]), "Frozen teaching command is legal")
		# Every active slot position is interchangeable in the rules. Reorder
		# all rows so original source/target coordinates need actual remapping.
		var permuted = Model.new()
		var permuted_state: Dictionary = model.snapshot()
		for tray in permuted_state.trays:
			var front: Array = tray.front
			tray.front = [front[2], front[0], front[1]]
		permuted.restore(permuted_state)
		var remapped: Dictionary = School.instruction(index, permuted)
		check(remapped.status == "guided" and remapped.step == step, "Equivalent slot arrangement retains its guide")
		check(follow(permuted, remapped), "Remapped teaching move is legal")
		check(permuted.search_key() == proof.search_key(), "Remapped move reaches equivalent next proof state")
		check(follow(model, hint), "Highlighted source and destination accept the guided move")
		check(model.search_key() == proof.search_key(), "Guidance follows the production proof")
		snapshots.append(model.snapshot())
	check(model.is_won() and model.remaining_tokens() == 0, "Frozen solution clears the entire lesson")
	var completed: Dictionary = School.instruction(index, model)
	check(completed.status == "complete", "Completion receives a friendly explanation")
	check(completed.source == School.NO_SLOT and completed.target == School.NO_SLOT, "Completed board has no phantom move")
	for step in range(level.solution.size() - 1, -1, -1):
		check(model.undo(), "Practice undo remains free and valid")
		check(model.snapshot() == snapshots[step], "Undo restores complete tutorial transaction")
		check(School.instruction(index, model).step == step, "Undo restores the correct teaching prompt")
	var independent: Dictionary = School.lesson(index)
	level.trays[0].front[0] = "mutation"
	check(independent.trays[0].front[0] != "mutation", "Repeated lesson loads own separate values")
	check(model.state.trays[0].front[0] != "mutation", "Practice model owns its values")


func test_exploration() -> void:
	var model = Model.new()
	model.setup(School.lesson(0))
	check(model.apply_move(0, 0, 2, 1), "Legal exploration is allowed")
	var explored: Dictionary = School.instruction(0, model)
	check(explored.status == "off_path", "Unproved arrangement is described honestly")
	check(explored.source == School.NO_SLOT and explored.target == School.NO_SLOT, "Off-path guide never invents a move")
	check("Undo" in explored.body and "Restart" in explored.body, "Off-path recovery offers working controls")
	check(model.undo(), "Player can undo exploration")
	check(School.instruction(0, model).status == "guided", "Guidance returns after undo")
	# A legitimate alternative route is also allowed to complete the lesson.
	for command in [[0, 0, 2, 1], [0, 1, 2, 2], [2, 0, 0, 0], [1, 0, 2, 0], [0, 0, 1, 0]]:
		check(model.apply_move(command[0], command[1], command[2], command[3]), "Exploration solution stays legal")
	check(model.is_won(), "Exploration can win without following the witness")
	check(School.instruction(0, model).status == "complete", "Alternative win still earns completion guidance")
	check(School.instruction(1, model).status == "unavailable", "Wrong lesson cannot display another board's move")
	check(School.instruction(0, null).status == "unavailable", "Absent model has no phantom move")


func test_reveal_lesson() -> void:
	var level: Dictionary = School.lesson(1)
	var model = Model.new()
	model.setup(level)
	check(follow(model, School.instruction(1, model)), "Move the first food out")
	check(count_events(model, "revealed") == 0, "Partial emptying never advances a hidden row")
	check(model.state.trays[0].front.count(null) == 2 and model.state.trays[0].queue.size() == 1, "Last mushroom holds the next row back")
	check(follow(model, School.instruction(1, model)), "Move the last mushroom out")
	check(count_events(model, "revealed") == 1, "Whole-row reveal happens after the final food leaves")
	check(count_events(model, "cleared") == 2, "Mushroom match and automatic corn cascade share one transaction")
	var saw_reveal: bool = false
	var saw_cascade: bool = false
	for event in model.last_events:
		if event.type == "revealed" and int(event.tray) == 0:
			saw_reveal = true
		if event.type == "cleared" and event.food == "corn_cob":
			saw_cascade = saw_reveal
	check(saw_cascade, "The corn clear occurs after its row is revealed")
	check(model.is_won() and int(model.state.batches) == 3, "The reveal lesson accounts for every triple")


func test_prepared_recipe() -> void:
	var model = Model.new()
	model.setup(School.lesson(2))
	check(follow(model, School.instruction(2, model)), "Prepare corn first")
	check(int(model.state.batches) == 1 and int(model.state.tickets[0].credits.corn_cob) == 1, "Three corn pieces create exactly one batch")
	check(not model.state.tickets[0].served, "The first plate still needs its mushroom batch")
	check(follow(model, School.instruction(2, model)), "Prepare the future pepper batch")
	var prepared: bool = false
	for event in model.last_events:
		if event.type == "allocated" and event.ticket_id == "next_plate":
			prepared = event.prepared
	check(prepared, "Production event explicitly credits an inactive future ticket")
	check(int(model.state.tickets[1].credits.bell_pepper_ring) == 1 and not model.state.tickets[1].served, "Prepared pepper waits instead of serving out of order")
	check("Prepared" in School.instruction(2, model).body, "Player is told why prepared food is safe")
	check(follow(model, School.instruction(2, model)), "Finish the mushrooms")
	var served_ids: Array = []
	for event in model.last_events:
		if event.type == "served":
			served_ids.append(event.ticket_id)
	check(served_ids == ["first_plate", "next_plate"], "Active ticket then already-prepared future ticket serve in order")
	check(model.is_won() and int(model.state.batches) == 3, "Recipe lesson finishes with all food and both tickets complete")


func test_independent_campaign() -> void:
	var campaign = Model.new()
	campaign.setup(Catalog.load_level(5))
	var move: Array = campaign.legal_moves()[0]
	check(campaign.apply_move(move[0], move[1], move[2], move[3]), "Existing campaign can be in progress")
	var state: Dictionary = campaign.snapshot()
	var history: Array = campaign.history.duplicate(true)
	for index in range(3):
		var school_model = Model.new()
		school_model.setup(School.lesson(index))
		while not school_model.is_won():
			if not follow(school_model, School.instruction(index, school_model)):
				check(false, "Practice should remain solvable independently")
				break
	check(campaign.snapshot() == state and campaign.history == history, "School models leave the existing campaign state and undo history intact")
	check(School.instruction(0, campaign).status == "unavailable", "School does not reinterpret a live campaign as a lesson")


func follow(model: BoardModel, guide: Dictionary) -> bool:
	if guide.get("status", "") != "guided":
		return false
	var source: Vector2i = guide.source
	var target: Vector2i = guide.target
	return model.apply_move(source.x, source.y, target.x, target.y)


func count_events(model: BoardModel, type: String) -> int:
	var result: int = 0
	for event in model.last_events:
		if event.type == type:
			result += 1
	return result


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
