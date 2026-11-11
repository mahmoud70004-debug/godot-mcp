extends Node
## Player-facing options, persisted to user://settings.cfg.

const SETTINGS_PATH := "user://settings.cfg"

## Emitted when the controls layout or look options change (the HUD re-lays out at once).
signal controls_changed

## Look sensitivity steps (settings menu); step 2 is the original behaviour.
const LOOK_STEPS: Array[float] = [0.5, 0.75, 1.0, 1.5, 2.0]
const LOOK_STEP_DEFAULT := 2
const BASE_LOOK_TOUCH := 0.28
const BASE_LOOK_MOUSE := 0.12

## Degrees of rotation per viewport pixel dragged on the look area (derived from look_step).
var look_sensitivity_touch := BASE_LOOK_TOUCH
## Degrees of rotation per pixel of captured mouse motion (derived from look_step).
var look_sensitivity_mouse := BASE_LOOK_MOUSE
## Index into LOOK_STEPS.
var look_step := LOOK_STEP_DEFAULT
## Mirror the touch layout: joystick bottom-right, buttons bottom-left, look zone on the left.
var swap_controls := false
## Degrees per second at full right-stick deflection.
var look_speed_gamepad := 140.0
var invert_y := false
## Show the on-screen controls even without a touchscreen (desktop testing).
var force_touch_controls := false
var master_volume := 1.0
var music_volume := 0.8
var sfx_volume := 1.0
var ambience_volume := 0.9
## Graphics quality: 0 Low, 1 Medium, 2 High.
var quality := 1
## The one-time FPS probe has run on this install.
var quality_auto_checked := false
## The player picked a quality in the pause menu: automatic downgrades stop.
var quality_manual := false
## Show the FPS / frame time overlay (pause menu toggle; the web page can force it with ?fps=1).
var show_fps := false


func _ready() -> void:
	load_settings()
	apply_audio()


func set_look_step(step: int) -> void:
	look_step = clampi(step, 0, LOOK_STEPS.size() - 1)
	look_sensitivity_touch = BASE_LOOK_TOUCH * LOOK_STEPS[look_step]
	look_sensitivity_mouse = BASE_LOOK_MOUSE * LOOK_STEPS[look_step]


func uses_touch_controls() -> bool:
	return force_touch_controls or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


func apply_audio() -> void:
	_set_bus_volume(&"Master", master_volume)
	_set_bus_volume(&"Music", music_volume)
	_set_bus_volume(&"SFX", sfx_volume)
	_set_bus_volume(&"Ambience", ambience_volume)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "look_step", look_step)
	cfg.set_value("controls", "swap_controls", swap_controls)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "force_touch_controls", force_touch_controls)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "ambience", ambience_volume)
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "quality_auto_checked", quality_auto_checked)
	cfg.set_value("graphics", "quality_manual", quality_manual)
	cfg.set_value("graphics", "show_fps", show_fps)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	set_look_step(int(cfg.get_value("controls", "look_step", look_step)))
	swap_controls = cfg.get_value("controls", "swap_controls", swap_controls)
	invert_y = cfg.get_value("controls", "invert_y", invert_y)
	force_touch_controls = cfg.get_value("controls", "force_touch_controls", force_touch_controls)
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	ambience_volume = cfg.get_value("audio", "ambience", ambience_volume)
	quality = clampi(int(cfg.get_value("graphics", "quality", quality)), 0, 2)
	quality_auto_checked = cfg.get_value("graphics", "quality_auto_checked", quality_auto_checked)
	quality_manual = cfg.get_value("graphics", "quality_manual", quality_manual)
	show_fps = cfg.get_value("graphics", "show_fps", show_fps)


func _set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
