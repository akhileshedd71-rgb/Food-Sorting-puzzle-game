extends "res://tests/expansion_ui_tests.gd"
## v0.3 integration: real scene/input, authentic save migration, chapter
## boundaries, all food/recipe cards, transparent art, and live tray rendering.
## Inherits the isolated-save guard and real mouse/touch helpers.

const LEGACY_FIXTURE := "res://tests/fixtures/v0_2_completed_30_save.json"
var legacy: Dictionary = {}


func run() -> void:
	root.content_scale_size = Vector2i(720, 1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = Vector2i(450, 1000)
	install_legacy_fixture()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle(2)
	await click_button("Skip intro  →")
	await screenshot("content_title")
	await click_button("Enter the cafe  →")
	await screenshot("content_home")
	await test_legacy_resume_and_map()
	await test_collection(31)
	test_sprite_alpha()
	await test_legacy_graduation()
	await test_chapter_boundary(50, "Backyard Barbecue")
	await test_collection(51)
	await test_new_recipe(55, "backyard_combo")
	await test_live_art(76)
	await test_chapter_boundary(100, "Breakfast Griddle")
	await test_collection(101)
	await test_new_recipe(115, "sweet_morning")
	await test_live_art(126)
	await test_terminal_victory()
	await test_collection(150)
	game.queue_free()
	await settle()
	if DisplayServer.get_name() != "headless": await create_timer(0.35).timeout
	for failure in failures: push_error(failure)
	print("CONTENT UI TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func install_legacy_fixture() -> void:
	# The inherited initializer requires explicit UI-test authorization and
	# isolated XDG data. Remove only the four test save candidates so an older
	# suite's high-revision backup cannot supersede this historical envelope.
	var seed := SaveService.new()
	for path in seed._candidate_paths():
		if FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "isolated save candidate removed")
	var raw := FileAccess.get_file_as_string(LEGACY_FIXTURE)
	var envelope: Dictionary = JSON.parse_string(raw)
	# Godot JSON parses integral values as floats; production validates then
	# normalizes them to integers. Normalize only representation for deep
	# comparison, preserving every historical field and value.
	legacy = SaveService._normalize_numbers(envelope.payload)
	check(int(legacy.profile.unlocked) == 30 and legacy.profile.completed.size() == 30, "fixture is the authentic former capstone save")
	check(legacy.session.state.moves == 2 and legacy.session.extra_tray_granted and legacy.session.hint_receipts.size() == 2, "fixture includes occupied extra tray, undo history and paid hints")
	var absolute := ProjectSettings.globalize_path(seed.save_path)
	check(DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) == OK, "isolated save directory created")
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	check(file != null, "legacy envelope destination is writable")
	if file != null:
		file.store_string(raw)
		file.close()


