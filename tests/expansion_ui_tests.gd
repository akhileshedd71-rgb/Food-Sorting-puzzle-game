extends SceneTree
## Live-scene integration tests. Run only with GARDEN_UI_TEST=1 and isolated XDG_DATA_HOME.
## Screenshots: add -- --expansion-screenshots=/tmp/garden-expansion-shots on a graphical display.

var game: Variant
var checks: int = 0
var failures: Array[String] = []
var screenshot_dir: String = ""
const NONE := Vector2i(-1, -1)


func _initialize() -> void:
	if OS.get_environment("GARDEN_UI_TEST") != "1" or OS.get_environment("XDG_DATA_HOME").is_empty():
		push_error("Expansion UI tests write progress. Set GARDEN_UI_TEST=1 and an isolated XDG_DATA_HOME.")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--expansion-screenshots="):
			screenshot_dir = arg.trim_prefix("--expansion-screenshots=")
		elif arg.begins_with("--ui-screenshots="):
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
	check(seed.save_game(), "fresh isolated expansion profile saves")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	check(game.screen == "splash", "boot enters splash before any campaign board")
	await settle(2)
	check(game.model == null and game.save.data.session.is_empty(), "boot does not create a campaign session")
	check(game.economy.balance() == EconomyService.WELCOME_COINS, "welcome gift is exactly 100 Chef Coins")
	await screenshot("expansion_splash")
	await click_button("Skip intro  →")
	check(game.screen == "title", "skip intro routes to title through mouse input")
	check_page_bounds("title")
	await screenshot("expansion_title")
	await click_button("Enter the cafe  →")
	check(game.screen == "home", "title opens the main menu through mouse input")
	check_page_bounds("home")
	await screenshot("expansion_home")
	await test_school_and_campaign_isolation()
	await clear_campaign(1)
	await test_confirmed_hints()
	await test_extra_tray()
	await clear_campaign(2)
	await test_shop_and_finishes()
	await test_insufficient_funds()
	await test_returning_boot()
	game.queue_free()
	await settle()
	# The audio mixer retires stopped WAV playbacks asynchronously. Let its
	# final buffer finish before process teardown when this suite uses X11.
	if DisplayServer.get_name() != "headless": await create_timer(0.35).timeout
	for failure in failures:
		push_error(failure)
	print("EXPANSION UI TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func test_school_and_campaign_isolation() -> void:
	var before: int = game.economy.balance()
	await click_button("Start cooking  →")
	check(game.tutorial_mode and game.tutorial_index == 0, "new player Start cooking opens lesson one")
	check(game.save.data.session.is_empty(), "practice entry leaves campaign session empty")
	game.request_hint()
	await settle()
	check(game.selected != NONE and game.hint_cell != NONE, "practice guide supplies legal source and destination")
	check(not is_instance_valid(game.modal) and game.economy.balance() == before, "practice guide is free and has no purchase modal")
	var practice_hash: String = game.model.state_hash()
	await move_command(game.level.solution[0])
	await click_button("↶\nUndo")
	check(game.model.state_hash() == practice_hash and game.economy.balance() == before, "practice undo restores the board and is free")
	check(game.selected != NONE and game.hint_cell != NONE, "practice undo restores the lesson guidance")
	game.request_extra_tray()
	check(not is_instance_valid(game.modal) and not game.model.extra_tray_granted, "paid extra tray is unavailable inside free practice")
	game.restart_current()
	await settle()
	check(game.tutorial_mode and game.tutorial_index == 0 and game.economy.balance() == before, "practice restart is free and retains lesson")
	game.show_pause()
	await settle()
	await click_button("Home")
	check(game.screen == "home" and not game.tutorial_mode, "school can be skipped through pause Home")
	check(game.save.data.session.is_empty() and not game.economy.tutorial_complete(), "skipping practice does not grant progress or replace a campaign")
	check(game.economy.balance() == before, "skipping practice grants no reward")

	game.start_level(17)
	await settle()
	await move_command(game.level.solution[0])
	var protected_hash: String = game.model.state_hash()
	var protected_session: Dictionary = game.save.data.session.duplicate(true)
	check(int(game.model.state.moves) == 1 and not game.model.is_won(), "campaign preservation fixture has unfinished progress")
	game.show_home()
	await settle()
	await click_button("✦  Cooking School")
	for index in range(3):
		check(game.tutorial_mode and game.tutorial_index == index, "school opens expected lesson %d" % (index + 1))
		check(batch_caption_count() == 0, "new lesson clears match captions from the previous board")
		check_board_bounds("school_%d" % (index + 1))
		await screenshot("expansion_school_%02d" % (index + 1))
		if index == 0 or index == 2:
			# Inject a deterministic save refusal before the completion checkpoint.
			game.save.write_blocked = true
		await solve_current()
		if index == 0 or index == 2:
			check(modal_has("One last thing to save"), "failed school checkpoint presents save retry instead of celebration")
			check(game.economy.tutorial_step() == index and not game.economy.tutorial_complete(), "failed lesson checkpoint does not advance or graduate")
			check(game.economy.balance() == before, "failed school save does not grant graduation currency")
			check(find_button("Next lesson  →") == null and find_button("To my table  →") == null, "failed lesson cannot silently continue past save failure")
			var durable := SaveService.new()
			check(durable.load_save(), "previous durable checkpoint remains readable after save refusal")
			check(int(durable.data.profile.tutorial.step) == index and int(durable.data.profile.coins) == before, "failed checkpoint leaves durable school progress and balance unchanged")
			check(durable.data.session == protected_session, "failed school checkpoint preserves durable campaign envelope")
			game.save.write_blocked = false
			await click_button("Try saving again")
			check(not modal_has("One last thing to save"), "retry succeeds when the save prerequisite is restored")
		check(game.model.is_won(), "school lesson %d can be completed through touch events" % (index + 1))
		check(is_instance_valid(game.modal), "school completion presents its next step")
		check(game.save.data.session == protected_session, "lesson %d preserves exact campaign envelope" % (index + 1))
		check(game.save.data.profile.completed.is_empty(), "practice awards no campaign completions")
		if index == 0:
			check(game.economy.tutorial_step() == 1, "first lesson advances durable school progress")
			await click_button("Main menu")
			await reload_game()
			check(game.economy.tutorial_step() == 1, "completed lesson progress survives a full scene reload")
			check(game.save.data.session == protected_session, "campaign envelope remains durable after school completion")
			game.show_home()
			game.continue_game()
			await settle()
			check(game.model.state_hash() == protected_hash and not game.tutorial_mode, "leaving school restores the campaign board")
			game.show_home()
			await settle()
			await click_button("✦  Cooking School")
			check(game.tutorial_index == 1, "returning school resumes the first incomplete lesson")
		elif index == 1:
			check(game.economy.balance() == before, "unfinished school pays no graduation reward")
			await click_button("Next lesson  →")
	check(game.economy.tutorial_complete() and game.economy.tutorial_step() == 3, "third lesson durably completes school")
	check(game.economy.balance() == before + EconomyService.TUTORIAL_COINS, "graduation grants exactly 30 coins once")
	await click_button("Main menu")
	await click_button("✦  Cooking School")
	check(game.tutorial_index == 0, "completed school can be replayed from lesson one")
	for index in range(3):
		await solve_current()
		if index < 2:
			await click_button("Next lesson  →")
	check(game.economy.balance() == before + EconomyService.TUTORIAL_COINS, "full school replay cannot farm graduation coins")
	check(game.save.data.session == protected_session, "school replay preserves campaign history and run metadata")
	game.save.data.session.content_hash = "0".repeat(64)
	await click_button("To my table  →")
	check(modal_has("This table has changed"), "graduation Continue explains an incompatible campaign")
	check(game.tutorial_mode and game.level.level_id == CookingSchool.lesson(2).level_id, "failed campaign resume retains the completed school context")
	await click_button("Back")
	check(game.tutorial_mode and modal_has("Ready, chef!"), "Back returns to the school graduation rather than a false campaign win")
	check(game.economy.balance() == before + EconomyService.TUTORIAL_COINS, "failed campaign handoff and Back cannot duplicate graduation reward")
	game.save.data.session = protected_session.duplicate(true)
	await click_button("To my table  →")
	check(game.model.state_hash() == protected_hash and not game.tutorial_mode, "graduation action returns to the saved campaign")


func test_confirmed_hints() -> void:
	game.start_level(5)
	await settle()
	var before: int = game.economy.balance()
	var before_hash: String = game.model.state_hash()
	await click_button("✦\nHint · 10")
	check(modal_has("A thoughtful hint"), "hint button displays price confirmation")
	check(game.economy.balance() == before, "opening hint confirmation does not spend coins")
	check(game.selected == NONE and game.hint_cell == NONE, "unconfirmed hint is not exposed for free")
	await click_button("Keep thinking")
	check(game.economy.balance() == before and game.model.state_hash() == before_hash, "canceling hint preserves balance and board")
	check(game.selected == NONE and game.hint_cell == NONE, "canceling does not leave an unpurchased hint")
	await request_paid_hint()
	check(game.economy.balance() == before - EconomyService.HINT_COST, "confirmed certified hint costs exactly 10")
	check(game.model.state_hash() == before_hash and game.model.history.is_empty(), "buying a hint does not move food or create undo")
	check_hint_executable()
	var purchased_source: Vector2i = game.selected
	var purchased_target: Vector2i = game.hint_cell
	await request_paid_hint()
	check(game.economy.balance() == before - EconomyService.HINT_COST, "same puzzle state is not charged twice")
	check(game.selected == purchased_source and game.hint_cell == purchased_target, "repeat confirmation shows the same already-purchased hint")
	check(game.status_label.text.contains("already paid"), "cached hint is labeled as already paid")
	await reload_game()
	game.show_home()
	game.continue_game()
	await settle()
	check(game.model.state_hash() == before_hash, "paid hint resume keeps puzzle state")
	await request_paid_hint()
	check(game.economy.balance() == before - EconomyService.HINT_COST, "cached hint receipt survives a full scene reload")
	check_hint_executable()

	# Deterministic exhaustion fixture: no authoring witness and zero solver budget.
	game.start_level(6)
	await settle()
	var witness: Array = game.level.solution.duplicate(true)
	var budget: int = game.tuning.hint_budget_ms
	game.level.solution = []
	game.tuning.hint_budget_ms = 0
	before = game.economy.balance()
	before_hash = game.model.state_hash()
	await request_paid_hint()
	check(game.economy.balance() == before and game.model.state_hash() == before_hash, "unverified hint never charges or changes the board")
	check(game.selected == NONE and game.hint_cell == NONE, "solver exhaustion does not advertise a false hint")
	check(toast_has("No coins spent"), "solver exhaustion explains that no coins were spent")
	game.level.solution = witness
	game.tuning.hint_budget_ms = budget


func test_extra_tray() -> void:
	game.start_level(30)
	await settle()
	check(game.board.trays.size() == 6, "extra-tray fixture begins with six authored trays")
	await move_command(game.level.solution[0])
	var before: int = game.economy.balance()
	var before_hash: String = game.model.state_hash()
	await click_button("+\nTray · 40")
	check(modal_has("Make a little more room"), "extra tray requires explicit price confirmation")
	await click_button("Keep playing")
	check(game.economy.balance() == before and game.model.state_hash() == before_hash, "canceling extra tray leaves board and wallet unchanged")
	await click_button("+\nTray · 40")
	await click_button("Add a tray · ◉ 40")
	check(game.economy.balance() == before - EconomyService.EXTRA_TRAY_COST, "confirmed extra tray costs exactly 40")
	check(game.model.extra_tray_granted and game.board.trays.size() == 7, "extra tray appears as the seventh live tray")
	if game.board.trays.size() != 7: return
	check_board_bounds("seven_trays")
	await screenshot("expansion_extra_tray_7")
	for test_size in [Vector2i(360, 780), Vector2i(800, 1280)]:
		root.size = test_size
		await settle()
		check_board_bounds("seven_trays_%dx%d" % [test_size.x, test_size.y])
	root.size = Vector2i(450, 1000)
	await settle()
	var after_grant: String = game.model.state_hash()
	var source: Vector2i = first_food()
	await move_command([source.x, source.y, 6, 0])
	check(game.model.state.trays[6].front[0] != null, "new seventh tray accepts a real touch drag")
	var occupied_hash: String = game.model.state_hash()
	var occupied_history: int = game.model.history.size()
	await reload_game()
	game.show_home()
	game.continue_game()
	await settle()
	check(game.model.state_hash() == occupied_hash and game.model.state.trays[6].front[0] != null, "Continue restores the occupied purchased tray without losing food")
	check(game.model.history.size() == occupied_history and occupied_history == 2, "Continue preserves both pre-purchase and post-purchase undo checkpoints")
	check(game.economy.balance() == before - EconomyService.EXTRA_TRAY_COST, "occupied-tray resume preserves its single debit")
	await click_button("↶\nUndo")
	check(game.model.state_hash() == after_grant, "undo returns food from the purchased tray")
	await click_button("↶\nUndo")
	check(game.model.extra_tray_granted and game.board.trays.size() == 7 and int(game.model.state.moves) == 0, "undo across purchase preserves entitlement and rewinds authored move")
	check(game.model.state.trays[6].front == [null, null, null], "undo across grant restores an empty extra tray without cloning food")
	check(game.economy.balance() == before - EconomyService.EXTRA_TRAY_COST, "undo never refunds or repeats the purchase")
	var granted_hash: String = game.model.state_hash()
	await click_button("+\nTray · 40")
	check(not is_instance_valid(game.modal) and game.economy.balance() == before - EconomyService.EXTRA_TRAY_COST, "duplicate tray request is not a second purchase")
	check(game.save.validate_session(game.level).is_empty(), "granted tray and undo history form a valid durable session")
	await reload_game()
	game.show_home()
	game.continue_game()
	await settle()
	check(game.model.state_hash() == granted_hash and game.model.extra_tray_granted, "Continue restores exact seven-tray session")
	check(game.economy.balance() == before - EconomyService.EXTRA_TRAY_COST, "tray debit survives scene reload")
	check_board_bounds("seven_trays_resumed")
	game.restart_current()
	await settle()
	check(not game.model.extra_tray_granted and game.board.trays.size() == 6, "restart begins a new run without the previous run's tray")
	check(game.economy.balance() == before - EconomyService.EXTRA_TRAY_COST, "free restart creates no charge or refund")


func test_shop_and_finishes() -> void:
	game.start_level(17)
	await settle()
	var classic: Color = game.board.trays[0].rim_color
	var state_before: String = game.model.state_hash()
	var before: int = game.economy.balance()
	await click_button(game.wallet_button.text)
	check(game.screen == "shop" and game.shop_origin == "game", "game wallet opens usable shop")
	check(batch_caption_count() == 0, "shop contains no stale match captions from a campaign board")
	var scroll: ScrollContainer = game.page.find_child("ShopScroll", true, false)
	check(scroll != null, "shop has a scrolling content viewport")
	check_page_bounds("shop")
	check(scroll.get_global_rect().end.y <= game.size.y + 1, "shop scroll viewport stays within screen")
	await screenshot("expansion_shop")
	await click_button("Unlock · ◉ 120")
	check(modal_has("Sage enamel, just for you"), "theme unlock shows confirmation")
	await click_button("Maybe later")
	check(game.economy.balance() == before and not game.save.data.profile.owned_themes.has("sage"), "canceling finish does not spend or unlock")
	await click_button("Unlock · ◉ 120")
	await click_button("Unlock · ◉ 120")
	check(game.save.data.profile.owned_themes.has("sage") and game.save.data.profile.active_theme == "sage", "confirmed finish is owned and equipped")
	check(game.economy.balance() == before - 120, "permanent Sage finish costs exactly 120")
	await click_button("‹")
	check(game.screen == "game" and game.model.state_hash() == state_before, "shop return preserves the puzzle")
	check_finish("sage", classic)
	await screenshot("expansion_sage_enamel")
	await click_button(game.wallet_button.text)
	await click_button("Equip")
	await click_button("‹")
	check(game.save.data.profile.active_theme == "classic" and game.board.trays[0].rim_color == classic, "owned classic finish can be re-equipped on live trays")
	await click_button(game.wallet_button.text)
	await click_button("Equip")
	await click_button("‹")
	check_finish("sage", classic)
	check(game.economy.balance() == before - 120, "switching owned finishes is free")
	await reload_game()
	game.show_home()
	game.continue_game()
	await settle()
	check_finish("sage", classic)
	check(game.economy.balance() == before - 120, "finish ownership and wallet survive scene reload")

	game.show_home()
	await settle()
	await click_button("◉  Coin shop")
	var hint_tool := find_button("◉ 10")
	var tray_tool := find_button("◉ 40")
	check(hint_tool != null and hint_tool.disabled and tray_tool != null and tray_tool.disabled, "home shop tools cannot affect an inactive board")
	var pack_buttons: Array[Button] = []
	for node in game.page.find_children("*", "Button", true, false):
		if node.text == "Coming later": pack_buttons.append(node)
	check(pack_buttons.size() == 3, "all three future coin packs are visible")
	before = game.economy.balance()
	for pack in pack_buttons:
		check(pack.disabled, "coin pack purchase button is disabled")
		check(pack.get_signal_connection_list("pressed").is_empty(), "coin pack has no fake payment or coin-grant callback")
		await click_control(pack)
	check(game.economy.balance() == before and not is_instance_valid(game.modal), "clicking unavailable packs cannot mint coins or simulate a payment")
	await screenshot("expansion_shop_coin_packs")
	await click_button("‹")
	check(game.screen == "home", "home-origin shop returns to home")


func test_insufficient_funds() -> void:
	# Currency is earned through real school/campaign clears, then spent through confirmed actions.
	check(game.economy.balance() == 20, "earned-and-spent fixture reaches the expected 20-coin balance")
	for number in [5, 6]:
		game.start_level(number)
		await settle()
		await request_paid_hint()
	check(game.economy.balance() == 0, "two new-run verified hints exhaust the remaining 20 coins")
	game.start_level(7)
	await settle()
	var original: String = game.model.state_hash()
	await request_paid_hint()
	check(modal_has("A few more Chef Coins"), "insufficient hint funds opens earn-coins explanation")
	check(game.economy.balance() == 0 and game.model.state_hash() == original, "insufficient hint does not debit or mutate")
	check(game.selected == NONE and game.hint_cell == NONE, "unaffordable hint is not displayed")
	await click_button("Keep playing")
	await click_button("+\nTray · 40")
	await click_button("Add a tray · ◉ 40")
	check(modal_has("A few more Chef Coins"), "insufficient tray funds uses the same honest recovery popup")
	check(game.economy.balance() == 0 and game.model.state_hash() == original and not game.model.extra_tray_granted, "unaffordable tray does not mutate the board")
	await click_button("Keep playing")


func test_returning_boot() -> void:
	var expected: int = game.economy.balance()
	var completed: Dictionary = game.save.data.profile.completed.duplicate(true)
	await reload_game()
	check(game.screen == "splash" or game.screen == "title", "returning player follows normal splash/title flow")
	if game.screen == "splash": await click_button("Skip intro  →")
	await click_button("Enter the cafe  →")
	check(game.screen == "home" and game.economy.balance() == expected, "returning main menu does not repeat welcome gift")
	check(game.save.data.profile.completed == completed and game.economy.tutorial_complete(), "returning boot retains both campaign and school completion")
	check(game.save.data.profile.active_theme == "sage", "returning boot retains equipped permanent finish")
	await click_button("Back to title")
	check(game.screen == "title", "main menu can return to title through real input")
	var title_generation: int = game.generation
	await create_timer(0.4).timeout
	check(game.screen == "title" and game.generation == title_generation, "old splash timer cannot rebuild or replace a newer page")
	game.settings().music = true
	game.audio.configure(game.settings())
	game.show_splash()
	game.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.4).timeout
	check(game.screen == "title", "unskipped reduced-motion splash automatically advances to title")
	check(not game.application_active and not game.audio._music_active, "background splash advance cannot restart music")
	if game.audio._audio_available:
		check(game.audio._music.stream_paused, "graphical music playback remains paused while splash advances")
	game.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(game.audio._music_active and not game.audio._music.stream_paused, "focus resume restores permitted music after paused splash")
	game.settings().music = false
	game.audio.configure(game.settings())
	check(game.economy.balance() == expected, "replaying the splash never awards additional currency")


