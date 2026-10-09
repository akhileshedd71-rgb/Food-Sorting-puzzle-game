extends SceneTree
## Campaign content regression: schemas, inventory, diversity, saved replay proofs.

const Catalog = preload("res://core/level_catalog.gd")
const Model = preload("res://core/board_model.gd")
const Validator = preload("res://core/level_validator.gd")
const Foods = preload("res://core/food_catalog.gd")
const EXPECTED_FOOD_UNLOCKS := {
	"tomato": 1, "corn_cob": 2, "button_mushroom": 3,
	"bell_pepper_ring": 11, "zucchini_round": 21, "eggplant_slice": 25,
	"chicken_drumstick": 51, "steak": 56, "prawn": 61,
	"fish_fillet": 66, "sausage_spiral": 71, "halloumi_slice": 76,
	"fried_egg": 101, "pancake_stack": 106, "waffle_square": 111,
	"toast_slice": 116, "hash_brown": 121, "croissant": 126,
}
const EXPECTED_RECIPE_UNLOCKS := {
	"garden_sampler": 15, "charred_duo": 16, "ratatouille_grill": 26, "garden_banquet": 28,
	"backyard_combo": 55, "surf_and_turf": 65, "seafood_grill": 70, "smoky_platter": 80,
	"sweet_morning": 115, "classic_breakfast": 125, "bakery_basket": 130, "brunch_board": 135,
}
const RHYTHMS := ["introduction", "normal", "variation", "challenge", "relief"]
var checks: int = 0
var failures: Array[String] = []
var layout_signatures: Dictionary = {}
var first_food_appearances: Dictionary = {}
var first_recipe_appearances: Dictionary = {}
var recipes_by_id: Dictionary = {}


