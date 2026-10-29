extends Node
## Visual smoke test: boots the game, plays a few scripted steps and saves screenshots.
## Run (needs a display, e.g. xvfb-run):
##   godot --path . res://tests/shots.tscn -- OUT_DIR

var out_dir := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var runner := Node.new()
	runner.set_script(load("res://tests/shots_runner.gd"))
	runner.set("out_dir", out_dir)
	if args.size() > 1:
		Loc.set_lang(args[1])
	get_tree().root.call_deferred("add_child", runner)