func clear_campaign(number: int) -> void:
	game.start_level(number)
	await settle()
	var before: int = game.economy.balance()
	await solve_current()
	check(game.model.is_won() and game.save.data.profile.completed.has(LevelCatalog.level_id(number)), "campaign %d completes through input" % number)
	check(game.economy.balance() == before + 30, "first campaign %d clear earns 30 spendable coins" % number)


func solve_current() -> void:
	var commands: Array = game.level.solution.duplicate(true)
	for command in commands:
		await move_command(command)


func move_command(command: Array) -> void:
	var before: int = int(game.model.state.moves)
	var source: Vector2 = game.board.center_of(Vector2i(command[0], command[1]))
	var target: Vector2 = game.board.center_of(Vector2i(command[2], command[3]))
	var down := InputEventScreenTouch.new()
	down.position = source
	down.index = 3
	down.pressed = true
	root.push_input(down, true)
	await process_frame
	var motion := InputEventScreenDrag.new()
	motion.position = target
	motion.index = 3
	root.push_input(motion, true)
	await process_frame
	var up := InputEventScreenTouch.new()
	up.position = target
	up.index = 3
	up.pressed = false
	root.push_input(up, true)
	await settle()
	check(int(game.model.state.moves) == before + 1, "touch drag commits exactly one intended move")


