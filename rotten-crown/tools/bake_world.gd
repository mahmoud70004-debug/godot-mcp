extends Node
## Offline world bake: runs the @tool builders once and saves their output as
## binary scenes, so phones never run procedural generation.
##   GODOT=... tools/bake_world.sh            (both)
##   RC_BAKE=overworld|prologue                (one)
## Outputs: src/levels/valdron/baked/overworld_world.scn, prologue_world.scn

const OUT_DIR := "res://src/levels/valdron/baked/"


func _ready() -> void:
	var what := OS.get_environment("RC_BAKE")
	if what == "" or what == "overworld":
		var root := _new_root("OverworldWorld")
		OverworldBuilder.build(root)
		await _finish(root, OUT_DIR + "overworld_world.scn")
	if what == "" or what == "prologue":
		var root := _new_root("PrologueWorld")
		var ward := OuterWardBlockout.new()
		_copy_scene_props("res://src/cutscenes/prologue.tscn", "Blockout", ward)
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


## Copies the exported property overrides of `node_name` in a .tscn (without
## instancing it, so the cutscene director never runs).
func _copy_scene_props(scene_path: String, node_name: String, target: Node) -> void:
	var state := (load(scene_path) as PackedScene).get_state()
	for i in state.get_node_count():
		if state.get_node_name(i) != node_name:
			continue
		for j in state.get_node_property_count(i):
			var prop := state.get_node_property_name(i, j)
			if prop != &"script":
				target.set(prop, state.get_node_property_value(i, j))


func _finish(root: Node3D, path: String) -> void:
	await get_tree().process_frame
	var stats := _finalize(root)
	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS)
	print("%s: %s | %d mesh instances, %d triangle verts, %d grass instances, %d lights" % [
		path, error_string(err), stats["meshes"], stats["verts"], stats["grass"], stats["lights"]])
	root.queue_free()


## Strips builder scripts (they would rebuild on load), drops the mesh data of
## merged originals (keeping their colliders) and gathers budget statistics.
func _finalize(root: Node3D) -> Dictionary:
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
		if mi.mesh:
			stats["meshes"] = int(stats["meshes"]) + 1
			stats["verts"] = int(stats["verts"]) + mi.mesh.get_faces().size()
	for node in root.find_children("*", "MultiMeshInstance3D", true, false):
		stats["grass"] = int(stats["grass"]) + (node as MultiMeshInstance3D).multimesh.instance_count
	stats["lights"] = root.find_children("*", "Light3D", true, false).size()
	return stats


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		if child.is_queued_for_deletion():
			continue
		child.owner = owner_node
		_own(child, owner_node)
