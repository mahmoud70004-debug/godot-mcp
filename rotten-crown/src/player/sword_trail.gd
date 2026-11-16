class_name SwordTrail
extends MeshInstance3D
## V24: a faint pale ribbon that follows the blade through a swing and dies out within a fifth of
## a second. World space (top_level), so the cut stays where it was made while the view turns.
## One ImmediateMesh, at most ~12 samples = 24 vertices rebuilt per frame, only while a trail lives.

const LIFE := 0.16
const MAX_SAMPLES := 14
## Where on the model (grip at the origin, blade along +Y; the model's own scale applies) the two
## edges of the ribbon sit: the outer fifth of the blade, fading from the point inwards.
const BASE := Vector3(0.0, 0.8, 0.0)
const TIP := Vector3(0.0, 0.95, 0.0)
const COLOR := Color(0.68, 0.8, 1.0)
const ALPHA := 0.34

static var _mat: StandardMaterial3D

var _model: Node3D
var _active := false
var _bases: Array[Vector3] = []
var _tips: Array[Vector3] = []
var _ages: Array[float] = []
var _imm := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	mesh = _imm
	material_override = _material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 4.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(false)


## Begin recording the blade of `model` (the first-person weapon model).
func start(model: Node3D) -> void:
	_model = model
	_active = _model != null
	set_process(_active)


## Stop recording; what was recorded fades out.
func stop() -> void:
	_active = false


func _process(delta: float) -> void:
	for i in range(_ages.size() - 1, -1, -1):
		_ages[i] += delta
		if _ages[i] >= LIFE:
			_bases.remove_at(i)
			_tips.remove_at(i)
			_ages.remove_at(i)
	if _active and is_instance_valid(_model) and _model.is_inside_tree():
		var xf := _model.global_transform
		_bases.append(xf * BASE)
		_tips.append(xf * TIP)
		_ages.append(0.0)
		if _ages.size() > MAX_SAMPLES:
			_bases.pop_front()
			_tips.pop_front()
			_ages.pop_front()
	_imm.clear_surfaces()
	if _ages.size() < 2:
		if not _active and _ages.is_empty():
			set_process(false)
		return
	_imm.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _ages.size():
		var a := pow(1.0 - _ages[i] / LIFE, 1.6) * ALPHA
		_imm.surface_set_color(Color(COLOR, a))
		_imm.surface_add_vertex(_tips[i])
		_imm.surface_set_color(Color(COLOR, 0.0))
		_imm.surface_add_vertex(_bases[i])
	_imm.surface_end()


static func _material() -> StandardMaterial3D:
	if _mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		m.disable_receive_shadows = true
		_mat = m
	return _mat
