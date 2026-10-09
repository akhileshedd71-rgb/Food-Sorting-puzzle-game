class_name SaveService
extends RefCounted
## Profile and stable board are one checksummed, recoverable transaction.
## Never resume an animation or credit a reward from a presentation callback.

const SCHEMA_VERSION := 2
const BOARD_SCHEMA_VERSION := 1
const RULES_VERSION := 1
const LEVEL_COUNT := 30
const FIRST_CLEAR_COINS := 30
const SETTING_KEYS := ["sound", "music", "haptics", "reduced_motion", "high_readability"]
const MAX_FILE_BYTES := 4000000

var data: Dictionary = default_data()
var last_error: String = ""
var recovery_notice: String = ""
var save_path: String
var _revision: int = 0
var write_blocked: bool = false

func _init(path: String = "user://garden_table.save.json") -> void:
	save_path = path

static func default_data() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"profile": {
			"unlocked": 1, "completed": {}, "coins": 0,
			"tutorial": {"step": 0, "completed": false},
			"economy": {"version": 1, "ledger": {}},
			"owned_themes": ["classic"], "active_theme": "classic",
			"settings": {"sound": true, "music": true, "haptics": false,
				"reduced_motion": false, "high_readability": false}
		},
		"session": {}
	}

static func content_hash(level: Dictionary) -> String:
	return _canonical(level).sha256_text()

func load_save() -> bool:
	last_error = ""
	recovery_notice = ""
	var best := _latest_valid()
	if write_blocked:
		last_error = "This save uses a newer version. Update the game before continuing."
		recovery_notice = last_error + " Your files have been preserved."
		return false
	if best.is_empty():
		data = default_data()
		_revision = 0
		for path in _candidate_paths():
			if FileAccess.file_exists(path):
				last_error = "No valid save copy was found."
				recovery_notice = "Saved progress could not be read. Damaged files have been retained; a new game can be started."
				break
		return false
	data = _migrate_payload(best.payload)
	_revision = int(best.revision)
	if best.path != save_path:
		recovery_notice = "Your latest valid progress was recovered from a safety copy."
	return true

