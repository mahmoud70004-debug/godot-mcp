class_name Monster
extends Node3D
## Grid-based stalker AI.
## DORMANT -> STALK (wanders closer) -> HUNT (sees you) -> SEARCH (last seen)
## It also "relocates" out of sight to cut you off when it loses you.

signal caught_player
signal started_hunt
signal lost_player

enum State { DORMANT, STALK, HUNT, SEARCH }

var level: Level
var player: Player
var body: Creature
var state := State.DORMANT
var aggression := 0          # number of keys collected
var path: Array[Vector2i] = []
var last_seen := Vector3.ZERO
var lost_timer := 0.0
var unseen_timer := 0.0
var repath_timer := 0.0
var step_acc := 0.0
var sees_player := false
var growl: AudioStreamPlayer3D
var steps: AudioStreamPlayer3D
var frozen := false

func setup(p_level: Level, p_player: Player) -> void:
	level = p_level
	player = p_player

func _ready() -> void:
	body = Creature.new()
	add_child(body)
	growl = AudioStreamPlayer3D.new()
	growl.stream = Sfx.get_sound("growl")
	growl.unit_size = 3.0
	growl.max_distance = 26.0
	growl.volume_db = -4.0
	growl.position.y = 2.2
	add_child(growl)
	steps = AudioStreamPlayer3D.new()
	steps.stream = Sfx.get_sound("monster_step")
	steps.unit_size = 5.0
	steps.max_distance = 35.0
	steps.volume_db = 2.0
	add_child(steps)
	visible = false

func activate() -> void:
	if state != State.DORMANT:
		return
	state = State.STALK
	visible = true
	# Spawn as far away as possible.
	var dist := level.bfs_dist(Level.world_to_cell(player.global_position))
	var best := Vector2i(Level.W - 1, Level.H - 1)
	for c in dist.keys():
		if dist[c] > dist.get(best, 0):
			best = c
	global_position = Level.cell_center(best)
	growl.play()

func speed() -> float:
	match state:
		State.HUNT:
			return 3.15 + aggression * 0.22
		State.SEARCH:
			return 2.4 + aggression * 0.15
		_:
			return 1.4 + aggression * 0.18

func has_los() -> bool:
	var from := global_position + Vector3(0, 2.0, 0)
	var to := player.camera.global_position
	if from.distance_to(to) > 22.0:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func player_sees_me() -> bool:
	var to_me := (global_position + Vector3(0, 1.8, 0)) - player.camera.global_position
	var fwd := -player.camera.global_transform.basis.z
	return fwd.dot(to_me.normalized()) > 0.6 and has_los()

func distance_to_player() -> float:
	return Vector2(global_position.x - player.global_position.x, global_position.z - player.global_position.z).length()

func _physics_process(delta: float) -> void:
	if state == State.DORMANT or frozen or player == null:
		return
	var d := distance_to_player()
	var los := has_los()
	# Detection: closer range in darkness.
	var detect := 15.0 if player.is_light_visible() else 7.0
	detect += aggression * 0.8
	sees_player = los and d < detect
	if sees_player:
		if state != State.HUNT:
			state = State.HUNT
			started_hunt.emit()
		last_seen = player.global_position
		lost_timer = 0.0
	elif state == State.HUNT:
		lost_timer += delta
		if lost_timer > 3.5:
			state = State.SEARCH
			path = level.path_cells(Level.world_to_cell(global_position), Level.world_to_cell(last_seen))
			lost_player.emit()
	# Relocation: if it has not seen the player for long, appear closer.
	if state == State.STALK and not player_sees_me():
		unseen_timer += delta
		if unseen_timer > maxf(26.0 - aggression * 3.0, 10.0) and d > 14.0:
			_relocate_near_player()
			unseen_timer = 0.0
	else:
		unseen_timer = 0.0
	# ---- movement
	var target := Vector3.ZERO
	var direct := false
	if state == State.HUNT and los:
		target = player.global_position
		direct = true
	else:
		repath_timer -= delta
		if path.is_empty() or repath_timer <= 0.0:
			repath_timer = 1.0
			var goal: Vector2i
			match state:
				State.HUNT:
					goal = Level.world_to_cell(last_seen)
				State.SEARCH:
					goal = Level.world_to_cell(last_seen)
					if Level.world_to_cell(global_position) == goal and path.size() <= 1:
						state = State.STALK
				_:
					# Wander toward a cell near the player.
					var pc := Level.world_to_cell(player.global_position)
					goal = Vector2i(clampi(pc.x + randi_range(-2, 2), 0, Level.W - 1), clampi(pc.y + randi_range(-2, 2), 0, Level.H - 1))
			path = level.path_cells(Level.world_to_cell(global_position), goal)
			if path.size() > 0 and path[0] == Level.world_to_cell(global_position) and path.size() > 1:
				# Skip current cell only if we are already near its centre.
				if Vector2(global_position.x, global_position.z).distance_to(Vector2(Level.cell_center(path[0]).x, Level.cell_center(path[0]).z)) < 0.6:
					path.pop_front()
		if not path.is_empty():
			target = Level.cell_center(path[0])
			if Vector2(global_position.x - target.x, global_position.z - target.z).length() < 0.35:
				path.pop_front()
				if not path.is_empty():
					target = Level.cell_center(path[0])
	var moving := false
	if target != Vector3.ZERO:
		var to := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
		var dist := to.length()
		if dist > 0.05:
			var step := minf(speed() * delta, dist)
			global_position += to / dist * step
			moving = true
			var face := Vector3(target.x, global_position.y, target.z)
			if direct:
				face = Vector3(player.global_position.x, global_position.y, player.global_position.z)
			if global_position.distance_to(face) > 0.1:
				var want := Transform3D(Basis(), global_position).looking_at(face, Vector3.UP).basis
				basis = basis.slerp(want.orthonormalized(), minf(delta * 8.0, 1.0)).orthonormalized()
	body.moving = lerpf(body.moving, (1.0 if state == State.HUNT else 0.5) if moving else 0.0, delta * 5.0)
	body.twitch_strength = 1.6 if state == State.HUNT else 0.8
	# ---- footsteps
	if moving:
		step_acc += speed() * delta
		if step_acc > (1.3 if state == State.HUNT else 1.7):
			step_acc = 0.0
			steps.pitch_scale = randf_range(0.8, 1.0)
			steps.play()
	growl.pitch_scale = 1.25 if state == State.HUNT else 0.9
	if not growl.playing:
		growl.play()
	# ---- catch
	if d < 1.05:
		frozen = true
		caught_player.emit()

func _relocate_near_player() -> void:
	# Pick a cell 2-3 steps from the player that the player cannot see.
	var pc := Level.world_to_cell(player.global_position)
	var dist := level.bfs_dist(pc)
	var options: Array = []
	for c in dist.keys():
		if dist[c] >= 2 and dist[c] <= 3:
			options.append(c)
	options.shuffle()
	var fwd := -player.camera.global_transform.basis.z
	for c in options:
		var p := Level.cell_center(c)
		var dir := (p - player.global_position)
		dir.y = 0
		if fwd.dot(dir.normalized()) < 0.2:   # behind or to the side
			global_position = p
			path.clear()
			return
	if not options.is_empty():
		global_position = Level.cell_center(options[0])
		path.clear()

func teleport_far() -> void:
	var pc := Level.world_to_cell(player.global_position)
	var dist := level.bfs_dist(pc)
	var options: Array = dist.keys().filter(func(c): return dist[c] >= 5)
	if options.is_empty():
		options = dist.keys()
	global_position = Level.cell_center(options[randi() % options.size()])
	state = State.STALK
	path.clear()
