class_name FoodCatalog
extends RefCounted
## Data registry shared by validation and presentation. New food needs only a
## FoodDefinition Resource, its art, and an entry in data/foods/catalog.json.

const MANIFEST_PATH := "res://data/foods/catalog.json"
static var _loaded: bool = false
static var _registry: Dictionary = {}
static var _definitions: Dictionary = {}
static var _display_names: Dictionary = {}
static var _ordered_ids: Array[String] = []

static func ids() -> Array:
	_ensure_loaded()
	return _ordered_ids.duplicate()

static func definition(food_id: String) -> FoodDefinition:
	_ensure_loaded()
	if _definitions.has(food_id):
		return _definitions[food_id] as FoodDefinition
	if not _registry.has(food_id):
		return null
	# The registry serves save validation and menu labels without loading any
	# image. Load a typed Resource and its atlas only when this food is drawn.
	var resource_path: String = _registry[food_id].resource
	if not ResourceLoader.exists(resource_path):
		push_error("Missing FoodDefinition: " + resource_path)
		return null
	var food: FoodDefinition = load(resource_path) as FoodDefinition
	if food == null or str(food.id) != food_id or food.texture == null:
		push_error("FoodDefinition identity or texture is invalid: " + resource_path)
		return null
	_definitions[food_id] = food
	return food

static func display_name(food_id: String) -> String:
	_ensure_loaded()
	return str(_display_names.get(food_id, food_id))

static func slot_label(food_id: String) -> String:
	_ensure_loaded()
	var label: Variant = _registry.get(food_id, {}).get("slot_label")
	return label if label is String and not label.is_empty() else display_name(food_id)

static func texture(food_id: String) -> Texture2D:
	var food: FoodDefinition = definition(food_id)
	return food.texture if food != null else null

static func has_food(food_id: String) -> bool:
	_ensure_loaded()
	return _registry.has(food_id)

static func unlock_level(food_id: String) -> int:
	_ensure_loaded()
	return int(_registry.get(food_id, {}).get("unlock_level", 0))

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
		if food_id.is_empty() or _registry.has(food_id):
			push_error("Food catalog IDs must be nonempty and unique: " + food_id)
			continue
		var unlock: Variant = entry.get("unlock_level")
		if not (unlock is int or unlock is float) or not is_finite(float(unlock)) or float(unlock) != floor(float(unlock)) or int(unlock) < 1:
			push_error("Food catalog requires a positive integral unlock_level: " + food_id)
			continue
		_ordered_ids.append(food_id)
		_registry[food_id] = entry.duplicate(true)
		_display_names[food_id] = entry.display_name
