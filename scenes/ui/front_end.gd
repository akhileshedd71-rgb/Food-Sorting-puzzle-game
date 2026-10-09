class_name GardenFrontEnd
extends RefCounted
## Front-end views emit intent through the application controller.

static func splash(game: Variant) -> void:
	game.clear_page("splash")
	game.page.add_child(GardenUI.spacer(0, true))
	var mark := BrandMark.new()
	mark.custom_minimum_size = Vector2(220, 220)
	var center := CenterContainer.new()
	center.add_child(mark)
	game.page.add_child(center)
	game.page.add_child(game.centered("GARDEN TABLE", 46, GardenUI.TEAL, true))
	game.page.add_child(game.centered("A little room. A lovely meal.", 23, GardenUI.INK))
	game.page.add_child(GardenUI.spacer(0, true))
	game.page.add_child(game.centered("ORIGINAL RECIPES FOR A QUIETER MOMENT", 15, GardenUI.TEAL, true))
	game.page.add_child(GardenUI.button("Skip intro  →", game.show_title, GardenUI.CREAM, Vector2(0, 62)))
	GardenMotion.enter(center, game.settings().reduced_motion)
	var serial: int = game.generation
	var delay: float = 0.3 if game.settings().reduced_motion else 1.8
	var game_ref : WeakRef = weakref(game)
	game.get_tree().create_timer(delay).timeout.connect(func():
		var active_game: Variant = game_ref.get_ref()
		if is_instance_valid(active_game) and active_game.generation == serial and active_game.screen == "splash": active_game.show_title())

static func title(game: Variant) -> void:
	game.clear_page("title")
	var top := GardenUI.hbox()
	top.add_child(GardenUI.expand(GardenUI.spacer()))
	top.add_child(GardenUI.button("☼", game.show_settings, GardenUI.CREAM, Vector2(76, 76)))
	game.page.add_child(top)
	game.page.add_child(GardenUI.spacer(76))
	var center := CenterContainer.new()
	var mark := BrandMark.new()
	mark.custom_minimum_size = Vector2(170, 170)
	center.add_child(mark)
	game.page.add_child(center)
	var brand: Label = game.centered("Garden\nTable", 86, GardenUI.CREAM, true)
	brand.add_theme_constant_override("outline_size", 12)
	brand.add_theme_color_override("font_shadow_color", Color("315941"))
	brand.add_theme_constant_override("shadow_offset_y", 5)
	game.page.add_child(brand)
	game.page.add_child(game.centered("SORT. SERVE. SAVOR.", 24, GardenUI.CREAM, true))
	game.page.add_child(GardenUI.spacer(0, true))
	var invitation := GardenUI.panel(Color("fff5dc"), 26)
	var content := GardenUI.vbox(12)
	invitation.add_child(content)
	content.add_child(game.centered("Your table is waiting", 30, GardenUI.TEAL, true))
	content.add_child(game.centered("A cozy collection of food-sorting puzzles.\nNo rush. Just one delicious match at a time.", 23))
	content.add_child(GardenUI.button("Enter the cafe  →", game.show_home, GardenUI.TEAL, Vector2(0, 98)))
	game.page.add_child(invitation)
	game.page.add_child(GardenUI.spacer(0, true))
	game.page.add_child(game.centered("GARDEN GRILL  ·  30 TABLES TO DISCOVER", 17, Color("64452f"), true))
	game.page.add_child(game.centered("v0.2  ·  Made for a little everyday joy", 15, Color("64452f")))
	game.animate_page()

