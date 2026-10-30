class_name HUD
extends CanvasLayer
## In-game overlay: stat bars, prompts, messages, region title cards, damage
## flash, touch controls, and the modal menus (inventory, pause, lore, death).

@onready var health_bar: PixelBar = %HealthBar
@onready var stamina_bar: PixelBar = %StaminaBar
@onready var prompt_label: Label = %PromptLabel
@onready var message_label: Label = %MessageLabel
@onready var region_title: Label = %RegionTitle
@onready var region_subtitle: Label = %RegionSubtitle
@onready var damage_flash: ColorRect = %DamageFlash
@onready var crosshair: Control = %Crosshair
@onready var touch_controls: TouchControls = %TouchControls
@onready var interact_button: TouchActionButton = %InteractButton
@onready var inventory_menu: InventoryMenu = %InventoryMenu
@onready var pause_menu: Control = %PauseMenu
@onready var lore_reader: Control = %LoreReader
@onready var lore_title: Label = %LoreTitle
@onready var lore_author: Label = %LoreAuthor
@onready var lore_text: Label = %LoreText
@onready var death_screen: Control = %DeathScreen

var _open_menu: Control
var _message_tween: Tween
var _region_tween: Tween
var _region_name := ""
var _insets := Vector4.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for menu in [inventory_menu, pause_menu, lore_reader, death_screen]:
		(menu as Control).hide()
	prompt_label.text = ""
	message_label.modulate.a = 0.0
	region_title.modulate.a = 0.0
	region_subtitle.modulate.a = 0.0
	damage_flash.modulate.a = 0.0
	interact_button.hide()

	Events.player_health_changed.connect(health_bar.set_values)
	Events.player_stamina_changed.connect(stamina_bar.set_values)
	Events.player_damaged.connect(_on_player_damaged)
	Events.player_died.connect(_on_player_died)
	Events.interaction_prompt_changed.connect(_on_prompt_changed)
	Events.message_requested.connect(_show_message)
	Events.item_picked_up.connect(_on_item_picked_up)
	Events.lore_discovered.connect(_open_lore)
	Events.lore_read_requested.connect(_open_lore)
	Events.region_entered.connect(_show_region)
	Events.wake_up_started.connect(_play_eyelids)

	inventory_menu.closed.connect(close_menu)
	%QualityOption.item_selected.connect(_on_quality_selected)
	Events.quality_changed.connect(_on_quality_changed)
	%ResumeButton.pressed.connect(close_menu)
	%SaveButton.pressed.connect(_on_save_pressed)
	%MainMenuButton.pressed.connect(_on_main_menu_pressed)
	%CloseLoreButton.pressed.connect(_close_lore)
	%RetryButton.pressed.connect(_on_retry_pressed)
	%InventoryTouchButton.pressed.connect(func() -> void: _toggle_menu(inventory_menu))
	%PauseTouchButton.pressed.connect(func() -> void: _toggle_menu(pause_menu))
	%InventoryTouchButton.visible = Settings.uses_touch_controls()
	%PauseTouchButton.visible = Settings.uses_touch_controls()
	get_viewport().size_changed.connect(_fit_safe_area)
	_fit_safe_area()
	# Insets can change without a resize (a 180 degree flip, late browser bars).
	var inset_poll := Timer.new()
	inset_poll.wait_time = 1.0
	inset_poll.autostart = true
	inset_poll.timeout.connect(_on_inset_poll)
	add_child(inset_poll)
	DebugBridge.register("hud", _debug_rects)


## Edge-anchored HUD controls that keep a scene margin of their own; moved in by the safe-area insets.
func _fit_safe_area() -> void:
	var edge_controls: Array[Control] = [
		health_bar, stamina_bar, prompt_label, message_label, touch_controls.joystick, %AttackButton, %BlockButton,
		interact_button, %InventoryTouchButton, %PauseTouchButton, %PauseColumn, %PauseRegion, %LorePanel,
	]
	for control in edge_controls:
		UiSafeArea.inset_control(control)
	_insets = UiSafeArea.insets()


func _on_inset_poll() -> void:
	if UiSafeArea.insets() != _insets:
		_fit_safe_area()


## Screen rectangles (UI units) of the bottom-anchored elements, for browser tests (?debug=1).
func _debug_rects() -> Dictionary:
	var rects := {}
	for control: Control in [prompt_label, message_label, touch_controls.joystick, %AttackButton, %BlockButton, interact_button, %PauseRegion]:
		var r := control.get_global_rect()
		rects[control.name] = [r.position.x, r.position.y, r.end.x, r.end.y]
	var vs := get_viewport().get_visible_rect().size
	rects["viewport"] = [0.0, 0.0, vs.x, vs.y]
	rects["bottom_margin"] = UiSafeArea.bottom_margin()
	rects["pause_open"] = pause_menu.visible
	return rects


func _process(_delta: float) -> void:
	if death_screen.visible:
		return
	if Input.is_action_just_pressed("inventory"):
		_toggle_menu(inventory_menu)
	elif Input.is_action_just_pressed("pause"):
		if _open_menu == lore_reader:
			_close_lore()
		elif _open_menu:
			close_menu()
		else:
			open_menu(pause_menu)


# --- Menus -----------------------------------------------------------------

func open_menu(menu: Control) -> void:
	if _open_menu:
		_open_menu.hide()
	_open_menu = menu
	_hide_region_card()
	if menu == inventory_menu:
		inventory_menu.open()
	else:
		if menu == pause_menu:
			%QualityOption.select(Settings.quality)
			%PauseRegion.text = _region_name
			%SaveButton.hint = "save"
		menu.show()
		if menu == pause_menu:
			%ResumeButton.grab_focus()
	_set_gameplay_paused(true)


