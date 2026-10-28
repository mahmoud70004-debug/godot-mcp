extends Node3D
## Preview of a PixelSprite3D on a ground plane under gloomy light.
##   RC_ORBIT=degrees (camera angle around the sprite)  RC_ANIM=idle|walk|...  RC_CHAR=hollow

const DISTANCE := 6.0
const HEIGHT := 1.6

var _cam: Camera3D
var _sprite: PixelSprite3D


func _ready() -> void:
	var char_name := OS.get_environment("RC_CHAR")
	if char_name == "":
		char_name = "hollow"
	_sprite = $PixelSprite3D as PixelSprite3D
	_sprite.sheet = load("res://assets/sprites/%s/%s.tres" % [char_name, char_name]) as SpriteSheetData
	var anim_name := OS.get_environment("RC_ANIM")
	if anim_name != "":
		_sprite.anim = StringName(anim_name)
	_cam = $Camera3D as Camera3D
	var orbit := OS.get_environment("RC_ORBIT")
	var angle := deg_to_rad(orbit.to_float()) if orbit != "" else 0.0
	_cam.position = Vector3(sin(angle) * DISTANCE, HEIGHT, cos(angle) * DISTANCE)
	_cam.look_at(Vector3(0, 1.1, 0))