func save_game() -> bool:
	last_error = ""
	if write_blocked:
		last_error = "A newer save version is present; overwriting it is disabled."
		return false
	var errors := _validate_payload(data)
	if not errors.is_empty():
		last_error = "Save rejected: " + "; ".join(errors)
		return false
	var absolute := ProjectSettings.globalize_path(save_path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		last_error = "Could not create the save directory."
		return false
	var previous := _latest_valid()
	if write_blocked:
		last_error = "A newer save version is present; overwriting it is disabled."
		return false
	if previous.is_empty() and not _archive_invalid_copies():
		return false
	if not previous.is_empty():
		_revision = maxi(_revision, int(previous.revision))
		# Preserve the newest existing checkpoint BEFORE reusing .tmp. This also
		# handles a crash where .tmp is the only complete, valid copy left.
		if previous.path == save_path + ".bak.tmp":
			if not _replace(previous.path, save_path + ".bak"):
				return false
		elif previous.path != save_path + ".bak":
			var backup_pending := save_path + ".bak.tmp"
			if not _write_checked(backup_pending, previous.envelope):
				return false
			if not _replace(backup_pending, save_path + ".bak"):
				return false
	var next_revision := _revision + 1
	var envelope := _make_envelope(data, next_revision)
	if not _write_checked(save_path + ".tmp", envelope):
		# A late write-status error must not refund a recoverable transaction.
		var pending := _read_valid(save_path + ".tmp")
		if pending.is_empty() or pending.envelope.checksum != envelope.checksum:
			return false
		last_error = ""
	# A flushed, validated temp is DURABLE: recovery selects its new revision.
	# Never report failure and refund a purchase after reaching this point.
	if not _replace(save_path + ".tmp", save_path):
		recovery_notice = "Progress was recorded in a safety copy and will recover on restart."
		last_error = ""
	_revision = next_revision
	return true

func commit_session(model: BoardModel, level: Dictionary) -> void:
	if not is_campaign_level(level):
		last_error = "Tutorial boards cannot replace the campaign session."
		return
	stage_session(model, level)
	save_game()

## Update the pending envelope without writing, for atomic economy transactions.
func stage_session(model: BoardModel, level: Dictionary) -> void:
	if not is_campaign_level(level):
		last_error = "Only authored campaign sessions can be saved."
		return
	var previous: Dictionary = data.get("session", {})
	if model.run_id.is_empty():
		model.run_id = str(previous.get("run_id", Crypto.new().generate_random_bytes(16).hex_encode()))
	var same_run: bool = previous.get("run_id", "") == model.run_id
	var number := int(level.get("number", 0))
	data.session = {
		"run_id": model.run_id,
		"hint_receipts": previous.get("hint_receipts", {}).duplicate(true) if same_run else {},
		"extra_tray_granted": model.extra_tray_granted,
		"level_number": number,
		"level_id": str(level.get("level_id", "")),
		"content_version": int(level.get("content_version", 1)),
		"rules_version": RULES_VERSION,
		"content_hash": content_hash(level),
		"state": model.snapshot(),
		"history": model.history.duplicate(true)
	}
	if model.is_won():
		var level_id := str(level.get("level_id", ""))
		var completed: Dictionary = data.profile.completed
		if not completed.has(level_id):
			completed[level_id] = {
				"level_number": number,
				"best_moves": int(model.state.moves),
				"reward": FIRST_CLEAR_COINS,
				"transaction_id": "first_clear:" + level_id,
				"recipes": _served_recipes(model.state)
			}
			data.profile.coins = int(data.profile.coins) + FIRST_CLEAR_COINS
		else:
			completed[level_id].best_moves = mini(int(completed[level_id].best_moves), int(model.state.moves))
		data.profile.unlocked = clampi(maxi(int(data.profile.unlocked), number + 1), 1, LEVEL_COUNT)

func restore_session(model: BoardModel) -> bool:
	if data.session.is_empty():
		return false
	model.restore(data.session.state)
	model.history = data.session.history.duplicate(true)
	model.run_id = str(data.session.run_id)
	return true

func clear_session() -> void:
	data.session = {}
	save_game()

func reset_progress() -> void:
	# Reset is a UI-confirmed transaction. Replace every recoverable checkpoint
	# with the reset state so backup recovery cannot resurrect deleted progress.
	data = default_data()
	if save_game():
		save_game()

## UI must run this against the current authored definition before restore().
## An incompatible session can be discarded with clear_session(); profile stays.
func validate_session(level: Dictionary) -> Array:
	var session: Dictionary = data.get("session", {})
	if session.is_empty():
		return []
	var errors := _validate_session_shape(session)
	if not errors.is_empty():
		return errors
	if session.content_hash != content_hash(level):
		errors.append("This level has changed. Restart it to use the current layout; your completed progress is safe.")
		return errors
	if int(session.level_number) != int(level.get("number", -1)) or session.state.level_id != level.get("level_id", ""):
		errors.append("The saved session belongs to a different level.")
		return errors
	var states: Array = session.history.duplicate()
	states.append(session.state)
	var authored_totals := _inventory(level.trays)
	var authored_total: int = 0
	for count in authored_totals.values():
		authored_total += int(count)
	var authored_tickets: Array = level.get("tickets", [])
	for state_value in states:
		var state: Dictionary = state_value
		if int(state.initial_total) != authored_total or int(state.content_version) != int(level.get("content_version", 1)):
			errors.append("Saved initial inventory or content version does not match the level.")
		var has_grant := bool(state.get("extra_tray_granted", false))
		var expected_trays: int = level.trays.size() + (1 if has_grant else 0)
		if state.trays.size() != expected_trays:
			errors.append("Saved tray count does not match its authored layout and grant.")
			break
		for index in range(level.trays.size()):
			if str(state.trays[index].id) != str(level.trays[index].id):
				errors.append("Saved tray IDs do not match the level.")
			var saved_queue: Array = state.trays[index].queue
			var authored_queue: Array = level.trays[index].queue
			if saved_queue.size() > authored_queue.size() or _canonical(saved_queue) != _canonical(authored_queue.slice(authored_queue.size() - saved_queue.size())):
				errors.append("Saved future rows do not match the authored queue.")
		var remaining := _inventory(state.trays)
		for food in FoodCatalog.ids():
			var difference := int(authored_totals.get(food, 0)) - int(remaining.get(food, 0))
			if difference < 0 or difference % 3 != 0:
				errors.append("Saved food inventory does not match the level.")
		if state.tickets.size() != authored_tickets.size():
			errors.append("Saved recipe count does not match the level.")
			break
		var allocated_by_food: Dictionary = {}
		for index in range(state.tickets.size()):
			var ticket: Dictionary = state.tickets[index]
			if ticket.id != authored_tickets[index].id or _canonical(ticket.requirements) != _canonical(authored_tickets[index].requirements):
				errors.append("Saved recipe demand does not match the level.")
			for food in ticket.credits:
				allocated_by_food[food] = int(allocated_by_food.get(food, 0)) + int(ticket.credits[food])
		for food in allocated_by_food:
			if int(allocated_by_food[food]) * 3 > int(authored_totals.get(food, 0)) - int(remaining.get(food, 0)):
				errors.append("Saved recipe credit exceeds matched inventory for its food.")
	return errors

static func _served_recipes(state: Dictionary) -> Array:
	var result: Array = []
	for ticket in state.get("tickets", []):
		if ticket.get("served", false):
			result.append({"id": ticket.id, "name": ticket.get("name", ticket.id), "requirements": ticket.requirements.duplicate(true)})
	return result

func _candidate_paths() -> Array:
	return [save_path, save_path + ".tmp", save_path + ".bak", save_path + ".bak.tmp"]

## Preserve unreadable originals before creating a fresh profile automatically.
## Archives are adjacent immutable byte copies, excluded from recovery candidates.
func _archive_invalid_copies() -> bool:
	var archived: bool = false
	for path in _candidate_paths():
		if not FileAccess.file_exists(path):
			continue
		var archive: String = path + ".corrupt." + str(int(Time.get_unix_time_from_system())) + "." + str(Time.get_ticks_usec())
		var suffix: int = 0
		while FileAccess.file_exists(archive) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(archive)):
			suffix += 1
			archive = path + ".corrupt." + str(int(Time.get_unix_time_from_system())) + "." + str(Time.get_ticks_usec()) + "." + str(suffix)
		if not _archive_file(path, archive):
			last_error = "Unreadable progress could not be archived. The original files have been left untouched."
			return false
		archived = true
	if archived:
		recovery_notice = "Saved progress could not be read. Original damaged files were preserved in adjacent .corrupt archives before starting fresh."
	return true