func test_legacy_resume_and_map() -> void:
	var expected_profile: Dictionary = legacy.profile.duplicate(true)
	expected_profile.unlocked = 31
	check(game.save.data.profile == expected_profile, "legacy migration changes only the derived unlock from 30 to 31")
	check(game.save.data.session == legacy.session, "legacy migration preserves the exact unfinished session")
	check(game.economy.balance() == 670 and game.economy.tutorial_complete(), "legacy wallet and completed cooking school survive boot")
	check(game.next_table_number() == 30, "unfinished former capstone remains the next resume target")
	await click_button("Continue · Level 30  →")
	check(game.screen == "game" and game.level.number == 30, "home resumes level 30 instead of silently starting 31")
	check(game.model.snapshot() == legacy.session.state, "continued legacy board matches the saved snapshot")
	check(game.model.history == legacy.session.history and game.model.extra_tray_granted, "continued legacy undo history retains purchased tray ownership")
	check(game.model.state.trays.size() == 7 and game.model.state.trays[6].front[0] == "tomato", "occupied seventh tray survives real scene recreation")
	check_board_bounds("legacy_seven_trays")
	check_readability_bounds()
	for tray in game.board.trays:
		check(tray.rim_color == Color("965b80"), "saved Berry finish is applied to every resumed tray")
	var protected_session: Dictionary = game.save.data.session.duplicate(true)
	var protected_hash: String = game.model.state_hash()
	game.show_levels()
	await settle()
	check_map(1, 30, 31)
	await screenshot("content_map_garden_current30")
	await click_named("Level030")
	check(game.screen == "game" and game.model.state_hash() == protected_hash, "selecting the current completed-but-unfinished replay resumes without reset")
	check(game.save.data.session == protected_session, "current map cell preserves run, history and paid-hint receipts")
	game.show_levels()
	await settle()
	await click_named("ChapterTab2")
	check_map(2, 30, 31)
	var locked: Button = game.page.find_child("Level051", true, false)
	await click_control(locked)
	check(game.screen == "levels" and not is_instance_valid(game.modal), "a locked level ignores real pointer input")
	check(game.save.data.session == protected_session and game.model.state_hash() == protected_hash, "browsing locked chapters cannot replace or charge the saved board")
	await click_named("ChapterTab3")
	check_map(3, 30, 31)
	await click_named("ChapterTab1")
	await click_named("Level031")
	check(modal_has("Start another table?"), "choosing an unlocked new table confirms replacement of unfinished replay")
	await click_button("Keep current board")
	check(game.save.data.session == protected_session, "canceling replacement preserves the exact session")
	await click_button("Continue · Level 30  →")
	await click_button("↶\nUndo")
	check(game.model.state.moves == 1 and game.model.extra_tray_granted, "legacy undo restores the prior board without revoking the purchased tray")
	var coins: int = game.economy.balance()
	await request_paid_hint()
	check_hint_executable()
	check(game.economy.balance() == coins and game.save.data.session.hint_receipts.size() == 2, "a migrated paid-hint receipt is reused without charging again")
	await click_button("↶\nUndo")
	check(game.model.state.moves == 0 and game.model.extra_tray_granted and game.model.state.trays.size() == 7, "undo across the old purchase boundary retains permanent run ownership")


func test_legacy_graduation() -> void:
	# The fixture already completed 30 once. Replay it through actual touch
	# events, then exercise the saved-win Continue path into new content.
	game.start_level(30)
	await settle()
	var balance: int = game.economy.balance()
	await solve_current()
	check(game.model.is_won() and game.economy.balance() == balance, "replaying the former capstone never duplicates its first-clear reward")
	game.show_home()
	await settle()
	check(game.next_table_number() == 31, "won old capstone now selects level 31")
	await click_button("Play · Level 31  →")
	check(game.level.number == 31 and game.model.state.moves == 0 and not game.model.is_won(), "won level-30 Continue opens a fresh level 31")
	check(game.save.data.profile.completed.size() == 30 and game.economy.balance() == balance, "entering expanded content grants no unearned clear or currency")
	# Explicitly cover a completed legacy profile with no resumable board.
	game.save.data.session = {}
	check(game.save.save_game(), "completed-profile no-session fixture saves")
	await reload_game()
	await click_button("Skip intro  →")
	await click_button("Enter the cafe  →")
	await click_button("Play · Level 31  →")
	check(game.level.number == 31 and game.economy.balance() == balance, "returning completed-30 profile without a session starts 31")


func test_chapter_boundary(number: int, next_chapter: String) -> void:
	# Test arrangement may jump to an authored boundary; all solving and
	# navigation after it use the same input route as play.
	game.start_level(number)
	await settle()
	check_board_bounds("boundary_%d" % number)
	var balance: int = game.economy.balance()
	await solve_current()
	check(game.model.is_won() and game.save.data.profile.completed.has(LevelCatalog.level_id(number)), "boundary %d records its canonical completion" % number)
	check(game.economy.balance() == balance + 30, "boundary %d grants one first-clear reward" % number)
	check(int(game.save.data.profile.unlocked) == number + 1, "boundary %d unlocks the first table of the next chapter" % number)
	check(modal_has("Chapter beautifully served!"), "boundary victory celebrates the chapter")
	check(labels_contain(game.modal, "Next stop: " + next_chapter), "boundary victory identifies the next chapter")
	await screenshot("content_chapter_win_%03d" % number)
	await click_button("Next table  →")
	check(game.level.number == number + 1 and int(game.level.chapter) == int(LevelCatalog.chapter_for_level(number + 1).id), "Next table crosses the chapter boundary correctly")
	check(labels_contain(game.page, next_chapter.to_upper()), "live game badge displays the new chapter")
	check(game.model.state.moves == 0 and game.save.data.session.level_number == number + 1, "next chapter starts and saves a fresh board")
	game.show_home()
	await settle()
	check_page_bounds("home_" + next_chapter)
	await screenshot("content_home_chapter%d" % int(LevelCatalog.chapter_for_level(number + 1).id))
	game.show_levels()
	await settle()
	check_map(int(LevelCatalog.chapter_for_level(number + 1).id), number + 1, number + 1)
	await screenshot("content_map_current%03d" % (number + 1))
	await click_button("Continue · Level %d  →" % (number + 1))


