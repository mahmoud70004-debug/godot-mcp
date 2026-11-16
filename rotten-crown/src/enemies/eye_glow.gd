class_name EyeGlow
extends Node3D
## V24: two dim eyes that shine out of the dark before the body can be made out. No jump scare:
## they only breathe and blink, fade in from 4 m to 11 m (the sprite shows its own face closer
## than that) and out again past ~28 m, and go out with the creature (the fog takes them first).
## Two billboards sharing one additive material; the fade is each instance's own transparency.

const NEAR_FADE := Vector2(4.0, 11.0)
const FAR_FADE := Vector2(26.0, 34.0)
const SIZE := 0.16

static var _mat: StandardMaterial3D

var _enemy: Enemy
var _player: Node3D
var _eyes: Array[MeshInstance3D] = []
var _clock := 0.0
var _blink := 0.0
var _next_blink := 3.0
var _phase := randf() * TAU
## Eyes grow with distance so they stay a readable point of light far off (1 near .. 2.2 far).
var _dist_scale := 1.0


func setup(enemy: Enemy, data: EnemyData) -> void:
	_enemy = enemy
	position = Vector3(0.0, data.eye_height, 0.0)
	for side in [-1.0, 1.0]:
		var quad := QuadMesh.new()
		quad.size = Vector2(SIZE, SIZE)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = _material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(side * data.eye_spacing * 0.5, 0.0, -0.12)
		add_child(mi)
		_eyes.append(mi)
	_tint(data.eye_color)
	visible = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _tint(colour: Color) -> void:
	# One material per colour would split the batch; the eyes keep the shared material and take their
	# colour from a vertex colour on the mesh.
	for mi in _eyes:
		var quad := mi.mesh as QuadMesh
		var arrays := quad.get_mesh_arrays()
		var cols := PackedColorArray()
		cols.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		cols.fill(colour)
		arrays[Mesh.ARRAY_COLOR] = cols
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mi.mesh = mesh


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	set_process(_player != null)


func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0:
		_animate(delta)
		return
	_clock = 0.1
	if _enemy == null or _enemy.state == Enemy.State.DEAD or _player == null:
		visible = false
		return
	var d := _enemy.global_position.distance_to(_player.global_position)
	var fade := smoothstep(NEAR_FADE.x, NEAR_FADE.y, d) * (1.0 - smoothstep(FAR_FADE.x, FAR_FADE.y, d))
	visible = fade > 0.02
	_dist_scale = 1.0 + clampf((d - 8.0) / 20.0, 0.0, 1.0) * 1.2
	for mi in _eyes:
		mi.transparency = 1.0 - fade * 0.9


func _animate(delta: float) -> void:
	if not visible:
		return
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink = 0.16
		_next_blink = randf_range(2.5, 6.5)
	var open := 1.0
	if _blink > 0.0:
		_blink -= delta
		open = 0.1
	var breathe := (0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.0021 + _phase)) * open
	for mi in _eyes:
		mi.scale = Vector3(breathe, breathe * (0.55 + 0.45 * open), 1.0) * _dist_scale


static func _material() -> StandardMaterial3D:
	if _mat == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 16
		tex.height = 16
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = tex
		m.disable_receive_shadows = true
		_mat = m
	return _mat
