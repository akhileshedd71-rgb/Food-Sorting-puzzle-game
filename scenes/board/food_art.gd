class_name FoodArt
extends RefCounted

const IDS := ["tomato", "corn_cob", "button_mushroom", "bell_pepper_ring", "zucchini_round", "eggplant_slice"]
static func title(id: String) -> String:
	return FoodCatalog.display_name(id)

static func texture(id: String) -> Texture2D:
	return FoodCatalog.texture(id)

static func icon(id: String, extent: float = 76) -> TextureRect:
	var t := TextureRect.new()
	t.texture = texture(id)
	t.custom_minimum_size = Vector2(extent, extent)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t
