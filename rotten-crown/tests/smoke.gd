extends SceneTree

# Run with: godot --headless --path rotten-crown --script res://tests/smoke.gd
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame
	assert(game.player != null and game.world != null and game.hud != null)
	assert(game.inventory.is_empty())
	# Multiple fingers must be owned independently, and released independently.
	var hud = game.hud
	hud._touch_start(1, hud._stick_center() + Vector2(hud._radius() * 0.5, 0))
	hud._touch_start(2, Vector2(hud.size.x * 0.6, hud.size.y * 0.45))
	hud._touch_start(3, hud._button_center("defend"))
	assert(hud.joystick_finger == 1 and hud.look_finger == 2 and game.player.defending)
	assert(game.player.move_input.x > 0.4)
	hud._touch_end(1)
	hud._touch_end(2)
	hud._touch_end(3)
	assert(game.player.move_input == Vector2.ZERO and not game.player.defending)
	game.player.position = Vector3(-2, 0.05, 9)
	game.interact()
	assert(game.inventory.size() == 1 and game.inventory[0] == "Torn decree")
	game.interact()
	assert(game.inventory.size() == 1)
	game.toggle_inventory()
	assert(game.inventory_open and game.player.input_locked)
	game.toggle_inventory()
	assert(not game.inventory_open and not game.player.input_locked)
	game.player.position = Vector3(0.5, 0.05, -1.5)
	game.player.rotation.y = 0
	assert(game.world.hit_enemy(game.player.global_position, Vector3.FORWARD))
	assert(game.world.hit_enemy(game.player.global_position, Vector3.FORWARD))
	assert(game.world.hit_enemy(game.player.global_position, Vector3.FORWARD))
	assert(not game.world.hit_enemy(game.player.global_position, Vector3.FORWARD))
	print("SMOKE TEST PASSED")
	game.queue_free()
	quit()