func test_terminal_victory() -> void:
	game.start_level(150)
	await settle()
	check_board_bounds("level150")
	await screenshot("content_level150")
	var balance: int = game.economy.balance()
	await solve_current()
	check(game.model.is_won() and game.save.data.profile.completed.has("breakfast_150"), "last table can be served through real touch input")
	check(game.save.data.profile.unlocked == 150 and game.next_table_number() == 150, "terminal progression is capped at 150")
	check(game.economy.balance() == balance + 30, "terminal first clear grants its reward exactly once")
	check(modal_has("A feast to remember!") and find_button("Next table  →") == null, "final celebration has no invalid level-151 route")
	await screenshot("content_final_victory")
	await click_button("Back to the garden")
	await click_button("Celebrate your collection  →")
	check(game.level.number == 150 and game.model.is_won() and modal_has("A feast to remember!"), "final home invitation restores the completed final table")
	check(game.economy.balance() == balance + 30, "reopening the finale never repeats its coin grant")
	await click_button("Replay this level")
	check(game.level.number == 150 and game.model.state.moves == 0 and not game.model.is_won(), "final level retains a working free replay action")
	await solve_current()
	check(game.economy.balance() == balance + 30, "solving the final replay grants no duplicate first-clear currency")


func check_map(chapter_id: int, current: int, unlocked: int) -> void:
	var chapter: Dictionary = LevelCatalog.chapter(chapter_id)
	check(labels_contain(game.page, str(chapter.name)), "map displays the selected chapter name")
	var grid_buttons: Array[Node] = []
	for node in game.page.find_children("*", "Button", true, false):
		if node.has_meta("level_number"): grid_buttons.append(node)
	check(grid_buttons.size() == 50, "selected map chapter contains exactly 50 level buttons")
	var highlights := 0
	for button: Button in grid_buttons:
		var number: int = button.get_meta("level_number")
		check(number >= int(chapter.start) and number <= int(chapter.end), "map button belongs to selected chapter")
		check(button.name == "Level%03d" % number and button.text.begins_with(str(number)), "map level label and identity match")
		check(button.disabled == (number > unlocked), "map button honors progress lock")
		check(bool(button.get_meta("completed")) == game.save.data.profile.completed.has(LevelCatalog.level_id(number)), "map completion check uses canonical chapter IDs")
		check(bool(button.get_meta("current")) == (number == current), "map current marker follows the actual resume target")
		if number == current:
			highlights += 1
			var box: StyleBoxFlat = button.get_theme_stylebox("normal")
			check(box.border_color == GardenUI.TEAL and box.border_width_left == 5, "current map cell has a visible teal outline")
	check(highlights == (1 if current >= int(chapter.start) and current <= int(chapter.end) else 0), "map has exactly the expected current highlight")
	check_scroll("LevelScroll", "chapter map")


