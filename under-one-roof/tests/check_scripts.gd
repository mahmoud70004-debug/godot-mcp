extends Node
## Loads every script and scene once so parse/compile errors show up in the log.
## Run: godot --headless --path . res://tests/check_scripts.tscn


func _ready() -> void:
	var bad := 0
	for path in _files("res://", [".gd", ".tscn"]):
		if path.begins_with("res://tests/") or path.begins_with("res://.godot"):
			continue
		var r = load(path)
		if r == null:
			bad += 1
			print("FAILED: ", path)
		elif r is GDScript and not r.can_instantiate():
			bad += 1
			print("FAILED: ", path)
	print("CHECK DONE, failures: ", bad)
	get_tree().quit(1 if bad > 0 else 0)


func _files(dir: String, exts: Array) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		for e in exts:
			if f.ends_with(e):
				out.append(dir.path_join(f))
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		out += _files(dir.path_join(sub), exts)
	return out
