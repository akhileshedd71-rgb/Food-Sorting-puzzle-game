class_name FoodDefinition
extends Resource

@export var id: StringName
@export var display_name_key: StringName
@export var texture: Texture2D
@export var tags: Array[StringName] = []
@export_range(1, 12, 1) var chapter: int = 1
@export var skin_of: StringName
