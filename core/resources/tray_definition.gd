class_name TrayDefinition
extends Resource
## Nullable three-position arrays are intentional; null means an empty slot.

@export var tray_id: StringName
@export var front: Array = [null, null, null]
@export var queued_rows: Array[Array] = []
@export var allowed_food_tags: Array[StringName] = []
@export var tray_identity_tags: Array[StringName] = []
@export var initial_seal: int = 0

static func from_dictionary(data: Dictionary) -> TrayDefinition:
	var result := TrayDefinition.new()
	result.tray_id = StringName(str(data.get("id", "")))
	result.front = data.get("front", [null, null, null]).duplicate(true)
	for row in data.get("queue", []):
		result.queued_rows.append(row.duplicate(true))
	return result

func to_dictionary() -> Dictionary:
	var queue: Array = []
	for row in queued_rows:
		queue.append(row.duplicate(true))
	return {"id": str(tray_id), "front": front.duplicate(true), "queue": queue}
