extends SceneTree
## Focused persistence regression suite. Uses a separate directory, never player saves.
## Run: godot --headless --path . --script tests/save_tests.gd

class ArchiveFailureStore extends SaveService:
	func _archive_file(_source: String, _target: String) -> bool:
		return false

var failures: int = 0
var checks: int = 0
var test_directory: String
var save_path: String

func _initialize() -> void:
	test_directory = OS.get_environment("GARDEN_TEST_SAVE_DIR")
	if test_directory.is_empty():
		test_directory = "user://save_tests"
	save_path = test_directory.path_join("integrity.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_directory))
	_cleanup()
	_test_profile_and_rewards()
	_test_recipe_undo_roundtrip()
	_test_recovery_boundaries()
	_test_corruption_archives()
	_test_validation_and_reset()
	_test_v02_content_expansion()
	_test_later_chapter_persistence()
	_cleanup()
	_test_audio.call_deferred()

func _test_profile_and_rewards() -> void:
	var service := SaveService.new(save_path)
	_check(not service.load_save() and service.last_error.is_empty(), "Fresh install has defaults without a corruption warning")
	service.data.profile.settings.sound = false
	service.data.profile.settings.music = true
	service.data.profile.settings.reduced_motion = true
	var level := _simple_level()
	var model := BoardModel.new()
	model.setup(level)
	service.commit_session(model, level)
	_check(service.last_error.is_empty(), "Initial stable checkpoint writes: " + service.last_error)
	var loaded := SaveService.new(save_path)
	_check(loaded.load_save(), "Valid checksummed envelope loads")
	_check(not loaded.data.profile.settings.sound and loaded.data.profile.settings.music and loaded.data.profile.settings.reduced_motion, "Independent settings round-trip")
	_check(loaded.validate_session(level).is_empty(), "Current content accepts saved state")
	var old_save: Dictionary = loaded.data.session.state.duplicate(true)
	_check(model.apply_move(1, 0, 0, 2), "Winning fixture command is legal")
	_check(loaded.data.session.state == old_save, "Saved snapshots do not alias model mutation")
	service.commit_session(model, level)
	_check(service.last_error.is_empty(), "Won board and completion commit together: " + service.last_error)
	_check(service.data.profile.coins == 30 and service.data.profile.unlocked == 2 and service.data.profile.completed.size() == 1, "First clear grants 30 coins and one unlock")
	service.commit_session(model, level)
	_check(service.data.profile.coins == 30, "Repeated presentation/Next callback cannot repeat reward")
	model.undo()
	service.commit_session(model, level)
	model.apply_move(1, 0, 0, 2)
	service.commit_session(model, level)
	_check(service.data.profile.coins == 30, "Undo and repeat win cannot duplicate permanent reward")
	_check(loaded.load_save(), "Completed checkpoint reloads")
	loaded.commit_session(model, level)
	_check(loaded.data.profile.coins == 30, "Cold-start win settlement is idempotent")
	var changed: Dictionary = level.duplicate(true)
	changed.content_version = 2
	_check(not loaded.validate_session(changed).is_empty(), "Changed content is rejected before restoring indices")
	_check(loaded.data.profile.completed.size() == 1, "Content mismatch preserves permanent completion")

func _test_recipe_undo_roundtrip() -> void:
	var level := _recipe_level()
	var model := BoardModel.new()
	model.setup(level)
	for command in [[1, 1, 0, 2], [2, 1, 0, 2], [0, 2, 2, 1], [2, 0, 0, 2]]:
		_check(model.apply_move(command[0], command[1], command[2], command[3]), "Prepared recipe replay command accepted")
	var service := SaveService.new(save_path)
	service.load_save()
	service.commit_session(model, level)
	_check(service.last_error.is_empty(), "Prepared future-ticket state saves: " + service.last_error)
	var loaded := SaveService.new(save_path)
	_check(loaded.load_save() and loaded.validate_session(level).is_empty(), "Layered board, future credits and undo history validate after reload")
	var resumed := BoardModel.new()
	resumed.restore(loaded.data.session.state)
	resumed.history = loaded.data.session.history.duplicate(true)
	_check(resumed.state_hash() == model.state_hash() and resumed.history.size() == model.history.size(), "Exact stable checksum and history survive JSON round-trip")
	_check(resumed.state.tickets[1].credits.bell_pepper_ring == 1 and not resumed.state.tickets[1].served, "Prepared future recipe survives reload without premature serve")
	resumed.undo()
	model.undo()
	_check(resumed.state_hash() == model.state_hash(), "Undo restores complete queue, recipe and counters after reload")

func _test_recovery_boundaries() -> void:
	var service := SaveService.new(save_path)
	service.load_save()
	service.data.profile.settings.haptics = false
	_check(service.save_game(), "Write known backup checkpoint")
	service.data.profile.settings.haptics = true
	_check(service.save_game(), "Write newer checkpoint before corruption")
	_write_text(save_path, "{interrupted garbage")
	var recovered := SaveService.new(save_path)
	_check(recovered.load_save() and not recovered.data.profile.settings.haptics, "Corrupt newest file recovers previous valid backup")
	_check(not recovered.recovery_notice.is_empty() and recovered.data.profile.coins == 30, "Recovery is visible and preserves earned coins")
	# Simulate a process stopping after validated temp flush and before rename.
	var temp_payload: Dictionary = recovered.data.duplicate(true)
	temp_payload.profile.settings.high_readability = true
	var envelope := SaveService._make_envelope(temp_payload, 500)
	_write_text(save_path + ".tmp", SaveService._canonical(envelope))
	var interrupted := SaveService.new(save_path)
	_check(interrupted.load_save() and interrupted.data.profile.settings.high_readability, "Complete pending temp wins over older main/backup revisions")
	_check(interrupted.save_game(), "A recovered temp can safely be saved again")
	_write_text(save_path, "bad primary")
	var after_rewrite := SaveService.new(save_path)
	_check(after_rewrite.load_save() and after_rewrite.data.profile.settings.high_readability, "Rewriting temp first preserved the newest valid checkpoint as backup")
	_cleanup()
	_write_text(save_path + ".bak.tmp", SaveService._canonical(envelope))
	var backup_interrupted := SaveService.new(save_path)
	_check(backup_interrupted.load_save(), "Interrupted backup replacement recovers its validated pending copy")
	_check(backup_interrupted.save_game(), "Sole valid pending backup is safely promoted on next write")
	_cleanup()
	_write_text(save_path, "corrupt main")
	_write_text(save_path + ".bak", "corrupt backup")
	var damaged := SaveService.new(save_path)
	_check(not damaged.load_save() and not damaged.recovery_notice.is_empty(), "All-copy corruption produces an explicit recovery notice")
	_check(FileAccess.get_file_as_string(save_path) == "corrupt main", "Failed load preserves damaged files for inspection")

func _test_corruption_archives() -> void:
	_cleanup()
	var original_hashes: Array = []
	for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
		var path: String = save_path + suffix
		_write_text(path, "damaged bytes " + suffix)
		original_hashes.append(FileAccess.get_sha256(path))
	var damaged := SaveService.new(save_path)
	_check(not damaged.load_save(), "All-copy damage is detected before automatic initialization")
	_check(EconomyService.new(damaged).initialize().status == "ok", "Fresh initialization succeeds after preserving every damaged copy")
	var archives := _archive_files()
	_check(archives.size() == 4 and damaged.recovery_notice.contains(".corrupt"), "Every original has a separate archive and the notice identifies them")
	var archived_hashes: Array = []
	for archive in archives:
		archived_hashes.append(FileAccess.get_sha256(archive))
	for original_hash in original_hashes:
		_check(archived_hashes.has(original_hash), "Archived damaged bytes exactly match their original")
	var loaded := SaveService.new(save_path)
	_check(loaded.load_save() and loaded.data.profile.coins == 100, "Fresh profile is valid without losing damaged originals")
	_check(EconomyService.new(loaded).initialize().awarded == 0 and _archive_files().size() == 4, "Later normal saves neither overwrite archives nor duplicate welcome reward")
	_cleanup()
	_write_text(save_path, "keep this original if archive fails")
	var blocked := ArchiveFailureStore.new(save_path)
	blocked.load_save()
	_check(EconomyService.new(blocked).initialize().status == "save_failed", "Archive failure prevents replacement by automatic initialization")
	_check(FileAccess.get_file_as_string(save_path) == "keep this original if archive fails" and blocked.data.profile.coins == 0, "Archive failure retains original bytes and rolls back welcome reward")
	_cleanup()

func _archive_files() -> Array:
	var result: Array = []
	var directory := DirAccess.open(save_path.get_base_dir())
	if directory == null:
		return result
	for filename in directory.get_files():
		if filename.begins_with(save_path.get_file()) and filename.contains(".corrupt."):
			result.append(save_path.get_base_dir().path_join(filename))
	return result

func _test_validation_and_reset() -> void:
	_cleanup()
	var service := SaveService.new(save_path)
	var model := BoardModel.new()
	var level := _simple_level()
	model.setup(level)
	service.commit_session(model, level)
	var good: Dictionary = service.data.duplicate(true)
	service.data.session.state.trays[0].front[0] = "unrecognized_food"
	_check(not service.save_game(), "Unknown food ID is rejected before replacing a valid save")
	service.data = good.duplicate(true)
	service.data.session.state.initial_total = 300
	_check(not service.save_game(), "Token accounting corruption is rejected")
	service.data = good.duplicate(true)
	service.data.profile.settings.sound = "yes"
	_check(not service.save_game(), "Nonboolean audio setting is rejected")
	service.data = good.duplicate(true)
	var forged := SaveService._make_envelope(service.data, 2000)
	forged.payload.profile.coins = 500000
	_write_text(save_path + ".tmp", SaveService._canonical(forged))
	var loaded := SaveService.new(save_path)
	_check(loaded.load_save() and loaded.data.profile.coins == 0, "Payload tampering fails checksum even at a higher revision")
	_cleanup()
	service = SaveService.new(save_path)
	level = _simple_level(LevelCatalog.LEVEL_COUNT)
	model.setup(level)
	model.apply_move(1, 0, 0, 2)
	service.commit_session(model, level)
	_check(service.data.profile.unlocked == LevelCatalog.LEVEL_COUNT and service.last_error.is_empty(), "Final chapter unlock stays within the authored campaign")
	service.clear_session()
	_check(service.data.session.is_empty() and service.data.profile.coins == 30, "Discarding a session preserves completion and currency")
	service.reset_progress()
	_check(service.last_error.is_empty() and service.data.profile.coins == 0 and service.data.profile.unlocked == 1, "Confirmed reset writes fresh profile")
	_write_text(save_path, "damaged after reset")
	loaded = SaveService.new(save_path)
	_check(loaded.load_save() and loaded.data.profile.completed.is_empty(), "Backup recovery cannot resurrect progress after confirmed reset")

func _test_v02_content_expansion() -> void:
	_cleanup()
	# Frozen bytes captured by the actual v0.2 production services before
	# changing either the catalog or SaveService. Never regenerate on test runs.
	var original_text := FileAccess.get_file_as_string("res://tests/fixtures/v0_2_completed_30_save.json")
	var original: Dictionary = JSON.parse_string(original_text).payload
	_write_text(save_path, original_text)
	var service := SaveService.new(save_path)
	_check(service.load_save(), "Authentic v0.2 envelope loads after content expansion")
	_check(service.data.schema_version == 2 and service.data.profile.unlocked == 31, "Completed old capstone unlocks 31 without a schema change")
	var expected: Dictionary = original.duplicate(true)
	expected.profile.unlocked = 31
	_check(SaveService._canonical(service.data) == SaveService._canonical(expected), "Unlock reconciliation changes no wallet, session, receipt, history, theme or tutorial field")
	var level := LevelCatalog.load_level(30)
	_check(not level.is_empty() and service.validate_session(level).is_empty(), "Frozen level30 dictionary remains compatible with the v0.2 content hash")
	var model := BoardModel.new()
	_check(service.restore_session(model) and model.run_id == original.session.run_id, "Legacy paid run resumes with its original identity")
	_check(model.extra_tray_granted and model.state.trays.back().front == ["tomato", null, null] and model.history.size() == 2, "Occupied purchased tray and pre-grant undo history survive expansion")
	var economy := EconomyService.new(service)
	_check(economy.initialize().awarded == 0 and economy.balance() == 670 and economy.complete_tutorial().awarded == 0, "Expansion grants neither welcome nor graduation coins twice")
	_check(service.data.profile.owned_themes.size() == 3 and service.data.profile.active_theme == "berry", "Purchased themes and equipped finish survive expansion")
	_check(model.undo() and model.state.trays.back().front == [null, null, null], "Legacy undo empties the previously occupied purchased tray")
	var hint := economy.buy_hint(model, level, 0)
	_check(hint.status == "ok" and hint.charged == 0 and economy.balance() == 670, "Old paid hint receipt remains free after undo")
	_check(model.undo() and model.extra_tray_granted and model.state.trays.back().front == [null, null, null], "Undo before the old grant retains an empty purchased tray")
	_check(SaveService._inventory(model.state.trays) == SaveService._inventory(level.trays), "Legacy grant undo preserves all original food exactly once")
	service.commit_session(model, level)
	_check(service.last_error.is_empty() and service.validate_session(level).is_empty(), "Expanded save safely persists the resumed legacy board")
	var loaded := SaveService.new(save_path)
	_check(loaded.load_save() and loaded.data.profile.unlocked == 31 and loaded.data.profile.coins == 670, "Derived unlock persists with the unchanged wallet")
	var clean_replay := BoardModel.new()
	clean_replay.setup(level)
	for command in level.solution:
		_check(clean_replay.apply_move(command[0], command[1], command[2], command[3]), "Original capstone proof command still executes")
	loaded.commit_session(clean_replay, level)
	_check(clean_replay.is_won() and loaded.data.profile.coins == 670 and loaded.data.profile.completed.size() == 30, "Replaying old capstone cannot repeat its first-clear reward")
	# An unfinished old capstone never unlocks the new chapter prematurely.
	var unfinished: Dictionary = original.duplicate(true)
	unfinished.profile.completed.erase("garden_030")
	unfinished.profile.coins = 640
	unfinished.profile.unlocked = 30
	_cleanup()
	_write_text(save_path, SaveService._canonical(SaveService._make_envelope(unfinished, 1)))
	var not_done := SaveService.new(save_path)
	_check(not_done.load_save() and not_done.data.profile.unlocked == 30, "An unfinished level30 stays locked at30 after expansion")
	_cleanup()

func _test_later_chapter_persistence() -> void:
	# Small persistence fixtures use only real registered foods and the catalog
	# identity mapping; content solution validation is exercised separately.
	for sample in [
		{"number": 51, "food": "chicken_drumstick"},
		{"number": 100, "food": "halloumi_slice"},
		{"number": 101, "food": "fried_egg"},
		{"number": 150, "food": "croissant"}
	]:
		_cleanup()
		var level := _simple_level(int(sample.number))
		for tray in level.trays:
			for index in range(3):
				if tray.front[index] != null:
					tray.front[index] = sample.food
		level.mode = "campaign_orders"
		level.tickets = [{"id": "new_chapter_order", "requirements": {sample.food: 1}}]
		var model := BoardModel.new()
		model.setup(level)
		var service := SaveService.new(save_path)
		service.commit_session(model, level)
		_check(service.last_error.is_empty(), "Later chapter registered food and ticket save successfully")
		var loaded := SaveService.new(save_path)
		_check(loaded.load_save() and loaded.validate_session(level).is_empty(), "Later chapter identity and inventory reload correctly")
		model.apply_move(1, 0, 0, 2)
		service.commit_session(model, level)
		_check(model.is_won() and service.last_error.is_empty() and service.data.profile.coins == 30, "Later chapter first clear grants the normal once-only reward")
		var expected_unlock := mini(int(sample.number) + 1, LevelCatalog.LEVEL_COUNT)
		_check(service.data.profile.unlocked == expected_unlock and service.data.profile.completed.has(LevelCatalog.level_id(int(sample.number))), "Later chapter completion uses the catalog ID and correct next level")
		service.commit_session(model, level)
		_check(service.data.profile.coins == 30 and loaded.load_save(), "Later chapter repeated settlement cannot duplicate currency")
		var before := service.data.duplicate(true)
		var wrong_identity: Dictionary = level.duplicate(true)
		wrong_identity.level_id = "garden_%03d" % int(sample.number)
		service.commit_session(model, wrong_identity)
		_check(service.data == before and not SaveService.is_campaign_level(wrong_identity), "Mismatched chapter identity cannot replace a valid session")
		var invalid: Dictionary = before.duplicate(true)
		invalid.session.state.level_id = wrong_identity.level_id
		_check(not SaveService._validate_payload(invalid).is_empty(), "Saved history/state cannot impersonate a different chapter prefix")
		invalid = before.duplicate(true)
		var record: Dictionary = invalid.profile.completed[LevelCatalog.level_id(int(sample.number))]
		invalid.profile.completed.clear()
		invalid.profile.completed[wrong_identity.level_id] = record
		_check(not SaveService._validate_payload(invalid).is_empty(), "Completion records cannot use the old garden prefix in later chapters")
	_cleanup()

func _test_audio() -> void:
	var audio := GameAudio.new()
	root.add_child(audio)
	audio.configure({"sound": false, "music": true})
	_check(audio._cues.size() == 8 and audio._music.stream != null, "Eight cue streams and original music load")
	_check(audio._music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Music is configured to loop")
	_check(not audio._sound_enabled and audio._music_enabled, "Music and sound configure independently")
	audio.configure({"sound": true, "music": false})
	audio.play_cue("match")
	_check(audio._sound_enabled and not audio._music_enabled, "Sound preference remains enabled when music is disabled")
	audio.set_music_active(false)
	_check(audio._sound_enabled and not audio._music_active, "Lifecycle music suspension does not change effects preference")
	audio.configure({"sound": false, "music": false})
	audio.queue_free()
	await create_timer(0.1).timeout
	print("Save/audio checks: %d; failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _simple_level(number: int = 1) -> Dictionary:
	return {"schema_version": 1, "content_version": 1, "level_id": LevelCatalog.level_id(number),
		"number": number, "mode": "campaign", "active_ticket_limit": 1,
		"trays": [{"id": "t1", "front": ["tomato", "tomato", null], "queue": []},
			{"id": "t2", "front": ["tomato", null, null], "queue": []}], "tickets": []}

func _recipe_level() -> Dictionary:
	return {"schema_version": 1, "content_version": 1, "level_id": "garden_017", "number": 17,
		"mode": "campaign_orders", "active_ticket_limit": 1,
		"trays": [
			{"id": "t1", "front": ["corn_cob", "corn_cob", null], "queue": [["bell_pepper_ring", "bell_pepper_ring", null]]},
			{"id": "t2", "front": ["button_mushroom", "corn_cob", "button_mushroom"], "queue": []},
			{"id": "t3", "front": [null, "button_mushroom", null], "queue": [["bell_pepper_ring", null, null]]}],
		"tickets": [{"id": "one", "requirements": {"corn_cob": 1, "button_mushroom": 1}},
			{"id": "two", "requirements": {"bell_pepper_ring": 1}}]}

func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _cleanup() -> void:
	for archive in _archive_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(archive))
	for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
		var path: String = save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
