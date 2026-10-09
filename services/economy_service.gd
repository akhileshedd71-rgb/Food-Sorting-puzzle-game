class_name EconomyService
extends RefCounted
## Local earnable Chef Coins only. There is deliberately no paid-grant API.
## Durable debit + receipt + board effect are one SaveService envelope.

const HINT_COST := 10
const EXTRA_TRAY_COST := 40
const WELCOME_COINS := 100
const TUTORIAL_COINS := 30
const THEME_DEFINITIONS := [
	{"id": "classic", "name": "Classic blue", "cost": 0, "rim": "24637b", "accent": "d3d9d5"},
	{"id": "sage", "name": "Sage enamel", "cost": 120, "rim": "608e75", "accent": "d9e5a5"},
	{"id": "berry", "name": "Berry enamel", "cost": 180, "rim": "965b80", "accent": "efbdd9"}
]

var store: SaveService

func _init(save_store: SaveService) -> void:
	store = save_store

func initialize() -> Dictionary:
	if store.write_blocked:
		return _result("save_failed")
	var previous := store.data.duplicate(true)
	store.data = SaveService._migrate_payload(store.data)
	var awarded: int = 0
	if not _ledger().has("welcome:v1"):
		_record("welcome:v1", "welcome", WELCOME_COINS)
		awarded = WELCOME_COINS
	if not store.save_game():
		store.data = previous
		return _result("save_failed")
	return {"status": "ok", "charged": 0, "awarded": awarded}

func balance() -> int:
	return int(store.data.profile.coins)

func buy_hint(model: BoardModel, level: Dictionary, budget_ms: int = 100) -> Dictionary:
	if not _usable_campaign(model, level) or model.is_won():
		return _result("unavailable")
	var key := model.search_key()
	var existing: Dictionary = _current_receipts(model).get(key, {})
	if not existing.is_empty():
		var cached := _remap_witness(existing.state, model, existing.solution)
		if not cached.is_empty():
			return {"status": "ok", "move": cached[0], "charged": 0, "cached": true}
	if balance() < HINT_COST:
		return _result("insufficient")
	var solution := _certified_path(model, level)
	if solution.is_empty():
		var solved := PuzzleSolver.solve(model, budget_ms)
		if solved.status == "UNKNOWN":
			return _result("unknown")
		if solved.status != "SOLVED":
			return _result("unavailable")
		solution = _remap_witness(model.snapshot(), model, solved.moves)
	if solution.is_empty():
		return _result("unavailable")
	var previous := store.data.duplicate(true)
	store.stage_session(model, level)
	var receipt_id := "hint:" + model.run_id + ":" + key
	# The ledger is permanent within the run; the board and undo are reversible.
	var charged: int = 0
	if not _ledger().has(receipt_id):
		_record(receipt_id, "hint", -HINT_COST)
		charged = HINT_COST
	store.data.session.hint_receipts[key] = {"state": model.snapshot(), "solution": solution.duplicate(true)}
	if not store.save_game():
		store.data = previous
		return _result("save_failed")
	return {"status": "ok", "move": solution[0], "charged": charged, "cached": false}

func buy_extra_tray(model: BoardModel, level: Dictionary) -> Dictionary:
	if not _usable_campaign(model, level) or model.is_won() or model.extra_tray_granted or model.state.trays.size() >= BoardModel.MAX_TRAYS:
		return _result("unavailable")
	if balance() < EXTRA_TRAY_COST:
		return _result("insufficient")
	var previous := store.data.duplicate(true)
	var old_state := model.snapshot()
	var old_history: Array = model.history.duplicate(true)
	var old_events: Array = model.last_events.duplicate(true)
	var old_run_id := model.run_id
	if not model.grant_extra_tray():
		return _result("unavailable")
	store.stage_session(model, level)
	var receipt_id := "extra:" + model.run_id
	if _ledger().has(receipt_id):
		# A grant must already be present after resume/undo. Never silently
		# issue another item if a caller supplied an inconsistent session.
		model.restore(old_state)
		model.history = old_history
		model.last_events = old_events
		model.run_id = old_run_id
		store.data = previous
		return _result("unavailable")
	_record(receipt_id, "extra_tray", -EXTRA_TRAY_COST)
	if not store.save_game():
		store.data = previous
		model.restore(old_state)
		model.history = old_history
		model.last_events = old_events
		model.run_id = old_run_id
		return _result("save_failed")
	return {"status": "ok", "charged": EXTRA_TRAY_COST}

func themes() -> Array:
	var result: Array = []
	for definition in THEME_DEFINITIONS:
		var theme: Dictionary = definition.duplicate()
		theme.rim = Color(str(theme.rim))
		theme.accent = Color(str(theme.accent))
		theme["owned"] = store.data.profile.owned_themes.has(theme.id)
		theme["equipped"] = store.data.profile.active_theme == theme.id
		result.append(theme)
	return result

