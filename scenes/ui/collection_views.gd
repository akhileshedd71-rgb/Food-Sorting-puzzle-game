class_name GardenCollection
extends RefCounted
## Chapter navigation and the illustrated recipe/ingredient collection.

static func chapter_tabs(selected: int, action: Callable) -> HBoxContainer:
	var row := GardenUI.hbox(12)
	for chapter in LevelCatalog.chapters():
		var short_name: String = ["Garden", "Barbecue", "Breakfast"][int(chapter.id) - 1]
		var tab := GardenUI.button("%02d  %s" % [chapter.id, short_name], action.bind(int(chapter.id)), GardenUI.TEAL if selected == int(chapter.id) else GardenUI.CREAM, Vector2(0, 76))
		tab.name = "ChapterTab%d" % chapter.id
		tab.add_theme_font_size_override("font_size", 21)
		row.add_child(GardenUI.expand(tab))
	return row

static func levels(game: Variant, chapter_id: int = 0) -> void:
	var current: int = game.next_table_number()
	var selected_chapter: int = int(LevelCatalog.chapter_for_level(current).id) if chapter_id == 0 else clampi(chapter_id, 1, LevelCatalog.chapters().size())
	var chapter: Dictionary = LevelCatalog.chapter(selected_chapter)
	game.clear_page("levels")
	game.add_header("Your food journey", game.show_home)
	game.page.add_child(GardenUI.spacer(40))
	game.page.add_child(game.centered(str(chapter.name), 39, GardenUI.CREAM, true))
	game.page.add_child(game.centered(str(chapter.subtitle), 22, GardenUI.CREAM))
	game.page.add_child(chapter_tabs(selected_chapter, game.show_levels))
	var panel := GardenUI.panel()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.name = "LevelScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var list := GardenUI.vbox(18)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	list.add_child(game.centered("LEVELS %d–%d  ·  %d / 50 COMPLETE" % [chapter.start, chapter.end, game.chapter_completed(chapter)], 22, GardenUI.TEAL, true))
	var foods := GardenUI.hbox(1)
	foods.alignment = BoxContainer.ALIGNMENT_CENTER
	for id in chapter.foods:
		foods.add_child(FoodArt.icon(str(id), 84))
	list.add_child(foods)
	var chapter_unlocked: bool = int(game.save.data.profile.unlocked) >= int(chapter.start)
	var note: String = "Choose your next table, or revisit a favorite."
	if not chapter_unlocked: note = "Clear level %d to open this chapter. No coins needed." % (int(chapter.start) - 1)
	list.add_child(game.centered(note, 20))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 14)
	list.add_child(grid)
	var current_button: Button
	for number in range(int(chapter.start), int(chapter.end) + 1):
		var completed: bool = game.save.data.profile.completed.has(LevelCatalog.level_id(number))
		var unlocked: bool = number <= int(game.save.data.profile.unlocked)
		var button := GardenUI.button("%d%s" % [number, " ✓" if completed else ""], game.choose_level.bind(number), GardenUI.TEAL if completed else GardenUI.GOLD, Vector2(0, 92))
		button.name = "Level%03d" % number
		button.set_meta("level_number", number)
		button.set_meta("completed", completed)
		button.set_meta("current", number == current)
		button.add_theme_font_size_override("font_size", 23)
		button.disabled = not unlocked
		if number == current:
			button.add_theme_stylebox_override("normal", GardenUI.box(GardenUI.GOLD, 21, GardenUI.TEAL, 5, 5))
			button.add_theme_color_override("font_color", GardenUI.INK)
			current_button = button
		grid.add_child(GardenUI.expand(button))
	game.page.add_child(panel)
	game.page.add_child(GardenUI.button("Continue · Level %d  →" % current, game.continue_game))
	if current_button: focus_scroll(scroll, current_button)
	game.animate_page()

