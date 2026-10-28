extends Node3D
## Review scene for TerrainBuilder: a sample spec with hills, a plateau, roads,
## dry fields and a forest patch, plus a camera at RC_CAM="x,y,z,lx,ly,lz".


func _ready() -> void:
	var spec := TerrainSpec.new()
	spec.min_corner = Vector2(-160.0, -60.0)
	spec.max_corner = Vector2(160.0, 260.0)
	spec.plateaus = [Vector4(-80.0, 140.0, 22.0, 18.0)]
	spec.roads = [PackedVector2Array([Vector2(0, 10), Vector2(0, 60), Vector2(-30, 100), Vector2(-80, 140)]),
		PackedVector2Array([Vector2(0, 60), Vector2(60, 110), Vector2(90, 200)])]
	spec.dry_fields = [Vector3(-60.0, 90.0, 40.0)]
	spec.forests = [Vector3(70.0, 150.0, 45.0)]
	var t0 := Time.get_ticks_msec()
	var terrain := TerrainBuilder.new(spec)
	terrain.build(self)
	print("terrain built in %d ms, %dx%d" % [Time.get_ticks_msec() - t0, terrain.cols, terrain.rows])
	var cam := $Camera3D as Camera3D
	var raw := OS.get_environment("RC_CAM")
	# Guard: "".split_floats() crashes Godot 4.4.1.
	var v := raw.split_floats(",") if raw != "" else PackedFloat64Array()
	if v.size() == 6:
		cam.position = Vector3(v[0], v[1], v[2])
		cam.look_at(Vector3(v[3], v[4], v[5]))
	if OS.has_environment("RC_NOPROBE"):
		return
	# Drop a probe on the collider to prove it matches the mesh.
	var probe := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = SphereShape3D.new()
	probe.add_child(cs)
	probe.position = Vector3(-60.0, 40.0, 90.0)
	add_child(probe)
	await get_tree().create_timer(3.0).timeout
	print("probe rests at y=%.2f, ground=%.2f" % [probe.position.y, terrain.height_at(-60.0, 90.0)])