func request_paid_hint() -> void:
	await click_button("✦\nHint · 10")
	await click_button("Show a hint · ◉ 10")


func check_hint_executable() -> void:
	check(game.selected != NONE and game.hint_cell != NONE, "paid hint shows a source and destination")
	if game.selected == NONE or game.hint_cell == NONE: return
	var copy := BoardModel.new()
	copy.restore(game.model.snapshot())
	check(copy.apply_move(game.selected.x, game.selected.y, game.hint_cell.x, game.hint_cell.y), "purchased hint is executable by the production resolver")


func check_finish(id: String, previous: Color) -> void:
	check(game.save.data.profile.active_theme == id, "profile equips " + id)
	var selected: Dictionary = {}
	for finish in game.economy.themes():
		if finish.id == id: selected = finish
	check(not selected.is_empty(), "equipped finish has a definition")
	if selected.is_empty(): return
	for tray in game.board.trays:
		check(tray.rim_color == selected.rim and tray.accent_color == selected.accent, "live tray uses purchased rim and accent colors")
	check(game.board.trays[0].rim_color != previous, "equipping finish changes visible tray styling")


func check_page_bounds(label: String) -> void:
	check(game.page.get_global_rect().position.y >= -1, label + " content starts within viewport")
	check(game.page.get_global_rect().end.y <= game.size.y + 1, label + " content fits viewport")


