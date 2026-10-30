extends Node
## Diagnostics for web builds, enabled by opening the page with ?debug=1.
## - Publishes live state to window.rcState so browser tests can assert on
##   it (see tools/web_touch_repro.cjs).
## - Shows a small on-screen readout (FPS, player, touch roles) so testers
##   can describe bugs precisely.
## Also publishes rcState.render (draw calls, primitives, process/physics ms, video memory), refreshed with the
## rest of the state every 0.1 s.
## Disabled (and free) in normal play and on non-web platforms.

var enabled := false

var _providers: Dictionary = {}
var _label: Label
var _accum := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		enabled = str(search).contains("debug")
	set_process(enabled)
	if not enabled:
		return
	var layer := CanvasLayer.new()
	layer.layer = 99
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 32)
	_label.add_theme_font_size_override("font_size", 19)
	_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.5))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_label)


## Registers a Callable returning JSON-friendly data under [param key].
func register(key: String, provider: Callable) -> void:
	_providers[key] = provider


func _process(delta: float) -> void:
	_accum += delta
	if _accum < 0.1:
		return
	_accum = 0.0
	var state := {"fps": Engine.get_frames_per_second(), "scene": str(get_tree().current_scene.name) if get_tree().current_scene else ""}
	var vp := get_viewport()
	state["screen"] = {
		"ui": [vp.get_visible_rect().size.x, vp.get_visible_rect().size.y],
		"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
	}
	state["render"] = {
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1.0e6, 0.1),
	}
	for key in _providers.keys():
		var provider: Callable = _providers[key]
		if provider.is_valid():
			state[key] = provider.call()
		else:
			_providers.erase(key)
	JavaScriptBridge.eval("window.rcState = %s;" % JSON.stringify(state))
	_label.text = JSON.stringify(state)
