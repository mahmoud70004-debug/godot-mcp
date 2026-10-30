class_name UiSafeArea
extends RefCounted
## Screen-edge margins for UI, in UI units (the stretched 640x360-and-up space).
## On the web build the launch shell publishes the browser's safe-area insets (notch,
## rounded corners, gesture bar) as window.rcSafe in CSS pixels; they are converted
## to UI units here. Elsewhere the insets come from DisplayServer.get_display_safe_area().
##   UiSafeArea.bottom_margin()  distance a bottom-anchored element (subtitles, prompts,
##                               dialogue) should keep from the bottom edge, never below MIN_MARGIN
##   UiSafeArea.top_margin() / left_margin() / right_margin()  likewise
##   UiSafeArea.inset_control(c) offsets an edge-anchored Control by the raw insets
## Controls that were laid out with their own margin call inset_control(); new bottom bands
## (dialogue) anchor to the bottom and use bottom_margin() as their offset.

## Smallest gap kept from any screen edge, in UI units.
const MIN_MARGIN := 6.0
const _REFRESH_FRAMES := 20
const _BASE_META := &"_safe_base_offsets"

static var _cache_frame := -1000
static var _cache_size := Vector2.ZERO
static var _insets := Vector4.ZERO  # left, top, right, bottom (UI units)


## Raw safe-area insets (left, top, right, bottom) in UI units; zero on desktop.
static func insets() -> Vector4:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return Vector4.ZERO
	var size := tree.root.get_visible_rect().size
	var frame := Engine.get_process_frames()
	if frame - _cache_frame < _REFRESH_FRAMES and size == _cache_size:
		return _insets
	_cache_frame = frame
	_cache_size = size
	_insets = _read_insets(size)
	return _insets


static func bottom_margin() -> float:
	return maxf(MIN_MARGIN, insets().w)


static func top_margin() -> float:
	return maxf(MIN_MARGIN, insets().y)


static func left_margin() -> float:
	return maxf(MIN_MARGIN, insets().x)


static func right_margin() -> float:
	return maxf(MIN_MARGIN, insets().z)


## Rectangle of the viewport (UI units) that is safe to draw UI in, MIN_MARGIN respected.
static func safe_rect() -> Rect2:
	var size := Engine.get_main_loop().root.get_visible_rect().size as Vector2
	var left := left_margin()
	var top := top_margin()
	return Rect2(left, top, size.x - left - right_margin(), size.y - top - bottom_margin())


## Pushes an edge-anchored Control inward by the raw insets (its own scene margin stays).
## Safe to call repeatedly; the scene's original offsets are remembered in metadata.
static func inset_control(control: Control) -> void:
	if not control.has_meta(_BASE_META):
		control.set_meta(_BASE_META, Vector4(control.offset_left, control.offset_top, control.offset_right, control.offset_bottom))
	var base: Vector4 = control.get_meta(_BASE_META)
	var ins := insets()
	control.offset_left = base.x + _shift(control.anchor_left, ins.x, ins.z)
	control.offset_top = base.y + _shift(control.anchor_top, ins.y, ins.w)
	control.offset_right = base.z + _shift(control.anchor_right, ins.x, ins.z)
	control.offset_bottom = base.w + _shift(control.anchor_bottom, ins.y, ins.w)


## Offset shift for one edge: inward from the near side when anchored there, from the far side otherwise.
static func _shift(anchor: float, near_inset: float, far_inset: float) -> float:
	if anchor < 0.5:
		return near_inset
	if anchor > 0.5:
		return -far_inset
	return 0.0


static func _read_insets(size: Vector2) -> Vector4:
	if OS.has_feature("web"):
		var raw: Variant = JavaScriptBridge.eval(
			"(function(){var s=window.rcSafe;if(!s)return '';return [s.left,s.top,s.right,s.bottom,window.innerWidth,window.innerHeight].join(',');})()", true)
		var parts := str(raw).split(",")
		if parts.size() < 6:
			return Vector4.ZERO
		var css_w := maxf(parts[4].to_float(), 1.0)
		var css_h := maxf(parts[5].to_float(), 1.0)
		var kx := size.x / css_w
		var ky := size.y / css_h
		return Vector4(parts[0].to_float() * kx, parts[1].to_float() * ky, parts[2].to_float() * kx, parts[3].to_float() * ky)
	var window := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if window.x <= 0 or window.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	# Native: the safe area is in screen pixels; assume the window fills the screen.
	var screen := DisplayServer.screen_get_size()
	if screen.x <= 0 or screen.y <= 0:
		return Vector4.ZERO
	var sx := size.x / screen.x
	var sy := size.y / screen.y
	return Vector4(
		maxf(safe.position.x, 0) * sx, maxf(safe.position.y, 0) * sy,
		maxf(screen.x - safe.end.x, 0) * sx, maxf(screen.y - safe.end.y, 0) * sy)
