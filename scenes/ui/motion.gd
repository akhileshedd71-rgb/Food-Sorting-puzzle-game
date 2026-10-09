class_name GardenMotion
extends RefCounted
## Presentation only. Bound finite tweens cannot change puzzle or profile state.
## Pass positions in owner's local canvas coordinates. Root Controls normally
## share viewport coordinates. cancel_all(owner) removes bursts on a screen swap.

const CONTROL_META := &"garden_control_motion"
const BURST_META := &"garden_motion_bursts"
const MAX_BURSTS := 8
static var serial: int = 0


static func enter(control: Control, reduced: bool = false) -> Tween:
	var tween := begin(control, reduced)
	if tween == null:
		return null
	var rest: Dictionary = control.get_meta(CONTROL_META)
	control.pivot_offset = control.size * 0.5
	control.modulate = Color(rest.modulate.r, rest.modulate.g, rest.modulate.b, 0.0)
	control.scale = rest.scale * 0.976
	# Container-managed positions remain untouched. A tiny scale lift is enough
	# to give entrance depth without fighting the next container layout pass.
	tween.set_parallel(true)
	tween.tween_property(control, "modulate", rest.modulate, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", rest.scale, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tween


static func press(control: Control, reduced: bool = false) -> Tween:
	var tween := begin(control, reduced)
	if tween == null:
		return null
	var rest: Dictionary = control.get_meta(CONTROL_META)
	control.pivot_offset = control.size * 0.5
	tween.tween_property(control, "scale", rest.scale * 0.955, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", rest.scale * 1.012, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", rest.scale, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween


static func pulse(control: Control, reduced: bool = false) -> Tween:
	var tween := begin(control, reduced)
	if tween == null:
		return null
	var rest: Dictionary = control.get_meta(CONTROL_META)
	control.pivot_offset = control.size * 0.5
	tween.set_loops(2)
	tween.tween_property(control, "scale", rest.scale * 1.035, 0.27).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(control, "scale", rest.scale, 0.29).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween


static func begin(control: Control, reduced: bool) -> Tween:
	if not is_instance_valid(control):
		return null
	stop(control)
	if reduced or not control.is_inside_tree():
		return null
	serial += 1
	var token := serial
	var tween := control.create_tween()
	control.set_meta(CONTROL_META, {
		"tween": tween, "token": token, "scale": control.scale,
		"modulate": control.modulate, "pivot": control.pivot_offset
	})
	var reference: WeakRef = weakref(control)
	tween.finished.connect(func(): finish(reference, token), CONNECT_ONE_SHOT)
	return tween


static func finish(reference: WeakRef, token: int) -> void:
	var control: Control = reference.get_ref()
	if not is_instance_valid(control) or not control.has_meta(CONTROL_META):
		return
	var rest: Dictionary = control.get_meta(CONTROL_META)
	if int(rest.token) != token:
		return
	restore_control(control, rest)


static func stop(control: Control) -> void:
	if not is_instance_valid(control) or not control.has_meta(CONTROL_META):
		return
	var rest: Dictionary = control.get_meta(CONTROL_META)
	var previous: Tween = rest.tween
	if previous != null and previous.is_valid():
		previous.kill()
	restore_control(control, rest)


static func restore_control(control: Control, rest: Dictionary) -> void:
	control.scale = rest.scale
	control.modulate = rest.modulate
	control.pivot_offset = rest.pivot
	control.remove_meta(CONTROL_META)


static func coin_burst(owner: Node, position: Vector2, amount: int, reduced: bool = false) -> void:
	if amount <= 0:
		return
	var layer := make_burst(owner, position)
	if layer == null:
		return
	layer.coins = true
	layer.reduced = reduced
	layer.reward = GardenUI.label("+%d Chef Coins" % amount, 26, GardenUI.CREAM, true)
	layer.reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.reward.size = Vector2(280, 44)
	layer.reward.position = Vector2(-140, -22)
	layer.reward.add_theme_color_override("font_outline_color", GardenUI.TEAL)
	layer.reward.add_theme_constant_override("outline_size", 7)
	layer.add_child(layer.reward)
	if reduced:
		layer.queue_redraw()
		var reference: WeakRef = weakref(layer)
		owner.get_tree().create_timer(1.1).timeout.connect(func(): release(reference), CONNECT_ONE_SHOT)
	else:
		animate_burst(layer, 0.90)


static func match_burst(owner: Node, position: Vector2, reduced: bool = false) -> void:
	if reduced:
		return
	var layer := make_burst(owner, position)
	if layer != null:
		animate_burst(layer, 0.60)


static func make_burst(owner: Node, position: Vector2) -> BurstLayer:
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		return null
	var references: Array = owner.get_meta(BURST_META, [])
	var alive: Array = []
	for reference in references:
		if is_instance_valid(reference.get_ref()):
			alive.append(reference)
	while alive.size() >= MAX_BURSTS:
		var oldest: WeakRef = alive.pop_front()
		var old_node: Node = oldest.get_ref()
		if is_instance_valid(old_node):
			# Remove immediately; queued nodes must not accumulate during a rapid
			# same-frame burst of presentation requests.
			owner.remove_child(old_node)
			old_node.queue_free()
	var layer := BurstLayer.new()
	layer.position = position
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = 200
	owner.add_child(layer)
	var owner_ref: WeakRef = weakref(owner)
	var layer_ref: WeakRef = weakref(layer)
	layer.tree_exiting.connect(func(): forget_burst(owner_ref, layer_ref), CONNECT_ONE_SHOT)
	alive.append(layer_ref)
	owner.set_meta(BURST_META, alive)
	return layer


static func animate_burst(layer: BurstLayer, seconds: float) -> void:
	var reference: WeakRef = weakref(layer)
	var tween := layer.create_tween()
	tween.tween_property(layer, "progress", 1.0, seconds)
	tween.finished.connect(func(): release(reference), CONNECT_ONE_SHOT)


static func release(reference: WeakRef) -> void:
	var node: Node = reference.get_ref()
	if is_instance_valid(node):
		node.queue_free()


static func forget_burst(owner_ref: WeakRef, layer_ref: WeakRef) -> void:
	var owner: Node = owner_ref.get_ref()
	if not is_instance_valid(owner) or not owner.has_meta(BURST_META):
		return
	var remaining: Array = []
	for reference in owner.get_meta(BURST_META):
		if reference != layer_ref and is_instance_valid(reference.get_ref()):
			remaining.append(reference)
	if remaining.is_empty():
		owner.remove_meta(BURST_META)
	else:
		owner.set_meta(BURST_META, remaining)


static func cancel_all(owner: Node) -> void:
	if not is_instance_valid(owner):
		return
	var references: Array = owner.get_meta(BURST_META, []).duplicate()
	for reference in references:
		var node: Node = reference.get_ref()
		if is_instance_valid(node):
			owner.remove_child(node)
			node.queue_free()
	if owner.has_meta(BURST_META):
		owner.remove_meta(BURST_META)


class BurstLayer extends Control:
	var coins: bool = false
	var reduced: bool = false
	var reward: Label
	var progress: float = 0.0:
		set(value):
			progress = value
			if is_instance_valid(reward) and not reduced:
				reward.position.y = -22.0 - 64.0 * (1.0 - pow(1.0 - progress, 2))
				reward.modulate.a = clampf((1.0 - progress) * 3.5, 0.0, 1.0)
			queue_redraw()


	func _draw() -> void:
		if reduced:
			CoinIcon.paint(self, Vector2(0, -54), 16.0)
			return
		var fade := clampf((1.0 - progress) * 2.7, 0.0, 1.0)
		var travel := 1.0 - pow(1.0 - progress, 2)
		if coins:
			for i in range(6):
				var spread := float(i) / 5.0 * 2.0 - 1.0
				var point := Vector2(spread * 94.0 * travel, -sin(progress * PI * 0.8) * (95.0 - absf(spread) * 25.0) + progress * 12.0)
				CoinIcon.paint(self, point, 11.0 - absf(spread) * 1.5, fade)
		else:
			draw_arc(Vector2.ZERO, 18.0 + travel * 41.0, 0, TAU, 40, Color(1, 0.86, 0.40, fade * 0.48), 2.0, true)
			for i in range(8):
				var angle := TAU * float(i) / 8.0 - PI * 0.25
				var point := Vector2.from_angle(angle) * (18.0 + travel * 60.0)
				var extent := (5.0 if i % 2 == 0 else 3.5) * (1.0 - progress * 0.5)
				var points := PackedVector2Array([point + Vector2(0, -extent), point + Vector2(extent * 0.48, 0), point + Vector2(0, extent), point + Vector2(-extent * 0.48, 0)])
				draw_colored_polygon(points, Color(1, 0.89, 0.47, fade) if i % 2 == 0 else Color(1, 0.98, 0.86, fade))
