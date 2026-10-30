extends CanvasLayer
## Performance readout for phone testing: current FPS, 1% low and average frame time over a
## rolling window, draw calls and the quality level. Shown when Settings.show_fps is on
## (pause menu toggle) or the web page was opened with ?fps=1. Frame deltas are measured with
## Time.get_ticks_usec between _process calls into a fixed ring buffer; the labels are only
## rewritten on the 0.5 s tick, so the overlay allocates nothing per frame.

const REFRESH_SECONDS := 0.5
const WINDOW_SECONDS := 5.0
const RING_SIZE := 2048
const FONT_SIZE := 12
const TOP_OFFSET := 34.0
const GOOD_FPS := 55.0
const OK_FPS := 30.0
const COLOR_GOOD := Color(0.663, 0.753, 0.306)
const COLOR_OK := Color(0.9, 0.7, 0.25)
const COLOR_BAD := Color(0.85, 0.32, 0.27)
const COLOR_MUTED := Color(0.604, 0.616, 0.545)
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High"]

## True when the web page was opened with ?fps=1: the overlay stays on regardless of the setting.
var forced := false

var _enabled := false
var _ring := PackedFloat32Array()
var _scratch := PackedFloat32Array()
var _stamps := PackedInt64Array()
var _head := 0
var _count := 0
var _last_usec := 0
var _accum := 0.0
var _box: PanelContainer
var _fps_label: Label
var _low_label: Label
var _draw_label: Label


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ring.resize(RING_SIZE)
	_scratch.resize(RING_SIZE)
	_stamps.resize(RING_SIZE)
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		forced = str(search).contains("fps=1")
	_build()
	get_viewport().size_changed.connect(_place)
	refresh_enabled()


## Re-reads Settings.show_fps (call after the toggle changes).
func refresh_enabled() -> void:
	_enabled = forced or Settings.show_fps
	_box.visible = _enabled
	set_process(_enabled)
	if _enabled:
		_place()
		_last_usec = Time.get_ticks_usec()
		_head = 0
		_count = 0
		_accum = 0.0
		_refresh_labels()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := float(now - _last_usec) * 0.000001
	_last_usec = now
	_ring[_head] = dt
	_stamps[_head] = now
	_head = (_head + 1) % RING_SIZE
	_count = mini(_count + 1, RING_SIZE)
	_accum += dt
	if _accum < REFRESH_SECONDS:
		return
	_accum = 0.0
	_refresh_labels()


func _build() -> void:
	_box = PanelContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.anchor_left = 1.0
	_box.anchor_right = 1.0
	_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.025, 0.02, 0.55)
	style.set_content_margin_all(4.0)
	_box.add_theme_stylebox_override("panel", style)
	add_child(_box)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	_box.add_child(column)
	_fps_label = _make_label(column)
	_low_label = _make_label(column)
	_draw_label = _make_label(column)
	_low_label.add_theme_color_override("font_color", COLOR_MUTED)
	_draw_label.add_theme_color_override("font_color", COLOR_MUTED)
	_fps_label.text = "-- FPS"


func _make_label(parent: Control) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	parent.add_child(label)
	return label


func _place() -> void:
	if _box == null:
		return
	_box.offset_right = -UiSafeArea.right_margin()
	_box.offset_left = _box.offset_right
	_box.offset_top = TOP_OFFSET + UiSafeArea.insets().y
	_box.offset_bottom = _box.offset_top


func _refresh_labels() -> void:
	var now := Time.get_ticks_usec()
	var recent_sum := 0.0
	var recent_n := 0
	var window_n := 0
	var window_sum := 0.0
	var recent_cut := now - int(REFRESH_SECONDS * 1000000.0)
	var window_cut := now - int(WINDOW_SECONDS * 1000000.0)
	for i in _count:
		var idx := (_head - 1 - i + RING_SIZE) % RING_SIZE
		var stamp := _stamps[idx]
		if stamp < window_cut:
			break
		var dt := _ring[idx]
		_scratch[window_n] = dt
		window_n += 1
		window_sum += dt
		if stamp >= recent_cut:
			recent_sum += dt
			recent_n += 1
	var fps := float(recent_n) / recent_sum if recent_sum > 0.0 else 0.0
	_fps_label.text = "%d FPS" % roundi(fps)
	_fps_label.add_theme_color_override("font_color", COLOR_GOOD if fps >= GOOD_FPS else (COLOR_OK if fps >= OK_FPS else COLOR_BAD))
	var low_fps := 0.0
	var avg_ms := 0.0
	if window_n > 0:
		avg_ms = window_sum / float(window_n) * 1000.0
		# Sort only the filled prefix: the 1% low is the frame rate at the 99th percentile frame time.
		var sorted := _scratch.slice(0, window_n)
		sorted.sort()
		var worst := maxf(sorted[clampi(ceili(float(window_n) * 0.99) - 1, 0, window_n - 1)], 0.000001)
		low_fps = 1.0 / worst
	_low_label.text = "1%% low %d  |  %.1f ms" % [roundi(low_fps), avg_ms]
	var draws := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_draw_label.text = "draws %d  |  %s" % [draws, QUALITY_NAMES[clampi(Settings.quality, 0, 2)]]
