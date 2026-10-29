extends Node
## Touch-only start-of-game test. Run: godot --path . res://tests/phone_flow.tscn
## (works headless too: godot --headless --path . res://tests/phone_flow.tscn)


func _ready() -> void:
	var runner := Node.new()
	runner.set_script(load("res://tests/phone_flow_runner.gd"))
	get_tree().root.call_deferred("add_child", runner)
