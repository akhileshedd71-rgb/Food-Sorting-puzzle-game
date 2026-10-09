extends SceneTree
## Read-only certification of the frozen catalogue. Never rewrites legacy content.
## To author additions, run author_expansion.py and author_expansion.gd instead.

const Model = preload("res://core/board_model.gd")
const Catalog = preload("res://core/level_catalog.gd")
var errors: Array[String] = []


func _initialize() -> void:
	var manifest: Dictionary = read_json("res://data/levels/legacy_manifest.json")
	for path in manifest.get("files", {}):
		if FileAccess.get_sha256("res://" + path) != manifest.files[path]:
			errors.append("Preserved level bytes changed: " + path)
	if not manifest.is_empty() and FileAccess.get_sha256("res://" + manifest.report_file) != manifest.report_sha256:
		errors.append("Preserved original replay report changed")
	var report: Dictionary = read_json("res://data/levels/replay_report.json")
	var certificates: Dictionary = {}
	for certificate in report.get("levels", []):
		certificates[certificate.level_id] = certificate
	for number in range(1, Catalog.LEVEL_COUNT + 1):
		var level: Dictionary = Catalog.load_level(number)
		if level.is_empty():
			errors.append("Missing or invalid level %d" % number)
			continue
		var certificate: Dictionary = certificates.get(level.level_id, {})
		if certificate.is_empty():
			errors.append("Missing certificate: " + level.level_id)
			continue
		var authored: Dictionary = read_json(Catalog.level_path(number))
		var hash_source := authored.duplicate(true)
		hash_source.erase("content_hash")
		if Model.canonical_json(hash_source).sha256_text() != authored.get("content_hash", ""):
			errors.append("Content hash mismatch: " + level.level_id)
			continue
		if certificate.get("content_hash", "") != authored.content_hash:
			errors.append("Certificate content hash mismatch: " + level.level_id)
			continue
		var model = Model.new()
		model.setup(level)
		var hashes: Array = certificate.get("state_hashes", [])
		if hashes.size() != level.solution.size() + 1 or hashes[0] != model.state_hash():
			errors.append("Initial replay checksum mismatch: " + level.level_id)
			continue
		var valid: bool = true
		for index in range(level.solution.size()):
			var command: Array = level.solution[index]
			if not model.apply_move(command[0], command[1], command[2], command[3]) or model.state_hash() != hashes[index + 1]:
				errors.append("Replay mismatch: %s move %d" % [level.level_id, index + 1])
				valid = false
				break
		if valid and (not model.is_won() or model.remaining_tokens() != 0):
			errors.append("Replay does not finish: " + level.level_id)
	for error in errors:
		push_error(error)
	print("FROZEN REPLAY VERIFICATION: %d levels, %d errors; no content files changed" % [Catalog.LEVEL_COUNT, errors.size()])
	quit(0 if errors.is_empty() else 1)


func read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