func test_collection(unlocked: int) -> void:
	check(int(game.save.data.profile.unlocked) == unlocked, "collection fixture uses real earned unlock %d" % unlocked)
	var saved: Dictionary = game.save.data.session.duplicate(true)
	var balance: int = game.economy.balance()
	game.show_album(1, true)
	await settle()
	var seen_foods: Dictionary = {}
	var seen_recipes: Dictionary = {}
	for chapter_id in range(1, 4):
		if chapter_id != 1: await click_named("ChapterTab%d" % chapter_id)
		var chapter: Dictionary = LevelCatalog.chapter(chapter_id)
		var cards: Array[Node] = game.page.find_children("FoodCard_*", "PanelContainer", true, false)
		check(cards.size() == 6, "ingredient page has six chapter cards")
		for id: String in chapter.foods:
			seen_foods[id] = true
			var card: Node = game.page.find_child("FoodCard_" + id, true, false)
			check(card != null, "food collection exposes " + id)
			if card == null: continue
			var available: bool = unlocked >= FoodCatalog.unlock_level(id)
			check(card.get_meta("food_id") == id and card.get_meta("unlocked") == available, "food identity and unlock metadata agree")
			check(labels_contain(card, FoodCatalog.display_name(id)), "food card displays the registered name")
			check(labels_contain(card, "At your table ✓" if available else "Meet at level %d" % FoodCatalog.unlock_level(id)), "food card communicates actual first appearance")
			var icon: TextureRect = card.find_child("FoodIcon_" + id, true, false)
			check(icon != null and icon.texture == FoodCatalog.texture(id), "food card renders the registered atlas crop")
		check_scroll("CollectionScroll", "ingredient collection")
		if unlocked == 31: await screenshot("content_ingredients_chapter%d" % chapter_id)
		await click_named("RecipesTab")
		var expected := 0
		for recipe: Dictionary in LevelCatalog.load_recipes():
			if int(recipe.chapter) != chapter_id: continue
			expected += 1
			seen_recipes[recipe.id] = true
			var card: Node = game.page.find_child("RecipeCard_" + str(recipe.id), true, false)
			check(card != null, "recipe collection exposes " + str(recipe.id))
			if card == null: continue
			check(card.get_meta("recipe_id") == recipe.id and labels_contain(card, str(recipe.name)), "recipe card matches its canonical identity and name")
			var served := recorded_recipe(recipe)
			check(card.get_meta("served") == served, "served badge recognizes recorded recipe dictionaries")
			if str(recipe.id) == "garden_sampler":
				check(bool(card.get_meta("served")) and labels_contain(card, "Served with love ✓"), "authentic old Garden Sampler completion has a served badge")
			var status: String = "Served with love ✓" if served else ("On your menu" if unlocked >= int(recipe.unlock_level) else "Discover at level %d" % recipe.unlock_level)
			check(labels_contain(card, status), "recipe card communicates served/discovery state")
			var icons := card.find_children("*", "TextureRect", true, false)
			check(icons.size() == recipe.requirements.size(), "recipe displays one real icon for every ingredient")
			var index := 0
			for id: String in recipe.requirements:
				check(icons[index].texture == FoodCatalog.texture(id), "recipe ingredient crop matches its demand")
				index += 1
		check(expected == 4 and game.page.find_children("RecipeCard_*", "PanelContainer", true, false).size() == 4, "each chapter presents its own four recipes")
		check_scroll("CollectionScroll", "recipe collection")
		if unlocked == 31: await screenshot("content_recipes_chapter%d" % chapter_id)
		await click_named("IngredientsTab")
	check(seen_foods.size() == 18 and seen_recipes.size() == 12, "chapter tabs expose all eighteen foods and twelve recipes")
	check(game.save.data.session == saved and game.economy.balance() == balance, "collection browsing preserves the active board and wallet")
	game.continue_game()
	await settle()


func recorded_recipe(recipe: Dictionary) -> bool:
	for completion in game.save.data.profile.completed.values():
		for entry in completion.recipes:
			if not entry is Dictionary or entry.get("name") != recipe.name: continue
			var requirements: Dictionary = entry.get("requirements", {})
			if requirements.size() != recipe.requirements.size(): continue
			var matches := true
			for food: String in recipe.requirements:
				if not requirements.has(food) or int(requirements[food]) != int(recipe.requirements[food]): matches = false
			if matches: return true
	return false


