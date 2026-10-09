class_name CoinIcon
extends Control
## Original Chef Coin emblem. No font glyph or external icon dependency.

func _init() -> void:
	custom_minimum_size = Vector2(48, 48)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	paint(self, size * 0.5, minf(size.x, size.y) * 0.43)


static func paint(canvas: CanvasItem, center: Vector2, radius: float, opacity: float = 1.0) -> void:
	if radius <= 0 or opacity <= 0:
		return
	var tint := Color(1, 1, 1, clampf(opacity, 0.0, 1.0))
	canvas.draw_circle(center + Vector2(0, radius * 0.14), radius, Color("795121") * tint, true, -1.0, true)
	canvas.draw_circle(center, radius, Color("bd8422") * tint, true, -1.0, true)
	canvas.draw_circle(center - Vector2(0, radius * 0.045), radius * 0.93, Color("ffdc68") * tint, true, -1.0, true)
	canvas.draw_circle(center + Vector2(0, radius * 0.04), radius * 0.78, Color("efb533") * tint, true, -1.0, true)
	canvas.draw_circle(center - Vector2(0, radius * 0.035), radius * 0.73, Color("f8c846") * tint, true, -1.0, true)
	canvas.draw_arc(center, radius * 0.86, PI * 1.02, PI * 1.89, 30, Color("fff3b8") * tint, maxf(1.0, radius * 0.055), true)
	canvas.draw_arc(center, radius * 0.75, PI * 0.04, PI * 0.86, 24, Color("d29421") * tint, maxf(1.0, radius * 0.05), true)
	# A small embossed herb leaf identifies the currency across all screens.
	var leaf := PackedVector2Array([
		center + Vector2(-0.30, 0.33) * radius,
		center + Vector2(-0.38, -0.04) * radius,
		center + Vector2(-0.16, -0.37) * radius,
		center + Vector2(0.40, -0.43) * radius,
		center + Vector2(0.34, 0.09) * radius,
		center + Vector2(0.06, 0.34) * radius
	])
	canvas.draw_colored_polygon(leaf, Color("c88c20") * tint)
	canvas.draw_polyline(leaf, Color("ffe99c") * tint, maxf(1.0, radius * 0.045), true)
	canvas.draw_line(center + Vector2(-0.37, 0.40) * radius, center + Vector2(0.21, -0.23) * radius, Color("ffe99c") * tint, maxf(1.0, radius * 0.07), true)