static func album(game: Variant, chapter_id: int = 0, foods_view: bool = false) -> void:
	var selected_chapter: int = int(LevelCatalog.chapter_for_level(game.next_table_number()).id) if chapter_id == 0 else clampi(chapter_id, 1, LevelCatalog.chapters().size())
	var chapter: Dictionary = LevelCatalog.chapter(selected_chapter)
	game.clear_page("album")
	game.add_header("Your ingredients" if foods_view else "The recipe book", game.show_home)
	game.page.add_child(GardenUI.spacer(32))
	game.page.add_child(game.centered(str(chapter.name), 36, GardenUI.CREAM, true))
	game.page.add_child(game.centered("Eighteen flavors. A whole table of possibilities." if foods_view else "One triple prepares one batch.", 22, GardenUI.CREAM))
	var tabs := GardenUI.hbox(12)
	var recipes_tab := GardenUI.button("Recipes · 12", game.show_album.bind(selected_chapter, false), GardenUI.TEAL if not foods_view else GardenUI.CREAM, Vector2(0, 70))
	recipes_tab.name = "RecipesTab"
	var ingredients_tab := GardenUI.button("Ingredients · 18", game.show_album.bind(selected_chapter, true), GardenUI.TEAL if foods_view else GardenUI.CREAM, Vector2(0, 70))
	ingredients_tab.name = "IngredientsTab"
	tabs.add_child(GardenUI.expand(recipes_tab))
	tabs.add_child(GardenUI.expand(ingredients_tab))
	game.page.add_child(tabs)
	game.page.add_child(chapter_tabs(selected_chapter, func(id: int): game.show_album(id, foods_view)))
	var scroll := ScrollContainer.new()
	scroll.name = "CollectionScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := GardenUI.vbox(18)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if foods_view:
		for id in chapter.foods:
			list.add_child(food_card(game, str(id)))
	else:
		for recipe in LevelCatalog.load_recipes():
			if int(recipe.chapter) == selected_chapter: list.add_child(recipe_card(game, recipe))
	game.page.add_child(scroll)
	game.animate_page()

static func food_card(game: Variant, id: String) -> PanelContainer:
	var unlocked: bool = int(game.save.data.profile.unlocked) >= FoodCatalog.unlock_level(id)
	var card := GardenUI.panel()
	card.name = "FoodCard_" + id
	card.set_meta("food_id", id)
	card.set_meta("unlocked", unlocked)
	var row := GardenUI.hbox(20)
	var icon := FoodArt.icon(id, 130)
	icon.name = "FoodIcon_" + id
	row.add_child(icon)
	var copy := GardenUI.vbox(8)
	copy.add_child(GardenUI.label(FoodArt.title(id), 28, GardenUI.TEAL, true))
	copy.add_child(GardenUI.label("At your table ✓" if unlocked else "Meet at level %d" % FoodCatalog.unlock_level(id), 20, Color("827059")))
	var description := GardenUI.label("Match three identical pieces to prepare one batch.", 19)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(description)
	row.add_child(GardenUI.expand(copy))
	card.add_child(row)
	return card

static func recipe_card(game: Variant, recipe: Dictionary) -> PanelContainer:
	var card := GardenUI.panel()
	card.name = "RecipeCard_" + str(recipe.id)
	card.set_meta("recipe_id", str(recipe.id))
	var body := GardenUI.vbox(10)
	card.add_child(body)
	var discovered: bool = int(game.save.data.profile.unlocked) >= int(recipe.unlock_level)
	var served := false
	for completion in game.save.data.profile.completed.values():
		for recorded in completion.get("recipes", []):
			if recorded is Dictionary and recorded.get("name", "") == recipe.name and BoardModel.canonical_json(recorded.get("requirements", {})) == BoardModel.canonical_json(recipe.requirements):
				served = true
	card.set_meta("served", served)
	body.add_child(GardenUI.label(str(recipe.name), 29, GardenUI.TEAL, true))
	body.add_child(GardenUI.label("Served with love ✓" if served else ("On your menu" if discovered else "Discover at level %d" % recipe.unlock_level), 19, Color("8a7960")))
	var foods := GardenUI.hbox(2)
	for id in recipe.requirements:
		var ingredient := GardenUI.vbox(0)
		ingredient.add_child(FoodArt.icon(str(id), 79))
		ingredient.add_child(game.centered("×%d" % recipe.requirements[id], 18))
		foods.add_child(ingredient)
	body.add_child(foods)
	return card

static func focus_scroll(scroll: ScrollContainer, target: Control) -> void:
	var scroll_ref: WeakRef = weakref(scroll)
	var target_ref: WeakRef = weakref(target)
	scroll.get_tree().process_frame.connect(func():
		var active_scroll: ScrollContainer = scroll_ref.get_ref()
		var active_target: Control = target_ref.get_ref()
		if active_scroll and active_target: active_scroll.ensure_control_visible(active_target), CONNECT_ONE_SHOT)