func test_new_recipe(number: int, recipe_id: String) -> void:
	game.start_level(number)
	await settle()
	await solve_current()
	check(game.model.is_won(), "new recipe introduction level %d can be completed through touch" % number)
	var chapter_id: int = int(LevelCatalog.chapter_for_level(number).id)
	game.show_album(chapter_id)
	await settle()
	var card: Node = game.page.find_child("RecipeCard_" + recipe_id, true, false)
	check(card != null and bool(card.get_meta("served")) and labels_contain(card, "Served with love ✓"), "freshly served " + recipe_id + " immediately gains its badge")
	await screenshot("content_recipe_served_" + recipe_id)
	var coins: int = game.economy.balance()
	await reload_game()
	await click_button("Skip intro  →")
	await click_button("Enter the cafe  →")
	game.show_album(chapter_id)
	await settle()
	card = game.page.find_child("RecipeCard_" + recipe_id, true, false)
	check(card != null and bool(card.get_meta("served")) and labels_contain(card, "Served with love ✓"), "served " + recipe_id + " badge survives a cold scene reload")
	check(game.economy.balance() == coins, "reloading a newly served recipe cannot duplicate currency")
	game.continue_game()
	await settle()


func test_sprite_alpha() -> void:
	for id: String in FoodCatalog.ids():
		var texture: AtlasTexture = FoodCatalog.texture(id)
		var image: Image = texture.atlas.get_image()
		check(image != null and not image.is_empty(), "atlas image data is available for " + id)
		if image == null or image.is_empty(): continue
		if image.is_compressed(): check(image.decompress() == OK, "atlas can be inspected for transparency")
		var region := Rect2i(texture.region)
		var transparent := 0
		var opaque := 0
		for y in range(16):
			for x in range(16):
				var point := region.position + Vector2i(16 + x * 32, 16 + y * 32)
				var alpha: float = image.get_pixelv(point).a
				if alpha < 0.05: transparent += 1
				if alpha > 0.95: opaque += 1
		check(transparent >= 26, "food crop has transparent surrounding space: " + id)
		check(opaque >= 26, "food crop has substantial visible food pixels: " + id)


func test_live_art(number: int) -> void:
	game.start_level(number)
	await settle()
	check_board_bounds("new_food_level%d" % number)
	check_readability_bounds()
	var found: Dictionary = {}
	for tray: TrayView in game.board.trays:
		for index in range(3):
			var id: Variant = tray.tray_data.front[index]
			if id == null: continue
			var icons := tray.food_nodes[index].find_children("*", "TextureRect", true, false)
			check(icons.size() == 1 and icons[0].texture == FoodCatalog.texture(str(id)), "live board uses the actual new food atlas texture")
			found[str(id)] = true
	check(found.has(str(game.level.authoring.new_food)), "introduction board visibly includes its new ingredient")
	await screenshot("content_live_foods_%03d" % number)


func check_readability_bounds() -> void:
	check(bool(game.settings().high_readability), "legacy high-readability setting remains active for long-label checks")
	for tray: TrayView in game.board.trays:
		for holder: Control in tray.food_nodes:
			for label: Label in holder.find_children("*", "Label", true, false):
				var bounds := holder.get_global_rect()
				var text_bounds := label.get_global_rect()
				check(text_bounds.position.x >= bounds.position.x - 1 and text_bounds.end.x <= bounds.end.x + 1, "high-readability food label stays in its own slot: " + label.text)


func check_scroll(name: String, label: String) -> void:
	var scroll: ScrollContainer = game.page.find_child(name, true, false)
	check(scroll != null, label + " exposes its scrolling container")
	if scroll == null: return
	check(scroll.get_global_rect().position.x >= -1 and scroll.get_global_rect().end.x <= game.size.x + 1, label + " scroll area fits horizontal viewport")
	check(scroll.get_global_rect().end.y <= game.size.y + 1 and scroll.size.y > 100, label + " scroll area fits vertical viewport")
	check(scroll.get_child(0).get_combined_minimum_size().x <= scroll.size.x + 1, label + " content needs no horizontal clipping")
	check(scroll.get_child(0).get_combined_minimum_size().y <= scroll.size.y + 1 or scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, label + " overflowing cards remain reachable by scrolling")
	check_page_bounds(label)


func click_named(name: String) -> void:
	var button: Button = game.page.find_child(name, true, false)
	check(button != null and not button.disabled, "named control is available: " + name)
	if button != null: await click_control(button)


func labels_contain(scope: Node, fragment: String) -> bool:
	for label in scope.find_children("*", "Label", true, false):
		if label.text.contains(fragment): return true
	return false
