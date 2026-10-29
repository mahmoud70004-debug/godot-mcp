extends Node
## Run (needs a display): godot --path . res://tests/menu_shots.tscn -- OUT_DIR


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var runner := Node.new()
	runner.set_script(load("res://tests/menu_shots_runner.gd"))
	runner.set("out_dir", args[0] if args.size() > 0 else "user://")
	get_tree().root.call_deferred("add_child", runner)
