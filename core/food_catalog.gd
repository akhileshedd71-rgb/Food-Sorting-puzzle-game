class_name FoodCatalog
extends RefCounted
## Data registry shared by validation and presentation. New food needs only a
## FoodDefinition Resource, its art, and an entry in data/foods/catalog.json.

const MANIFEST_PATH := "res://data/foods/catalog.json"
static var _loaded: bool = false
static var _definitions: Dictionary = {}
static var _display_names: Dictionary = {}
static var _ordered_ids: Array[String] = []

static func ids() -> Array:
	_ensure_loaded()
	return _ordered_ids.duplicate()

static func definition(food_id: String) -> FoodDefinition:
	_ensure_loaded()
	return _definitions.get(food_id) as FoodDefinition

static func display_name(food_id: String) -> String:
	_ensure_loaded()
	return str(_display_names.get(food_id, food_id))

static func texture(food_id: String) -> Texture2D:
	var food: FoodDefinition = definition(food_id)
	return food.texture if food != null else null

static func has_food(food_id: String) -> bool:
	_ensure_loaded()
	return _definitions.has(food_id)

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary or parsed.get("schema_version") != 1 or not parsed.get("foods") is Array:
		push_error("Food catalog must contain schema_version 1 and a foods array")
		return
	for entry in parsed.foods:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("resource") is String or not entry.get("display_name") is String:
			push_error("Food catalog entry requires id, resource and display_name strings")
			continue
		var food_id: String = entry.id
		if food_id.is_empty() or _definitions.has(food_id):
			push_error("Food catalog IDs must be nonempty and unique: " + food_id)
			continue
		var resource_path: String = entry.resource
		if not ResourceLoader.exists(resource_path):
			push_error("Missing FoodDefinition: " + resource_path)
			continue
		var food: FoodDefinition = load(resource_path) as FoodDefinition
		if food == null or str(food.id) != food_id or food.texture == null:
			push_error("FoodDefinition identity or texture is invalid: " + resource_path)
			continue
		_ordered_ids.append(food_id)
		_definitions[food_id] = food
		_display_names[food_id] = entry.display_name
