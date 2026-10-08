extends SceneTree
## Offline authoring certification; uses the same resolver as the running game.
## Run only after tools/author_levels.py, or to recertify deliberately edited data.

const Model = preload("res://core/board_model.gd")
const Solver = preload("res://core/solver.gd")
const Validator = preload("res://core/level_validator.gd")
const Definition = preload("res://core/resources/level_definition.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var reports: Array = []
	for number in range(1, 31):
		var report := certify(number)
		reports.append(report)
		print("Level %02d: %s" % [number, JSON.stringify(report)])
	var summary := {
		"schema_version": 1,
		"generator": "tools/build_levels.gd",
		"resolver": "core/board_model.gd",
		"scope": "30 authored Garden campaign levels; no boosters",
		"human_playtest_status": "pending",
		"shortest_solution_claim": false,
		"passed": failures.is_empty(),
		"levels": reports,
		"errors": failures,
	}
	var file := FileAccess.open("res://data/levels/replay_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "  ") + "\n")
	quit(0 if failures.is_empty() else 1)


func certify(number: int) -> Dictionary:
	var path := "res://data/levels/garden_%03d.json" % number
	var level: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var errors: Array = Validator.validate(level)
	if not errors.is_empty():
		return fail(number, "validation", str(errors))
	var model = Model.new()
	var runtime_level: Dictionary = Definition.from_dictionary(level).to_dictionary()
	model.setup(runtime_level)
	var solution: Array = []
	# These short opening witnesses make the taught interactions explicit. The
	# remaining commands are found by the production-resolver search below.
	var openings := {
		1: [[1, 0, 0, 2]],
		7: [[2, 0, 0, 2]],
		8: [[0, 0, 1, 2]],
		9: [[1, 0, 0, 2]],
		19: [[0, 0, 1, 2]],
		27: [[1, 2, 3, 2], [0, 0, 1, 2], [3, 2, 0, 0]],
	}
	for command in openings.get(number, []):
		if not model.apply_move(command[0], command[1], command[2], command[3]):
			return fail(number, "opening", str(command))
		solution.append(command)
	var solved: Dictionary = Solver.solve(model, 30000)
	if solved.get("status") != "SOLVED":
		return fail(number, "search", JSON.stringify(solved))
	solution.append_array(solved.get("moves", []))
	# Replay fresh: a solver's success flag alone is never a certificate.
	model.setup(runtime_level)
	var hashes: Array = [model.state_hash()]
	var clears: int = 0
	var reveals: int = 0
	var served: int = 0
	var first_clear_move: int = -1
	var simultaneous_reveal_match: bool = false
	var multiple_clears: bool = false
	var orders_before_board_clear: bool = false
	var food_retrieved: bool = false
	var moved_destinations: Dictionary = {}
	for index in range(solution.size()):
		var command: Array = solution[index]
		var source_key := "%d:%d" % [command[0], command[1]]
		if moved_destinations.has(source_key):
			food_retrieved = true
		moved_destinations.erase(source_key)
		if not model.apply_move(command[0], command[1], command[2], command[3]):
			return fail(number, "replay", "Rejected move %d: %s" % [index + 1, str(command)])
		var destination_key := "%d:%d" % [command[2], command[3]]
		moved_destinations[destination_key] = true
		var transaction_clears: int = 0
		var transaction_reveals: int = 0
		for event in model.last_events:
			if event.get("type", "") in ["cleared", "revealed"]:
				for slot in range(3):
					moved_destinations.erase("%d:%d" % [event["tray"], slot])
			match event.get("type", ""):
				"cleared":
					clears += 1
					transaction_clears += 1
					if first_clear_move == -1:
						first_clear_move = index + 1
				"revealed":
					reveals += 1
					transaction_reveals += 1
				"served":
					served += 1
		if transaction_clears > 0 and transaction_reveals > 0:
			simultaneous_reveal_match = true
		if transaction_clears > 1:
			multiple_clears = true
		if served == level.get("tickets", []).size() and served > 0 and model.remaining_tokens() > 0:
			orders_before_board_clear = true
		hashes.append(model.state_hash())
	if not model.is_won() or model.remaining_tokens() != 0:
		return fail(number, "completion", "Replay did not clear the board and every ticket")
	level["solution"] = solution
	level.erase("content_hash")
	level["content_hash"] = Model.canonical_json(level).sha256_text()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(level, "  ") + "\n")
	return {
		"level_id": level["level_id"], "status": "PASS",
		"content_hash": level["content_hash"], "moves": solution.size(),
		"initial_tokens": model.state["initial_total"], "remaining_tokens": 0,
		"cleared_batches": clears, "revealed_rows": reveals, "served_tickets": served,
		"first_clear_move": first_clear_move, "temporary_placement_witness": first_clear_move > 1,
		"retrieval_witness": food_retrieved,
		"simultaneous_reveal_and_clear": simultaneous_reveal_match,
		"automatic_cascade_witness": multiple_clears,
		"orders_completed_before_board_clear": orders_before_board_clear,
		"state_hashes": hashes, "final_state_hash": model.state_hash(),
	}


func fail(number: int, stage: String, reason: String) -> Dictionary:
	failures.append("Level %d %s: %s" % [number, stage, reason])
	return {"level_id": "garden_%03d" % number, "status": "FAIL", "stage": stage, "reason": reason}
