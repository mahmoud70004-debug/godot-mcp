extends Node
## Player-facing options, persisted to user://settings.cfg.

const SETTINGS_PATH := "user://settings.cfg"

## Degrees of rotation per viewport pixel dragged on the look area.
var look_sensitivity_touch := 0.28
## Degrees of rotation per pixel of captured mouse motion (desktop testing).
var look_sensitivity_mouse := 0.12
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


func _ready() -> void:
	load_settings()
	apply_audio()


func uses_touch_controls() -> bool:
	return force_touch_controls or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


func apply_audio() -> void:
	_set_bus_volume(&"Master", master_volume)
	_set_bus_volume(&"Music", music_volume)
	_set_bus_volume(&"SFX", sfx_volume)
	_set_bus_volume(&"Ambience", ambience_volume)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "look_sensitivity_touch", look_sensitivity_touch)
	cfg.set_value("controls", "look_sensitivity_mouse", look_sensitivity_mouse)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "force_touch_controls", force_touch_controls)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "ambience", ambience_volume)
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "quality_auto_checked", quality_auto_checked)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	look_sensitivity_touch = cfg.get_value("controls", "look_sensitivity_touch", look_sensitivity_touch)
	look_sensitivity_mouse = cfg.get_value("controls", "look_sensitivity_mouse", look_sensitivity_mouse)
	invert_y = cfg.get_value("controls", "invert_y", invert_y)
	force_touch_controls = cfg.get_value("controls", "force_touch_controls", force_touch_controls)
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	ambience_volume = cfg.get_value("audio", "ambience", ambience_volume)
	quality = clampi(int(cfg.get_value("graphics", "quality", quality)), 0, 2)
	quality_auto_checked = cfg.get_value("graphics", "quality_auto_checked", quality_auto_checked)


func _set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
