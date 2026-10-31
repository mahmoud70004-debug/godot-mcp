extends Node
var game
var t := 0.0
var step := 0
func _ready():
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
func _process(d):
	t += d
	if game.phase == 1 and step == 0:
		step = 1
		game.title_panel.visible = false
		game.start_game()
		print("keys at ", game.level.key_cells, " batteries ", game.level.battery_cells)
	if step == 1 and t > 3.0:
		# run every scare event once
		for ev in ["apparition", "behind", "blackout", "bang", "runner", "glitch", "footsteps", "breath"]:
			game.last_event = ""
			match ev:
				"apparition": game._ev_apparition()
				"behind": game._ev_behind()
				"blackout": game._ev_blackout()
				"bang": game._ev_bang()
				"runner": game._ev_runner()
				"glitch": game._ev_glitch()
				"footsteps": game._ev_footsteps()
				"breath": game._ev_breath()
		step = 2
	if step >= 2 and step < 7 and t > 4.0 + (step - 2) * 2.5:
		game.monster.frozen = true
		var k = game.keys[0]
		game.player.global_position = Vector3(k.global_position.x, 0.05, k.global_position.z)
		step += 1
	if step == 7 and t > 18.0:
		print("keys found ", game.keys_found, " monster state ", game.monster.state, " dist ", game.monster.distance_to_player(), " phase ", game.phase)
		step = 8
	if step == 8 and t > 30.0:
		print("after chase: phase ", game.phase, " monster state ", game.monster.state)
		if game.phase == 2:
			game.monster.frozen = true
			game.player.global_position = game.level.exit_pos + Vector3(0.3, 0.05, 0)
		step = 9
	if step == 9 and t > 40.0:
		print("final phase ", game.phase, " end panel ", game.end_panel != null)
		print("PASS" if game.phase == 4 and game.keys_found == 5 and game.end_panel != null else "FAIL")
		get_tree().quit()
