class_name RecipeRequirement
extends Resource

@export var food_id: StringName
@export_range(1, 100, 1) var batches: int = 1
## Reserved for a future explicitly validated rules version.
@export var tray_tag: StringName
