class_name BrandMark
extends Control
## Original plate-and-sprig mark for Garden Table's title and welcome screens.

func _init() -> void:
	custom_minimum_size = Vector2(180, 180)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.43
	if radius <= 0:
		return
	draw_circle(center + Vector2(0, radius * 0.09), radius * 1.02, Color(0.10, 0.23, 0.17, 0.28), true, -1.0, true)
	draw_circle(center, radius, Color("21675e"), true, -1.0, true)
	draw_circle(center, radius * 0.94, Color("e9bd52"), true, -1.0, true)
	draw_circle(center, radius * 0.89, Color("fff6df"), true, -1.0, true)
	draw_circle(center + Vector2(0, radius * 0.025), radius * 0.71, Color("d9ddc4"), true, -1.0, true)
	draw_circle(center - Vector2(0, radius * 0.01), radius * 0.66, Color("fffaf0"), true, -1.0, true)
	draw_arc(center, radius * 0.80, PI * 1.05, PI * 1.88, 36, Color.WHITE, maxf(1.0, radius * 0.025), true)
	var bottom := center + Vector2(-0.28, 0.39) * radius
	var top := center + Vector2(0.30, -0.43) * radius
	draw_line(bottom, top, Color("286e52"), radius * 0.055, true)
	leaf(center + Vector2(-0.15, 0.17) * radius, Vector2(-0.41, -0.14) * radius, radius * 0.16, Color("54985d"))
	leaf(center + Vector2(-0.03, -0.02) * radius, Vector2(0.41, 0.06) * radius, radius * 0.17, Color("3a8057"))
	leaf(center + Vector2(0.10, -0.20) * radius, Vector2(-0.30, -0.22) * radius, radius * 0.14, Color("71aa68"))
	leaf(center + Vector2(0.20, -0.34) * radius, Vector2(0.24, -0.20) * radius, radius * 0.12, Color("3a8057"))
	draw_circle(center + Vector2(0.40, 0.35) * radius, radius * 0.045, Color("e2ad33"))
	draw_circle(center + Vector2(0.51, 0.23) * radius, radius * 0.024, Color("e2ad33"))


func leaf(base: Vector2, direction: Vector2, width: float, color: Color) -> void:
	var normal := direction.normalized().orthogonal()
	var points := PackedVector2Array()
	for i in range(11):
		var t := float(i) / 10.0
		points.append(base + direction * t + normal * sin(t * PI) * width)
	for i in range(10, -1, -1):
		var t := float(i) / 10.0
		points.append(base + direction * t - normal * sin(t * PI) * width * 0.72)
	draw_colored_polygon(points, color)
	draw_line(base, base + direction * 0.84, color.lightened(0.23), maxf(1.0, width * 0.08), true)
