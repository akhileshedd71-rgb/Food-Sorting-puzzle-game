class_name ValidationReport
extends Resource

@export var content_hash: String
@export var engine_version: String
@export var rules_version: int = 1
@export_enum("SOLVED", "UNSOLVABLE", "UNKNOWN", "INVALID") var status: String = "UNKNOWN"
@export var solution_commands: Array[Array] = []
@export var stable_hashes: PackedStringArray = []
@export var moves: int = 0
@export var solver_budget_ms: int = 0
@export_enum("pending", "reviewed") var human_review_state: String = "pending"
