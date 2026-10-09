extends SceneTree
## Real scene + real Godot input-event integration. Use a separate save directory:
## GARDEN_UI_TEST=1 XDG_DATA_HOME=/tmp/garden-ui-test godot --headless --path . --script tests/ui_tests.gd
## Add -- --ui-screenshots=/tmp/garden-ui-shots on a graphical display to capture renders.

var game: Variant
var checks: int = 0
var failures: Array[String] = []
var screenshot_dir: String = ""


func _initialize() -> void:
	if OS.get_environment("GARDEN_UI_TEST") != "1" or OS.get_environment("XDG_DATA_HOME").is_empty():
		push_error("UI tests write progress. Set GARDEN_UI_TEST=1 and an isolated XDG_DATA_HOME.")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-screenshots="):
			screenshot_dir = arg.trim_prefix("--ui-screenshots=")
	call_deferred("run")


func run() -> void:
	root.content_scale_size = Vector2i(720, 1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = Vector2i(450, 1000)
	var seed := SaveService.new()
	seed.load_save()
	seed.data = SaveService.default_data()
	seed.data.profile.settings.reduced_motion = true
	seed.data.profile.settings.sound = false
	seed.data.profile.settings.music = false
	check(seed.save_game(), "isolated test profile saves")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	check(game.screen == "splash", "fresh launch starts at splash")
	await click_ui_button("Skip intro  →")
	check(game.screen == "title", "skip intro opens title")
	await click_ui_button("Enter the cafe  →")
	check(game.screen == "home", "title opens main menu")
	check(game.economy.balance() == EconomyService.WELCOME_COINS, "fresh profile receives one welcome gift")
	game.start_level(1)
	await settle()
	check(game.screen == "game" and int(game.level.number) == 1, "first campaign can be started explicitly")
	check(game.selected != Vector2i(-1, -1), "tutorial preselects a food")
	check(game.hint_cell != Vector2i(-1, -1), "tutorial highlights destination")
	check_layout("level_01")
	await screenshot("level_01")
	await test_tutorial()
	await test_multitouch()
	await test_toolbar_pointer_capture()
	await test_invalid_and_cancel()
	await test_pause_during_drag()
	await test_pause_during_presentation()
	await test_mouse_and_scale()
	await test_reload_and_incompatible_content()
	await test_hints_after_slot_permutation()
	await test_repeated_transitions()
	root.size = Vector2i(720, 1600)
	await settle()
	for number in [17, 30]:
		game.start_level(number)
		await settle()
		check(int(game.level.number) == number, "requested visual level %d loads" % number)
		check_layout("level_%02d" % number)
		await screenshot("level_%02d" % number)
	game.show_pause()
	await settle()
	await screenshot("pause")
	game.show_queues()
	await settle()
	await check_modal_scroll("queues")
	await screenshot("queues")
	game.show_settings()
	await settle()
	await check_modal_scroll("settings")
	await screenshot("settings")
	game.show_album()
	await settle()
	var album_scroll: ScrollContainer = game.page.find_children("*", "ScrollContainer", true, false)[0]
	check(album_scroll.get_global_rect().end.y <= game.size.y + 1, "recipe album scroll viewport fits screen")
	var recipe_names: Dictionary = {}
	var album_chapter: int = int(LevelCatalog.chapter_for_level(game.next_table_number()).id)
	for recipe in LevelCatalog.load_recipes():
		if int(recipe.chapter) == album_chapter: recipe_names[str(recipe.name)] = 0
	check(recipe_names.size() == 4, "selected chapter has four recipe cards")
	for label in album_scroll.find_children("*", "Label", true, false):
		if recipe_names.has(label.text): recipe_names[label.text] += 1
	for recipe_name in recipe_names:
		check(recipe_names[recipe_name] == 1, "recipe album exposes exactly one card for " + recipe_name)
	check(album_scroll.get_child(0).get_combined_minimum_size().y <= album_scroll.size.y + 1 or album_scroll.get_v_scroll_bar().max_value > album_scroll.get_v_scroll_bar().page, "recipe album fits or scrolls its content")
	await screenshot("album")
	album_scroll.scroll_vertical = int(album_scroll.get_v_scroll_bar().max_value)
	await settle()
	await screenshot("album_bottom")
	game.show_home()
	await settle()
	check(game.screen == "home", "home can be reached after a session")
	check(game.page.get_global_rect().end.y <= game.size.y + 1, "home content fits viewport")
	await screenshot("home")
	game.queue_free()
	await settle()
	for failure in failures:
		push_error(failure)
	print("UI TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func test_tutorial() -> void:
	var target: Vector2 = game.board.center_of(game.hint_cell)
	await touch(target, 0, true)
	await touch(target, 0, false)
	check(game.model.is_won(), "one highlighted tutorial tap wins")
	check(int(game.model.state.moves) == 1, "tutorial records exactly one move")
	check(is_instance_valid(game.modal), "tutorial victory opens completion modal")
	check(game.save.data.profile.completed.has("garden_001"), "victory immediately records completion")
	check(int(game.save.data.profile.unlocked) == 2, "victory unlocks level 2")
	var saved := SaveService.new()
	check(saved.load_save(), "completed tutorial loads from disk")
	check(saved.data.session.state.outcome == "won", "stable won state saved before presentation")
	var coins_before: int = saved.data.profile.coins
	game.start_level(1)
	await settle()
	target = game.board.center_of(game.hint_cell)
	await touch(target, 0, true)
	await touch(target, 0, false)
	check(int(game.save.data.profile.coins) == coins_before, "replaying tutorial does not duplicate coins")


func test_multitouch() -> void:
	game.start_level(5)
	await settle()
	var command: Array = game.level.solution[0]
	var source: Vector2 = game.board.center_of(Vector2i(command[0], command[1]))
	var target: Vector2 = game.board.center_of(Vector2i(command[2], command[3]))
	var before: String = game.model.state_hash()
	var expected := BoardModel.new()
	expected.setup(game.level)
	check(expected.apply_move(command[0], command[1], command[2], command[3]), "multitouch fixture move is legal")
	await touch(source, 11, true)
	check(game.pointer == 11, "first touch owns pointer")
	await touch(target, 12, true)
	await drag(target + Vector2(30, 0), 12)
	await touch(target, 12, false)
	check(game.pointer == 11, "second finger cannot steal or release pointer")
	check(game.model.state_hash() == before, "second finger does not change board")
	await drag(target, 11)
	check(game.dragging and is_instance_valid(game.ghost), "active finger creates drag ghost")
	await touch(target, 11, false)
	check(game.model.state_hash() == expected.state_hash(), "active drag applies exactly the intended transaction")
	check(game.pointer == -2 and not is_instance_valid(game.ghost), "successful drag releases pointer and ghost")


func test_invalid_and_cancel() -> void:
	game.start_level(5)
	await settle()
	var occupied := occupied_pair()
	var source: Vector2 = game.board.center_of(occupied[0])
	var target: Vector2 = game.board.center_of(occupied[1])
	var before: String = game.model.state_hash()
	await touch(source, 2, true)
	await drag(target, 2)
	await touch(target, 2, false)
	check(game.model.state_hash() == before, "occupied drop rejects without changing board")
	check(game.model.history.is_empty(), "invalid drop creates no undo checkpoint")
	check(game.pointer == -2 and not is_instance_valid(game.ghost), "invalid drop releases pointer and ghost")
	await touch(source, 3, true)
	await drag(source + Vector2(0, -40), 3)
	await touch(source + Vector2(0, -40), 3, false, true)
	check(game.model.state_hash() == before, "OS-canceled touch leaves board unchanged")
	check(game.pointer == -2 and not is_instance_valid(game.ghost), "OS-canceled touch clears all drag state")
	await touch(source, 4, true)
	await drag(Vector2(4, 4), 4)
	await touch(Vector2(4, 4), 4, false)
	check(game.model.state_hash() == before, "drop outside trays leaves board unchanged")
	check(game.selected == Vector2i(-1, -1), "outside drop clears selection")


func test_toolbar_pointer_capture() -> void:
	game.start_level(5)
	await settle()
	var command: Array = game.level.solution[0]
	var source: Vector2 = game.board.center_of(Vector2i(command[0], command[1]))
	var pause_button: Button = button_with_text("Ⅱ")
	var pause_position: Vector2 = pause_button.get_global_rect().get_center()
	var toolbar: Vector2 = game.undo_button.get_global_rect().get_center()
	var before: String = game.model.state_hash()
	await touch(source, 8, true)
	await drag(source + Vector2(30, 0), 8)
	await touch(pause_position, 9, true)
	await touch(pause_position, 9, false)
	check(game.pointer == 8 and not is_instance_valid(game.modal), "second finger over pause cannot activate GUI or steal drag")
	await drag(toolbar, 8)
	await touch(toolbar, 8, false)
	check(game.pointer == -2 and not is_instance_valid(game.ghost), "touch release over toolbar clears pointer and ghost")
	check(game.model.state_hash() == before, "toolbar drop does not move food")
	await mouse_button(source, true)
	var motion := InputEventMouseMotion.new()
	motion.position = button_with_text("✦\nHint · 10").get_global_rect().get_center()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	await mouse_button(motion.position, false)
	check(game.pointer == -2 and game.selected == Vector2i(-1, -1), "mouse release over Hint does not stick pointer or trigger hint")
	check(game.model.state_hash() == before, "mouse toolbar drop leaves board unchanged")
	await mouse_button(pause_position, true)
	await mouse_button(pause_position, false)
	check(is_instance_valid(game.modal), "ordinary mouse pause button remains functional")
	game.close_modal()
	await settle()


func test_pause_during_drag() -> void:
	game.start_level(5)
	await settle()
	var command: Array = game.level.solution[0]
	var source: Vector2 = game.board.center_of(Vector2i(command[0], command[1]))
	var target: Vector2 = game.board.center_of(Vector2i(command[2], command[3]))
	var before: String = game.model.state_hash()
	await touch(source, 5, true)
	await drag(source + Vector2(0, -40), 5)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await settle()
	check(is_instance_valid(game.modal), "Escape opens pause modal during a drag")
	check(game.pointer == -2 and not is_instance_valid(game.ghost), "pause cancels active drag")
	await touch(target, 5, false)
	check(game.model.state_hash() == before, "late release behind pause cannot move food")
	root.push_input(escape, true)
	await settle()
	check(not is_instance_valid(game.modal), "Escape closes pause modal")
	check(game.model.state_hash() == before, "resume retains stable board")
	await touch(source, 6, true)
	await drag(source + Vector2(0, -40), 6)
	game.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await settle()
	check(game.pointer == -2 and is_instance_valid(game.modal), "focus loss cancels drag and pauses")
	game.close_modal()
	game.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)


func test_pause_during_presentation() -> void:
	game.start_level(1)
	game.settings().reduced_motion = false
	await settle()
	var target: Vector2 = game.board.center_of(game.hint_cell)
	await touch(target, 13, true)
	await touch(target, 13, false)
	check(game.model.is_won() and game.busy, "accepted animated move is committed while presentation is busy")
	game.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await settle()
	check(modal_has_text("A little breather"), "focus loss opens pause during accepted animation")
	await create_timer(0.8).timeout
	check(not game.busy, "accepted presentation settles while app is inactive")
	check(modal_has_text("A little breather"), "animation completion preserves pause overlay")
	game.close_modal()
	game.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	await settle()
	check(modal_has_text("Beautifully served!"), "resume opens deferred victory after closing pause")
	check(game.save.data.session.state.outcome == "won", "pause during presentation retains saved victory")
	game.settings().reduced_motion = true


func test_repeated_transitions() -> void:
	await create_timer(1.1).timeout
	game.start_level(17)
	await settle()
	var baseline_nodes: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var baseline_resources: int = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	var baseline_bytes: int = OS.get_static_memory_usage()
	var start_us: int = Time.get_ticks_usec()
	for n in range(1, 21):
		game.start_level(n)
		await settle()
		game.show_home()
		await settle()
	game.start_level(17)
	await settle()
	var after_nodes: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var after_resources: int = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	var after_bytes: int = OS.get_static_memory_usage()
	check(after_nodes <= baseline_nodes + 2, "20 repeated transitions do not accumulate scene nodes")
	check(after_resources <= baseline_resources + 8, "20 repeated transitions do not accumulate UI resources")
	print("UI DESKTOP TRANSITIONS: 20 level/home roundtrips %.1f ms; nodes %d -> %d; resources %d -> %d; static bytes %d -> %d" % [(Time.get_ticks_usec() - start_us) / 1000.0, baseline_nodes, after_nodes, baseline_resources, after_resources, baseline_bytes, after_bytes])


func check_modal_scroll(label: String) -> void:
	var scroll: ScrollContainer = game.modal.find_children("*", "ScrollContainer", true, false)[0]
	check(scroll.get_global_rect().position.y >= 0 and scroll.get_global_rect().end.y <= game.size.y + 1, label + " modal scroll viewport fits screen")
	if scroll.get_v_scroll_bar().max_value > scroll.size.y:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await settle()
		check(scroll.scroll_vertical > 0, label + " tall modal scrolls to final button")


func click_ui_button(text: String) -> void:
	var button: Button = button_with_text(text)
	check(button != null, "button exists: " + text)
	if button == null:
		return
	var center := button.get_global_rect().get_center()
	await mouse_button(center, true)
	await mouse_button(center, false)
	await settle()


func button_with_text(text: String) -> Button:
	for node in game.find_children("*", "Button", true, false):
		if node.text == text:
			return node
	return null


func test_mouse_and_scale() -> void:
	game.start_level(5)
	await settle()
	var command: Array = game.level.solution[0]
	var source: Vector2 = game.board.center_of(Vector2i(command[0], command[1]))
	var target: Vector2 = game.board.center_of(Vector2i(command[2], command[3]))
	await mouse_button(source, true)
	await mouse_button(source, false)
	check(game.selected == Vector2i(command[0], command[1]), "mouse click selects source food")
	await mouse_button(target, true)
	await mouse_button(target, false)
	check(int(game.model.state.moves) == 1, "mouse click destination applies one move")
	game.undo_move()
	await settle()
	check(int(game.model.state.moves) == 0, "UI undo restores mouse move")
	root.size = Vector2i(360, 800)
	await settle()
	check(is_equal_approx(game.size.x, 720), "half-size physical window retains logical 720 width")
	source = game.board.center_of(Vector2i(command[0], command[1]))
	target = game.board.center_of(Vector2i(command[2], command[3]))
	# push_input(false) takes physical window coordinates and applies viewport scale.
	var transform: Transform2D = root.get_final_transform()
	await mouse_button(transform * source, true, false)
	var motion := InputEventMouseMotion.new()
	motion.position = transform * target
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, false)
	await process_frame
	await mouse_button(transform * target, false, false)
	check(int(game.model.state.moves) == 1, "physical-coordinate mouse drag works at half scale")
	root.size = Vector2i(450, 1000)
	await settle()


