extends Node3D
## Review scene for region builders on the real overworld terrain.
##   RC_REGION=thornfield|hollowmere|whispering_wood  RC_CAM="x,y,z,look_x,look_y,look_z"
## Uses the gloom atmosphere of the cursed kingdom.


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var terrain := TerrainBuilder.new(OverworldSpec.make())
	terrain.build(self)
	var region := OS.get_environment("RC_REGION")
	var t0 := Time.get_ticks_msec()
	match region:
		"thornfield":
			_call_builder("ThornfieldBuilder", terrain, rng)
		"hollowmere":
			_call_builder("HollowmereBuilder", terrain, rng)
		"whispering_wood":
			_call_builder("WhisperingWoodBuilder", terrain, rng)
	print("region %s built in %d ms" % [region, Time.get_ticks_msec() - t0])
	var raw := OS.get_environment("RC_CAM")
	var v := raw.split_floats(",") if raw != "" else PackedFloat64Array()  # "".split_floats crashes 4.4.1
	if v.size() == 6:
		var cam := $Camera3D as Camera3D
		cam.position = Vector3(v[0], v[1], v[2])
		cam.look_at(Vector3(v[3], v[4], v[5]))


func _call_builder(class_id: String, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == class_id:
			var script: Script = load(c["path"])
			script.call("build", self, terrain, rng)
			return
	push_error("builder %s not found" % class_id)
