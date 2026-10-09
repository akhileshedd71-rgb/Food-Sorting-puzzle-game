extends Control
## Application flow and presentation. The BoardModel is the sole game authority.

const NONE := Vector2i(-1, -1)
const TOTAL_LEVELS := 30
@export var tuning: GameTuning = preload("res://data/tuning/default.tres")

var save: SaveService
var audio: GameAudio
var economy: EconomyService
var background: TextureRect
var tutorial_mode: bool = false
var tutorial_index: int = 0
var shop_origin: String = "home"
var wallet_button: Button
var scenery_gap: Control
var first_clear_reward: int = 0
var model: BoardModel
var level: Dictionary = {}
var screen: String = "home"
var stage: Control
var page: VBoxContainer
var modal: Control
var board: BoardView
var orders: VBoxContainer
var moves_label: Label
var status_label: Label
var progress_label: Label
var progress_bar: ProgressBar
var undo_button: Button
var selected := NONE
var hint_cell := NONE
var pointer: int = -2
var press_cell := NONE
var press_position := Vector2.ZERO
var dragging: bool = false
var ghost: TextureRect
var busy: bool = false
var generation: int = 0
var toast_node: PanelContainer
var application_active: bool = true

func _ready() -> void:
	theme = preload("res://data/tuning/garden_theme.tres")
	get_tree().auto_accept_quit = false
	save = SaveService.new()
	save.load_save()
	economy = EconomyService.new(save)
	economy.initialize()
	GardenUI.reduced_motion = bool(settings().reduced_motion)
	audio = GameAudio.new()
	add_child(audio)
	audio.configure(settings())
	var base := ColorRect.new()
	base.color = GardenUI.CREAM
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(base)
	var bg := TextureRect.new()
	background = bg
	bg.texture = preload("res://assets/backgrounds/restaurant.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	stage = Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	resized.connect(_layout_stage)
	_layout_stage()
	show_splash()
	if not save.recovery_notice.is_empty():
		show_toast(save.recovery_notice)
	# Reproducible QA entrypoints; ordinary play never uses these flags.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			start_level(int(arg.get_slice("=", 1)))
		elif arg == "--home":
			show_home()
		elif arg == "--title":
			show_title()
		elif arg == "--school":
			start_tutorial(0)

func settings() -> Dictionary:
	return save.data.profile.settings

func show_splash() -> void:
	GardenFrontEnd.splash(self)

func show_title() -> void:
	tutorial_mode = false
	GardenFrontEnd.title(self)

func animate_page() -> void:
	GardenMotion.enter(page, bool(settings().reduced_motion))

func begin_adventure() -> void:
	if not economy.tutorial_complete() and save.data.session.is_empty() and save.data.profile.completed.is_empty():
		start_tutorial()
	else:
		continue_game()

func start_tutorial(index: int = -1) -> void:
	if screen == "game" and not tutorial_mode and model:
		commit_current_session()
	tutorial_mode = true
	tutorial_index = clampi(economy.tutorial_step() if index < 0 else index, 0, 2)
	if index < 0 and economy.tutorial_complete(): tutorial_index = 0
	level = CookingSchool.lesson(tutorial_index)
	model = BoardModel.new()
	model.undo_capacity = tuning.undo_capacity
	model.setup(level)
	first_clear_reward = 0
	build_game()
	update_tutorial_guidance()

func update_tutorial_guidance() -> void:
	if not tutorial_mode or not is_instance_valid(board): return
	var instruction := CookingSchool.instruction(tutorial_index, model)
	selected = instruction.source
	hint_cell = instruction.target
	refresh_game()
	status_label.text = str(instruction.body)
	progress_label.text = str(instruction.progress)
	GardenMotion.enter(status_label, bool(settings().reduced_motion))

func show_lesson_complete() -> void:
	cancel_pointer()
	var last_lesson := tutorial_index == 2
	var awarded := 0
	var recorded := false
	if last_lesson:
		var reward := economy.complete_tutorial()
		awarded = int(reward.get("awarded", 0))
		recorded = reward.status == "ok"
	else:
		recorded = economy.set_tutorial_step(tutorial_index + 1)
	if not recorded:
		var retry := open_modal("One last thing to save", "You completed this lesson, but your progress couldn't be saved. Your coins are unchanged. Check available storage, then try again before continuing.")
		retry.add_child(GardenUI.button("Try saving again", show_lesson_complete))
		retry.add_child(GardenUI.button("Leave without saving this lesson", show_home, GardenUI.CREAM))
		return
	audio.play_cue("win")
	var description := "You matched identical foods. A full tray of three makes one batch."
	if tutorial_index == 1: description = "You emptied a row and revealed the next plate. Ready-made triples clear all by themselves!"
	if last_lesson: description = "You prepared batches, saved ingredients for a future order, and served the whole menu. You're ready for your own table."
	var body := open_modal("Ready, chef!" if last_lesson else "Lovely work!", description)
	var row := GardenUI.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in range(3):
		row.add_child(centered("✓" if i <= tutorial_index else "○", 34, GardenUI.TEAL, true))
	body.add_child(row)
	if awarded > 0:
		body.add_child(centered("Graduation gift · +%d Chef Coins" % awarded, 26, GardenUI.TEAL, true))
		GardenMotion.coin_burst(self, size * Vector2(0.5, 0.45), awarded, settings().reduced_motion)
	if last_lesson:
		body.add_child(GardenUI.button("To my table  →", continue_game))
	else:
		body.add_child(GardenUI.button("Next lesson  →", start_tutorial.bind(tutorial_index + 1)))
	body.add_child(GardenUI.button("Main menu", show_home, GardenUI.CREAM))

func restart_current() -> void:
	if tutorial_mode: start_tutorial(tutorial_index)
	else: start_level(int(level.number))

func show_shop() -> void:
	if busy: return
	if screen != "shop": shop_origin = "game" if screen == "game" else "home"
	if screen == "game": commit_current_session()
	GardenFrontEnd.shop(self)

func return_from_shop() -> void:
	if shop_origin == "game" and model:
		build_game()
		if tutorial_mode: update_tutorial_guidance()
	else:
		show_home()

func show_earn_coins() -> void:
	var body := open_modal("Good food earns good things", "100 Chef Coins welcome you to the cafe.\n\nEarn 30 for each first-time campaign clear, plus a one-time 30-coin Cooking School graduation gift.\n\nReplay, undo and restart stay free. Coin purchases will arrive in a later update.")
	body.add_child(centered("Your wallet: %d Chef Coins" % economy.balance(), 26, GardenUI.TEAL, true))
	body.add_child(GardenUI.button("Lovely", close_modal))

func shop_hint() -> void:
	return_from_shop()
	request_hint()

func shop_extra_tray() -> void:
	return_from_shop()
	request_extra_tray()

func request_extra_tray() -> void:
	if busy or not model or model.is_won() or tutorial_mode: return
	if model.extra_tray_granted:
		show_toast("Your extra tray is already on the table for this attempt.")
		return
	var body := open_modal("Make a little more room", "Add one empty tray for 40 Chef Coins. It stays through undo and Continue, until you restart or finish this level.")
	body.add_child(centered("Your balance: %d Chef Coins" % economy.balance(), 23, GardenUI.TEAL, true))
	body.add_child(GardenUI.button("Add a tray · ◉ 40", purchase_extra_tray, GardenUI.GOLD))
	body.add_child(GardenUI.button("Keep playing", close_modal, GardenUI.CREAM))

func purchase_extra_tray() -> void:
	var result := economy.buy_extra_tray(model, level)
	close_modal()
	if result.status != "ok":
		economy_message(result)
		return
	build_game()
	audio.play_cue("serve")
	show_toast("A little breathing room. Your extra tray stays through undo.")

func purchase_hint() -> void:
	var result := economy.buy_hint(model, level, tuning.hint_budget_ms)
	close_modal()
	if result.status != "ok":
		economy_message(result)
		return
	var next: Array = result.move
	selected = Vector2i(next[0], next[1])
	hint_cell = Vector2i(next[2], next[3])
	refresh_game()
	status_label.text = "Move %s to the outlined space. %s" % [FoodArt.title(str(model.state.trays[selected.x].front[selected.y])), "Hint already paid for." if int(result.charged) == 0 else "10 Chef Coins spent."]
	GardenMotion.enter(status_label, settings().reduced_motion)
	audio.play_cue("select")

func economy_message(result: Dictionary) -> void:
	match str(result.get("status", "unavailable")):
		"insufficient":
			var body := open_modal("A few more Chef Coins", "You don't have enough coins for that yet. Clear a new campaign level to earn 30, or finish Cooking School for its graduation gift. Undo and restart are always free.")
			body.add_child(centered("Your wallet: %d" % economy.balance(), 25, GardenUI.TEAL, true))
			body.add_child(GardenUI.button("Keep playing", close_modal))
		"unknown": show_toast("No verified solution found in time. No coins spent. Try undo or restart.")
		"save_failed": show_toast("Couldn't save this action. Your coins and board are unchanged.")
		_: show_toast("That helper is unavailable on this table. No coins spent.")

func equipped_finish() -> Dictionary:
	for finish in economy.themes():
		if finish.equipped: return finish
	return {}

func confirm_finish(id: String) -> void:
	for finish in economy.themes():
		if str(finish.id) != id: continue
		var body := open_modal("%s, just for you" % finish.name, "Unlock this enamel finish permanently for %d Chef Coins. Switch between your owned finishes whenever you like." % finish.cost)
		body.add_child(GardenUI.button("Unlock · ◉ %d" % finish.cost, buy_finish.bind(id), GardenUI.GOLD))
		body.add_child(GardenUI.button("Maybe later", close_modal, GardenUI.CREAM))
		return

func buy_finish(id: String) -> void:
	var result := economy.buy_theme(id)
	close_modal()
	if result.status != "ok":
		economy_message(result)
		return
	GardenFrontEnd.shop(self)
	audio.play_cue("serve")
	show_toast("A lovely new finish. It's yours to keep.")

func equip_finish(id: String) -> void:
	var result := economy.equip_theme(id)
	if result.status == "ok":
		GardenFrontEnd.shop(self)
		audio.play_cue("click")
	else: economy_message(result)

func _layout_stage() -> void:
	if not stage:
		return
	stage.size = Vector2(minf(size.x, 760), size.y)
	stage.position = Vector2((size.x - stage.size.x) * 0.5, 0)
	cancel_pointer()

func clear_page(kind: String) -> void:
	GardenMotion.cancel_all(self)
	for child in get_children():
		if child.has_meta("page_effect"):
			remove_child(child)
			child.queue_free()
	if is_instance_valid(toast_node): toast_node.queue_free()
	toast_node = null
	generation += 1
	cancel_pointer()
	close_modal()
	screen = kind
	background.visible = kind != "splash"
	board = null
	wallet_button = null
	busy = false
	for child in stage.get_children():
		stage.remove_child(child)
		child.queue_free()
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margins.add_theme_constant_override("margin_left", 24)
	margins.add_theme_constant_override("margin_right", 24)
	margins.add_theme_constant_override("margin_top", safe_top())
	margins.add_theme_constant_override("margin_bottom", safe_bottom())
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(margins)
	page = GardenUI.vbox(18)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margins.add_child(page)
	audio.set_music_active(application_active)

func safe_top() -> int:
	if OS.get_name() != "Android":
		return 28
	var safe_area := DisplayServer.get_display_safe_area()
	var ratio := size.y / float(DisplayServer.window_get_size().y)
	return maxi(28, int(safe_area.position.y * ratio) + 12)

func safe_bottom() -> int:
	if OS.get_name() != "Android":
		return 26
	var safe_area := DisplayServer.get_display_safe_area()
	var ratio := size.y / float(DisplayServer.window_get_size().y)
	return maxi(26, int((DisplayServer.window_get_size().y - safe_area.end.y) * ratio) + 12)

func centered(text: String, font_size: int, color: Color = GardenUI.INK, bold: bool = false) -> Label:
	var l := GardenUI.label(text, font_size, color, bold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if color == GardenUI.CREAM and font_size >= 20:
		l.add_theme_color_override("font_outline_color", Color("365c48"))
		l.add_theme_constant_override("outline_size", 5)
	return l

func add_header(title: String, back: Callable) -> void:
	var row := GardenUI.hbox(16)
	row.add_child(GardenUI.button("‹", back, GardenUI.CREAM, Vector2(76, 76)))
	var p := GardenUI.panel()
	p.add_child(centered(title, 28, GardenUI.TEAL, true))
	row.add_child(GardenUI.expand(p))
	page.add_child(row)

func show_home() -> void:
	tutorial_mode = false
	GardenFrontEnd.home(self)

func continue_game() -> void:
	if save.data.session.is_empty():
		start_level(int(save.data.profile.unlocked))
		return
	var number := int(save.data.session.level_number)
	var candidate := LevelCatalog.load_level(number)
	var errors: Array = save.validate_session(candidate)
	if not errors.is_empty():
		var body := open_modal("This table has changed", "Your completed progress is safe. Restart this level to use its updated recipe and tray layout.")
		body.add_child(GardenUI.button("Restart level %d" % number, func(): start_level(number)))
		body.add_child(GardenUI.button("Back", close_modal, GardenUI.CREAM))
		return
	tutorial_mode = false
	level = candidate
	model = BoardModel.new()
	model.undo_capacity = tuning.undo_capacity
	model.setup(level)
	save.restore_session(model)
	build_game()
	if model.is_won():
		show_win()

func start_level(number: int) -> void:
	tutorial_mode = false
	first_clear_reward = 0
	number = clampi(number, 1, TOTAL_LEVELS)
	level = LevelCatalog.load_level(number)
	if level.is_empty():
		show_toast("This level could not be loaded.")
		return
	model = BoardModel.new()
	model.undo_capacity = tuning.undo_capacity
	model.setup(level)
	commit_current_session()
	build_game()
	if number == 1:
		show_tutorial_hint()

func build_game() -> void:
	clear_page("game")
	if model.state.trays.size() > 6: page.add_theme_constant_override("separation", 12)
	selected = NONE
	hint_cell = NONE
	var top := GardenUI.hbox(14)
	top.add_child(GardenUI.button("Ⅱ", show_pause, GardenUI.TEAL, Vector2(76, 80)))
	var badge := GardenUI.panel()
	var badge_text := GardenUI.vbox(0)
	badge_text.add_child(centered("COOKING SCHOOL" if tutorial_mode else "GARDEN GRILL", 16, GardenUI.TEAL, true))
	badge_text.add_child(centered("Lesson %d / 3" % (tutorial_index + 1) if tutorial_mode else "Level %02d" % int(level.number), 30, GardenUI.INK, true))
	badge.add_child(badge_text)
	top.add_child(GardenUI.expand(badge))
	moves_label = centered("0 moves", 16, GardenUI.TEAL)
	badge_text.add_child(moves_label)
	wallet_button = GardenUI.button("Guide\nFREE" if tutorial_mode else "◉ %d\nChef Coins" % economy.balance(), request_hint if tutorial_mode else show_shop, GardenUI.GOLD, Vector2(140, 84))
	wallet_button.add_theme_font_size_override("font_size", 20)
	top.add_child(wallet_button)
	page.add_child(top)
	# Scenery remains visible above the worktop.
	scenery_gap = GardenUI.spacer(24 if model.state.trays.size() > 6 else (114 if tutorial_mode else 146))
	page.add_child(scenery_gap)
	var title_card := GardenUI.panel(Color("fff4d8"), 18)
	var title_box := GardenUI.vbox(4)
	title_card.add_child(title_box)
	var goal_row := GardenUI.hbox(8)
	goal_row.add_child(GardenUI.expand(centered(str(level.get("title", "Fresh beginnings")), 25, GardenUI.INK, true)))
	var queue_button := GardenUI.button("≡", show_queues, GardenUI.CREAM, Vector2(56, 42))
	queue_button.tooltip_text = "Inspect queued plates"
	goal_row.add_child(queue_button)
	title_box.add_child(goal_row)
	progress_label = centered("", 19, GardenUI.TEAL)
	title_box.add_child(progress_label)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 10
	progress_bar.show_percentage = false
	var track := GardenUI.box(Color("e1d7b8"), 5)
	track.content_margin_top = 0
	track.content_margin_bottom = 0
	var fill := GardenUI.box(GardenUI.TEAL, 5)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	progress_bar.add_theme_stylebox_override("background", track)
	progress_bar.add_theme_stylebox_override("fill", fill)
	title_box.add_child(progress_bar)
	page.add_child(title_card)
	orders = GardenUI.vbox(0)
	page.add_child(orders)
	var board_space := VBoxContainer.new()
	board_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_space.add_child(GardenUI.spacer(0, true))
	board = BoardView.new()
	board_space.add_child(board)
	board_space.add_child(GardenUI.spacer(0, true))
	page.add_child(board_space)
	var help_card := GardenUI.panel(Color("fff4d8"), 17)
	status_label = centered(str(level.get("lesson", "Move food to an empty slot. Match three of a kind.")), 21, Color("5b5946"))
	status_label.custom_minimum_size.y = 56
	help_card.add_child(status_label)
	page.add_child(help_card)
	var tools_row := GardenUI.hbox(14)
	undo_button = GardenUI.button("↶\nUndo", undo_move, GardenUI.TEAL, Vector2(0, 102))
	tools_row.add_child(GardenUI.expand(undo_button))
	tools_row.add_child(GardenUI.expand(GardenUI.button("✦\nGuide" if tutorial_mode else "✦\nHint · 10", request_hint, GardenUI.TEAL, Vector2(0, 102))))
	tools_row.add_child(GardenUI.expand(GardenUI.button("?\nHelp" if tutorial_mode else "+\nTray · 40", show_help if tutorial_mode else request_extra_tray, GardenUI.TEAL, Vector2(0, 102))))
	tools_row.add_child(GardenUI.expand(GardenUI.button("⟳\nRestart", confirm_restart, GardenUI.TEAL, Vector2(0, 102))))
	page.add_child(tools_row)
	page.add_child(centered("LEARN AT YOUR OWN PACE  ·  EVERY TOOL IS FREE HERE" if tutorial_mode else "UNDO & RESTART ARE FREE  ·  TOOLS ARE ALWAYS OPTIONAL", 14, Color("684629"), true))
	refresh_game()
	animate_page()

func refresh_game() -> void:
	if not is_instance_valid(board):
		return
	board.finish = equipped_finish()
	board.bind(model.state, selected, hint_cell, bool(settings().high_readability))
	moves_label.text = "%d moves" % int(model.state.moves)
	if is_instance_valid(wallet_button) and not tutorial_mode: wallet_button.text = "◉ %d\nChef Coins" % economy.balance()
	undo_button.disabled = model.history.is_empty() or model.is_won()
	var total_batches := int(model.state.initial_total) / 3
	progress_label.text = "%d / %d batches prepared  ·  No timer" % [model.state.batches, total_batches]
	progress_bar.max_value = maxi(1, total_batches)
	progress_bar.value = model.state.batches
	refresh_orders()

func refresh_orders() -> void:
	for child in orders.get_children():
		orders.remove_child(child)
		child.queue_free()
	if model.state.tickets.is_empty():
		return
	var ticket_index := 0
	while ticket_index < model.state.tickets.size() and model.state.tickets[ticket_index].served:
		ticket_index += 1
	if ticket_index == model.state.tickets.size():
		orders.add_child(centered("✓ Orders served! Clear the remaining food.", 22, GardenUI.CREAM, true))
		return
	var ticket: Dictionary = model.state.tickets[ticket_index]
	var panel := GardenUI.panel(Color("fff6de"), 18)
	var body := GardenUI.vbox(2)
	panel.add_child(body)
	var row := GardenUI.hbox(4)
	row.add_child(GardenUI.expand(GardenUI.label(str(ticket.get("name", "Garden order")), 19, GardenUI.TEAL, true)))
	var all_orders := GardenUI.button("Menu %d/%d" % [ticket_index + 1, model.state.tickets.size()], show_orders, GardenUI.GOLD, Vector2(130, 40))
	all_orders.add_theme_font_size_override("font_size", 16)
	row.add_child(all_orders)
	body.add_child(row)
	var foods := GardenUI.hbox(8)
	foods.alignment = BoxContainer.ALIGNMENT_CENTER
	for id in ticket.requirements:
		var pair := GardenUI.hbox(0)
		pair.add_child(FoodArt.icon(id, 47))
		pair.add_child(GardenUI.label("%d/%d" % [ticket.credits.get(id, 0), ticket.requirements[id]], 18, GardenUI.TEAL, true))
		foods.add_child(pair)
	body.add_child(foods)
	orders.add_child(panel)

func show_levels() -> void:
	clear_page("levels")
	add_header("Your garden journey", show_home)
	page.add_child(GardenUI.spacer(70))
	page.add_child(centered("Thirty little victories", 36, GardenUI.CREAM, true))
	page.add_child(centered("Replay a favorite. Discover something fresh.", 22, GardenUI.CREAM))
	page.add_child(GardenUI.spacer(40))
	var panel := GardenUI.panel()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var list := GardenUI.vbox(16)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	list.add_child(centered("CHAPTER 01 · GARDEN GRILL", 23, GardenUI.TEAL, true))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 16)
	list.add_child(grid)
	for n in range(1, TOTAL_LEVELS + 1):
		var completed: bool = save.data.profile.completed.has("garden_%03d" % n)
		var unlocked: bool = n <= int(save.data.profile.unlocked)
		var button := GardenUI.button("%02d%s" % [n, " ✓" if completed else ""], choose_level.bind(n), GardenUI.TEAL if completed else GardenUI.GOLD, Vector2(0, 96))
		button.add_theme_font_size_override("font_size", 23)
		button.disabled = not unlocked
		grid.add_child(GardenUI.expand(button))
	list.add_child(GardenUI.spacer(10))
	list.add_child(centered("Next season: Backyard Barbecue", 23, GardenUI.TEAL, true))
	list.add_child(centered("More chapters are on the menu.\nThis edition includes the complete 30-level Garden slice.", 20))
	page.add_child(panel)
	page.add_child(GardenUI.button("Continue", continue_game))

func choose_level(n: int) -> void:
	if not save.data.session.is_empty() and int(save.data.session.level_number) != n and save.data.session.state.outcome != "won":
		var body := open_modal("Start another table?", "Your current board will be replaced. Completed levels and coins are kept.")
		body.add_child(GardenUI.button("Play level %d" % n, start_level.bind(n)))
		body.add_child(GardenUI.button("Keep current board", close_modal, GardenUI.CREAM))
	else:
		start_level(n)

func show_album() -> void:
	clear_page("album")
	add_header("The recipe book", show_home)
	page.add_child(GardenUI.spacer(48))
	page.add_child(centered("Made with a match", 37, GardenUI.CREAM, true))
	page.add_child(centered("One triple prepares one batch.", 24, GardenUI.CREAM))
	page.add_child(GardenUI.spacer(36))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := GardenUI.vbox(20)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var recipes: Array = LevelCatalog.load_recipes()
	for recipe in recipes:
		var card := GardenUI.panel()
		var body := GardenUI.vbox(10)
		card.add_child(body)
		var unlocked: bool = int(save.data.profile.unlocked) >= int(recipe.unlock_level)
		body.add_child(GardenUI.label(str(recipe.name), 29, GardenUI.TEAL, true))
		body.add_child(GardenUI.label("On your menu" if unlocked else "Discover at level %d" % recipe.unlock_level, 19, Color("8a7960")))
		var foods := GardenUI.hbox(2)
		for id in recipe.requirements:
			var ingredient := GardenUI.vbox(0)
			ingredient.add_child(FoodArt.icon(id, 79))
			ingredient.add_child(centered("×%d" % recipe.requirements[id], 18))
			foods.add_child(ingredient)
		body.add_child(foods)
		list.add_child(card)
	page.add_child(scroll)

func show_settings() -> void:
	var body := open_modal("Make yourself at home", "Tune your table. Your settings save automatically.")
	for entry in [["sound", "Sound effects"], ["music", "Cafe music"], ["haptics", "Gentle vibration"], ["reduced_motion", "Reduced motion"], ["high_readability", "Food name labels"]]:
		var toggle := CheckButton.new()
		toggle.text = entry[1]
		toggle.custom_minimum_size.y = 62
		toggle.add_theme_font_override("font", GardenUI.BODY)
		toggle.add_theme_font_size_override("font_size", 25)
		toggle.add_theme_color_override("font_color", GardenUI.INK)
		toggle.add_theme_color_override("font_pressed_color", GardenUI.INK)
		toggle.add_theme_color_override("font_hover_pressed_color", GardenUI.INK)
		toggle.add_theme_color_override("font_hover_color", GardenUI.TEAL)
		toggle.button_pressed = bool(settings().get(entry[0], false))
		toggle.toggled.connect(func(value: bool):
			settings()[entry[0]] = value
			GardenUI.reduced_motion = bool(settings().reduced_motion)
			save.save_game()
			audio.configure(settings())
			if screen == "game": refresh_game())
		body.add_child(toggle)
	body.add_child(GardenUI.button("Cooking School", start_tutorial, GardenUI.GOLD))
	body.add_child(GardenUI.button("How to play", show_help, GardenUI.CREAM))
	body.add_child(GardenUI.button("Credits", show_credits, GardenUI.CREAM))
	body.add_child(GardenUI.button("Reset progress", confirm_reset, GardenUI.CREAM))
	body.add_child(GardenUI.button("Done", close_modal))

func show_help() -> void:
	var body := open_modal("A recipe for a lovely time", "1. Tap a food, then an empty slot on another tray. Or drag it there.\n\n2. Three identical foods on one tray clear automatically.\n\n3. A fully empty tray reveals its next row. The small plates show what comes next.\n\n4. Each triple makes one recipe batch. Future orders keep prepared batches. Clear every food to finish.\n\nUndo and restart are free. There is no timer.")
	body.add_child(GardenUI.button("Let's play", close_modal))

func show_credits() -> void:
	var body := open_modal("Garden Table", "An original food sorting puzzle for Akhilesh Mahto.\n\nBuilt with Godot 4.7.2. Original AI-generated food and restaurant art; original synthesized audio. Open Sans font by the Open Sans authors (Apache 2.0).\n\nThe reference images informed the art direction. No reference sprites are used.\n\nVersion 0.2 · Welcome to the Garden")
	body.add_child(GardenUI.button("Lovely", close_modal))

func confirm_reset() -> void:
	var body := open_modal("Start fresh?", "This deletes saved levels, coins and the current board from this device. This cannot be undone.")
	body.add_child(GardenUI.button("Keep my progress", close_modal))
	body.add_child(GardenUI.button("Delete local progress", func():
		save.reset_progress()
		economy.initialize()
		GardenUI.reduced_motion = bool(settings().reduced_motion)
		audio.configure(settings())
		model = null
		level = {}
		tutorial_mode = false
		show_home(), GardenUI.CORAL))

func show_pause() -> void:
	if screen != "game": return
	cancel_pointer()
	commit_current_session()
	var body := open_modal("A little breather", "Your campaign table is safe. This lesson restarts when you return." if tutorial_mode else "Your table is saved. Come back whenever you like.")
	body.add_child(GardenUI.button("Resume", close_modal))
	body.add_child(GardenUI.button("Settings", show_settings, GardenUI.CREAM))
	body.add_child(GardenUI.button("Restart level", confirm_restart, GardenUI.CREAM))
	body.add_child(GardenUI.button("Home", show_home, GardenUI.CREAM))

func confirm_restart() -> void:
	if not model: return
	var body := open_modal("Set the table again?", "Restart this level from its original layout. Your completed progress is kept.")
	body.add_child(GardenUI.button("Keep playing", close_modal))
	body.add_child(GardenUI.button("Restart level", restart_current, GardenUI.GOLD))

func show_orders() -> void:
	var body := open_modal("Today's menu", "Each match makes one batch. Future orders keep your prepared ingredients.")
	for ticket in model.state.tickets:
		var card := GardenUI.panel(Color("eee8d4"), 12)
		var content := GardenUI.vbox(8)
		content.add_child(GardenUI.label(str(ticket.get("name", ticket.id)) + ("  ✓ Served" if ticket.served else ""), 24, GardenUI.TEAL, true))
		var description := ""
		for id in ticket.requirements:
			description += "%s  %d / %d prepared\n" % [FoodArt.title(id), ticket.credits.get(id, 0), ticket.requirements[id]]
		content.add_child(GardenUI.label(description.strip_edges(), 21))
		card.add_child(content)
		body.add_child(card)
	body.add_child(GardenUI.button("Back to the table", close_modal))

func show_queues() -> void:
	var body := open_modal("Coming up next", "Rows reveal only when all three active slots are empty.")
	var has_queue := false
	for i in range(model.state.trays.size()):
		var tray: Dictionary = model.state.trays[i]
		if tray.queue.is_empty(): continue
		has_queue = true
		body.add_child(GardenUI.label("Tray %d · %d row%s waiting" % [i + 1, tray.queue.size(), "s" if tray.queue.size() > 1 else ""], 23, GardenUI.TEAL, true))
		for row in tray.queue:
			var icons := GardenUI.hbox(12)
			for food in row:
				if food != null: icons.add_child(FoodArt.icon(str(food), 70))
				else: icons.add_child(centered("—", 25))
			body.add_child(icons)
	if not has_queue:
		body.add_child(centered("All your food is already on the table.", 25))
	body.add_child(GardenUI.button("Got it", close_modal))

func show_win() -> void:
	if tutorial_mode:
		show_lesson_complete()
		return
	cancel_pointer()
	audio.play_cue("win")
	var last_level: bool = int(level.number) == TOTAL_LEVELS
	var body := open_modal("A garden well served!" if last_level else "Beautifully served!", "All trays clear. All good things together.\nLevel %d finished in %d moves." % [level.number, model.state.moves])
	var icons := GardenUI.hbox(0)
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	for id in FoodArt.IDS.slice(0, 3): icons.add_child(FoodArt.icon(id, 110))
	body.add_child(icons)
	body.add_child(centered("+%d Chef Coins · First clear!" % first_clear_reward if first_clear_reward > 0 else "A lovely replay · reward already collected", 24, GardenUI.TEAL, true))
	body.add_child(centered("Wallet: %d Chef Coins" % economy.balance(), 22, GardenUI.TEAL))
	if first_clear_reward > 0: GardenMotion.coin_burst(self, size * Vector2(0.5, 0.4), first_clear_reward, settings().reduced_motion)
	first_clear_reward = 0
	if last_level:
		body.add_child(centered("The Garden Grill collection is complete.\nBackyard Barbecue is a future chapter.", 23))
		body.add_child(GardenUI.button("Back to the garden", show_home))
	else:
		body.add_child(GardenUI.button("Next table  →", func(): start_level(int(level.number) + 1)))
	body.add_child(GardenUI.button("Replay this level", restart_current, GardenUI.CREAM))
	body.add_child(GardenUI.button("Home", show_home, GardenUI.CREAM))

func show_recovery() -> void:
	var body := open_modal("Let's make some room", "There are no legal moves on this board. Undo a move or restart for a fresh approach.")
	var undo := GardenUI.button("Undo last move", func(): close_modal(); undo_move())
	undo.disabled = model.history.is_empty()
	body.add_child(undo)
	body.add_child(GardenUI.button("Restart level", restart_current, GardenUI.GOLD))

func open_modal(title: String, description: String) -> VBoxContainer:
	close_modal()
	cancel_pointer()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.12, 0.1, 0.67)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(center)
	var panel := GardenUI.panel(GardenUI.CREAM, 28)
	panel.custom_minimum_size.x = minf(stage.size.x - 60, 630)
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(panel.custom_minimum_size.x - 44, 0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var body := GardenUI.vbox(17)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(centered(title, 36, GardenUI.TEAL, true))
	body.add_child(centered(description, 24, GardenUI.INK))
	scroll.add_child(body)
	# Cap tall menus to the safe viewport and allow their contents to scroll.
	var owner_ref : WeakRef = weakref(self)
	var scroll_ref : WeakRef = weakref(scroll)
	var body_ref : WeakRef = weakref(body)
	var panel_ref : WeakRef = weakref(panel)
	get_tree().process_frame.connect(func():
		var controller: Variant = owner_ref.get_ref()
		var active_scroll: ScrollContainer = scroll_ref.get_ref()
		var active_body: VBoxContainer = body_ref.get_ref()
		var active_panel: PanelContainer = panel_ref.get_ref()
		if is_instance_valid(controller) and is_instance_valid(active_scroll) and is_instance_valid(active_body) and is_instance_valid(active_panel):
			active_scroll.custom_minimum_size.y = minf(active_body.get_combined_minimum_size().y, controller.size.y - controller.safe_top() - controller.safe_bottom() - 130)
			GardenMotion.enter(active_panel, controller.settings().reduced_motion), CONNECT_ONE_SHOT)
	audio.play_cue("click")
	return body

func close_modal() -> void:
	if is_instance_valid(modal):
		remove_child(modal)
		modal.queue_free()
	modal = null
	if model and screen == "game" and not busy:
		resume_terminal.call_deferred(generation)

func resume_terminal(serial: int) -> void:
	if serial != generation or screen != "game" or is_instance_valid(modal) or busy or not application_active:
		return
	if model.is_won(): show_win()
	elif model.legal_moves().is_empty(): show_recovery()

func show_toast(message: String) -> void:
	if is_instance_valid(toast_node): toast_node.queue_free()
	toast_node = GardenUI.panel(GardenUI.TEAL, 16)
	toast_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := centered(message, 22, GardenUI.CREAM)
	text.custom_minimum_size = Vector2(minf(size.x - 100, 600), 56)
	toast_node.add_child(text)
	add_child(toast_node)
	toast_node.position = Vector2((size.x - text.custom_minimum_size.x - 44) / 2, size.y - 260)
	var toast_ref : WeakRef = weakref(toast_node)
	get_tree().create_timer(3.5).timeout.connect(func():
		var current: Node = toast_ref.get_ref()
		if is_instance_valid(current): current.queue_free())

func show_tutorial_hint() -> void:
	if not level.get("solution", []).is_empty():
		var command: Array = level.solution[0]
		selected = Vector2i(command[0], command[1])
		hint_cell = Vector2i(command[2], command[3])
		refresh_game()
		status_label.text = "Tap the highlighted empty space to make your first triple. You can drag the tomato there, too."

func undo_move() -> void:
	if busy or not model or model.is_won(): return
	cancel_pointer()
	if model.undo():
		commit_current_session()
		audio.play_cue("move")
		refresh_game()
		status_label.text = "One move back. Reveals and recipe progress restored."
		if tutorial_mode: update_tutorial_guidance()
	else: show_toast("You're at the beginning of this table.")

func request_hint() -> void:
	if busy or not model or model.is_won(): return
	cancel_pointer()
	if tutorial_mode:
		update_tutorial_guidance()
		return
	var body := open_modal("A thoughtful hint", "Highlight a verified step for 10 Chef Coins. If no solution is found, no coins are spent. Rechecking the same board in this attempt is free.")
	body.add_child(centered("Your balance: %d Chef Coins" % economy.balance(), 23, GardenUI.TEAL, true))
	body.add_child(GardenUI.button("Show a hint · ◉ 10", purchase_hint, GardenUI.GOLD))
	body.add_child(GardenUI.button("Keep thinking", close_modal, GardenUI.CREAM))

func _input(event: InputEvent) -> void:
	# Once a board gesture owns a pointer, GUI controls cannot steal its release
	# or accept another finger. Initial UI presses still use Godot's GUI routing.
	if pointer == -2:
		return
	if event is InputEventScreenTouch:
		if event.index == pointer and not event.pressed:
			if event.canceled: cancel_pointer()
			else: pointer_up(event.position, event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == pointer: pointer_motion(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if pointer == -1 and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			pointer_up(event.position, -1)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if pointer == -1: pointer_motion(event.position)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_instance_valid(modal): close_modal()
		elif screen == "game": show_pause()
		else: show_home()
		get_viewport().set_input_as_handled()
		return
	if screen != "game" or not is_instance_valid(board) or is_instance_valid(modal) or busy or model.is_won(): return
	if event is InputEventScreenTouch:
		if event.pressed:
			pointer_down(event.position, event.index)
		elif event.index == pointer:
			if event.canceled: cancel_pointer()
			else: pointer_up(event.position, event.index)
	elif event is InputEventScreenDrag and event.index == pointer:
		pointer_motion(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: pointer_down(event.position, -1)
		else: pointer_up(event.position, -1)
	elif event is InputEventMouseMotion and pointer == -1:
		pointer_motion(event.position)

func pointer_down(point: Vector2, id: int) -> void:
	if pointer != -2: return
	var cell := board.hit_test(point)
	if cell == NONE: return
	pointer = id
	press_position = point
	press_cell = cell
	dragging = false

func pointer_motion(point: Vector2) -> void:
	if press_cell == NONE: return
	var food: Variant = model.state.trays[press_cell.x].front[press_cell.y]
	if food == null: return
	if not dragging and point.distance_to(press_position) >= tuning.drag_threshold:
		dragging = true
		selected = press_cell
		hint_cell = NONE
		audio.play_cue("select")
		refresh_game()
		ghost = FoodArt.icon(str(food), 132)
		ghost.size = Vector2(132, 132)
		ghost.z_index = 100
		add_child(ghost)
	if dragging and is_instance_valid(ghost): ghost.position = point - ghost.size * 0.5 + Vector2(0, -22)

func pointer_up(point: Vector2, id: int) -> void:
	if pointer != id or press_cell == NONE: return
	var target := board.hit_test(point)
	var source := press_cell
	var was_drag := dragging
	clear_press()
	if was_drag:
		if target != NONE and target != source: submit_move(source, target)
		else: cancel_pointer(); refresh_game()
		return
	if target != source: return
	var food: Variant = model.state.trays[source.x].front[source.y]
	if selected != NONE:
		if source == selected:
			selected = NONE
			hint_cell = NONE
		elif food == null:
			submit_move(selected, source)
			return
		else:
			selected = source
			hint_cell = NONE
	else:
		if food != null: selected = source
	if selected != NONE:
		audio.play_cue("select")
		status_label.text = "%s selected · choose an empty slot on another tray." % FoodArt.title(str(model.state.trays[selected.x].front[selected.y]))
	refresh_game()

func clear_press() -> void:
	pointer = -2
	press_cell = NONE
	dragging = false
	if is_instance_valid(ghost): ghost.queue_free()
	ghost = null

func cancel_pointer() -> void:
	clear_press()
	selected = NONE
	hint_cell = NONE
	if is_instance_valid(board) and model:
		board.bind(model.state, NONE, NONE, bool(settings().high_readability))

func submit_move(source: Vector2i, target: Vector2i) -> void:
	if busy or is_instance_valid(modal): return
	var from_pos := board.center_of(source)
	var to_pos := board.center_of(target)
	var food := str(model.state.trays[source.x].front[source.y])
	if not model.apply_move(source.x, source.y, target.x, target.y):
		audio.play_cue("invalid")
		show_toast("Choose an empty space on a different tray.")
		selected = NONE
		hint_cell = NONE
		refresh_game()
		return
	busy = true
	var earned_before: int = economy.balance()
	selected = NONE
	hint_cell = NONE
	# Persist the final stable board before its presentation begins.
	commit_current_session()
	first_clear_reward = economy.balance() - earned_before
	audio.play_cue("move")
	if bool(settings().haptics) and OS.get_name() == "Android": Input.vibrate_handheld(20)
	var serial := generation
	if not bool(settings().reduced_motion):
		var flight := FoodArt.icon(food, 115)
		flight.size = Vector2(115, 115)
		flight.position = from_pos - flight.size * 0.5
		flight.set_meta("page_effect", true)
		add_child(flight)
		var start := flight.position
		var destination := to_pos - flight.size * 0.5
		var flight_ref : WeakRef = weakref(flight)
		var tween := flight.create_tween()
		tween.tween_method(func(amount: float):
			var current: TextureRect = flight_ref.get_ref()
			if current: current.position = start.lerp(destination, amount) - Vector2(0, sin(amount * PI) * 22), 0.0, 1.0, tuning.snap_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tween.finished
		flight.queue_free()
	if generation != serial: return
	refresh_game()
	if tutorial_mode and not model.is_won(): update_tutorial_guidance()
	var matched := false
	for event in model.last_events:
		if event.type == "cleared":
			matched = true
			if application_active: audio.play_cue("match")
			var tray_i := int(event.tray)
			pop_text("%s +1 batch" % FoodArt.title(str(event.food)), board.center_of(Vector2i(tray_i, 1)))
			GardenMotion.match_burst(self, board.center_of(Vector2i(tray_i, 1)), settings().reduced_motion)
		elif event.type == "revealed":
			if application_active: audio.play_cue("reveal")
			GardenMotion.enter(board.trays[int(event.tray)], settings().reduced_motion)
		elif event.type == "served" and application_active: audio.play_cue("serve")
	if not tutorial_mode: status_label.text = "Lovely! One triple makes one batch." if matched else "A little space makes all the difference."
	if not bool(settings().reduced_motion): await get_tree().create_timer(tuning.match_seconds).timeout
	if generation != serial: return
	busy = false
	resume_terminal(serial)

func pop_text(message: String, position_on_board: Vector2) -> void:
	var label := GardenUI.label(message, 23, GardenUI.CREAM, true)
	label.add_theme_color_override("font_outline_color", GardenUI.TEAL)
	label.add_theme_constant_override("outline_size", 7)
	label.position = position_on_board - Vector2(125, 22)
	label.set_meta("page_effect", true)
	add_child(label)
	var tween := label.create_tween().set_parallel(true)
	if not bool(settings().reduced_motion): tween.tween_property(label, "position:y", label.position.y - 55, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.2)
	tween.finished.connect(label.queue_free)

func commit_current_session() -> void:
	if tutorial_mode: return
	save.commit_session(model, level)
	if not save.last_error.is_empty():
		show_toast("Your move works, but progress could not be saved. Check available storage.")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if save and model and screen == "game": commit_current_session()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		application_active = false
		cancel_pointer()
		if save and model and screen == "game":
			commit_current_session()
			if not is_instance_valid(modal): show_pause()
		if audio: audio.set_music_active(false)
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		application_active = true
		if audio: audio.set_music_active(true)
		if model and screen == "game": resume_terminal.call_deferred(generation)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(modal): close_modal()
		elif screen == "game": show_pause()
		else: show_home()