func _archive_file(source: String, target: String) -> bool:
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target)) != OK:
		return false
	var source_hash := FileAccess.get_sha256(source)
	return not source_hash.is_empty() and source_hash == FileAccess.get_sha256(target)

func _latest_valid() -> Dictionary:
	var best: Dictionary = {}
	for path in _candidate_paths():
		var candidate := _read_valid(path)
		if not candidate.is_empty() and (best.is_empty() or int(candidate.revision) > int(best.revision)):
			best = candidate
	return best

func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return {}
	var parser := JSON.new()
	var parse_status := parser.parse(file.get_as_text())
	file.close()
	if parse_status != OK:
		return {}
	var parsed: Variant = _normalize_numbers(parser.data)
	if not parsed is Dictionary:
		return {}
	var envelope: Dictionary = parsed
	if envelope.get("format") != "garden-table-save":
		return {}
	if not _integer(envelope.get("envelope_version"), 1, 2147483647):
		return {}
	if int(envelope.envelope_version) > 1:
		write_blocked = true
		return {}
	if envelope.get("envelope_version") != 1:
		return {}
	if not _integer(envelope.get("revision"), 1, 2147483647):
		return {}
	if not envelope.get("payload") is Dictionary or not envelope.get("checksum") is String:
		return {}
	var digest := _canonical({"revision": envelope.revision, "payload": envelope.payload}).sha256_text()
	if digest != envelope.checksum:
		return {}
	if not _integer(envelope.payload.get("schema_version"), 1, 2147483647):
		return {}
	if int(envelope.payload.schema_version) > SCHEMA_VERSION:
		write_blocked = true
		return {}
	if not _validate_payload(envelope.payload).is_empty():
		return {}
	return {"path": path, "revision": int(envelope.revision), "payload": envelope.payload, "envelope": envelope}

