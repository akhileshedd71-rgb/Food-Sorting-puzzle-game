extends SceneTree
## Focused persistence regression suite. Uses a separate directory, never player saves.
## Run: godot --headless --path . --script tests/save_tests.gd

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
	_test_validation_and_reset()
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
	level = _simple_level(30)
	model.setup(level)
	model.apply_move(1, 0, 0, 2)
	service.commit_session(model, level)
	_check(service.data.profile.unlocked == 30 and service.last_error.is_empty(), "Final chapter unlock stays within 30 authored levels")
	service.clear_session()
	_check(service.data.session.is_empty() and service.data.profile.coins == 30, "Discarding a session preserves completion and currency")
	service.reset_progress()
	_check(service.last_error.is_empty() and service.data.profile.coins == 0 and service.data.profile.unlocked == 1, "Confirmed reset writes fresh profile")
	_write_text(save_path, "damaged after reset")
	loaded = SaveService.new(save_path)
	_check(loaded.load_save() and loaded.data.profile.completed.is_empty(), "Backup recovery cannot resurrect progress after confirmed reset")

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
	return {"schema_version": 1, "content_version": 1, "level_id": "garden_%03d" % number,
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
	for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
		var path: String = save_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
