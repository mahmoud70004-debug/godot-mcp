extends Node
## Diagnostics for web builds, enabled by opening the page with ?debug=1.
## - Publishes live state to window.rcState so browser tests can assert on
##   it (see tools/web_touch_repro.cjs).
## - Shows a small on-screen readout (FPS, player, touch roles) so testers
##   can describe bugs precisely.
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
	_label.position = Vector2(4, 30)
	_label.add_theme_font_size_override("font_size", 8)
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
	for key in _providers.keys():
		var provider: Callable = _providers[key]
		if provider.is_valid():
			state[key] = provider.call()
		else:
			_providers.erase(key)
	JavaScriptBridge.eval("window.rcState = %s;" % JSON.stringify(state))
	_label.text = JSON.stringify(state)
