class_name CookingSchool
extends RefCounted
## Three short, independent practice boards. No campaign or economy persistence.
## All indices in this API are zero-based; tutorial_step values are one-based.

const LESSON_COUNT: int = 3
const NO_SLOT: Vector2i = Vector2i(-1, -1)
const Model = preload("res://core/board_model.gd")
const Validator = preload("res://core/level_validator.gd")
const Definition = preload("res://core/resources/level_definition.gd")


static func lessons() -> Array:
	var result: Array = []
	for index in range(LESSON_COUNT):
		result.append(lesson(index))
	return result


static func lesson(index: int) -> Dictionary:
	if index < 0 or index >= LESSON_COUNT:
		return {}
	var path := "res://data/tutorials/cooking_school_%03d.json" % (index + 1)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Could not read the cooking-school lesson: " + path)
		return {}
	var errors: Array = Validator.validate(parsed)
	if not errors.is_empty():
		push_error("Invalid cooking-school lesson: " + str(errors))
		return {}
	var hash_source: Dictionary = parsed.duplicate(true)
	hash_source.erase("content_hash")
	if Model.canonical_json(hash_source).sha256_text() != parsed.get("content_hash", ""):
		push_error("Cooking-school lesson content hash does not match: " + path)
		return {}
	return Definition.from_dictionary(parsed).to_dictionary()


static func instruction(index: int, model: BoardModel) -> Dictionary:
	var level: Dictionary = lesson(index)
	if level.is_empty():
		return _message("A lesson is missing", "Return to Cooking School to choose an available lesson.", "unavailable", "", -1)
	var progress := "Lesson %d of %d" % [index + 1, LESSON_COUNT]
	if model == null or model.state.get("level_id", "") != level.level_id:
		return _message(level.title, "Open this practice board to follow its gentle guide.", "unavailable", progress, -1)
	if model.is_won():
		return _message("Nicely done!", level.tutorial_complete, "complete", progress + " · Complete", level.solution.size())
	var proof = Model.new()
	proof.setup(level)
	var current_key: String = model.search_key()
	for step in range(level.solution.size()):
		var command: Array = level.solution[step]
		if proof.search_key() == current_key:
			var remapped: Array = _remap_command(command, proof, model)
			if not remapped.is_empty():
				var copy = Model.new()
				copy.restore(model.snapshot())
				if copy.apply_move(remapped[0], remapped[1], remapped[2], remapped[3]):
					var guide: Dictionary = level.tutorial_guide[step]
					return {
						"title": guide.title, "body": guide.body,
						"source": Vector2i(remapped[0], remapped[1]),
						"target": Vector2i(remapped[2], remapped[3]),
						"progress": progress + " · Move %d of %d" % [step + 1, level.solution.size()],
						"status": "guided", "step": step,
					}
		if not proof.apply_move(command[0], command[1], command[2], command[3]):
			break
	# Exploration remains legal. Never point at an arbitrary move and call it a
	# solution when this state is absent from the checked teaching witness.
	return _message("A little exploring", "You've tried a different arrangement. Keep exploring, or use Undo to return to the guide. Restart brings back this small practice board.", "off_path", progress + " · Your turn", -1)


static func _remap_command(command: Array, proof: BoardModel, current: BoardModel) -> Array:
	var source_tray: int = int(command[0])
	var target_tray: int = int(command[2])
	if source_tray >= current.state.trays.size() or target_tray >= current.state.trays.size():
		return []
	var food: Variant = proof.state.trays[source_tray].front[int(command[1])]
	var source_row: Array = current.state.trays[source_tray].front
	var target_row: Array = current.state.trays[target_tray].front
	var source_slot: int = int(command[1])
	var target_slot: int = int(command[3])
	if source_row[source_slot] != food:
		source_slot = source_row.find(food)
	if target_row[target_slot] != null:
		target_slot = target_row.find(null)
	if food == null or source_slot < 0 or target_slot < 0:
		return []
	return [source_tray, source_slot, target_tray, target_slot]


static func _message(title: String, body: String, status: String, progress: String, step: int) -> Dictionary:
	return {
		"title": title, "body": body, "source": NO_SLOT, "target": NO_SLOT,
		"progress": progress, "status": status, "step": step,
	}
