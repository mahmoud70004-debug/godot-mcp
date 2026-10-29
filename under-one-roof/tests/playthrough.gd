extends Node
## Automated story test. Validates the data files, then plays the whole game
## from the first morning to the credits (fast mode) and checks every story flag.
## Run: godot --headless --path . res://tests/playthrough.tscn


func _ready() -> void:
	var runner := Node.new()
	runner.set_script(load("res://tests/playthrough_runner.gd"))
	get_tree().root.call_deferred("add_child", runner)
