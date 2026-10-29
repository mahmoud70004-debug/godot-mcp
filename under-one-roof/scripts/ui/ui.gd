class_name UI
extends RefCounted
## Shared look for every panel: warm parchment inside a dark wooden frame,
## matching the HUD of the concept art.

const INK := Color(0.24, 0.15, 0.09)
const INK_SOFT := Color(0.42, 0.30, 0.20)
const PAPER := Color(0.95, 0.89, 0.74)
const PAPER_DARK := Color(0.87, 0.78, 0.60)
const WOOD := Color(0.42, 0.26, 0.14)
const WOOD_DARK := Color(0.27, 0.16, 0.09)
const GOLD := Color(0.93, 0.74, 0.30)

static var _icons: Texture2D
static var _icon_index := {}


static func panel_style(bg := PAPER, border := WOOD, width := 3, radius := 5) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 3
	s.shadow_offset = Vector2(0, 2)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s


static func panel(bg := PAPER) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg))
	return p


## align RIGHT means "start of the reading direction", LEFT means "end" (mirrored for LTR languages).
static func label(text := "", size := 14, color := INK, align := HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var l := Label.new()
	l.text = Loc.t(text)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = flow(align)
	l.text_direction = Loc.dir()
	return l


static func flow(align: HorizontalAlignment) -> HorizontalAlignment:
	if Loc.rtl() or align == HORIZONTAL_ALIGNMENT_CENTER or align == HORIZONTAL_ALIGNMENT_FILL:
		return align
	return HORIZONTAL_ALIGNMENT_LEFT if align == HORIZONTAL_ALIGNMENT_RIGHT else HORIZONTAL_ALIGNMENT_RIGHT


static func button(text: String, size := 14) -> Button:
	var b := Button.new()
	b.text = Loc.t(text)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", WOOD_DARK)
	b.add_theme_color_override("font_pressed_color", WOOD_DARK)
	b.add_theme_color_override("font_focus_color", INK)
	b.add_theme_color_override("font_hover_pressed_color", WOOD_DARK)
	var focus := panel_style(Color(0, 0, 0, 0), GOLD, 2, 4)
	focus.shadow_size = 0
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("normal", panel_style(PAPER, WOOD, 2, 4))
	b.add_theme_stylebox_override("hover", panel_style(Color(1.0, 0.94, 0.80), WOOD, 2, 4))
	b.add_theme_stylebox_override("pressed", panel_style(PAPER_DARK, WOOD_DARK, 2, 4))
	b.add_theme_stylebox_override("disabled", panel_style(Color(0.8, 0.76, 0.68), Color(0.5, 0.45, 0.4), 2, 4))
	return b


static func icon(item: String) -> Texture2D:
	if _icons == null:
		_icons = load("res://assets/ui/icons.png")
		var meta = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprites.json"))
		_icon_index = meta["icons"]
	var name: String = Story.ITEMS.get(item, {}).get("icon", item)
	var i := int(_icon_index.get(name, 0))
	var at := AtlasTexture.new()
	at.atlas = _icons
	at.region = Rect2((i % 8) * 16, (i / 8) * 16, 16, 16)
	return at


static func portrait(id: String) -> Texture2D:
	var path := "res://assets/portraits/%s.png" % id
	if ResourceLoader.exists(path):
		return load(path)
	return null


static func full_rect(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0
