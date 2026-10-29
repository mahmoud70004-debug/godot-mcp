extends Node
## Real-time input test: walking, collisions, doors and the interact button.
## Run: godot --headless --path . res://tests/controls.tscn


func _ready() -> void:
	var runner := Node.new()
	runner.set_script(load("res://tests/controls_runner.gd"))
	get_tree().root.call_deferred("add_child", runner)
