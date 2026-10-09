extends SceneTree
## Transactions, migration, certified assistance and permanent grant regressions.

class FaultStore extends SaveService:
	var fail_phase: String = ""
	func _write_checked(path: String, envelope: Dictionary) -> bool:
		if fail_phase == "write" and path == save_path + ".tmp":
			last_error = "Injected failure before durable temp write."
			return false
		var written := super._write_checked(path, envelope)
		if fail_phase == "late_write" and path == save_path + ".tmp" and written:
			last_error = "Injected status error after complete temp write."
			return false
		return written
	func _replace(source: String, target: String) -> bool:
		if fail_phase == "rename" and target == save_path:
			last_error = "Injected failure after durable temp write."
			return false
		return super._replace(source, target)

var checks: int = 0
var failures: int = 0
var test_root := "user://economy_tests"

func _initialize() -> void:
	if not OS.get_environment("GARDEN_TEST_SAVE_DIR").is_empty():
		test_root = OS.get_environment("GARDEN_TEST_SAVE_DIR").path_join("economy")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_root))
	_test_migration()
	_test_hints()
	_test_extra_tray()
	_test_profile_purchases()
	_test_atomic_failures()
	print("Economy checks: %d; failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_migration() -> void:
	var path := _path("migration")
	_clean(path)
	var old := SaveService.new(path)
	var level := _level()
	var model := BoardModel.new()
	model.setup(level)
	_play_solution(model, level)
	old.commit_session(model, level)
	var legacy: Dictionary = old.data.duplicate(true)
	legacy.schema_version = 1
	for key in ["tutorial", "economy", "owned_themes", "active_theme"]:
		legacy.profile.erase(key)
	for key in ["run_id", "hint_receipts", "extra_tray_granted"]:
		legacy.session.erase(key)
	_clean(path)
	_write(path, SaveService._make_envelope(legacy, 7))
	var loaded := SaveService.new(path)
	_check(loaded.load_save(), "Original v1 checksum envelope loads")
	_check(loaded.data.schema_version == 2 and loaded.data.profile.coins == 30 and loaded.data.profile.completed.size() == 1, "v1 migration preserves earned coins and completed levels")
	_check(loaded.validate_session(level).is_empty(), "Migrated session preserves original content and board")
	var economy := EconomyService.new(loaded)
	_check(economy.initialize().awarded == 100 and economy.balance() == 130, "Migration grants one welcome gift on top of earned coins")
	_check(economy.initialize().awarded == 0 and economy.balance() == 130, "Initialization cannot duplicate welcome gift")
	var resumed := SaveService.new(path)
	_check(resumed.load_save(), "Migrated envelope persists at v2")
	economy = EconomyService.new(resumed)
	_check(economy.initialize().awarded == 0 and economy.balance() == 130, "Cold-start initialization does not repeat welcome gift")
	var future: Dictionary = resumed.data.duplicate(true)
	future.schema_version = 99
	var future_envelope := SaveService._make_envelope(future, 999)
	_write(path, future_envelope)
	var future_text := FileAccess.get_file_as_string(path)
	var blocked := SaveService.new(path)
	_check(not blocked.load_save() and blocked.write_blocked, "Future primary is rejected despite readable older backup")
	_check(EconomyService.new(blocked).initialize().status == "save_failed", "Future schema cannot be overwritten by initialization")
	_check(FileAccess.get_file_as_string(path) == future_text, "Unknown future save bytes are preserved")
	_clean(path)
	_write(path + ".bak", SaveService._make_envelope(legacy, 7))
	for bad_version in ["bad", {}, null]:
		var malformed := SaveService._make_envelope(legacy, 8)
		malformed.envelope_version = bad_version
		_write(path, malformed)
		var fallback := SaveService.new(path)
		_check(fallback.load_save() and not fallback.write_blocked, "Malformed envelope version recovers valid backup")
		var bad_payload: Dictionary = legacy.duplicate(true)
		bad_payload.schema_version = bad_version
		_write(path, SaveService._make_envelope(bad_payload, 8))
		fallback = SaveService.new(path)
		_check(fallback.load_save() and not fallback.write_blocked, "Malformed payload version recovers valid backup")
	_clean(path)

func _test_hints() -> void:
	var service := _fresh("hints")
	var economy := EconomyService.new(service)
	var level := _level()
	var model := BoardModel.new()
	model.setup(level)
	var first_hash := model.state_hash()
	var duplicate := BoardModel.new()
	duplicate.setup(level)
	_check(model.run_id != duplicate.run_id and first_hash == duplicate.state_hash(), "Per-run identity never changes original replay hashes")
	service.commit_session(model, level)
	var result := economy.buy_hint(model, level, 0)
	_check(result.status == "ok" and result.charged == 10 and economy.balance() == 90, "Certified stored solution gives legal paid hint with no search budget")
	_check(model.legal_moves().has(result.move) and model.state_hash() == first_hash, "A hint reveals a command without moving food")
	_check(economy.buy_hint(model, level).charged == 0 and economy.balance() == 90, "Repeat exact-state receipt does not charge twice")
	# Slot-equivalent state keeps the same receipt but changes actual destination.
	model.state.trays[0].front = [null, "tomato", "tomato"]
	result = economy.buy_hint(model, level)
	_check(result.status == "ok" and result.charged == 0 and result.move[3] == 0 and model.legal_moves().has(result.move), "Cached witness remaps slots before returning free hint")
	_check(model.apply_move(0, 1, 2, 1) and model.apply_move(2, 1, 0, 1), "Harmless cycle returns to the same logical puzzle")
	_check(economy.buy_hint(model, level).charged == 0 and economy.balance() == 90, "Move counters do not allow repeated charges for same puzzle")
	service.commit_session(model, level)
	var loaded := SaveService.new(service.save_path)
	_check(loaded.load_save(), "Hint receipt survives disk reload")
	var resumed := BoardModel.new()
	_check(loaded.restore_session(resumed) and resumed.run_id == model.run_id, "Resume preserves run identity")
	var resumed_economy := EconomyService.new(loaded)
	_check(resumed_economy.buy_hint(resumed, level).charged == 0 and resumed_economy.balance() == 90, "Resumed hint receipt remains free")
	resumed.setup(level)
	_check(resumed_economy.buy_hint(resumed, level).charged == 10 and resumed_economy.balance() == 80, "Explicit restart starts a separate run")
	# Off-path states may be solved, but a timeout is never sold as a hint.
	resumed.setup(level)
	resumed.apply_move(0, 0, 2, 1)
	var before := resumed_economy.balance()
	_check(resumed_economy.buy_hint(resumed, level, 0).status == "unknown" and resumed_economy.balance() == before, "Off-path timeout spends nothing")
	result = resumed_economy.buy_hint(resumed, level, 1000)
	_check(result.status == "ok" and result.charged == 10 and resumed.legal_moves().has(result.move), "Bounded solver certifies a full off-path solution before charging")
	var broken_level: Dictionary = _level().duplicate(true)
	broken_level.solution = [[0, 0, 0, 2]]
	resumed.setup(broken_level)
	before = resumed_economy.balance()
	_check(resumed_economy.buy_hint(resumed, broken_level, 0).status == "unknown" and resumed_economy.balance() == before, "Illegal authored witness cannot charge currency")
	loaded.data.profile.coins = 0
	resumed.setup(level)
	_check(resumed_economy.buy_hint(resumed, level).status == "insufficient", "Insufficient balance cannot buy an uncached hint")
	_play_solution(resumed, level)
	_check(resumed_economy.buy_hint(resumed, level).status == "unavailable", "Completed board has no purchasable hint")
	_clean(service.save_path)

func _test_extra_tray() -> void:
	var service := _fresh("extra")
	var economy := EconomyService.new(service)
	var level := _level()
	var model := BoardModel.new()
	model.setup(level)
	model.apply_move(0, 0, 2, 1)
	var before_grant_tokens := model.remaining_tokens()
	var result := economy.buy_extra_tray(model, level)
	_check(result.status == "ok" and result.charged == 40 and economy.balance() == 60, "Extra tray debits exactly 40 coins")
	_check(model.extra_tray_granted and model.state.trays.size() == 4 and model.remaining_tokens() == before_grant_tokens, "Granted tray adds space without creating food")
	_check(economy.buy_extra_tray(model, level).status == "unavailable" and economy.balance() == 60, "Only one extra tray can be purchased per run")
	_check(model.apply_move(2, 1, 3, 0), "Food can enter the purchased tray")
	_check(model.undo() and model.state.trays[3].front == [null, null, null], "Undo restores the tray's earlier empty contents")
	_check(model.undo() and model.extra_tray_granted and model.state.trays.size() == 4 and model.state.trays[3].front == [null, null, null], "Undo across purchase reapplies an empty permanent grant")
	_check(model.remaining_tokens() == 6 and SaveService._inventory(model.state.trays) == SaveService._inventory(level.trays), "Undo across grant preserves exact per-food inventory")
	service.commit_session(model, level)
	_check(service.last_error.is_empty() and service.validate_session(level).is_empty(), "Granted board validates against unchanged authored inventory")
	var loaded := SaveService.new(service.save_path)
	_check(loaded.load_save() and loaded.validate_session(level).is_empty(), "Permanent grant survives cold load")
	var restored := BoardModel.new()
	loaded.restore_session(restored)
	_check(restored.extra_tray_granted and EconomyService.new(loaded).buy_extra_tray(restored, level).status == "unavailable", "Resume cannot repurchase same run grant")
	var enlarged: Dictionary = level.duplicate(true)
	for index in range(3, 8):
		enlarged.trays.append({"id": "t%d" % index, "front": [null, null, null], "queue": []})
	model.setup(enlarged)
	_check(economy.buy_extra_tray(model, enlarged).status == "unavailable" and model.state.trays.size() == 8, "Eight-tray cap rejects purchase")
	model.setup(level)
	_play_solution(model, level)
	_check(economy.buy_extra_tray(model, level).status == "unavailable", "Won board cannot buy extra tray")
	model.setup(level)
	service.data.profile.coins = 0
	_check(economy.buy_extra_tray(model, level).status == "insufficient" and not model.extra_tray_granted, "Insufficient funds leave board unchanged")
	_clean(service.save_path)

func _test_profile_purchases() -> void:
	var service := _fresh("profile")
	var economy := EconomyService.new(service)
	_check(economy.themes().size() == 3 and economy.themes()[0].owned, "Classic theme is initially owned")
	_check(economy.buy_theme("sage").status == "insufficient" and economy.equip_theme("sage").status == "unavailable", "Unowned theme cannot be equipped or bought without funds")
	_check(economy.set_tutorial_step(2) and economy.set_tutorial_step(1) and economy.tutorial_step() == 2, "Tutorial progress is monotonic")
	_check(economy.complete_tutorial().awarded == 30 and economy.balance() == 130 and economy.tutorial_complete(), "Graduation marks completion and awards 30 coins together")
	_check(economy.complete_tutorial().awarded == 0 and economy.balance() == 130, "Tutorial reward is once-only")
	_check(economy.buy_theme("sage").charged == 120 and economy.balance() == 10, "Sage theme costs 120 Chef Coins")
	_check(service.data.profile.active_theme == "sage" and economy.buy_theme("sage").charged == 0 and economy.balance() == 10, "Purchased theme equips and cannot charge twice")
	_check(economy.equip_theme("classic").status == "ok" and economy.equip_theme("sage").status == "ok", "Owned themes equip freely")
	_check(economy.buy_theme("unknown").status == "unavailable", "Unknown theme is unavailable")
	for number in range(1, 7):
		var level := _level(number)
		var model := BoardModel.new()
		model.setup(level)
		_play_solution(model, level)
		service.commit_session(model, level)
	_check(economy.balance() == 190, "Campaign first-clear coins remain earnable after purchases")
	_check(economy.buy_theme("berry").charged == 180 and economy.balance() == 10, "Berry theme costs 180 Chef Coins")
	var before := service.data.duplicate(true)
	var tutorial := _level()
	tutorial.level_id = "cooking_school_001"
	tutorial["tutorial_step"] = 1
	var tutorial_model := BoardModel.new()
	tutorial_model.setup(tutorial)
	_play_solution(tutorial_model, tutorial)
	service.commit_session(tutorial_model, tutorial)
	_check(service.data == before, "Accidental school commit neither replaces campaign nor grants first-clear coins")
	_check(economy.buy_hint(tutorial_model, tutorial).status == "unavailable", "Cooking school cannot incur a paid hint")
	var loaded := SaveService.new(service.save_path)
	_check(loaded.load_save(), "Cosmetic ownership reloads")
	var resumed_economy := EconomyService.new(loaded)
	_check(resumed_economy.tutorial_complete() and resumed_economy.complete_tutorial().awarded == 0 and loaded.data.profile.owned_themes.size() == 3, "Themes and tutorial receipt survive restart")
	_clean(service.save_path)

func _test_atomic_failures() -> void:
	var path := _path("failures")
	_clean(path)
	var store := FaultStore.new(path)
	var economy := EconomyService.new(store)
	_check(economy.initialize().status == "ok", "Fault harness initializes")
	var level := _level()
	var model := BoardModel.new()
	model.setup(level)
	store.commit_session(model, level)
	var original := model.state_hash()
	var old_run := model.run_id
	store.fail_phase = "write"
	_check(economy.buy_extra_tray(model, level).status == "save_failed" and economy.balance() == 100, "Pre-commit failure refunds extra tray debit")
	_check(not model.extra_tray_granted and model.state_hash() == original and model.run_id == old_run, "Pre-commit failure restores model, history and run identity")
	_check(economy.buy_hint(model, level).status == "save_failed" and economy.balance() == 100 and store.data.session.hint_receipts.is_empty(), "Pre-commit failure refunds hint and discards receipt")
	_check(economy.complete_tutorial().status == "save_failed" and not economy.tutorial_complete() and economy.balance() == 100, "Failed tutorial reward rolls back completion and currency")
	_check(not economy.set_tutorial_step(2) and economy.tutorial_step() == 0, "Failed step save rolls back tutorial progress")
	var reloaded := SaveService.new(path)
	_check(reloaded.load_save() and reloaded.data.profile.coins == 100 and not reloaded.data.session.extra_tray_granted, "Failed purchase cannot reappear on cold load")
	store.fail_phase = "rename"
	var result := economy.buy_extra_tray(model, level)
	_check(result.status == "ok" and economy.balance() == 60 and model.extra_tray_granted, "Verified durable temp is a successful purchase despite rename failure")
	reloaded = SaveService.new(path)
	_check(reloaded.load_save() and reloaded.data.profile.coins == 60 and reloaded.data.session.extra_tray_granted, "Crash recovery restores debit and extra tray atomically from pending temp")
	store.fail_phase = ""
	_check(store.save_game(), "Recovered transaction can finalize on a later save")
	store.fail_phase = "late_write"
	_check(economy.complete_tutorial().status == "ok" and economy.balance() == 90, "Late status error after verified temp cannot roll back a recoverable reward")
	reloaded = SaveService.new(path)
	_check(reloaded.load_save() and reloaded.data.profile.coins == 90 and reloaded.data.profile.tutorial.completed, "Late-write transaction has the same outcome on disk and in memory")
	store.fail_phase = ""
	store.data.profile.coins = 500
	store.save_game()
	store.fail_phase = "write"
	_check(economy.buy_theme("berry").status == "save_failed" and economy.balance() == 500 and not store.data.profile.owned_themes.has("berry"), "Failed theme purchase restores coins and ownership")
	store.fail_phase = ""
	economy.buy_theme("sage")
	store.fail_phase = "write"
	_check(economy.equip_theme("classic").status == "save_failed" and store.data.profile.active_theme == "sage", "Failed theme equip restores prior theme")
	_clean(path)
	store = FaultStore.new(path)
	store.fail_phase = "write"
	economy = EconomyService.new(store)
	_check(economy.initialize().status == "save_failed" and economy.balance() == 0 and store.data.profile.economy.ledger.is_empty(), "Failed welcome gift creates no in-memory entitlement")
	_clean(path)

func _fresh(name: String) -> SaveService:
	var path := _path(name)
	_clean(path)
	var service := SaveService.new(path)
	_check(EconomyService.new(service).initialize().status == "ok", "Initialize " + name)
	return service

func _level(number: int = 2) -> Dictionary:
	return {"schema_version": 1, "content_version": 1, "level_id": "garden_%03d" % number,
		"number": number, "mode": "campaign", "active_ticket_limit": 1,
		"trays": [
			{"id": "t1", "front": ["tomato", "tomato", null], "queue": []},
			{"id": "t2", "front": ["corn_cob", "corn_cob", "tomato"], "queue": []},
			{"id": "t3", "front": ["corn_cob", null, null], "queue": []}],
		"tickets": [], "solution": [[1, 2, 0, 2], [2, 0, 1, 2]]}

func _play_solution(model: BoardModel, level: Dictionary) -> void:
	for command in level.solution:
		_check(model.apply_move(command[0], command[1], command[2], command[3]), "Fixture solution command is legal")

func _path(name: String) -> String:
	return test_root.path_join(name + ".json")

func _write(path: String, envelope: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(SaveService._canonical(envelope))
	file.close()

func _clean(path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
