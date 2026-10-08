class_name RecipeTicket
extends Resource

@export var id: StringName
@export var display_name: String
@export var requirements: Array[RecipeRequirement] = []

static func from_dictionary(data: Dictionary) -> RecipeTicket:
	var result := RecipeTicket.new()
	result.id = StringName(str(data.get("id", "")))
	result.display_name = str(data.get("name", result.id))
	for food in data.get("requirements", {}):
		var requirement := RecipeRequirement.new()
		requirement.food_id = StringName(food)
		requirement.batches = int(data.requirements[food])
		result.requirements.append(requirement)
	return result

func to_dictionary() -> Dictionary:
	var requirement_data: Dictionary = {}
	for requirement in requirements:
		requirement_data[str(requirement.food_id)] = requirement.batches
	return {"id": str(id), "name": display_name, "requirements": requirement_data}
