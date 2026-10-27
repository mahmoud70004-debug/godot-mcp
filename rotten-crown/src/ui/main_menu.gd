extends Control
## Title screen.

const PROLOGUE := "res://src/cutscenes/prologue.tscn"

@onready var title: Label = %Title
@onready var new_game_button: Button = %NewGameButton
@onready var continue_button: Button = %ContinueButton
@onready var quit_button: Button = %QuitButton
@onready var touch_toggle: CheckButton = %TouchToggle

var _t := 0.0
var _title_x := 0.0


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	new_game_button.pressed.connect(_on_new_game)
	continue_button.pressed.connect(_on_continue)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	continue_button.disabled = not SaveManager.has_save()
	quit_button.visible = not OS.has_feature("web")
	# Desktop testing aid: preview the mobile layout with a mouse.
	touch_toggle.visible = not OS.has_feature("mobile")
	touch_toggle.button_pressed = Settings.force_touch_controls
	touch_toggle.toggled.connect(_on_touch_toggled)
	new_game_button.grab_focus()
	_title_x = title.position.x


func _process(delta: float) -> void:
	_t += delta
	# The title breathes, and every few seconds it flinches.
	var flinch := 1.0 if fmod(_t, 7.3) < 0.08 else 0.0
	title.modulate = Color(1, 1, 1, 0.82 + sin(_t * 1.3) * 0.12 - flinch * 0.5)
	title.position.x = _title_x + (randf_range(-2.0, 2.0) if flinch > 0.0 else 0.0)


func _on_new_game() -> void:
	GameState.new_game()
	SceneLoader.change_scene(PROLOGUE, 1.2)


func _on_continue() -> void:
	SaveManager.load_game()


func _on_touch_toggled(pressed: bool) -> void:
	Settings.force_touch_controls = pressed
	Settings.save_settings()
