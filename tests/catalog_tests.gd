extends SceneTree
## Catalog contracts: chapter routing, independent metadata, lazy food assets,
## native resource/art integrity, and the complete recipe registry.
## During parallel authoring only, -- --registry-only checks metadata without
## requiring the new image files. Normal test runs always validate every asset.

const UNLOCKS: Dictionary = {
	"tomato": 1, "corn_cob": 2, "button_mushroom": 3, "bell_pepper_ring": 11,
	"zucchini_round": 21, "eggplant_slice": 25,
	"chicken_drumstick": 51, "steak": 56, "prawn": 61, "fish_fillet": 66,
	"sausage_spiral": 71, "halloumi_slice": 76,
	"fried_egg": 101, "pancake_stack": 106, "waffle_square": 111,
	"toast_slice": 116, "hash_brown": 121, "croissant": 126
}
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	var registry_only: bool = OS.get_cmdline_user_args().has("--registry-only")
	test_chapters()
	test_lazy_registry()
	test_legacy_dictionary_isolation()
	if not registry_only:
		test_native_resources()
		test_recipes()
	for failure in failures:
		push_error(failure)
	print("CATALOG TESTS%s: %d checks, %d failures" % [" (registry only)" if registry_only else "", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

func test_chapters() -> void:
	check(LevelCatalog.LEVEL_COUNT == 150, "Campaign exposes 150 levels")
	check(LevelCatalog.chapters().size() == 3, "Campaign has three chapters")
	for number in range(1, 151):
		var chapter_id: int = (number - 1) / 50 + 1
		var slug: String = ["garden", "barbecue", "breakfast"][chapter_id - 1]
		var expected_id: String = "%s_%03d" % [slug, number]
		check(LevelCatalog.level_id(number) == expected_id, "Absolute level numbering %d" % number)
		check(LevelCatalog.level_path(number) == "res://data/levels/" + expected_id + ".json", "Level path %d" % number)
		var metadata: Dictionary = LevelCatalog.chapter_for_level(number)
		check(metadata.id == chapter_id and metadata.start <= number and metadata.end >= number, "Chapter interval %d" % number)
	for number in [-20, 0, 151, 1000]:
		check(LevelCatalog.level_id(number).is_empty() and LevelCatalog.level_path(number).is_empty(), "Invalid level number gives no path")
		check(LevelCatalog.chapter_for_level(number).is_empty(), "Invalid level number gives no chapter")
	check(LevelCatalog.chapter(0).is_empty() and LevelCatalog.chapter(4).is_empty(), "Invalid chapter returns empty metadata")
	var metadata: Array = LevelCatalog.chapters()
	for chapter in metadata:
		for required in ["id", "slug", "name", "start", "end", "subtitle", "foods"]:
			check(chapter.has(required), "Chapter contains " + required)
		check(chapter.foods.size() == 6, "Chapter palette contains six identities")
	metadata[0].foods[0] = "mutated"
	metadata[0].name = "Changed name"
	check(LevelCatalog.chapter(1).foods[0] == "tomato" and LevelCatalog.chapter(1).name == "Garden Grill", "Chapter metadata is independent")
	var single: Dictionary = LevelCatalog.chapter_for_level(51)
	single.foods.clear()
	check(LevelCatalog.chapter(2).foods.size() == 6, "Single chapter lookup returns a deep copy")

func test_lazy_registry() -> void:
	check(FoodCatalog._definitions.is_empty(), "No food images are loaded by level catalog metadata")
	check(FoodCatalog.ids().size() == 18, "Exactly eighteen foods are registered")
	for id in UNLOCKS:
		check(FoodCatalog.has_food(id), "Registered identity " + id)
		check(FoodCatalog.unlock_level(id) == UNLOCKS[id], "Authored unlock for " + id)
		check(not FoodCatalog.display_name(id).is_empty(), "Registered display name for " + id)
	check(FoodCatalog._definitions.is_empty(), "Identity, labels and unlock queries do not load native food resources or atlases")
	var ids: Array = FoodCatalog.ids()
	ids.clear()
	check(FoodCatalog.ids().size() == 18, "Registry list is independent")
	check(not FoodCatalog.has_food("missing") and FoodCatalog.unlock_level("missing") == 0, "Unknown food identity stays unregistered")
	check(FoodCatalog.definition("missing") == null and FoodCatalog.texture("missing") == null, "Unknown food never supplies placeholder art")
	check(FoodCatalog.display_name("missing") == "missing", "Unknown display names retain diagnostic identity")
	check(FoodCatalog.slot_label("chicken_drumstick") == "Drumstick" and FoodCatalog.display_name("chicken_drumstick") == "Chicken Drumstick", "Short tray labels preserve full collection names")
	check(FoodCatalog.slot_label("halloumi_slice") == "Halloumi" and FoodCatalog.slot_label("sausage_spiral") == "Sausage", "Long ingredient names have explicit short tray labels")
	check(FoodCatalog.slot_label("tomato") == FoodCatalog.display_name("tomato"), "Tray label defaults to full name when no override is needed")
	check(FoodCatalog.slot_label("missing") == "missing", "Unknown tray label retains diagnostic identity")
	check(FoodCatalog._definitions.is_empty(), "Short label lookup does not load food textures")

func test_legacy_dictionary_isolation() -> void:
	var first: Dictionary = LevelCatalog.load_level(1)
	check(first.level_id == "garden_001" and first.content_hash == "5374156bcd4b7f44dff166286c4e407fcaa507629f30b5e3c4a0bc2c3b08e6fd", "Original first-level identity and certificate hash unchanged")
	check(first.chapter == 1 and not first.has("subtitle"), "New chapter metadata is not injected into old level dictionaries")
	first.trays[0].front[0] = "changed"
	first.authoring.expected_foods = 99
	var second: Dictionary = LevelCatalog.load_level(1)
	check(second.trays[0].front[0] == "tomato" and second.authoring.expected_foods == 1, "Level loads own independent nested authoring and board dictionaries")
	check(FoodCatalog._definitions.is_empty(), "Level validation remains independent of image loading")

func test_native_resources() -> void:
	for chapter_id in range(1, 4):
		var chapter: Dictionary = LevelCatalog.chapter(chapter_id)
		var atlas_path: String = "res://assets/food/" + ["food_atlas.png", "barbecue_atlas.png", "breakfast_atlas.png"][chapter_id - 1]
		check(ResourceLoader.exists(atlas_path), "Original atlas exists for " + chapter.name)
		for index in range(chapter.foods.size()):
			var id: String = chapter.foods[index]
			var definition: FoodDefinition = FoodCatalog.definition(id)
			check(definition != null, "Native FoodDefinition loads: " + id)
			if definition == null:
				continue
			check(str(definition.id) == id and definition.chapter == chapter_id, "Native resource identity/chapter: " + id)
			check(not str(definition.display_name_key).is_empty(), "Native resource has localization key: " + id)
			var texture: AtlasTexture = FoodCatalog.texture(id) as AtlasTexture
			check(texture != null and texture.atlas != null, "Registered food has a real atlas texture: " + id)
			if texture == null or texture.atlas == null:
				continue
			check(texture.atlas.resource_path == atlas_path, "Food uses the correct chapter atlas: " + id)
			check(texture.atlas.get_size() == Vector2(1536, 1024), "Chapter atlas dimensions: " + id)
			var expected_region := Rect2((index % 3) * 512, (index / 3) * 512, 512, 512)
			check(texture.region == expected_region, "Food atlas cell order: " + id)
			check(FoodCatalog.definition(id) == definition and FoodCatalog.texture(id) == texture, "Loaded resources are cached: " + id)
	check(FoodCatalog._definitions.size() == 18, "Every food native Resource was verified")

func test_recipes() -> void:
	var recipes: Array = LevelCatalog.load_recipes()
	check(recipes.size() == 12 and LevelCatalog.RECIPE_IDS.size() == 12, "Twelve real recipe bundles load")
	var seen: Dictionary = {}
	for recipe in recipes:
		check(not seen.has(recipe.id), "Recipe IDs are unique")
		seen[recipe.id] = true
		check(recipe.id in LevelCatalog.RECIPE_IDS and not recipe.name.is_empty(), "Recipe has a registered identity and display name")
		check(not recipe.requirements.is_empty(), "Recipe contains batch demand")
		for food_id in recipe.requirements:
			check(FoodCatalog.has_food(food_id), "Recipe references a registered food")
			check(FoodCatalog.unlock_level(food_id) <= int(recipe.unlock_level), "Recipe cannot demand an undiscovered food")
