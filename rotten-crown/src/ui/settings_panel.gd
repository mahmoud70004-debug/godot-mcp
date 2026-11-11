class_name SettingsPanel
extends Control
## One settings panel shared by the pause menu and the title screen: touch layout side,
## look sensitivity, invert Y, graphics quality and the FPS overlay. Same MenuItem style
## as the pause menu. Emits `closed` for Back / Esc; the owner decides what comes next.

signal closed

## False when the owner (the HUD) already polls the pause action itself.
var handles_cancel := true

@onready var _controls: MenuItemButton = %ControlsButton
@onready var _sensitivity: MenuItemButton = %SensitivityButton
@onready var _invert: MenuItemButton = %InvertButton
@onready var _quality: OptionButton = %QualityOption
@onready var _fps: MenuItemButton = %FpsToggle
@onready var _back: MenuItemButton = %BackButton
@onready var _column: Control = %Column


func _ready() -> void:
	hide()
	_controls.pressed.connect(_on_controls_pressed)
	_sensitivity.pressed.connect(_on_sensitivity_pressed)
	_invert.toggled.connect(_on_invert_toggled)
	_quality.item_selected.connect(_on_quality_selected)
	Events.quality_changed.connect(_on_quality_changed)
	_fps.toggled.connect(_on_fps_toggled)
	_back.pressed.connect(close)
	get_viewport().size_changed.connect(_fit)
	_fit()


func open() -> void:
	_quality.select(Settings.quality)
	_refresh()
	_fit()
	show()
	_controls.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible or not handles_cancel:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _fit() -> void:
	UiSafeArea.inset_control(_column)


func _refresh() -> void:
	_controls.hint = "Joystick right" if Settings.swap_controls else "Joystick left"
	_sensitivity.hint = "%d / %d" % [Settings.look_step + 1, Settings.LOOK_STEPS.size()]
	_invert.set_pressed_no_signal(Settings.invert_y)
	_invert.hint = "on" if Settings.invert_y else "off"
	var fps_on: bool = Settings.show_fps or FpsOverlay.forced
	_fps.set_pressed_no_signal(fps_on)
	_fps.hint = "on" if fps_on else "off"
	# The page link forces it on: the toggle cannot turn it off, so say why.
	if FpsOverlay.forced:
		_fps.disabled = true
		_fps.disabled_hint = "on (link)"


func _on_controls_pressed() -> void:
	Settings.swap_controls = not Settings.swap_controls
	Settings.save_settings()
	Settings.controls_changed.emit()
	_refresh()


func _on_sensitivity_pressed() -> void:
	Settings.set_look_step((Settings.look_step + 1) % Settings.LOOK_STEPS.size())
	Settings.save_settings()
	Settings.controls_changed.emit()
	_refresh()


func _on_invert_toggled(pressed: bool) -> void:
	Settings.invert_y = pressed
	Settings.save_settings()
	_refresh()


func _on_quality_selected(index: int) -> void:
	Settings.quality_manual = true
	Settings.quality = index
	Settings.save_settings()
	Events.quality_changed.emit(index)


## A method, not a lambda: Godot drops the connection when the panel is freed.
func _on_quality_changed(level: int) -> void:
	_quality.select(level)


func _on_fps_toggled(pressed: bool) -> void:
	Settings.show_fps = pressed
	Settings.save_settings()
	FpsOverlay.refresh_enabled()
	_fps.hint = "on" if pressed else "off"
