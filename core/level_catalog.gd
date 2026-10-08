class_name LevelCatalog
extends RefCounted
## Loads frozen, certified authoring data through typed Resource definitions.
## Every call returns an independent dictionary; mutable runtime data is not cached.

const LEVEL_COUNT: int = 30
const RECIPE_IDS: Array[String] = [
	"garden_sampler", "charred_duo", "ratatouille_grill", "garden_banquet"
]
const Definition = preload("res://core/resources/level_definition.gd")
const Validator = preload("res://core/level_validator.gd")


static func load_level(number: int) -> Dictionary:
	if number < 1 or number > LEVEL_COUNT:
		push_error("Level number outside the authored campaign: %d" % number)
		return {}
	var path := "res://data/levels/garden_%03d.json" % number
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