func _initialize() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/replay_report.json"))
	check(report.get("passed", false), "Published replay report passed")
	check(report.get("errors", []).is_empty(), "Published replay report has no errors")
	check(Catalog.LEVEL_COUNT == 150, "Exactly 150 authored campaign levels")
	check(report.get("levels", []).size() == Catalog.LEVEL_COUNT, "One replay certificate for every level")
	test_catalog()
	test_legacy_preservation(report)
	var certificates: Array = report.get("levels", [])
	for number in range(1, Catalog.LEVEL_COUNT + 1):
		if number <= certificates.size():
			test_level(number, certificates[number - 1])
	for food_id in EXPECTED_FOOD_UNLOCKS:
		check(first_food_appearances.get(food_id, 0) == EXPECTED_FOOD_UNLOCKS[food_id], "%s first appears at its authored unlock" % food_id)
	for recipe_id in EXPECTED_RECIPE_UNLOCKS:
		check(first_recipe_appearances.get(recipe_id, 0) == EXPECTED_RECIPE_UNLOCKS[recipe_id], "%s first appears at its recipe unlock" % recipe_id)
	check(layout_signatures.size() == Catalog.LEVEL_COUNT, "Every campaign board has a globally unique structure")
	check(report.levels[0].moves == 1, "First level teaches a single guided move")
	check(report.levels[4].temporary_placement_witness, "Level 5 stores food before its first clear")
	check(report.levels[8].automatic_cascade_witness, "Level 9 has an automatic hidden-row cascade")
	check(report.levels[11].temporary_placement_witness, "Level 12 prepares mixed storage")
	check(report.levels[17].orders_completed_before_board_clear, "Level 18 teaches the remaining-board objective")
	check(report.levels[18].simultaneous_reveal_and_clear, "Level 19 reveals and clears in one transaction")
	check(report.levels[22].temporary_placement_witness, "Level 23 prepares space before its first clear")
	check(report.levels[26].retrieval_witness, "Level 27 later retrieves temporarily placed food")
	for failure in failures:
		push_error(failure)
	print("LEVEL TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func test_catalog() -> void:
	var chapters: Array = Catalog.chapters()
	check(chapters.size() == 3, "Three campaign chapters")
	var expected_slugs := ["garden", "barbecue", "breakfast"]
	var expected_names := ["Garden Grill", "Backyard Barbecue", "Breakfast Griddle"]
	for index in range(3):
		var chapter: Dictionary = Catalog.chapter(index + 1)
		check(chapter.get("id") == index + 1, "Chapter %d identity" % (index + 1))
		check(chapter.get("slug") == expected_slugs[index], "Chapter %d stable slug" % (index + 1))
		check(chapter.get("name") == expected_names[index], "Chapter %d theme" % (index + 1))
		check(chapter.get("start") == index * 50 + 1 and chapter.get("end") == (index + 1) * 50, "Chapter %d has fifty levels" % (index + 1))
		var expected_foods: Array = EXPECTED_FOOD_UNLOCKS.keys().slice(index * 6, (index + 1) * 6)
		check(chapter.get("foods", []) == expected_foods, "Chapter %d food palette in atlas order" % (index + 1))
		check(not str(chapter.get("subtitle", "")).is_empty(), "Chapter %d has a subtitle" % (index + 1))
		for number in range(index * 50 + 1, (index + 1) * 50 + 1):
			var expected_id := "%s_%03d" % [expected_slugs[index], number]
			check(Catalog.level_id(number) == expected_id, "Level %d stable catalog ID" % number)
			check(Catalog.level_path(number) == "res://data/levels/%s.json" % expected_id, "Level %d mapped file path" % number)
			check(Catalog.chapter_for_level(number) == chapter, "Level %d maps to its chapter" % number)
		chapter["name"] = "test_mutation"
		chapter.foods[0] = "test_mutation"
		check(Catalog.chapter(index + 1).name == expected_names[index], "Chapter lookup returns independent dictionaries")
		check(Catalog.chapter(index + 1).foods == expected_foods, "Chapter lookup preserves independent food palettes")
	for invalid in [-1, 0, Catalog.LEVEL_COUNT + 1]:
		check(Catalog.level_id(invalid).is_empty(), "Invalid campaign number has no ID")
		check(Catalog.level_path(invalid).is_empty(), "Invalid campaign number has no file path")
		check(Catalog.chapter_for_level(invalid).is_empty(), "Invalid campaign number has no chapter")
	check(Foods.ids().size() == EXPECTED_FOOD_UNLOCKS.size(), "Exactly eighteen food identities")
	for food_id in EXPECTED_FOOD_UNLOCKS:
		check(Foods.has_food(food_id), food_id + " is registered")
		check(Foods.unlock_level(food_id) == EXPECTED_FOOD_UNLOCKS[food_id], food_id + " unlock metadata")
	var recipes: Array = Catalog.load_recipes()
	check(recipes.size() == EXPECTED_RECIPE_UNLOCKS.size(), "Exactly twelve recipe bundles")
	for recipe in recipes:
		var recipe_id: String = recipe.get("id", "")
		check(EXPECTED_RECIPE_UNLOCKS.has(recipe_id), recipe_id + " is an expected recipe identity")
		check(not recipes_by_id.has(recipe_id), recipe_id + " is not a duplicate recipe")
		check(recipe.get("unlock_level") == EXPECTED_RECIPE_UNLOCKS.get(recipe_id), recipe_id + " authored unlock")
		check(recipe.get("chapter") == Catalog.chapter_for_level(int(recipe.get("unlock_level", 0))).get("id"), recipe_id + " belongs to its unlock chapter")
		recipes_by_id[recipe_id] = recipe


func test_legacy_preservation(report: Dictionary) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/legacy_manifest.json"))
	var file_hashes: Dictionary = manifest.get("files", {})
	var certificate_hashes: Dictionary = manifest.get("certificates", {})
	check(file_hashes.size() == 30, "Legacy manifest freezes thirty complete authored files")
	check(certificate_hashes.size() == 30, "Legacy manifest freezes thirty complete certificates")
	var legacy_path: String = "res://" + str(manifest.get("report_file", ""))
	check(FileAccess.get_sha256(legacy_path) == manifest.get("report_sha256"), "Original replay report bytes remain frozen")
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(legacy_path))
	check(legacy.get("levels", []).size() == 30, "Original report contains thirty certificates")
	for number in range(1, 31):
		var level_id := "garden_%03d" % number
		var relative_path := "data/levels/%s.json" % level_id
		check(FileAccess.get_sha256("res://" + relative_path) == file_hashes.get(relative_path), level_id + " authored file unchanged byte-for-byte")
		if report.get("levels", []).size() < number or legacy.get("levels", []).size() < number:
			continue
		var certificate: Dictionary = report.levels[number - 1]
		check(Model.canonical_json(certificate).sha256_text() == certificate_hashes.get(level_id), level_id + " complete legacy certificate SHA-256 unchanged")
		check(Model.canonical_json(certificate) == Model.canonical_json(legacy.levels[number - 1]), level_id + " appended report preserves original certificate")


