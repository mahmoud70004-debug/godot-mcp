extends Control
## Title screen: the sleeping knight in the Moonlit Meadows (TitleBackdrop), the title,
## and the three text-style menu items. "Wake Up" always comes first.

const PROLOGUE := "res://src/cutscenes/prologue.tscn"

@onready var new_game_button: MenuItemButton = %NewGameButton
@onready var continue_button: MenuItemButton = %ContinueButton
@onready var quit_button: MenuItemButton = %QuitButton
@onready var touch_toggle: MenuItemButton = %TouchToggle


func _ready() -> void:
	get_tree().paused = false
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
	new_game_button.grab_focus()


func _on_new_game() -> void:
	GameState.new_game()
	SceneLoader.change_scene(PROLOGUE, 1.2)


func _on_continue() -> void:
	SaveManager.load_game()


func _on_touch_toggled(pressed: bool) -> void:
	touch_toggle.hint = "on" if pressed else "off"
	Settings.force_touch_controls = pressed
	Settings.save_settings()
