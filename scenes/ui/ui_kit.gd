class_name GardenUI
extends RefCounted

const INK := Color("263c43")
const TEAL := Color("2b7a70")
const CREAM := Color("fff7eb")
const GOLD := Color("f5ca47")
const CORAL := Color("e87650")
const BODY = preload("res://assets/fonts/Body.ttf")
const HEADING = preload("res://assets/fonts/Heading.ttf")

static func box(color: Color, radius: int = 20, border: Color = Color.TRANSPARENT, width: int = 0, shadow: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(width)
	s.shadow_color = Color(0.12, 0.07, 0.02, 0.25)
	s.shadow_size = shadow
	s.shadow_offset = Vector2(0, shadow * 0.7)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s

static func label(text: String, size: int = 26, color: Color = INK, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = TranslationServer.translate(text)
	l.add_theme_font_override("font", HEADING if bold else BODY)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func button(text: String, action: Callable, color: Color = TEAL, minimum: Vector2 = Vector2(0, 84)) -> Button:
	var b := Button.new()
	b.text = TranslationServer.translate(text)
	b.custom_minimum_size = minimum
	b.add_theme_font_override("font", HEADING)
	b.add_theme_font_size_override("font_size", 25)
	b.add_theme_color_override("font_color", CREAM if color == TEAL else INK)
	b.add_theme_color_override("font_hover_color", CREAM if color == TEAL else INK)
	b.add_theme_color_override("font_pressed_color", CREAM if color == TEAL else INK)
	b.add_theme_color_override("font_disabled_color", Color("9b9b85"))
	b.add_theme_stylebox_override("normal", box(color, 21, color.lightened(0.28), 3, 5))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.10), 21, GOLD, 3, 6))
	b.add_theme_stylebox_override("pressed", box(color.darkened(0.08), 21, color.lightened(0.1), 3))
	b.add_theme_stylebox_override("disabled", box(Color("e1d7bd"), 21, Color("c5b89c"), 2))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), 21, GOLD, 4))
	b.pressed.connect(action)
	return b

static func panel(color: Color = CREAM, radius: int = 24) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, radius, color.lightened(0.12), 2, 6))
	return p

static func vbox(gap: int = 16) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v

static func hbox(gap: int = 16) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h

static func expand(control: Control) -> Control:
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return control

static func spacer(height: float = 0, grow: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if grow:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c