func test_level(number: int, certificate: Dictionary) -> void:
	var label := "Level %02d" % number
	var path := Catalog.level_path(number)
	var authored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(Validator.validate(authored).is_empty(), label + " validates")
	check(authored.get("number") == number, label + " authored number matches catalog")
	check(authored.get("level_id") == Catalog.level_id(number), label + " authored identity matches catalog")
	check(authored.get("chapter") == Catalog.chapter_for_level(number).id, label + " authored chapter matches catalog")
	var expected_hash: String = authored.get("content_hash", "")
	var hash_source := authored.duplicate(true)
	hash_source.erase("content_hash")
	check(Model.canonical_json(hash_source).sha256_text() == expected_hash, label + " content SHA-256")
	check(certificate.get("content_hash", "") == expected_hash, label + " certificate matches content")
	check(certificate.get("status", "") == "PASS", label + " replay certificate passed")
	check(certificate.get("level_id") == Catalog.level_id(number), label + " certificate identity")
	check(certificate.get("moves") == authored.solution.size(), label + " certificate records every move")
	check(certificate.get("state_hashes", []).size() == authored.solution.size() + 1, label + " certificate records every state")
	if certificate.get("state_hashes", []).size() != authored.solution.size() + 1:
		return
	var level: Dictionary = Catalog.load_level(number)
	check(not level.is_empty(), label + " loads through Resources")
	if level.is_empty():
		return
	check(level.trays.size() == int(level.authoring.expected_trays), label + " exact authored tray count")
	check(level.trays.size() <= 6, label + " fits two columns with at most six trays")
	var free_slots: int = 0
	var deepest_row: int = 1
	var inventory: Dictionary = {}
	for tray in level.trays:
		free_slots += tray.front.count(null)
		deepest_row = maxi(deepest_row, 1 + tray.queue.size())
		for row in [tray.front] + tray.queue:
			for food in row:
				if food != null:
					inventory[food] = int(inventory.get(food, 0)) + 1
	check(free_slots == int(level.authoring.expected_free_slots), label + " exact initial free slots")
	check(deepest_row == int(level.authoring.expected_max_rows), label + " exact queue depth")
	check(inventory.size() == int(level.authoring.expected_foods), label + " exact food variety")
	check(inventory.size() <= 6, label + " curated palette uses at most six foods")
	for food_id in inventory:
		if not first_food_appearances.has(food_id):
			first_food_appearances[food_id] = number
		check(number >= Foods.unlock_level(food_id), label + " uses food only after its unlock: " + str(food_id))
	# Keep the factorial canonicalization bounded even when content is malformed.
	if inventory.size() <= 6:
		var signature := canonical_layout(level)
		check(not layout_signatures.has(signature), label + " is not a food/slot/tray permutation of level %s" % str(layout_signatures.get(signature, "none")))
		layout_signatures[signature] = number
	test_recipes(authored, inventory, label)
	if number > 30:
		test_expansion_pacing(level, deepest_row, label)
	var model = Model.new()
	model.setup(level)
	check(model.state_hash() == certificate.state_hashes[0], label + " initial replay checksum")
	for index in range(level.solution.size()):
		var command: Array = level.solution[index]
		var before_invalid: String = model.state_hash()
		check(not model.apply_move(command[0], command[1], command[0], command[1]), label + " rejects same-tray command")
		check(model.state_hash() == before_invalid, label + " rejected command leaves state unchanged")
		var legal: bool = model.apply_move(command[0], command[1], command[2], command[3])
		check(legal, label + " recorded command %d is legal" % (index + 1))
		if not legal:
			return
		check(model.state_hash() == certificate.state_hashes[index + 1], label + " command %d replay checksum" % (index + 1))
	check(model.is_won(), label + " replay wins without tools")
	check(model.remaining_tokens() == 0, label + " board including queues cleared")
	check(int(model.state.batches) * 3 == int(model.state.initial_total), label + " token conservation")
	check(model.state_hash() == certificate.get("final_state_hash"), label + " final replay checksum")
	check(model.state.initial_total == certificate.get("initial_tokens"), label + " certificate initial token count")
	check(model.state.batches == certificate.get("cleared_batches"), label + " certificate cleared batch count")
	check(model.remaining_tokens() == certificate.get("remaining_tokens"), label + " certificate remaining token count")
	for ticket in model.state.tickets:
		check(ticket.served, label + " all finite tickets served")
	# Undo must restore every intermediate queue, ticket and counter exactly.
	for index in range(level.solution.size() - 1, -1, -1):
		check(model.undo(), label + " undo recorded transaction")
		check(model.state_hash() == certificate.state_hashes[index], label + " undo restores complete state")
	# Independent level loads and model instances must never share mutable state.
	var other: Dictionary = Catalog.load_level(number)
	level.trays[0].front[0] = "test_mutation"
	check(other.trays[0].front[0] != "test_mutation", label + " Resource conversion returns independent copies")
	check(model.state.trays[0].front[0] != "test_mutation", label + " model owns its copied state")


