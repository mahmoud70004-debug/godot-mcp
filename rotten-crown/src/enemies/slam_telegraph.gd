class_name SlamTelegraph
extends MeshInstance3D
## Ground shadow that marks where a slam will land: grows and darkens over the windup.

const START_RADIUS := 0.2
const FADE_TIME := 0.15
const COLOR_START := Color(0.12, 0.0, 0.0, 0.15)
const COLOR_END := Color(0.04, 0.0, 0.0, 0.7)

var _material := StandardMaterial3D.new()
var _tween: Tween


func _init() -> void:
	# Grows by tween in idle time: keep it out of physics interpolation (it would trail the blow).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.01
	disc.radial_segments = 24
	disc.rings = 1
	mesh = disc
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = COLOR_START
	_material.render_priority = 1
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scale = Vector3(START_RADIUS, 1.0, START_RADIUS)


## Call after the node is in the tree.
func grow(radius: float, duration: float) -> void:
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "scale", Vector3(radius, 1.0, radius), duration)
	_tween.tween_property(_material, "albedo_color", COLOR_END, duration)


func fade_and_free() -> void:
	_kill_tween()
	_tween = create_tween()
	var clear := COLOR_END
	clear.a = 0.0
	_tween.tween_property(_material, "albedo_color", clear, FADE_TIME)
	_tween.tween_callback(queue_free)


func _kill_tween() -> void:
	if _tween:
		_tween.kill()