func test_reload_and_incompatible_content() -> void:
	var expected_hash: String = game.model.state_hash()
	var expected_history: int = game.model.history.size()
	game.show_home()
	await settle()
	game.save = SaveService.new()
	check(game.save.load_save(), "UI session can be reloaded from disk")
	game.economy = EconomyService.new(game.save)
	game.economy.initialize()
	game.continue_game()
	await settle()
	check(game.model.state_hash() == expected_hash, "Continue restores exact saved board")
	check(game.model.history.size() == expected_history, "Continue restores undo history")
	game.save.data.session.content_hash = "0".repeat(64)
	game.show_home()
	await settle()
	game.continue_game()
	await settle()
	check(is_instance_valid(game.modal), "changed level checksum shows recovery modal")
	check(game.screen == "home", "incompatible session does not enter stale board")
	check(game.save.data.profile.completed.has("garden_001"), "session recovery retains completed profile")
	check(modal_has_text("This table has changed"), "recovery modal explains content change")
	game.start_level(5)
	await settle()
	check(not is_instance_valid(game.modal), "restarting clears incompatible-session modal")


func test_hints_after_slot_permutation() -> void:
	game.start_level(5)
	await settle()
	# A player's equivalent slot permutation must still produce a usable hint.
	for tray in game.model.state.trays:
		tray.front.reverse()
	game.refresh_game()
	game.request_hint()
	await settle()
	check(modal_has_text("A thoughtful hint"), "hint requires price confirmation")
	await click_ui_button("Show a hint · ◉ 10")
	check(game.selected != Vector2i(-1, -1) and game.hint_cell != Vector2i(-1, -1), "hint resolves after equivalent slot permutation")
	if game.selected != Vector2i(-1, -1) and game.hint_cell != Vector2i(-1, -1):
		check(game.model.state.trays[game.selected.x].front[game.selected.y] != null, "hint source contains food")
		check(game.model.state.trays[game.hint_cell.x].front[game.hint_cell.y] == null, "hint destination is empty")
		var copy := BoardModel.new()
		copy.setup(game.level)
		copy.restore(game.model.snapshot())
		check(copy.apply_move(game.selected.x, game.selected.y, game.hint_cell.x, game.hint_cell.y), "presented hint is executable")


