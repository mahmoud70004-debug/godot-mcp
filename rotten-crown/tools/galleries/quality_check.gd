extends Node
## Dev check: applies each quality level to visual_test.tscn and prints the state.


func _ready() -> void:
	var scene: Node = (load("res://src/levels/test/visual_test.tscn") as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	if get_tree().get_first_node_in_group(&"grass_chunks") == null:
		# visual_test has no grass; add a synthetic chunk so the density path is exercised.
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = QuadMesh.new()
		mm.instance_count = 100
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = 50.0
		mmi.add_to_group(&"grass_chunks")
		scene.add_child(mmi)
	for level in [0, 2, 1]:
		Quality.apply(level)
		var light := scene.find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D
		var chunk := get_tree().get_first_node_in_group(&"grass_chunks") as MultiMeshInstance3D
		var grass := "none"
		if chunk:
			grass = "%d/%d range_end=%s" % [chunk.multimesh.visible_instance_count, chunk.multimesh.instance_count, chunk.visibility_range_end]
		print("Q%d scale=%s shadow=%s dist=%s grass=%s" % [level, get_tree().root.content_scale_size, light.shadow_enabled, light.directional_shadow_max_distance, grass])
	get_tree().quit()