func close_menu() -> void:
	if _open_menu:
		_open_menu.hide()
	lore_reader.hide()
	_open_menu = null
	_set_gameplay_paused(false)


## A region title card must not show through an open menu.
func _hide_region_card() -> void:
	if _region_tween and _region_tween.is_valid():
		_region_tween.kill()
	region_title.modulate.a = 0.0
	region_subtitle.modulate.a = 0.0


func _on_quality_selected(index: int) -> void:
	Settings.quality_manual = true
	Settings.quality = index
	Settings.save_settings()
	Events.quality_changed.emit(index)


func _toggle_menu(menu: Control) -> void:
	if _open_menu == menu:
		close_menu()
	else:
		open_menu(menu)


func _set_gameplay_paused(paused: bool) -> void:
	get_tree().paused = paused
	touch_controls.set_enabled(not paused)
	crosshair.visible = not paused
	Events.menu_state_changed.emit(paused)


func _open_lore(lore: LoreData) -> void:
	lore_title.text = lore.display_name
	lore_author.text = "- %s" % lore.author if lore.author != "" else ""
	lore_text.text = lore.lore_text
	if _open_menu == inventory_menu:
		# Read on top of the inventory, return to it afterwards.
		lore_reader.show()
		return
	open_menu(lore_reader)


func _close_lore() -> void:
	if _open_menu == inventory_menu:
		lore_reader.hide()
	else:
		close_menu()


# --- Feedback --------------------------------------------------------------

func _on_prompt_changed(text: String) -> void:
	prompt_label.text = text
	interact_button.visible = text != "" and Settings.uses_touch_controls()


func _show_message(text: String, duration: float) -> void:
	message_label.text = text
	if _message_tween and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_property(message_label, "modulate:a", 1.0, 0.25)
	_message_tween.tween_interval(duration)
	_message_tween.tween_property(message_label, "modulate:a", 0.0, 0.8)


func _on_item_picked_up(item: ItemData, quantity: int) -> void:
	var suffix := " x%d" % quantity if quantity > 1 else ""
	_show_message("Obtained: %s%s" % [item.display_name, suffix], 2.5)


func _show_region(region: RegionData) -> void:
	# Title case: blackletter capitals in a row cannot be read.
	region_title.text = region.display_name
	_region_name = region.display_name
	region_subtitle.text = region.subtitle
	if _region_tween and _region_tween.is_valid():
		_region_tween.kill()
	_region_tween = create_tween()
	_region_tween.tween_interval(0.6)
	_region_tween.tween_property(region_title, "modulate:a", 1.0, 1.6)
	_region_tween.parallel().tween_property(region_subtitle, "modulate:a", 0.8, 2.4)
	_region_tween.tween_interval(2.5)
	_region_tween.tween_property(region_title, "modulate:a", 0.0, 2.0)
	_region_tween.parallel().tween_property(region_subtitle, "modulate:a", 0.0, 1.6)


## Heavy eyelids: open a crack, sink shut, then open for real.
func _play_eyelids(duration: float) -> void:
	var lids: Array[ColorRect] = []
	for top in [true, false]:
		var lid := ColorRect.new()
		lid.color = Color.BLACK
		lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lid.anchor_right = 1.0
		if top:
			lid.anchor_bottom = 0.5
		else:
			lid.anchor_top = 0.5
			lid.anchor_bottom = 1.0
		add_child(lid)
		lids.append(lid)
	var h := get_viewport().get_visible_rect().size.y * 0.5
	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_interval(duration * 0.08)
	tw.tween_property(lids[0], "position:y", -h * 0.25, duration * 0.12)
	tw.parallel().tween_property(lids[1], "position:y", h * 0.25, duration * 0.12)
	tw.tween_interval(duration * 0.08)
	tw.tween_property(lids[0], "position:y", 0.0, duration * 0.1)
	tw.parallel().tween_property(lids[1], "position:y", 0.0, duration * 0.1)
	tw.tween_interval(duration * 0.05)
	tw.tween_property(lids[0], "position:y", -h * 1.05, duration * 0.2)
	tw.parallel().tween_property(lids[1], "position:y", h * 1.05, duration * 0.2)
	await tw.finished
	for lid in lids:
		lid.queue_free()


func _on_player_damaged(_amount: float) -> void:
	damage_flash.modulate.a = 0.55
	create_tween().tween_property(damage_flash, "modulate:a", 0.0, 0.5)


func _on_player_died() -> void:
	if _open_menu:
		_open_menu.hide()
		_open_menu = null
	touch_controls.set_enabled(false)
	_hide_region_card()
	crosshair.hide()
	prompt_label.text = ""
	death_screen.modulate.a = 0.0
	death_screen.show()
	var tween := create_tween()
	tween.tween_interval(1.2)
	tween.tween_property(death_screen, "modulate:a", 1.0, 2.0)


func _on_save_pressed() -> void:
	var player := get_parent() as Node3D
	if player and SaveManager.save_game(player.global_position):
		# The quiet stamp sits on the item itself; the menu dims the message line.
		%SaveButton.hint = "written in blood"
		_show_message("Your memories are written in blood.", 2.0)


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	SceneLoader.change_scene("res://src/ui/main_menu.tscn")


func _on_retry_pressed() -> void:
	GameState.player_health = -1.0
	get_tree().paused = false
	if not SaveManager.load_game():
		SceneLoader.reload_current()


## A method, not a lambda: Godot drops the connection when the HUD is freed.
func _on_quality_changed(level: int) -> void:
	%QualityOption.select(level)
