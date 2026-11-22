extends SceneTree
## Turns the Blender export build/aether/hero_<name>.json into data/trees/hero_<name>.res
## (the close-up trunk of ForestTrees.hero). Run through tools/bake_aether_hero.sh.


func _init() -> void:
	for name in ["tall", "broad", "elder", "hollow"]:
		var path := "res://build/aether".path_join("hero_%s.json" % name)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			push_error("missing %s (run aether_trees.py -- export first)" % path)
			quit(1)
			return
		var mesh := ForestHero.from_json(parsed as Dictionary)
		var out := "res://data/trees".path_join("hero_%s.res" % name)
		var err := ResourceSaver.save(mesh, out, ResourceSaver.FLAG_COMPRESS)
		print("%s: %d tris -> %s (%s)" % [name, (parsed["i"] as Array).size() / 3, out, error_string(err)])
	quit()
