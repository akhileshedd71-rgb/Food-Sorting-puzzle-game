class_name LevelDefinition
extends Resource
## Validated interchange data becomes explicit editor-friendly Resources.

@export var schema_version: int = 1
@export var content_version: int = 1
@export var level_id: StringName
@export var number: int = 1
@export var title: String
@export_multiline var lesson: String
@export_enum("campaign", "campaign_orders") var mode: String = "campaign"
@export_range(1, 2, 1) var active_ticket_limit: int = 1
@export var trays: Array[TrayDefinition] = []
@export var tickets: Array[RecipeTicket] = []
@export var solution: Array[Array] = []
@export var source_data: Dictionary = {}

static func from_dictionary(data: Dictionary) -> LevelDefinition:
	var result := LevelDefinition.new()
	result.source_data = data.duplicate(true)
	result.schema_version = int(data.get("schema_version", 1))
	result.content_version = int(data.get("content_version", 1))
	result.level_id = StringName(str(data.get("level_id", "")))
	result.number = int(data.get("number", 1))
	result.title = str(data.get("title", ""))
	result.lesson = str(data.get("lesson", ""))
	result.mode = str(data.get("mode", "campaign"))
	result.active_ticket_limit = int(data.get("active_ticket_limit", 1))
	for tray_data in data.get("trays", []):
		result.trays.append(TrayDefinition.from_dictionary(tray_data))
	for ticket_data in data.get("tickets", []):
		result.tickets.append(RecipeTicket.from_dictionary(ticket_data))
	for command in data.get("solution", []):
		result.solution.append(command.duplicate())
	return result

func to_dictionary() -> Dictionary:
	var result: Dictionary = source_data.duplicate(true)
	result.merge({"schema_version": schema_version, "content_version": content_version,
		"level_id": str(level_id), "number": number, "title": title, "lesson": lesson,
		"mode": mode, "active_ticket_limit": active_ticket_limit}, true)
	result.trays = []
	for tray in trays:
		result.trays.append(tray.to_dictionary())
	result.tickets = []
	for ticket in tickets:
		result.tickets.append(ticket.to_dictionary())
	result.solution = []
	for command in solution:
		result.solution.append(command.duplicate())
	return result
