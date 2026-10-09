class_name GameTuning
extends Resource
## Shared, inspector-editable input and presentation values. Campaign has no clock.

@export_group("Input")
@export_range(4.0, 40.0, 1.0) var drag_threshold: float = 14.0
@export_range(44.0, 96.0, 1.0) var touch_target_min: float = 48.0
@export_group("Animation")
@export_range(0.0, 0.4, 0.01) var snap_seconds: float = 0.18
@export_range(0.0, 0.5, 0.01) var match_seconds: float = 0.22
@export_range(0.0, 0.5, 0.01) var reveal_seconds: float = 0.18
@export_group("Recovery")
@export_range(20, 100, 1) var undo_capacity: int = 40
@export_range(10, 1000, 10) var hint_budget_ms: int = 100
@export_group("Accessibility")
@export var reduced_motion: bool = false
@export var high_readability: bool = false