func test_recipes(authored: Dictionary, inventory: Dictionary, label: String) -> void:
	var demand: Dictionary = {}
	for ticket in authored.get("tickets", []):
		var recipe_id: String = ticket.get("recipe_id", "")
		check(recipes_by_id.has(recipe_id), label + " ticket references a registered recipe")
		if not recipes_by_id.has(recipe_id):
			continue
		var recipe: Dictionary = recipes_by_id[recipe_id]
		check(Model.canonical_json(ticket.requirements) == Model.canonical_json(recipe.requirements), label + " ticket uses exact recipe batch requirements")
		check(int(authored.number) >= int(recipe.unlock_level), label + " recipe appears only after unlock")
		if not first_recipe_appearances.has(recipe_id):
			first_recipe_appearances[recipe_id] = int(authored.number)
		for food_id in ticket.requirements:
			demand[food_id] = int(demand.get(food_id, 0)) + int(ticket.requirements[food_id])
	for food_id in demand:
		check(int(inventory.get(food_id, 0)) >= int(demand[food_id]) * 3, label + " total inventory covers every requested batch of " + str(food_id))


func test_expansion_pacing(level: Dictionary, deepest_row: int, label: String) -> void:
	var rhythm: String = RHYTHMS[(int(level.number) - 1) % RHYTHMS.size()]
	check(level.authoring.get("rhythm") == rhythm, label + " follows the five-level content rhythm")
	check(level.trays.size() >= 4, label + " uses four to six trays")
	check(deepest_row <= 4, label + " queue depth stays within four rows")
	check(level.solution.size() <= 40, label + " replay fits the forty-transaction undo window")
	check(level.authoring.get("human_playtest_status") == "pending", label + " does not claim unperformed human playtesting")
	check(bool(level.authoring.get("challenge", false)) == (rhythm == "challenge"), label + " challenge flag matches rhythm")
	check(bool(level.authoring.get("relief", false)) == (rhythm == "relief"), label + " relief flag matches rhythm")
	if rhythm == "introduction" or rhythm == "relief":
		check(deepest_row <= 2, label + " introductory or relief queues remain shallow")
	elif rhythm == "normal":
		check(deepest_row >= 2 and deepest_row <= 3, label + " normal queue depth")
	else:
		check(deepest_row >= 2, label + " variation or challenge includes queued rows")
	if rhythm == "relief":
		var introduces_recipe: bool = EXPECTED_RECIPE_UNLOCKS.values().has(int(level.number))
		var max_moves: int = 18 if introduces_recipe else 12
		check(level.authoring.get("max_solution_moves") == max_moves, label + " relief move budget is explicit")
		check(level.solution.size() <= max_moves, label + " relief witness fits its move budget")


func canonical_layout(level: Dictionary) -> String:
	# Food names, slot order and tray order cannot disguise a repeated puzzle.
	# Hidden row order remains significant. Recipes are deliberately excluded:
	# merely changing an order does not make a new board under these rules.
	var food_ids: Array = []
	for tray in level.trays:
		for row in [tray.front] + tray.queue:
			for food in row:
				if food != null and not food_ids.has(food):
					food_ids.append(food)
	var best: String = ""
	for ordering in permutations(food_ids):
		var mapping: Dictionary = {}
		for index in range(ordering.size()):
			mapping[ordering[index]] = str(index + 1)
		var trays: Array[String] = []
		for tray in level.trays:
			var rows: Array[String] = []
			for row in [tray.front] + tray.queue:
				var slots: Array[String] = []
				for food in row:
					slots.append("0" if food == null else mapping[food])
				slots.sort()
				rows.append("".join(slots))
			trays.append("/".join(rows))
		trays.sort()
		var encoded := "|".join(trays)
		if best.is_empty() or encoded < best:
			best = encoded
	return best


func permutations(values: Array) -> Array:
	if values.is_empty():
		return [[]]
	var result: Array = []
	for index in range(values.size()):
		var remaining: Array = values.duplicate()
		var first: Variant = remaining.pop_at(index)
		for tail in permutations(remaining):
			result.append([first] + tail)
	return result


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