func buy_theme(id: String) -> Dictionary:
	var definition := _theme(id)
	if definition.is_empty():
		return _result("unavailable")
	if store.data.profile.owned_themes.has(id):
		return _result("ok")
	var cost: int = int(definition.cost)
	if balance() < cost:
		return _result("insufficient")
	var previous := store.data.duplicate(true)
	_record("theme:" + id, "theme", -cost)
	store.data.profile.owned_themes.append(id)
	store.data.profile.active_theme = id
	if not store.save_game():
		store.data = previous
		return _result("save_failed")
	return {"status": "ok", "charged": cost}

func equip_theme(id: String) -> Dictionary:
	if _theme(id).is_empty() or not store.data.profile.owned_themes.has(id):
		return _result("unavailable")
	if store.data.profile.active_theme == id:
		return _result("ok")
	var previous := store.data.duplicate(true)
	store.data.profile.active_theme = id
	if not store.save_game():
		store.data = previous
		return _result("save_failed")
	return _result("ok")

func complete_tutorial() -> Dictionary:
	if tutorial_complete():
		return {"status": "ok", "charged": 0, "awarded": 0}
	var previous := store.data.duplicate(true)
	var awarded: int = 0
	if not _ledger().has("tutorial:graduation"):
		_record("tutorial:graduation", "tutorial", TUTORIAL_COINS)
		awarded = TUTORIAL_COINS
	store.data.profile.tutorial = {"step": 3, "completed": true}
	if not store.save_game():
		store.data = previous
		return _result("save_failed")
	return {"status": "ok", "charged": 0, "awarded": awarded}

func set_tutorial_step(step: int) -> bool:
	var next := maxi(tutorial_step(), clampi(step, 0, 3))
	if next == tutorial_step():
		return true
	var previous := store.data.duplicate(true)
	store.data.profile.tutorial.step = next
	if not store.save_game():
		store.data = previous
		return false
	return true

func tutorial_step() -> int:
	return int(store.data.profile.tutorial.step)

func tutorial_complete() -> bool:
	return bool(store.data.profile.tutorial.completed)

func _current_receipts(model: BoardModel) -> Dictionary:
	if store.data.session.get("run_id", "") != model.run_id:
		return {}
	return store.data.session.get("hint_receipts", {})

func _usable_campaign(model: BoardModel, level: Dictionary) -> bool:
	return not store.write_blocked and SaveService.is_campaign_level(level) and not model.state.is_empty() and model.state.level_id == level.level_id and not model.run_id.is_empty()

func _ledger() -> Dictionary:
	return store.data.profile.economy.ledger

func _record(id: String, kind: String, amount: int) -> void:
	_ledger()[id] = {"kind": kind, "amount": amount}
	store.data.profile.coins = balance() + amount

static func _theme(id: String) -> Dictionary:
	for definition in THEME_DEFINITIONS:
		if definition.id == id:
			return definition
	return {}

static func _result(status: String) -> Dictionary:
	return {"status": status, "charged": 0}

static func _certified_path(model: BoardModel, level: Dictionary) -> Array:
	var proof := BoardModel.new()
	proof.setup(level)
	if model.extra_tray_granted:
		proof.grant_extra_tray()
	var commands: Array = level.get("solution", [])
	for index in range(commands.size()):
		if proof.search_key() == model.search_key():
			return _remap_witness(proof.snapshot(), model, commands.slice(index))
		var command: Array = commands[index]
		if command.size() != 4 or not proof.apply_move(command[0], command[1], command[2], command[3]):
			return []
	return []

## Slot-equivalent proof states share a receipt. Remap EVERY witness command
## onto actual slots, then require a full win before revealing a paid hint.
static func _remap_witness(reference_state: Dictionary, actual: BoardModel, commands: Array) -> Array:
	var reference := BoardModel.new()
	reference.restore(reference_state)
	var replay := BoardModel.new()
	replay.restore(actual.snapshot())
	if reference.search_key() != replay.search_key():
		return []
	var remapped: Array = []
	for command in commands:
		if not command is Array or command.size() != 4:
			return []
		var source_tray: int = int(command[0])
		var target_tray: int = int(command[2])
		if source_tray < 0 or source_tray >= reference.state.trays.size() or target_tray < 0 or target_tray >= reference.state.trays.size() or int(command[1]) < 0 or int(command[1]) > 2:
			return []
		var food: Variant = reference.state.trays[source_tray].front[int(command[1])]
		if food == null:
			return []
		var source_slot: int = replay.state.trays[source_tray].front.find(food)
		var target_slot: int = replay.state.trays[target_tray].front.find(null)
		if source_slot < 0 or target_slot < 0:
			return []
		if not reference.apply_move(source_tray, int(command[1]), target_tray, int(command[3])) or not replay.apply_move(source_tray, source_slot, target_tray, target_slot):
			return []
		remapped.append([source_tray, source_slot, target_tray, target_slot])
		if reference.search_key() != replay.search_key():
			return []
	return remapped if replay.is_won() else []
