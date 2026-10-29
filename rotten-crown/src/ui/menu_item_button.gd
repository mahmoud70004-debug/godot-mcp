@tool
class_name MenuItemButton
extends Button
## Text-style menu entry (theme type "MenuItem"): no box, the label in ink and an optional
## hint in the muted tone after it. Focus, hover and press draw the accent mark hanging in the
## margin left of the label (the lit green window of the Royal Keep), so every label in a
## column shares one left edge; press turns the label accent.

const ACCENT := Color(0.663, 0.753, 0.306)
const MUTED := Color(0.604, 0.616, 0.545)
const FAINT := Color(0.424, 0.439, 0.392)
const HINT_GAP := 10.0

## Small second word, e.g. "new game" after "Wake Up". Shown in the muted tone.
@export var hint := "":
	set(value):
		hint = value
		_refresh_minimum()
		queue_redraw()
## Hint shown instead of `hint` while the item is disabled (say why it is unavailable).
@export var disabled_hint := "":
	set(value):
		disabled_hint = value
		_refresh_minimum()
		queue_redraw()


func _ready() -> void:
	if theme_type_variation == &"":
		theme_type_variation = &"MenuItem"
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	_refresh_minimum()


func _on_mouse_entered() -> void:
	# Pointer and keyboard share one highlight: hovering an item focuses it.
	if not disabled and focus_mode != FOCUS_NONE and not Engine.is_editor_hint():
		grab_focus()
	queue_redraw()


func _current_hint() -> String:
	return disabled_hint if disabled and disabled_hint != "" else hint


func _refresh_minimum() -> void:
	update_minimum_size()


func _get_minimum_size() -> Vector2:
	var extra := 0.0
	var h := _current_hint()
	if h != "":
		var font := get_theme_font(&"font")
		var fs := get_theme_font_size(&"font_size")
		if font:
			extra = HINT_GAP + font.get_string_size(h, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return Vector2(extra, 0.0)


func _is_lit() -> bool:
	return not disabled and (has_focus() or is_hovered() or button_pressed)


func _draw() -> void:
	var font := get_theme_font(&"font")
	var fs := get_theme_font_size(&"font_size")
	if font == null:
		return
	var lit := _is_lit()
	if lit:
		# A 4x6 lit window, centred on the label, 6 px left of the text edge.
		var mid := floorf(size.y * 0.5)
		draw_rect(Rect2(Vector2(-10, mid - 3), Vector2(4, 6)), ACCENT)
	var h := _current_hint()
	if h == "":
		return
	var label_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var style := get_theme_stylebox(&"normal")
	var left := style.content_margin_left if style else 0.0
	var baseline := floorf((size.y - font.get_height(fs)) * 0.5 + font.get_ascent(fs))
	var x := left + label_w + HINT_GAP
	draw_string(font, Vector2(x, baseline), h, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, FAINT if disabled else MUTED)
