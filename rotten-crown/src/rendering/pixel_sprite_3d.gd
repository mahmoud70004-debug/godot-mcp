class_name PixelSprite3D
extends Sprite3D
## Billboarded pixel-art character that shows the pre-rendered frame matching the view direction.

signal animation_finished(anim: StringName)

@export var sheet: SpriteSheetData:
	set(value):
		sheet = value
		_apply_sheet()
@export var anim: StringName = &"idle":
	set(value):
		anim = value
		_refresh_anim_info()
@export var speed_scale := 1.0
## >= 0 always shows that baked direction (e.g. a pose that must not flip as the camera moves).
@export var fixed_direction := -1

var _time := 0.0
var _finished := false
var _flash_tween: Tween
# Cached info of the current anim (refreshed when anim or sheet changes).
var _has_info := false
var _frames := 1
var _fps := 1.0
var _loop := true
var _row := 0
var _last_region_key := -1


func _ready() -> void:
	_apply_sheet()
	_update_region()


func _process(delta: float) -> void:
	if not _has_info:
		return
	if not _finished:
		_time += delta * speed_scale
		if not _loop and _time * _fps >= _frames:
			_finished = true
			_time = (_frames - 1) / maxf(_fps, 0.001)
			animation_finished.emit(anim)
	_update_region()


func play(anim_name: StringName, restart := false) -> void:
	if anim_name == anim and not restart:
		return
	anim = anim_name
	_refresh_anim_info()
	_time = 0.0
	_finished = false
	_update_region()


func get_direction_index() -> int:
	if sheet == null:
		return 0
	if fixed_direction >= 0:
		return fixed_direction % sheet.directions
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0
	var local := global_basis.inverse() * (cam.global_position - global_position)
	local.y = 0.0
	return SpriteSheetData.direction_index(local, sheet.directions)


func flash(color := Color(1, 0.2, 0.15), time := 0.15) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color.WHITE, time)


func _apply_sheet() -> void:
	if sheet == null:
		return
	texture = sheet.texture
	pixel_size = sheet.pixel_size
	region_enabled = true
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	shaded = true
	double_sided = true
	centered = true
	# Centre horizontally; lift so the feet (foot_offset_px above the frame bottom) sit at the origin.
	offset = Vector2(0.0, sheet.frame_size.y * 0.5 - sheet.foot_offset_px)
	_refresh_anim_info()


func _refresh_anim_info() -> void:
	_has_info = false
	_last_region_key = -1
	if sheet == null:
		return
	var info: Dictionary = sheet.anims.get(anim, {})
	if info.is_empty():
		return
	_frames = maxi(int(info["frames"]), 1)
	_fps = float(info["fps"])
	_loop = bool(info["loop"])
	_row = int(info["row"])
	_has_info = true


func _update_region() -> void:
	if not _has_info:
		return
	var step := int(_time * _fps)
	var frame := step % _frames if _loop else clampi(step, 0, _frames - 1)
	var row := _row + get_direction_index()
	var key := row * 4096 + frame
	if key == _last_region_key:
		return
	_last_region_key = key
	region_rect = Rect2(
		Vector2(frame * sheet.frame_size.x, row * sheet.frame_size.y), Vector2(sheet.frame_size)
	)
