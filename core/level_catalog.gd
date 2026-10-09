class_name LevelCatalog
extends RefCounted
## Loads frozen, certified authoring data through typed Resource definitions.
## Every call returns an independent dictionary; mutable runtime data is not cached.

const LEVEL_COUNT: int = 150
const RECIPE_IDS: Array[String] = [
	"garden_sampler", "charred_duo", "ratatouille_grill", "garden_banquet",
	"backyard_combo", "surf_and_turf", "seafood_grill", "smoky_platter",
	"sweet_morning", "classic_breakfast", "bakery_basket", "brunch_board"
]
## Chapter metadata is deliberately separate from level interchange data:
## extending this menu must never change a saved level's content checksum.
const CHAPTERS: Array[Dictionary] = [
	{
		"id": 1, "slug": "garden", "name": "Garden Grill", "start": 1, "end": 50,
		"subtitle": "Fresh vegetables and a little room to grow.",
		"foods": ["tomato", "corn_cob", "button_mushroom", "bell_pepper_ring", "zucchini_round", "eggplant_slice"]
	},
	{
		"id": 2, "slug": "barbecue", "name": "Backyard Barbecue", "start": 51, "end": 100,
		"subtitle": "Gather around the grill for a generous feast.",
		"foods": ["chicken_drumstick", "steak", "prawn", "fish_fillet", "sausage_spiral", "halloumi_slice"]
	},
	{
		"id": 3, "slug": "breakfast", "name": "Breakfast Griddle", "start": 101, "end": 150,
		"subtitle": "A warm griddle and a bright start to the day.",
		"foods": ["fried_egg", "pancake_stack", "waffle_square", "toast_slice", "hash_brown", "croissant"]
	}
]
const Definition = preload("res://core/resources/level_definition.gd")
const Validator = preload("res://core/level_validator.gd")


static func load_level(number: int) -> Dictionary:
	if number < 1 or number > LEVEL_COUNT:
		push_error("Level number outside the authored campaign: %d" % number)
		return {}
	var path := level_path(number)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Cannot read authored level: " + path)
		return {}
	var errors: Array = Validator.validate(parsed)
	if not errors.is_empty():
		push_error("Invalid level %d: %s" % [number, str(errors)])
		return {}
	var definition = Definition.from_dictionary(parsed)
	return definition.to_dictionary()


static func level_id(number: int) -> String:
	if number < 1 or number > LEVEL_COUNT:
		return ""
	return "%s_%03d" % [CHAPTERS[(number - 1) / 50].slug, number]


static func level_path(number: int) -> String:
	var id: String = level_id(number)
	return "" if id.is_empty() else "res://data/levels/%s.json" % id


static func chapters() -> Array:
	return CHAPTERS.duplicate(true)


static func chapter(id: int) -> Dictionary:
	if id < 1 or id > CHAPTERS.size():
		return {}
	return CHAPTERS[id - 1].duplicate(true)


static func chapter_for_level(number: int) -> Dictionary:
	if number < 1 or number > LEVEL_COUNT:
		return {}
	return chapter((number - 1) / 50 + 1)


static func load_all() -> Array:
	var levels: Array = []
	for number in range(1, LEVEL_COUNT + 1):
		levels.append(load_level(number))
	return levels


static func load_recipes() -> Array:
	var recipes: Array = []
	for recipe_id in RECIPE_IDS:
		var path := "res://data/recipes/%s.json" % recipe_id
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			recipes.append(parsed.duplicate(true))
	return recipes
