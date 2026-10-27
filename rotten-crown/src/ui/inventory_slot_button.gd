class_name InventorySlotButton
extends Button
## One inventory cell. Draws a tiny pixel glyph per item category until
## real icons are painted.

var item: ItemData
var quantity := 0
var equipped := false


func setup(p_item: ItemData, p_quantity: int, p_equipped: bool) -> void:
	item = p_item
	quantity = p_quantity
	equipped = p_equipped
	custom_minimum_size = Vector2(34, 34)
	focus_mode = Control.FOCUS_ALL
	disabled = item == null
	tooltip_text = item.display_name if item else ""
	if item and item.icon:
		icon = item.icon
		expand_icon = true
	queue_redraw()


func _draw() -> void:
	if item == null or item.icon != null:
		_draw_overlays()
		return
	var c := (size * 0.5).floor()
	var col := item.tint
	match item.category:
		ItemData.Category.WEAPON:
			for i in range(-8, 8):
				draw_rect(Rect2(c + Vector2(i, -i), Vector2(2, 2)), col)
			draw_rect(Rect2(c + Vector2(-8, 3), Vector2(6, 2)), col.darkened(0.3))
		ItemData.Category.CONSUMABLE:
			draw_rect(Rect2(c + Vector2(-5, -3), Vector2(10, 11)), col)
			draw_rect(Rect2(c + Vector2(-2, -7), Vector2(4, 4)), col.darkened(0.4))
		ItemData.Category.RELIC:
			for y in range(-7, 8):
				var w := 7 - absi(y)
				draw_rect(Rect2(c + Vector2(-w, y), Vector2(w * 2 + 1, 1)), col)
		ItemData.Category.LORE:
			draw_rect(Rect2(c + Vector2(-6, -8), Vector2(12, 16)), col)
			for y in [-5, -2, 1, 4]:
				draw_rect(Rect2(c + Vector2(-4, y), Vector2(8, 1)), col.darkened(0.5))
		_:
			draw_rect(Rect2(c + Vector2(-5, -5), Vector2(10, 10)), col)
	_draw_overlays()


func _draw_overlays() -> void:
	if item == null:
		return
	var font := get_theme_default_font()
	if quantity > 1 and font:
		draw_string(font, Vector2(size.x - 10, size.y - 3), str(quantity), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.95, 0.9, 0.75))
	if equipped:
		draw_rect(Rect2(Vector2(2, 2), Vector2(4, 4)), Color(0.4, 0.75, 0.15))
