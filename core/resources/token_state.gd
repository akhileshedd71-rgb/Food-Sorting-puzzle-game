class_name TokenState
extends Resource
## Authoring extension point. This initial campaign uses unblocked food IDs.

@export var instance_id: StringName
@export var food_id: StringName
@export_enum("none") var blocker_kind: String = "none"
@export var remaining_counter: int = 0
