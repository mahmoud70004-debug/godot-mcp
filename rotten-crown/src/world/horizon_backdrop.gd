@tool
class_name HorizonBackdrop
extends Node3D
## Painted silhouette layers (rolling hills, crags, ruined spires) that stay
## centred on the active camera, so they always read as the far horizon no
## matter how far the player walks across the kingdom. Unshaded and fog-free
## (silhouette.gdshader), three meshes in total.

const SILHOUETTE_SHADER := preload("res://assets/shaders/silhouette.gdshader")

@export var seed := 1337
## Nearest layer first: base colour, top colour.
@export var horizon_colors: Array[Color] = [
	Color(0.025, 0.035, 0.025), Color(0.07, 0.085, 0.06),
	Color(0.05, 0.06, 0.045), Color(0.12, 0.13, 0.1),
	Color(0.09, 0.1, 0.08), Color(0.2, 0.21, 0.16),
]
@export var follow_camera := true
## Vertical offset applied to the rings (sink them below the terrain hills).
@export var base_height := -2.0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for child in get_children():
		child.free()
	_rng.seed = seed
	_build_horizon()


func _process(_delta: float) -> void:
	if not follow_camera or Engine.is_editor_hint():
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = Vector3(cam.global_position.x, base_height, cam.global_position.z)


func _group(group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	add_child(node)
	return node


## Three rings of painted silhouettes: rolling hills, crags and ruined spires.
func _build_horizon() -> void:
	var horizon := _group("Horizon")
	var layers := [
		{"radius": 95.0, "height": 9.0, "rough": 5.0, "spires": 4},
		{"radius": 120.0, "height": 16.0, "rough": 9.0, "spires": 7},
		{"radius": 145.0, "height": 26.0, "rough": 14.0, "spires": 0},
	]
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.9
	for li in layers.size():
		var layer: Dictionary = layers[li]
		var radius: float = layer["radius"]
		var height: float = layer["height"]
		var rough: float = layer["rough"]
		var mat := ShaderMaterial.new()
		mat.shader = SILHOUETTE_SHADER
		mat.set_shader_parameter("base_color", horizon_colors[(li * 2) % horizon_colors.size()])
		mat.set_shader_parameter("top_color", horizon_colors[(li * 2 + 1) % horizon_colors.size()])
		mat.set_shader_parameter("top_height", height + rough)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segments := 160
		var prev_top := Vector3.ZERO
		var prev_bottom := Vector3.ZERO
		for i in segments + 1:
			var a := TAU * float(i) / segments
			var ridge := height + noise.get_noise_2d(cos(a) * 3.0 + li * 10.0, sin(a) * 3.0) * rough
			ridge += absf(noise.get_noise_2d(a * 9.0, li * 5.0)) * rough * 0.6
			var top := Vector3(sin(a) * radius, maxf(ridge, 1.0), cos(a) * radius)
			var bottom := Vector3(sin(a) * radius, -2.0, cos(a) * radius)
			if i > 0:
				st.add_vertex(prev_bottom)
				st.add_vertex(prev_top)
				st.add_vertex(top)
				st.add_vertex(prev_bottom)
				st.add_vertex(top)
				st.add_vertex(bottom)
			prev_top = top
			prev_bottom = bottom
		# Ruined spires and jagged crags standing on the ridge.
		for i in int(layer["spires"]):
			var a := _rng.randf() * TAU
			var base := Vector3(sin(a) * radius, height * 0.6, cos(a) * radius)
			var side := Vector3(cos(a), 0.0, -sin(a))
			var w := _rng.randf_range(1.5, 4.0)
			var tall := height + _rng.randf_range(8.0, 22.0)
			var tip := base + Vector3(0.0, tall, 0.0) + side * _rng.randf_range(-1.0, 1.0)
			st.add_vertex(base - side * w)
			st.add_vertex(tip)
			st.add_vertex(base + side * w)
			# A broken shoulder beside the spire.
			st.add_vertex(base + side * w)
			st.add_vertex(base + side * (w * 2.5) + Vector3(0.0, tall * 0.45, 0.0))
			st.add_vertex(base + side * (w * 3.5))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		horizon.add_child(mi)