func occupied_pair() -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for i in range(game.model.state.trays.size()):
		for j in range(3):
			if game.model.state.trays[i].front[j] != null and (found.is_empty() or found[0].x != i):
				found.append(Vector2i(i, j))
				break
		if found.size() == 2:
			return found
	return found


func check_layout(label: String) -> void:
	var bounds := Rect2(Vector2.ZERO, game.size)
	for i in range(game.board.trays.size()):
		for j in range(3):
			var cell := Vector2i(i, j)
			var center: Vector2 = game.board.center_of(cell)
			check(bounds.has_point(center), "%s tray %d slot %d inside viewport" % [label, i, j])
			check(game.board.hit_test(center) == cell, "%s tray %d slot %d hit-test roundtrip" % [label, i, j])
	check(game.undo_button.get_global_rect().end.y <= game.size.y + 1, label + " tool buttons fully visible")
	check(game.page.get_global_rect().end.y <= game.size.y + 1, label + " all page content fits viewport")


func modal_has_text(text: String) -> bool:
	for node in game.modal.find_children("*", "Label", true, false):
		if node.text == text:
			return true
	return false


func touch(position: Vector2, index: int, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)
	await process_frame


func drag(position: Vector2, index: int) -> void:
	var event := InputEventScreenDrag.new()
	event.position = position
	event.index = index
	root.push_input(event, true)
	await process_frame


func mouse_button(position: Vector2, pressed: bool, local: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, local)
	await process_frame


func settle() -> void:
	for i in range(5):
		await process_frame


func screenshot(name: String) -> void:
	if screenshot_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png(screenshot_dir.path_join(name + ".png")) == OK, "screenshot " + name)


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