static func _make_envelope(payload: Dictionary, revision: int) -> Dictionary:
	return {
		"format": "garden-table-save", "envelope_version": 1,
		"revision": revision, "payload": payload.duplicate(true),
		"checksum": _canonical({"revision": revision, "payload": payload}).sha256_text()
	}

func _write_checked(path: String, envelope: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_error = "Progress could not be written. Please check free storage."
		return false
	file.store_string(_canonical(envelope))
	file.flush()
	var status := file.get_error()
	file.close()
	if status != OK or _read_valid(path).is_empty():
		last_error = "The new save failed its integrity check; the previous copy was retained."
		return false
	return true

func _replace(source: String, target: String) -> bool:
	var status := DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target))
	if status != OK:
		last_error = "The save could not be finalized; a recovery copy has been retained."
		return false
	return true

static func _validate_payload(payload: Dictionary) -> Array:
	var errors: Array = []
	if payload.get("schema_version") not in [1, SCHEMA_VERSION]:
		return ["Unsupported save version."]
	if not payload.get("profile") is Dictionary or not payload.get("session") is Dictionary:
		return ["Profile or session is missing."]
	var profile: Dictionary = payload.profile
	if not _integer(profile.get("unlocked"), 1, LEVEL_COUNT) or not _integer(profile.get("coins"), 0, 100000000):
		errors.append("Invalid progression counters.")
	if not profile.get("settings") is Dictionary:
		errors.append("Settings are missing.")
	else:
		for key in SETTING_KEYS:
			if not profile.settings.get(key) is bool:
				errors.append("Invalid setting: " + key)
	if not profile.get("completed") is Dictionary:
		errors.append("Completion records are missing.")
	else:
		for level_id in profile.completed:
			var record: Variant = profile.completed[level_id]
			if not record is Dictionary:
				errors.append("Invalid completion record.")
				continue
			if not _integer(record.get("level_number"), 1, LEVEL_COUNT) or not _integer(record.get("best_moves"), 0, 1000000):
				errors.append("Invalid completion counters.")
				continue
			if level_id != "garden_%03d" % int(record.level_number) or record.get("transaction_id") != "first_clear:" + str(level_id):
				errors.append("Invalid completion identity.")
			if record.get("reward") != FIRST_CLEAR_COINS or not record.get("recipes") is Array:
				errors.append("Invalid completion reward.")
	if int(payload.schema_version) >= 2:
		errors.append_array(_validate_economy_profile(profile))
	if not payload.session.is_empty():
		errors.append_array(_validate_session_shape(payload.session))
		if int(payload.schema_version) >= 2:
			errors.append_array(_validate_session_extensions(payload.session))
	return errors

static func _validate_session_shape(session: Dictionary) -> Array:
	var errors: Array = []
	if not _integer(session.get("level_number"), 1, LEVEL_COUNT):
		return ["Invalid session level."]
	if not session.get("content_hash") is String or session.content_hash.length() != 64:
		return ["Missing level content checksum."]
	if session.get("rules_version") != RULES_VERSION or not _integer(session.get("content_version"), 1, 1000000):
		return ["Unsupported session rules or content version."]
	if not session.get("state") is Dictionary or not session.get("history") is Array:
		return ["Invalid board or undo history."]
	var states: Array = session.history.duplicate()
	states.append(session.state)
	var previous_moves: int = -1
	for state in states:
		if not state is Dictionary:
			return ["Invalid undo checkpoint."]
		var state_errors := _validate_state(state)
		if not state_errors.is_empty():
			return state_errors
		if state.level_id != "garden_%03d" % int(session.level_number):
			errors.append("Saved level identity does not match.")
		if previous_moves >= 0 and int(state.moves) != previous_moves + 1:
			errors.append("Undo history is not consecutive.")
		previous_moves = int(state.moves)
	return errors