static func home(game: Variant) -> void:
	game.clear_page("home")
	var top := GardenUI.hbox(14)
	var hello := GardenUI.panel()
	hello.add_child(GardenUI.label("YOUR LITTLE CAFE", 21, GardenUI.TEAL, true))
	top.add_child(GardenUI.expand(hello))
	top.add_child(wallet_button(game))
	top.add_child(GardenUI.button("☼", game.show_settings, GardenUI.CREAM, Vector2(72, 76)))
	game.page.add_child(top)
	game.page.add_child(GardenUI.spacer(82))
	game.page.add_child(game.centered("Welcome to\nthe garden", 52, GardenUI.CREAM, true))
	game.page.add_child(game.centered("Good food. Great company.", 25, GardenUI.CREAM, true))
	game.page.add_child(GardenUI.spacer(34))
	var card := GardenUI.panel()
	var body := GardenUI.vbox(10)
	card.add_child(body)
	var chapter := GardenUI.hbox(10)
	chapter.add_child(GardenUI.expand(GardenUI.label("01  GARDEN GRILL", 24, GardenUI.TEAL, true)))
	chapter.add_child(GardenUI.label("%d / 30" % game.save.data.profile.completed.size(), 22, GardenUI.TEAL, true))
	body.add_child(chapter)
	var foods := GardenUI.hbox(2)
	foods.alignment = BoxContainer.ALIGNMENT_CENTER
	for id in ["tomato", "corn_cob", "button_mushroom", "bell_pepper_ring"]:
		foods.add_child(FoodArt.icon(id, 114))
	body.add_child(foods)
	var resume: bool = not game.save.data.session.is_empty()
	var number: int = int(game.save.data.session.level_number) if resume else int(game.save.data.profile.unlocked)
	var needs_school: bool = not game.economy.tutorial_complete() and not resume and game.save.data.profile.completed.is_empty()
	body.add_child(game.centered("A fresh start, one plate at a time." if needs_school else "A little space makes all the difference.", 22))
	body.add_child(GardenUI.button("Start cooking  →" if needs_school else "%s · Level %d  →" % ["Continue" if resume else "Play", number], game.begin_adventure, GardenUI.TEAL, Vector2(0, 92)))
	if needs_school:
		body.add_child(game.centered("Includes three quick, hands-on lessons", 18, Color("837660")))
	game.page.add_child(card)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	for entry in [["☷  Level map", game.show_levels], ["▤  Recipe book", game.show_album], ["✦  Cooking School", game.start_tutorial], ["◉  Coin shop", game.show_shop]]:
		var button := GardenUI.button(entry[0], entry[1], GardenUI.CREAM, Vector2(0, 94))
		button.add_theme_font_size_override("font_size", 23)
		grid.add_child(GardenUI.expand(button))
	game.page.add_child(grid)
	var wallet := GardenUI.panel(Color("fff0bf"), 20)
	var wallet_row := GardenUI.hbox(14)
	var coin := CoinIcon.new()
	coin.custom_minimum_size = Vector2(58, 58)
	wallet_row.add_child(coin)
	var note := GardenUI.vbox(2)
	note.add_child(GardenUI.label("A little help, on the house", 22, GardenUI.TEAL, true))
	var text: Label = game.centered("Earn 30 Chef Coins for each new table. Spend them on helpful tools and lovely tray finishes.", 19)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	note.add_child(text)
	wallet_row.add_child(GardenUI.expand(note))
	wallet.add_child(wallet_row)
	game.page.add_child(wallet)
	game.page.add_child(GardenUI.spacer(0, true))
	var title_button := GardenUI.button("Back to title", game.show_title, GardenUI.CREAM, Vector2(0, 54))
	title_button.add_theme_font_size_override("font_size", 18)
	game.page.add_child(title_button)
	game.animate_page()

static func wallet_button(game: Variant) -> Button:
	var button := GardenUI.button("◉ %d +" % game.economy.balance(), game.show_shop, GardenUI.GOLD, Vector2(152, 76))
	button.name = "WalletButton"
	button.add_theme_font_size_override("font_size", 24)
	return button

