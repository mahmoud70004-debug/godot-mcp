class_name InventoryMenu
extends Control
## Resident-Evil-style pause inventory: item grid on the left, detail
## panel and context actions (Use / Equip / Read) on the right.

signal closed

## Widest the panel gets on wide phones; narrower screens (Low quality: 480x270) use all but 8 px.
const PANEL_MAX_WIDTH := 640.0

@onready var grid: GridContainer = %SlotGrid
@onready var name_label: Label = %ItemName
@onready var category_label: Label = %ItemCategory
@onready var description_label: Label = %ItemDescription
@onready var stats_label: Label = %ItemStats
@onready var status_label: Label = %StatusLabel
@onready var use_button: Button = %UseButton
@onready var equip_button: Button = %EquipButton
@onready var read_button: Button = %ReadButton
@onready var close_button: Button = %CloseButton
@onready var panel: Control = $Panel

var _selected: ItemData


func _ready() -> void:
	resized.connect(_fit_panel)
	_fit_panel()
	close_button.pressed.connect(func() -> void: closed.emit())
	use_button.pressed.connect(_on_use_pressed)
	equip_button.pressed.connect(_on_equip_pressed)
	read_button.pressed.connect(_on_read_pressed)


func _fit_panel() -> void:
	var side := maxf(8.0, floorf((size.x - PANEL_MAX_WIDTH) * 0.5))
	# 480x270 (Low quality on a 16:9 screen): tighter gutters, and the summary line gives way.
	var narrow := size.x < 560.0
	if narrow:
		side = 4.0
	panel.offset_left = side
	panel.offset_right = -side
	var margin := $Panel/Margin as MarginContainer
	margin.add_theme_constant_override("margin_left", 10 if narrow else 16)
	margin.add_theme_constant_override("margin_right", 10 if narrow else 16)
	($Panel/Margin/VBox/Body as HBoxContainer).add_theme_constant_override("separation", 12 if narrow else 20)
	status_label.visible = not (narrow and size.y < 300.0)


func open() -> void:
	refresh()
	show()
	if grid.get_child_count() > 0:
		(grid.get_child(0) as Control).grab_focus()


func refresh() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var slots := GameState.inventory.get_slots()
	var still_selected := false
	for slot in slots:
		var button := InventorySlotButton.new()
		button.setup(slot.item, slot.quantity, slot.item == GameState.equipped_weapon)
		button.pressed.connect(_select.bind(slot.item))
		button.focus_entered.connect(_select.bind(slot.item))
		grid.add_child(button)
		if slot.item == _selected:
			still_selected = true
	for i in Inventory.MAX_SLOTS - slots.size():
		var empty := InventorySlotButton.new()
		empty.setup(null, 0, false)
		grid.add_child(empty)
	if not still_selected:
		_selected = slots[0].item if slots.size() > 0 else null
	_select(_selected)
	_update_status()


func _select(item: ItemData) -> void:
	_selected = item
	var has := item != null
	name_label.text = item.display_name if has else "-"
	category_label.text = item.get_category_name() if has else ""
	description_label.text = item.description if has else "Your pack is empty."
	var lines := item.get_stat_lines() if has else PackedStringArray()
	if item is WeaponData:
		var level := GameState.get_weapon_level(item as WeaponData)
		if level > 0:
			lines.append("Honed +%d" % level)
	# One wrapped line, so the panel still fits the 270 px tall Low-quality screen.
	stats_label.text = "   ".join(lines)
	use_button.visible = item is ConsumableData
	equip_button.visible = item is WeaponData
	equip_button.disabled = item != null and item == GameState.equipped_weapon
	equip_button.text = "Equipped" if equip_button.disabled else "Equip"
	read_button.visible = item is LoreData


func _update_status() -> void:
	var weapon_name := GameState.equipped_weapon.display_name if GameState.equipped_weapon else "Bare hands"
	status_label.text = "In hand: %s      Damage %d      Vigour %d" % [
		weapon_name, roundi(GameState.get_attack_damage()), roundi(GameState.get_max_health())]


func _on_use_pressed() -> void:
	if _selected and GameState.use_item(_selected):
		refresh()


func _on_equip_pressed() -> void:
	if _selected is WeaponData:
		GameState.equip_weapon(_selected as WeaponData)
		refresh()


func _on_read_pressed() -> void:
	if _selected is LoreData:
		Events.lore_read_requested.emit(_selected as LoreData)
