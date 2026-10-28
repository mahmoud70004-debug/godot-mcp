@tool
extends EditorScenePostImport
## Post-import for assets/models/*.glb (CC0 kit, see tools/assets/process_model.py).
## Every material becomes retro-friendly: nearest filtering with mipmaps, no PBR extras,
## alpha cut-outs use scissor (no sorting) and are double sided.
## Wired through each .glb.import (nodes/import_script/path) by tools/assets/write_import.py.

## Per-vertex shading is cheaper under many omni lights on the web renderer; builders may opt in.
const VERTEX_LIT := false


func _post_import(scene: Node) -> Object:
	_walk(scene)
	return scene


func _walk(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var mesh := mi.mesh
		if mesh != null:
			for s in mesh.get_surface_count():
				var m := mesh.surface_get_material(s)
				if m is BaseMaterial3D:
					_retro(m as BaseMaterial3D)
	for c in node.get_children():
		_walk(c)


func _retro(m: BaseMaterial3D) -> void:
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.metallic = 0.0
	m.roughness = maxf(m.roughness, 0.9)
	if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if VERTEX_LIT:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
