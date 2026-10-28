class_name PixelSprite3D
extends Sprite3D
## Billboarded pixel-art character that shows the pre-rendered frame matching the view direction.

signal animation_finished(anim: StringName)

@export var sheet: SpriteSheetData:
	set(value):
		sheet = value
		_apply_sheet()
@export var anim: StringName = &"idle"
@export var speed_scale := 1.0

var _time := 0.0
var _finished := false
var _flash_tween: Tween


func _ready() -> void:
	_apply_sheet()
	_update_region()


func _process(delta: float) -> void:
	if sheet == null:
		return
	var info: Dictionary = sheet.anims.get(anim, {})
	if info.is_empty():
		return
	var frames: int = info["frames"]
	var fps: float = info["fps"]
	if not _finished:
		_time += delta * speed_scale
		if not bool(info["loop"]) and _time * fps >= frames:
			_finished = true
			_time = (frames - 1) / maxf(fps, 0.001)
			animation_finished.emit(anim)
	_update_region()


func play(anim_name: StringName, restart := false) -> void:
	if anim_name == anim and not restart:
		return
	anim = anim_name
	_time = 0.0
	_finished = false
	_update_region()


func get_direction_index() -> int:
	if sheet == null:
		return 0
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


func _update_region() -> void:
	if sheet == null:
		return
	var info: Dictionary = sheet.anims.get(anim, {})
	if info.is_empty():
		return
	var frames: int = info["frames"]
	var frame := clampi(int(_time * float(info["fps"])), 0, frames - 1)
	if bool(info["loop"]):
		frame = int(_time * float(info["fps"])) % frames
	var row: int = int(info["row"]) + get_direction_index()
	region_rect = Rect2(
		Vector2(frame * sheet.frame_size.x, row * sheet.frame_size.y), Vector2(sheet.frame_size)
	)