static func _validate_state(state: Dictionary) -> Array:
	var errors: Array = []
	if state.get("schema_version") != BOARD_SCHEMA_VERSION or state.get("rules_version") != RULES_VERSION or not _integer(state.get("content_version"), 1, 1000000):
		return ["Unsupported saved board version."]
	if state.get("mode") not in ["campaign", "campaign_orders"]:
		return ["Unsupported saved mode."]
	for key in ["moves", "batches", "sequence", "initial_total"]:
		if not _integer(state.get(key), 0, 1000000):
			return ["Invalid board counter: " + key]
	if not state.get("level_id") is String or state.get("outcome") not in ["ready", "won", "recovery"]:
		return ["Invalid stable board identity or outcome."]
	if not state.get("trays") is Array or state.trays.size() < 2 or state.trays.size() > 32:
		return ["Invalid saved trays."]
	if state.has("extra_tray_granted"):
		if state.extra_tray_granted != true or state.get("extra_tray_id") != BoardModel.EXTRA_TRAY_ID or state.trays.size() > BoardModel.MAX_TRAYS:
			return ["Invalid extra-tray entitlement."]
		var extra: Variant = state.trays.back()
		if not extra is Dictionary or extra.get("id") != BoardModel.EXTRA_TRAY_ID or extra.get("queue") != []:
			return ["Invalid granted tray."]
	var ids: Array = []
	var remaining: int = 0
	for tray in state.trays:
		if not tray is Dictionary or not tray.get("id") is String or ids.has(tray.get("id")):
			return ["Invalid or duplicated tray identity."]
		ids.append(tray.id)
		if not tray.get("queue") is Array or tray.queue.size() > 100:
			return ["Invalid queued rows."]
		var rows: Array = [tray.get("front")]
		rows.append_array(tray.queue)
		for row_index in range(rows.size()):
			var row: Variant = rows[row_index]
			if not row is Array or row.size() != 3:
				return ["A saved row must contain exactly three slots."]
			var row_count: int = 0
			for food in row:
				if food == null:
					continue
				if not food is String or not FoodCatalog.has_food(str(food)):
					return ["Unknown saved food identity."]
				row_count += 1
			remaining += row_count
			if row_index > 0 and row_count == 0:
				return ["An empty queued row is invalid."]
			if row_index == 0 and ((row_count == 0 and not tray.queue.is_empty()) or (row_count == 3 and row[0] == row[1] and row[1] == row[2])):
				return ["The saved board is not at a stable checkpoint."]
	if int(state.sequence) != int(state.batches):
		errors.append("Saved batch event sequence does not balance.")
	if remaining + int(state.batches) * 3 != int(state.initial_total):
		errors.append("Saved token accounting does not balance.")
	if (state.outcome == "won") != (remaining == 0):
		errors.append("Saved outcome does not match remaining food.")
	if not state.get("tickets") is Array or not _integer(state.get("active_ticket_limit"), 1, 2):
		return ["Invalid saved tickets."]
	var credits_total: int = 0
	var ticket_ids: Array = []
	for ticket in state.tickets:
		if not ticket is Dictionary or not ticket.get("id") is String or ticket_ids.has(ticket.get("id")):
			return ["Invalid saved ticket identity."]
		ticket_ids.append(ticket.id)
		if not ticket.get("requirements") is Dictionary or not ticket.get("credits") is Dictionary or not ticket.get("served") is bool:
			return ["Invalid saved recipe accounting."]
		if ticket.requirements.is_empty() or (state.outcome == "won" and not ticket.served):
			errors.append("Saved ticket completion is invalid.")
		for food in ticket.credits:
			if not ticket.requirements.has(food):
				return ["Recipe credit has no matching demand."]
		for food in ticket.requirements:
			if not FoodCatalog.has_food(str(food)) or not _integer(ticket.requirements[food], 1, 100000):
				return ["Invalid saved recipe demand."]
			var credit: Variant = ticket.credits.get(food, 0)
			if not _integer(credit, 0, int(ticket.requirements[food])):
				return ["Invalid saved recipe credit."]
			credits_total += int(credit)
			if (ticket.served or state.outcome == "won") and int(credit) != int(ticket.requirements[food]):
				errors.append("A completed ticket is missing food credits.")
	if credits_total > int(state.batches):
		errors.append("Recipe credits exceed cleared batches.")
	return errors

static func _inventory(trays: Array) -> Dictionary:
	var result: Dictionary = {}
	for tray in trays:
		var rows: Array = [tray.front]
		rows.append_array(tray.queue)
		for row in rows:
			for food in row:
				if food != null:
					result[food] = int(result.get(food, 0)) + 1
	return result

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

