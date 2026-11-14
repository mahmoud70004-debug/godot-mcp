extends Control
## Title screen: the sleeping knight in the Moonlit Meadows (TitleBackdrop), the title,
## and the three text-style menu items. "Wake Up" always comes first.

const PROLOGUE := "res://src/cutscenes/prologue.tscn"

@onready var new_game_button: MenuItemButton = %NewGameButton
@onready var continue_button: MenuItemButton = %ContinueButton
@onready var quit_button: MenuItemButton = %QuitButton
@onready var touch_toggle: MenuItemButton = %TouchToggle
@onready var settings_button: MenuItemButton = %SettingsButton
@onready var settings_panel: SettingsPanel = %SettingsPanel
@onready var version_label: Label = %VersionLabel


func _ready() -> void:
	get_tree().paused = false
	version_label.text = _build_text()
	_keep_title_colours()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	new_game_button.pressed.connect(_on_new_game)
	continue_button.pressed.connect(_on_continue)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	continue_button.disabled = not SaveManager.has_save()
	continue_button.focus_mode = Control.FOCUS_NONE if continue_button.disabled else Control.FOCUS_ALL
	quit_button.visible = not OS.has_feature("web")
	# Desktop testing aid: preview the mobile layout with a mouse.
	touch_toggle.visible = not OS.has_feature("mobile")
	touch_toggle.set_pressed_no_signal(Settings.force_touch_controls)
	touch_toggle.hint = "on" if Settings.force_touch_controls else "off"
	touch_toggle.toggled.connect(_on_touch_toggled)
	settings_button.pressed.connect(_open_settings)
	settings_panel.closed.connect(_close_settings)
	new_game_button.grab_focus()


## The title painting keeps its own colours: the gameplay night grade (V8 LUT) is for the 3D world.
## Duplicated so the change does not leak into the shared post-process material.
func _keep_title_colours() -> void:
	var screen := get_node_or_null("PostProcess/Screen") as ColorRect
	if screen == null or not screen.material is ShaderMaterial:
		return
	var mat := screen.material.duplicate() as ShaderMaterial
	mat.set_shader_parameter("grade_amount", 0.0)
	screen.material = mat


## "V7 - build 2026-11-14 08:40 UTC": the numbered update plus when this pack was exported, so a
## phone shows at a glance whether it runs the newest build (tools/export_web.sh sets the stamp).
func _build_text() -> String:
	var label := str(ProjectSettings.get_setting("application/config/build_label", "dev"))
	var stamp := str(ProjectSettings.get_setting("application/config/build_stamp", ""))
	if stamp.length() < 16 or stamp == "dev":
		return label
	return "%s  -  build %s %s UTC" % [label, stamp.substr(0, 10), stamp.substr(11, 5)]


func _on_new_game() -> void:
	GameState.new_game()
	SceneLoader.change_scene(PROLOGUE, 1.2)


func _on_continue() -> void:
	SaveManager.load_game()


func _on_touch_toggled(pressed: bool) -> void:
	touch_toggle.hint = "on" if pressed else "off"
	Settings.force_touch_controls = pressed
	Settings.save_settings()


## The panel covers the title menu; its items are hidden so focus cannot wander behind it.
func _open_settings() -> void:
	$Ui/Buttons.hide()
	touch_toggle.hide()
	settings_panel.open()


func _close_settings() -> void:
	$Ui/Buttons.show()
	touch_toggle.visible = not OS.has_feature("mobile")
	settings_button.grab_focus()
