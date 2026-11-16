extends Node3D
## Dev preview of the sword trail and the blood on the blade (V24): the player swings once at a
## wall of dark; frames are written by the movie writer (see tools/render_shots.sh for the flags).
##   xvfb-run -a <godot> --path . --rendering-driver opengl3 --write-movie /tmp/s/f.png --fixed-fps 20 --quit-after 40 res://tools/swing_preview.tscn

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.05, 0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.2, 0.26, 0.42)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.6, 0.72, 1.0)
	sun.light_energy = 0.8
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var player := load("res://src/player/player.tscn").instantiate() as Player
	add_child(player)
	await get_tree().create_timer(0.4).timeout
	# Stained steps as if a few hits had landed.
	player.weapon._blood = 0.7
	player.weapon._apply_blood()
	player.try_attack()
