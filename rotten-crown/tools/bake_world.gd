extends Node
## Offline world bake: runs the @tool builders once and saves their output as
## binary scenes, so phones never run procedural generation.
##   GODOT=... tools/bake_world.sh            (both)
##   RC_BAKE=overworld|prologue                (one)
## Outputs: src/levels/valdron/baked/overworld_world.scn, prologue_world.scn

const OUT_DIR := "res://src/levels/valdron/baked/"
## Overworld meshes left unmerged (single props, shafts, gore) stop drawing
## beyond this; the fog hides them long before.
const OVERWORLD_DEFAULT_RANGE := 110.0
## Shadow stand-ins (MeshMerger.build_shadow_proxies): square size, and the longest moon
## shadow distance any quality level uses (QualityManager High, valdron_overworld.tscn).
const SHADOW_PROXY_CELL := 40.0
const SHADOW_MAX_DISTANCE := 40.0
## Grass MultiMesh chunks drawn together (3x3 per draw call, GrassScatter.merge_chunks).
const GRASS_MERGE := 3
## Ground chunks are joined 2x2 (64 -> 128 m) where the light budget allows.
const TERRAIN_CELL := 128.0


func _ready() -> void:
	var what := OS.get_environment("RC_BAKE")
	if what == "" or what == "overworld":
		var root := _new_root("OverworldWorld")
		OverworldBuilder.build(root)
		await _finish(root, OUT_DIR + "overworld_world.scn", OVERWORLD_DEFAULT_RANGE)
	if what == "" or what == "prologue":
		var root := _new_root("PrologueWorld")
		var ward := OuterWardBlockout.new()
		# The night of the feast (palette of the first concept painting).
		ward.festive = true
		ward.horizon_colors = [Color(0.01, 0.02, 0.06), Color(0.04, 0.07, 0.17), Color(0.03, 0.05, 0.14),
			Color(0.08, 0.13, 0.3), Color(0.06, 0.1, 0.25), Color(0.15, 0.24, 0.5)]
		ward.grass_tip = Color(0.12, 0.3, 0.22)
		ward.name = "Blockout"
		root.add_child(ward)
		await _finish(root, OUT_DIR + "prologue_world.scn")
	print("WORLD_BAKE_DONE")
	get_tree().quit()


func _new_root(root_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = root_name
	add_child(root)
	return root


func _finish(root: Node3D, path: String, default_range := 0.0) -> void:
	await get_tree().process_frame
	var stats := _finalize(root, default_range)
	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS)
	print("%s: %s | %d mesh instances, %d triangle verts, %d grass instances, %d lights, %d casters in shadow proxies" % [
		path, error_string(err), stats["meshes"], stats["verts"], stats["grass"], stats["lights"], stats.get("shadow_proxied", 0)])
	root.queue_free()


## Strips builder scripts (they would rebuild on load), drops the mesh data of
## merged originals (keeping their colliders), gives every visible mesh still
## without one a visibility range of `default_range` (0 = leave as is) and
## gathers budget statistics.
func _finalize(root: Node3D, default_range: float) -> Dictionary:
	var stats := {"meshes": 0, "verts": 0, "grass": 0, "lights": 0}
	for node in root.find_children("*", "", true, false):
		if node.get_script() == OuterWardBlockout or node.get_script() == HorizonBackdrop:
			node.set_script(null)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.visible:
			if mi.get_child_count() == 0:
				mi.queue_free()
			else:
				mi.mesh = null
			continue
		_cheap_cutout(mi.material_override)
		if default_range > 0.0 and mi.visibility_range_end <= 0.0:
			mi.visibility_range_end = default_range
		if mi.mesh:
			stats["meshes"] = int(stats["meshes"]) + 1
			stats["verts"] = int(stats["verts"]) + mi.mesh.get_faces().size()
	if default_range > 0.0:
		var lights := root.find_children("*", "OmniLight3D", true, false)
		for terrain in root.find_children("Terrain", "Node3D", false, false):
			MeshMerger.merge_children_by_cell(terrain as Node3D, TERRAIN_CELL, lights, MeshMerger.LIGHT_BUDGET)
		GrassScatter.merge_chunks(root, GRASS_MERGE)
		stats["shadow_proxied"] = MeshMerger.build_shadow_proxies(root, SHADOW_PROXY_CELL, SHADOW_MAX_DISTANCE)
	for node in root.find_children("*", "MultiMeshInstance3D", true, false):
		if node.is_queued_for_deletion():
			continue
		stats["grass"] = int(stats["grass"]) + (node as MultiMeshInstance3D).multimesh.instance_count
	stats["lights"] = root.find_children("*", "Light3D", true, false).size()
	_check_light_budget(root)
	return stats


## The Compatibility renderer shades each mesh with at most 8 omni/spot lights
## (rendering/limits/opengl/max_lights_per_object); more and some silently drop out.
## Baked meshes keep room for the moving ones (MeshMerger.LIGHT_BUDGET).
func _check_light_budget(root: Node3D) -> void:
	var limit := MeshMerger.LIGHT_BUDGET
	var lights := root.find_children("*", "OmniLight3D", true, false)
	var worst := 0
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		if not gi.is_visible_in_tree() or gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var box := gi.global_transform * gi.get_aabb()
		var touching := 0
		for l in lights:
			var light := l as OmniLight3D
			var p := light.global_position
			if p.clamp(box.position, box.end).distance_to(p) < light.omni_range:
				touching += 1
		worst = maxi(worst, touching)
		if touching > limit:
			push_warning("light budget: %s touched by %d lights (budget %d)" % [root.get_path_to(gi), touching, limit])
	print("light budget: at most %d baked omni lights on one mesh (budget %d)" % [worst, limit])


## Alpha-cut cards (canopy leaves, ferns) stack in many layers and defeat early-z on
## phone GPUs: light them per vertex and skip shadow receiving. Measured +19% fps in the
## Whispering Wood (web), and the canopy reads darker and calmer, nearer the reference.
func _cheap_cutout(mat: Material) -> void:
	var bm := mat as BaseMaterial3D
	if bm == null or bm.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		return
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	bm.disable_receive_shadows = true


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		if child.is_queued_for_deletion():
			continue
		child.owner = owner_node
		_own(child, owner_node)