static func shop(game: Variant) -> void:
	game.clear_page("shop")
	var top := GardenUI.hbox(12)
	top.add_child(GardenUI.button("‹", game.return_from_shop, GardenUI.CREAM, Vector2(72, 76)))
	var title_card := GardenUI.panel()
	title_card.add_child(game.centered("Chef's cupboard", 28, GardenUI.TEAL, true))
	top.add_child(GardenUI.expand(title_card))
	var wallet := GardenUI.button("◉ %d" % game.economy.balance(), game.show_earn_coins, GardenUI.GOLD, Vector2(150, 76))
	wallet.add_theme_font_size_override("font_size", 23)
	top.add_child(wallet)
	game.page.add_child(top)
	game.page.add_child(GardenUI.spacer(48))
	game.page.add_child(game.centered("A little extra delight", 37, GardenUI.CREAM, true))
	game.page.add_child(game.centered("Helpful tools. Your own finishing touch.", 22, GardenUI.CREAM, true))
	game.page.add_child(GardenUI.spacer(12))
	var scroll := ScrollContainer.new()
	scroll.name = "ShopScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var content := GardenUI.vbox(20)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	game.page.add_child(scroll)
	var tools_card := GardenUI.panel()
	var tool_body := GardenUI.vbox(14)
	tool_body.add_child(GardenUI.label("A HELPING HAND", 21, GardenUI.TEAL, true))
	var can_use: bool = game.shop_origin == "game" and game.model != null and not game.model.is_won() and not game.tutorial_mode
	for item in [["✦", "A thoughtful hint", "Highlights a verified step toward a solution.", 10, game.shop_hint], ["+", "A little more room", "One extra tray for this level attempt. It stays when you undo.", 40, game.shop_extra_tray]]:
		var row := GardenUI.hbox(16)
		var icon: Label = game.centered(item[0], 42, GardenUI.TEAL, true)
		icon.custom_minimum_size.x = 54
		row.add_child(icon)
		var description := GardenUI.vbox(4)
		description.add_child(GardenUI.label(item[1], 24, GardenUI.INK, true))
		var detail := GardenUI.label(item[2], 18)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.add_child(detail)
		row.add_child(GardenUI.expand(description))
		var use := GardenUI.button("◉ %d" % item[3], item[4], GardenUI.GOLD, Vector2(108, 66))
		use.add_theme_font_size_override("font_size", 21)
		use.disabled = not can_use
		row.add_child(use)
		tool_body.add_child(row)
	tool_body.add_child(game.centered("Use tools from your table. Undo and restart are always free.", 18, Color("81725e")))
	tools_card.add_child(tool_body)
	content.add_child(tools_card)
	content.add_child(_styles(game))
	var packs := GardenUI.panel(Color("fff0ca"), 24)
	var packs_body := GardenUI.vbox(12)
	packs_body.add_child(GardenUI.label("CHEF COIN PACKS", 21, GardenUI.TEAL, true))
	packs_body.add_child(game.centered("Coin purchases are coming later.\nFor now, earn every coin by playing.", 21))
	var pack_row := GardenUI.hbox(12)
	for amount in [250, 700, 1600]:
		var pack := GardenUI.panel(GardenUI.CREAM, 16)
		var stack := GardenUI.vbox(8)
		var icon_center := CenterContainer.new()
		var icon := CoinIcon.new()
		icon.custom_minimum_size = Vector2(64, 64)
		icon_center.add_child(icon)
		stack.add_child(icon_center)
		stack.add_child(game.centered(str(amount), 32, GardenUI.TEAL, true))
		stack.add_child(game.centered("Chef Coins", 16))
		var soon := GardenUI.button("Coming later", Callable(), GardenUI.GOLD, Vector2(0, 56))
		soon.add_theme_font_size_override("font_size", 16)
		soon.disabled = true
		stack.add_child(soon)
		pack.add_child(stack)
		pack_row.add_child(GardenUI.expand(pack))
	packs_body.add_child(pack_row)
	packs.add_child(packs_body)
	content.add_child(packs)
	game.page.add_child(GardenUI.button("How to earn Chef Coins", game.show_earn_coins, GardenUI.TEAL, Vector2(0, 70)))
	game.animate_page()

static func _styles(game: Variant) -> PanelContainer:
	var panel := GardenUI.panel()
	var content := GardenUI.vbox(12)
	panel.add_child(content)
	content.add_child(GardenUI.label("MAKE IT YOURS", 21, GardenUI.TEAL, true))
	content.add_child(GardenUI.label("Permanent enamel finishes for your trays", 19))
	for finish in game.economy.themes():
		var row := GardenUI.hbox(14)
		var preview := TrayView.new()
		preview.custom_minimum_size = Vector2(180, 140)
		preview.rim_color = finish.rim
		preview.accent_color = finish.accent
		row.add_child(preview)
		preview.bind(0, {"id":"preview", "front":["tomato", "corn_cob", "button_mushroom"], "queue":[]}, Vector2i(-1, -1), Vector2i(-1, -1), false)
		var info := GardenUI.vbox(8)
		info.add_child(GardenUI.label(str(finish.name), 24, GardenUI.TEAL, true))
		var equipped: bool = finish.equipped
		var owned: bool = finish.owned
		var action: Callable = game.equip_finish.bind(str(finish.id)) if owned else game.confirm_finish.bind(str(finish.id))
		var button := GardenUI.button("Equipped ✓" if equipped else ("Equip" if owned else "Unlock · ◉ %d" % int(finish.cost)), action, GardenUI.CREAM if owned else GardenUI.GOLD, Vector2(0, 64))
		button.add_theme_font_size_override("font_size", 20)
		button.disabled = equipped
		info.add_child(button)
		row.add_child(GardenUI.expand(info))
		content.add_child(row)
	return panel