func check_board_bounds(label: String) -> void:
	var bounds := Rect2(Vector2.ZERO, game.size)
	for i in range(game.board.trays.size()):
		for j in range(3):
			var cell := Vector2i(i, j)
			var center: Vector2 = game.board.center_of(cell)
			check(bounds.has_point(center), "%s tray %d slot %d within viewport" % [label, i, j])
			check(game.board.hit_test(center) == cell, "%s tray %d slot %d hit test roundtrip" % [label, i, j])
	check(game.board.get_global_rect().end.y <= game.undo_button.get_global_rect().position.y, label + " board does not overlap tools")
	check(game.undo_button.get_global_rect().end.y <= game.size.y + 1, label + " tool row remains fully visible")
	check_page_bounds(label)


func batch_caption_count() -> int:
	var count: int = 0
	for child in game.get_children():
		if child is Label and child.text.contains("+1 batch"): count += 1
	return count


func first_food() -> Vector2i:
	for i in range(game.model.state.trays.size()):
		for j in range(3):
			if game.model.state.trays[i].front[j] != null: return Vector2i(i, j)
	return NONE


func find_button(text: String) -> Button:
	var scope: Node = game.modal if is_instance_valid(game.modal) else game.page
	for node in scope.find_children("*", "Button", true, false):
		if node.text == text: return node
	return null


func click_button(text: String) -> void:
	var button := find_button(text)
	check(button != null, "button exists: " + text)
	if button == null: return
	check(not button.disabled, "button is enabled: " + text)
	await click_control(button)


func click_control(button: Button) -> void:
	var parent: Node = button.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
		parent = parent.get_parent()
	await settle(2)
	var position: Vector2 = button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame
	await settle()


func modal_has(text: String) -> bool:
	if not is_instance_valid(game.modal): return false
	for node in game.modal.find_children("*", "Label", true, false):
		if node.text == text: return true
	return false


func toast_has(text: String) -> bool:
	if not is_instance_valid(game.toast_node): return false
	for node in game.toast_node.find_children("*", "Label", true, false):
		if node.text.contains(text): return true
	return false


func reload_game() -> void:
	game.queue_free()
	await settle()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle(2)


func settle(frames: int = 5) -> void:
	for i in range(frames): await process_frame


func screenshot(name: String) -> void:
	if screenshot_dir.is_empty() or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png(screenshot_dir.path_join(name + ".png")) == OK, "screenshot " + name)


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)