## Canonical JSON makes hashes independent of key insertion order and JSON's
## conversion of integral numbers to float on load. No native object decoding.
static func _canonical(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var fields := PackedStringArray()
		for key in keys:
			fields.append(JSON.stringify(str(key)) + ":" + _canonical(value[key]))
		return "{" + ",".join(fields) + "}"
	if value is Array:
		var entries := PackedStringArray()
		for entry in value:
			entries.append(_canonical(entry))
		return "[" + ",".join(entries) + "]"
	if (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)):
		return str(int(value))
	return JSON.stringify(value)

static func _normalize_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = _normalize_numbers(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry in value:
			result.append(_normalize_numbers(entry))
		return result
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value

static func _migrate_payload(payload: Dictionary) -> Dictionary:
	var result: Dictionary = payload.duplicate(true)
	if int(result.schema_version) == 1:
		result.schema_version = SCHEMA_VERSION
		result.profile["tutorial"] = {"step": 0, "completed": false}
		result.profile["economy"] = {"version": 1, "ledger": {}}
		result.profile["owned_themes"] = ["classic"]
		result.profile["active_theme"] = "classic"
		if not result.session.is_empty():
			result.session["run_id"] = "legacy_" + _canonical(result.session).sha256_text().substr(0, 32)
			result.session["hint_receipts"] = {}
			result.session["extra_tray_granted"] = false
	return result

static func _validate_economy_profile(profile: Dictionary) -> Array:
	if not profile.get("tutorial") is Dictionary or not _integer(profile.tutorial.get("step"), 0, 3) or not profile.tutorial.get("completed") is bool:
		return ["Invalid cooking-school progress."]
	if profile.tutorial.completed and profile.tutorial.step != 3:
		return ["Completed cooking school is missing its final step."]
	if not profile.get("economy") is Dictionary or profile.economy.get("version") != 1 or not profile.economy.get("ledger") is Dictionary:
		return ["Unsupported economy version or ledger."]
	for receipt_id in profile.economy.ledger:
		var receipt: Variant = profile.economy.ledger[receipt_id]
		if not receipt is Dictionary or not receipt.get("kind") is String or not _integer(receipt.get("amount"), -100000000, 100000000):
			return ["Invalid coin transaction receipt."]
	if not profile.get("owned_themes") is Array or not profile.owned_themes.has("classic") or not profile.get("active_theme") is String or not profile.owned_themes.has(profile.active_theme):
		return ["Invalid owned or active tray theme."]
	var seen: Array = []
	for theme in profile.owned_themes:
		if theme not in ["classic", "sage", "berry"] or seen.has(theme):
			return ["Invalid tray theme ownership."]
		seen.append(theme)
	return []

static func _validate_session_extensions(session: Dictionary) -> Array:
	if not session.get("run_id") is String or session.run_id.is_empty() or session.run_id.length() > 100:
		return ["Invalid session run identity."]
	if not session.get("hint_receipts") is Dictionary or not session.get("extra_tray_granted") is bool:
		return ["Invalid session purchases."]
	if session.extra_tray_granted != bool(session.state.get("extra_tray_granted", false)):
		return ["Saved grant does not match the board."]
	for snapshot in session.history:
		if bool(snapshot.get("extra_tray_granted", false)) and not session.extra_tray_granted:
			return ["Undo history contains an unowned extra tray."]
	for key in session.hint_receipts:
		var receipt: Variant = session.hint_receipts[key]
		if not key is String or key.length() != 64 or not receipt is Dictionary or not receipt.get("solution") is Array or receipt.solution.is_empty() or not receipt.get("state") is Dictionary:
			return ["Invalid hint receipt."]
		if not _validate_state(receipt.state).is_empty() or receipt.state.level_id != session.state.level_id:
			return ["Invalid saved hint proof state."]
		var proof := BoardModel.new()
		proof.restore(receipt.state)
		if proof.search_key() != key:
			return ["Hint receipt does not match its puzzle identity."]
		for command in receipt.solution:
			if not command is Array or command.size() != 4:
				return ["Invalid saved hint command."]
			for index in range(4):
				if not _integer(command[index], 0, 7 if index % 2 == 0 else 2):
					return ["Invalid saved hint coordinates."]
	return []

static func is_campaign_level(level: Dictionary) -> bool:
	var number := int(level.get("number", 0))
	return not level.has("tutorial_step") and number >= 1 and number <= LEVEL_COUNT and level.get("level_id", "") == "garden_%03d" % number
