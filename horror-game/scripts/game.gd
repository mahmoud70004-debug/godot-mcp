extends Node3D
## "لا تنظر خلفك" — main game controller.
## Builds the world, HUD, touch controls, runs the scare director and the
## death / escape sequences.

enum Phase { LOADING, TITLE, PLAYING, DEAD, WON }

const KEYS_NEEDED := 5

static var quick_restart := false
static var best_time := -1.0

var phase := Phase.LOADING
var font: Font
var _thread: Thread

var level: Level
var player: Player
var monster: Monster
var controls: TouchControls
var env: Environment

var keys: Array[Node3D] = []
var batteries: Array[Node3D] = []
var keys_found := 0
var play_time := 0.0

# UI
var ui: CanvasLayer
var overlay: ColorRect
var overlay_mat: ShaderMaterial
var hud: Control
var keys_label: Label
var battery_bar: ColorRect
var stamina_bar: ColorRect
var msg_label: Label
var big_label: Label
var title_panel: Control
var title_hint: Label
var end_panel: Control

# Audio
var drone: AudioStreamPlayer
var heart: AudioStreamPlayer
var heart_timer := 0.0

# Effects state
var fear := 0.0
var glitch := 0.0
var red_flash := 0.0
var fade := 0.0
var _msg_time := 0.0
var _big_time := 0.0

# Scare director
var scare_cooldown := 14.0
var last_event := ""
var ghost: Creature
var ghost_timer := 0.0
var ghost_mode := ""          # "", "apparition", "runner", "flash"
var ghost_seen := false
var ghost_vel := Vector3.ZERO
var behind_window := 0.0
var behind_dir := Vector3.ZERO
var face: Creature
var face_light: OmniLight3D
var doll_move_timer := 3.0
var hunt_announced := false

# ============================================================== lifecycle
func _ready() -> void:
	font = load("res://fonts/NotoKufiArabic.ttf")
	_build_ui()
	if Sfx.ready:
		_after_loading()
	else:
		_show_big("...", 999.0)
		_thread = Thread.new()
		_thread.start(func(): Sfx.generate_all())

func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()

func _after_loading() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	big_label.text = ""
	if quick_restart:
		quick_restart = false
		title_panel.visible = false
		start_game()
	else:
		phase = Phase.TITLE
		title_panel.visible = true
		var amb := _play2d("drone", -14.0, 0.8)
		amb.name = "TitleDrone"

func _process(delta: float) -> void:
	match phase:
		Phase.LOADING:
			if Sfx.ready:
				_after_loading()
		Phase.TITLE:
			title_hint.modulate.a = 0.4 + 0.6 * absf(sin(Time.get_ticks_msec() * 0.003))
		Phase.PLAYING:
			play_time += delta
			_update_gameplay(delta)
	_update_effects(delta)

func _input(event: InputEvent) -> void:
	if phase == Phase.TITLE:
		var tapped: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed)
		if tapped:
			get_viewport().set_input_as_handled()
			var td := get_node_or_null("TitleDrone")
			if td:
				td.queue_free()
			title_panel.visible = false
			start_game()

# ============================================================== world setup
func start_game() -> void:
	phase = Phase.PLAYING
	# Environment: darkness and fog.
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.055, 0.07)
	env.ambient_light_energy = 0.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.0, 0.0, 0.0)
	env.fog_density = 0.055
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)

	level = Level.new()
	add_child(level)
	level.build(font)

	player = Player.new()
	add_child(player)
	player.global_position = Level.cell_center(Vector2i(0, 0)) + Vector3(-0.6, 0.05, 0)
	# Face the open corridor leading away from the exit door.
	var open_dir: Vector2i = level.neighbors(Vector2i(0, 0))[0]
	var dir3 := Vector3(open_dir.x, 0, open_dir.y)
	player.yaw = atan2(-dir3.x, -dir3.z)
	player.setup(controls)
	controls.enabled = true
	controls.visible = true
	hud.visible = true

	monster = Monster.new()
	add_child(monster)
	monster.setup(level, player)
	monster.caught_player.connect(_on_caught)
	monster.started_hunt.connect(_on_hunt)
	monster.lost_player.connect(func(): _show_msg("...فقد أثرك. لا تتحرك", 2.5))

	ghost = Creature.new()
	ghost.visible = false
	add_child(ghost)

	face = Creature.new(true)
	face.rotation.y = PI   # the face is modelled on -Z; turn it toward the camera
	face.visible = false
	player.face_anchor.add_child(face)
	face_light = OmniLight3D.new()
	face_light.light_color = Color(1.0, 0.82, 0.72)
	face_light.light_energy = 1.6
	face_light.omni_range = 1.2
	face_light.position = Vector3(0.0, -0.32, -0.1)
	face_light.visible = false
	player.face_anchor.add_child(face_light)

	for c in level.key_cells:
		keys.append(_make_key(Level.cell_center(c)))
	for c in level.battery_cells:
		batteries.append(_make_battery(Level.cell_center(c) + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))))

	drone = AudioStreamPlayer.new()
	drone.stream = Sfx.get_sound("drone")
	drone.volume_db = -6.0
	add_child(drone)
	drone.play()
	heart = AudioStreamPlayer.new()
	heart.stream = Sfx.get_sound("heartbeat")
	heart.volume_db = -30.0
	add_child(heart)

	fade = 1.0
	_intro()

func _intro() -> void:
	await _wait(0.6)
	_show_msg("استيقظتَ في الجناح المهجور...", 3.5)
	await _wait(4.0)
	if phase != Phase.PLAYING: return
	_show_msg("اجمع المفاتيح الخمسة وافتح باب المخرج", 4.0)
	await _wait(4.5)
	if phase != Phase.PLAYING: return
	_show_msg("ومهما سمعت... لا تنظر خلفك", 4.0)

func _make_key(p: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.position = p + Vector3(0, 0.9, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.6, 0.25)
	m.metallic = 0.8
	m.roughness = 0.35
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.2)
	m.emission_energy_multiplier = 0.9
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.05
	tm.outer_radius = 0.09
	ring.mesh = tm
	ring.material_override = m
	ring.rotation.x = PI * 0.5
	ring.position.y = 0.12
	n.add_child(ring)
	var shaft := MeshInstance3D.new()
	shaft.mesh = Creature._box(Vector3(0.03, 0.22, 0.03))
	shaft.material_override = m
	shaft.position.y = -0.05
	n.add_child(shaft)
	var bit := MeshInstance3D.new()
	bit.mesh = Creature._box(Vector3(0.07, 0.03, 0.03))
	bit.material_override = m
	bit.position = Vector3(0.035, -0.13, 0)
	n.add_child(bit)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.3)
	l.light_energy = 0.5
	l.omni_range = 2.2
	n.add_child(l)
	return n

func _make_battery(p: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.position = p + Vector3(0, 0.12, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.4, 0.15)
	m.emission_enabled = true
	m.emission = Color(0.2, 1.0, 0.3)
	m.emission_energy_multiplier = 0.6
	var c := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.05
	cy.bottom_radius = 0.05
	cy.height = 0.22
	c.mesh = cy
	c.material_override = m
	c.rotation.z = PI * 0.5
	n.add_child(c)
	return n

# ============================================================== gameplay
func _update_gameplay(delta: float) -> void:
	var cam := player.camera
	# --- pickups
	for k in keys.duplicate():
		k.rotation.y += delta * 1.5
		k.position.y = 0.9 + sin(play_time * 2.0 + k.position.x) * 0.06
		if _flat_dist(k.global_position, player.global_position) < 1.2:
			keys.erase(k)
			k.queue_free()
			_on_key()
	for b in batteries.duplicate():
		b.rotation.y += delta
		if _flat_dist(b.global_position, player.global_position) < 1.0:
			batteries.erase(b)
			b.queue_free()
			player.battery = minf(player.battery + 0.45, 1.0)
			_play2d("pickup", -8.0, 1.4)
			_show_msg("بطارية للمصباح", 2.0)
	# --- exit
	if keys_found >= KEYS_NEEDED and _flat_dist(level.exit_pos, player.global_position) < 1.5:
		_on_win()
		return
	if keys_found < KEYS_NEEDED and _flat_dist(level.exit_pos, player.global_position) < 1.3 and _msg_time <= 0.0:
		_show_msg("الباب مقفل... تحتاج %d مفاتيح" % (KEYS_NEEDED - keys_found), 2.0)
	# --- monster activation by time
	if monster.state == Monster.State.DORMANT and play_time > 50.0:
		monster.activate()
		_play3d("growl", player.global_position + Vector3(0, 2, 0) - cam.global_transform.basis.z * -12.0, 0.0)
		_show_msg("...هناك شيء ما يتحرك", 3.0)
	# --- fear
	var target_fear := 0.0
	if monster.state != Monster.State.DORMANT:
		var d := monster.distance_to_player()
		target_fear = clampf(1.0 - (d - 2.0) / 16.0, 0.0, 1.0)
		if monster.state == Monster.State.HUNT:
			target_fear = maxf(target_fear, 0.75)
	if ghost_mode != "":
		target_fear = maxf(target_fear, 0.5)
	fear = lerpf(fear, target_fear, delta * 1.5)
	player.fear = fear
	drone.pitch_scale = lerpf(1.0, 0.85, fear)
	# --- heartbeat
	heart_timer -= delta
	if heart_timer <= 0.0 and fear > 0.12:
		heart_timer = lerpf(1.25, 0.36, fear)
		heart.volume_db = lerpf(-24.0, 2.0, fear)
		heart.play()
		if fear > 0.8:
			Input.vibrate_handheld(40)
	# --- lamps flicker (heavily when the creature is near)
	for L in level.lights:
		var l: OmniLight3D = L.light
		L.t -= delta
		L.kill -= delta
		var near := 0.0
		if monster.state != Monster.State.DORMANT:
			near = clampf(1.0 - l.global_position.distance_to(monster.global_position) / 9.0, 0.0, 1.0)
		if L.kill > 0.0:
			l.light_energy = 0.0
		elif L.broken:
			l.light_energy = 1.2 if randf() < 0.01 else 0.0
		elif L.t <= 0.0:
			L.t = randf_range(0.03, 0.25) if (randf() < 0.15 + near * 0.8) else randf_range(0.5, 3.0)
			l.light_energy = L.base * (randf_range(0.0, 0.3) if randf() < 0.3 + near * 0.6 else randf_range(0.8, 1.0))
		L.mat.emission_energy_multiplier = l.light_energy * 2.2
	level.exit_light.light_energy = 0.8 + sin(play_time * 3.0) * 0.3 if keys_found < KEYS_NEEDED else 1.2
	# --- dolls: they turn to face you when you are not looking
	doll_move_timer -= delta
	for doll in level.dolls:
		var to_doll := doll.global_position + Vector3(0, 0.45, 0) - cam.global_position
		var looking := (-cam.global_transform.basis.z).dot(to_doll.normalized()) > 0.45 and to_doll.length() < 14.0
		if not looking:
			var h: Node3D = doll.get_node("Head")
			var tp := cam.global_position
			if h.global_position.distance_to(tp) > 0.3:
				h.look_at(tp, Vector3.UP)
			if doll_move_timer <= 0.0 and to_doll.length() < 9.0 and to_doll.length() > 2.5 and _ray_clear(doll.global_position + Vector3(0, 0.4, 0), cam.global_position):
				var step := Vector3(-to_doll.x, 0, -to_doll.z).normalized() * 0.7
				doll.global_position += step
				doll.look_at(Vector3(cam.global_position.x, doll.global_position.y, cam.global_position.z), Vector3.UP)
				doll_move_timer = randf_range(5.0, 12.0)
				if randf() < 0.5:
					_play3d("laugh", doll.global_position + Vector3(0, 0.5, 0), -6.0, randf_range(1.1, 1.4))
	# --- scare director
	_update_ghost(delta)
	_update_behind(delta)
	if ghost_mode == "" and monster.state != Monster.State.HUNT:
		scare_cooldown -= delta
		if scare_cooldown <= 0.0:
			scare_cooldown = randf_range(18.0, 34.0) - keys_found * 1.5
			_run_random_scare()
	# --- HUD
	keys_label.text = "المفاتيح  %d / %d" % [keys_found, KEYS_NEEDED]
	battery_bar.size.x = 180.0 * player.battery
	battery_bar.color = Color(0.85, 0.75, 0.3) if player.battery > 0.2 else Color(0.8, 0.15, 0.1)
	stamina_bar.size.x = 180.0 * player.stamina

func _on_key() -> void:
	keys_found += 1
	monster.aggression = keys_found
	_play2d("pickup", -2.0)
	_show_msg("وجدت مفتاحاً  %d / %d" % [keys_found, KEYS_NEEDED], 2.5)
	match keys_found:
		1:
			await _wait(1.2)
			if phase != Phase.PLAYING: return
			monster.activate()
			_blackout_all(2.5)
			_play3d("laugh", player.global_position - player.camera.global_transform.basis.z * -3.0 + Vector3(0, 1, 0), -2.0, 0.8)
			_show_msg("...لقد أيقظته", 3.0)
		3:
			await _wait(2.0)
			if phase != Phase.PLAYING: return
			monster._relocate_near_player()
			monster.state = Monster.State.STALK
			_play3d("bang", monster.global_position + Vector3(0, 1.5, 0), 4.0)
			player.add_shake(0.6)
			_show_msg("إنه قريب جداً", 2.5)
		KEYS_NEEDED:
			level.exit_label.text = "مخرج"
			level.exit_label.modulate = Color(0.3, 1.0, 0.4)
			level.exit_light.light_color = Color(0.3, 1.0, 0.35)
			await _wait(1.5)
			if phase != Phase.PLAYING: return
			_show_msg("الباب فُتح! اركض إلى المخرج!", 4.0)
			for L in level.lights:
				L.light.light_color = Color(1.0, 0.15, 0.1)
				L.mat.emission = Color(1.0, 0.1, 0.05)
			_play2d("sting", 0.0)
			monster._relocate_near_player()
			monster.state = Monster.State.HUNT
			monster.last_seen = player.global_position
			glitch = 0.6

func _on_hunt() -> void:
	_play2d("sting", -3.0, randf_range(0.9, 1.1))
	player.add_shake(0.3)
	Input.vibrate_handheld(120)
	if not hunt_announced:
		hunt_announced = true
		_show_msg("اركض!", 2.0)

# ============================================================== scares
func _run_random_scare() -> void:
	var events := ["apparition", "behind", "blackout", "bang", "runner", "glitch", "footsteps", "breath"]
	events.erase(last_event)
	var ev: String = events[randi() % events.size()]
	last_event = ev
	match ev:
		"apparition": _ev_apparition()
		"behind": _ev_behind()
		"blackout": _ev_blackout()
		"bang": _ev_bang()
		"runner": _ev_runner()
		"glitch": _ev_glitch()
		"footsteps": _ev_footsteps()
		"breath": _ev_breath()

func _forward_point(min_d: float, max_d: float) -> Variant:
	var cam := player.camera
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var from := Vector3(cam.global_position.x, 1.2, cam.global_position.z)
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 30.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var free_d := 30.0 if hit.is_empty() else from.distance_to(hit.position)
	if free_d < min_d + 0.6:
		return null
	var d := minf(max_d, free_d - 0.6)
	var p := from + fwd * d
	p.y = 0
	return p

func _place_ghost(p: Vector3) -> void:
	ghost.global_position = p
	var cp := player.camera.global_position
	ghost.look_at(Vector3(cp.x, p.y, cp.z), Vector3.UP)
	ghost.visible = true
	ghost_seen = false

func _ev_apparition() -> void:
	var p = _forward_point(6.0, 13.0)
	if p == null:
		_ev_bang()
		return
	_place_ghost(p)
	ghost_mode = "apparition"
	ghost_timer = 7.0

func _ev_runner() -> void:
	var p = _forward_point(5.0, 9.0)
	if p == null:
		_ev_footsteps()
		return
	var fwd: Vector3 = -player.camera.global_transform.basis.z
	fwd.y = 0
	var side := fwd.normalized().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	_place_ghost(p - side * 1.6)
	ghost.look_at(ghost.global_position + side, Vector3.UP)
	ghost_vel = side * 9.0
	ghost_mode = "runner"
	ghost_timer = 0.38
	ghost.moving = 1.0
	_play3d("monster_step", p, 0.0, 1.6)
	_play2d("sting", -6.0, 1.2)

func _update_ghost(delta: float) -> void:
	if ghost_mode == "":
		return
	ghost_timer -= delta
	var cam := player.camera
	match ghost_mode:
		"apparition":
			var to := ghost.global_position + Vector3(0, 1.8, 0) - cam.global_position
			var seen := (-cam.global_transform.basis.z).dot(to.normalized()) > 0.88 and _ray_clear(cam.global_position, ghost.global_position + Vector3(0, 1.8, 0))
			if seen and not ghost_seen:
				ghost_seen = true
				ghost_timer = 0.45
				_play2d("sting", -2.0)
				Input.vibrate_handheld(80)
				_flicker_near(cam.global_position, 12.0, 0.6)
			if ghost_timer <= 0.0:
				if ghost_seen:
					glitch = 0.7
					_play2d("static", -8.0)
				_hide_ghost()
		"runner":
			ghost.global_position += ghost_vel * delta
			if ghost_timer <= 0.0:
				_hide_ghost()
		"flash":
			if ghost_timer <= 0.0:
				player.flicker_override = 0.25
				_play2d("static", -10.0)
				_hide_ghost()

func _hide_ghost() -> void:
	ghost.visible = false
	ghost.moving = 0.0
	ghost_mode = ""

func _ev_behind() -> void:
	var back := player.camera.global_transform.basis.z
	back.y = 0
	back = back.normalized()
	_play3d("whisper", player.camera.global_position + back * 1.1, 2.0)
	behind_dir = back
	behind_window = 4.5
	await _wait(1.0)
	if phase != Phase.PLAYING: return
	_show_msg("...لا تلتفت", 2.0)

func _update_behind(delta: float) -> void:
	if behind_window <= 0.0:
		return
	behind_window -= delta
	var fwd := -player.camera.global_transform.basis.z
	fwd.y = 0
	if fwd.normalized().dot(behind_dir) > 0.55:
		behind_window = 0.0
		_face_scare(0.6, -3.0)

func _face_scare(duration: float, vol: float) -> void:
	face.visible = true
	face_light.visible = true
	face.position = Vector3(0, -0.04, -0.8)
	face.scale = Vector3.ONE
	face.twitch_strength = 2.0
	face.set_eye_glow(9.0)
	_play2d("screech", vol)
	player.add_shake(1.0)
	red_flash = 0.8
	glitch = 0.9
	Input.vibrate_handheld(int(duration * 900))
	var t := 0.0
	while t < duration:
		await get_tree().process_frame
		t += get_process_delta_time()
		face.position.z = lerpf(-0.8, -0.58, minf(t / duration * 3.0, 1.0))
		face.position.x = randf_range(-0.01, 0.01)
	face.set_eye_glow(4.0)
	if phase == Phase.PLAYING:
		face.visible = false
		face_light.visible = false

func _ev_blackout() -> void:
	player.flicker_override = 3.0
	_blackout_all(3.2)
	_play2d("static", -12.0)
	var left := player.camera.global_transform.basis.x * -1.4
	await _wait(0.8)
	if phase != Phase.PLAYING: return
	_play3d("breath", player.camera.global_position + left, 3.0)
	await _wait(2.2)
	if phase != Phase.PLAYING: return
	# The light returns... and something is standing right in front of you.
	var p = _forward_point(1.8, 2.6)
	if p != null and monster.state != Monster.State.HUNT:
		_place_ghost(p)
		ghost_mode = "flash"
		ghost_timer = 0.55
		_play2d("sting", 0.0)
		player.add_shake(0.5)
		Input.vibrate_handheld(200)

func _ev_bang() -> void:
	var side := player.camera.global_transform.basis.x * (2.5 if randf() < 0.5 else -2.5)
	_play3d("bang", player.global_position + side + Vector3(0, 1.5, 0), 6.0)
	player.add_shake(0.7)
	Input.vibrate_handheld(150)
	_flicker_near(player.global_position, 10.0, 0.8)

func _ev_glitch() -> void:
	var lines := ["أنا أراك", "خلفك", "لن تخرج", "استدر"]
	var text: String = lines[randi() % lines.size()]
	for i in 3:
		glitch = 1.0
		_play2d("static", -4.0, randf_range(0.8, 1.2))
		_show_big(text, 0.18)
		Input.vibrate_handheld(60)
		await _wait(randf_range(0.25, 0.5))
		if phase != Phase.PLAYING: return

func _ev_footsteps() -> void:
	var back := player.camera.global_transform.basis.z
	back.y = 0
	back = back.normalized()
	for i in 7:
		var d := 6.0 - i * 0.75
		_play3d("monster_step", player.global_position + back * d, -2.0 + i, 1.1)
		await _wait(0.42)
		if phase != Phase.PLAYING: return
	# Silence... and a chance that something is really there.
	behind_dir = back
	behind_window = 3.0 if randf() < 0.6 else 0.0

func _ev_breath() -> void:
	var right := player.camera.global_transform.basis.x * 0.7
	_play3d("breath", player.camera.global_position + right + Vector3(0, 0.1, 0), 4.0, 0.85)
	await _wait(2.5)
	if phase != Phase.PLAYING: return
	_show_msg("...كان قريباً من أذنك", 2.0)

func _blackout_all(t: float) -> void:
	for L in level.lights:
		L.kill = t

func _flicker_near(p: Vector3, r: float, t: float) -> void:
	for L in level.lights:
		if L.light.global_position.distance_to(p) < r:
			L.kill = t * randf_range(0.6, 1.0)

# ============================================================== endings
func _on_caught() -> void:
	if phase != Phase.PLAYING:
		return
	phase = Phase.DEAD
	controls.enabled = false
	controls.visible = false
	hud.visible = false
	player.frozen = true
	_hide_ghost()
	# Snap the view to the creature, then its face lunges into the camera.
	var cam := player.camera
	monster.global_position = player.global_position - cam.global_transform.basis.z * 0.9
	monster.global_position.y = 0
	var flat_target := Vector3(player.global_position.x, 0, player.global_position.z)
	if monster.global_position.distance_to(flat_target) > 0.1:
		monster.look_at(flat_target, Vector3.UP)
	player.forced_look_target = monster.global_position + Vector3(0, 2.3, 0)
	player.flicker_override = 0.0
	player.flashlight_on = true
	player.battery = maxf(player.battery, 0.5)
	await _wait(0.12)
	monster.visible = false
	face.visible = true
	face_light.visible = true
	face.twitch_strength = 3.0
	face.set_eye_glow(12.0)
	_play2d("screech", 4.0, 0.9)
	_play2d("bang", 2.0, 0.7)
	Input.vibrate_handheld(1000)
	player.add_shake(1.6)
	var t := 0.0
	while t < 1.5:
		await get_tree().process_frame
		t += get_process_delta_time()
		player.add_shake(1.2)
		face.position = Vector3(randf_range(-0.015, 0.015), -0.04 + randf_range(-0.01, 0.01), lerpf(-1.8, -0.55, minf(t * 7.0, 1.0)))
		red_flash = 0.12 + 0.3 * absf(sin(t * 18.0))
		glitch = 0.35 + 0.3 * randf()
	drone.stop()
	heart.stop()
	get_tree().call_group("sfx", "stop")
	red_flash = 0.0
	fade = 1.0
	face.visible = false
	face_light.visible = false
	await _wait(1.0)
	_show_end("لقد أمسك بك", "جمعت %d من %d مفاتيح" % [keys_found, KEYS_NEEDED], "حاول مجدداً")

func _on_win() -> void:
	phase = Phase.WON
	controls.enabled = false
	controls.visible = false
	hud.visible = false
	player.frozen = true
	monster.frozen = true
	monster.visible = false
	_play2d("bang", -2.0, 1.3)
	fade = 1.0
	drone.stop()
	heart.stop()
	await _wait(1.5)
	_show_big("نجوت...", 3.0)
	await _wait(3.2)
	# ...or did you?
	fade = 0.0
	face.visible = true
	face_light.visible = true
	face.twitch_strength = 3.0
	face.set_eye_glow(12.0)
	face.position = Vector3(0, -0.04, -0.6)
	_play2d("screech", 4.0, 1.1)
	Input.vibrate_handheld(800)
	player.add_shake(1.5)
	red_flash = 1.0
	glitch = 1.0
	await _wait(0.7)
	face.visible = false
	face_light.visible = false
	fade = 1.0
	red_flash = 0.0
	await _wait(1.2)
	var tm := "%d:%02d" % [int(play_time) / 60, int(play_time) % 60]
	if best_time < 0.0 or play_time < best_time:
		best_time = play_time
	_show_end("...حقاً؟", "هربت في %s\nلكنه لا يزال يتذكر وجهك" % tm, "العب مجدداً")

# ============================================================== UI
func _build_ui() -> void:
	var fx := CanvasLayer.new()
	fx.layer = 1
	add_child(fx)
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_mat = ShaderMaterial.new()
	overlay_mat.shader = load("res://shaders/overlay.gdshader")
	overlay.material = overlay_mat
	fx.add_child(overlay)

	ui = CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 30

	controls = TouchControls.new()
	controls.theme = theme
	controls.enabled = false
	controls.visible = false
	ui.add_child(controls)

	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.theme = theme
	hud.visible = false
	ui.add_child(hud)
	keys_label = Label.new()
	keys_label.position = Vector2(40, 60)
	keys_label.add_theme_font_size_override("font_size", 34)
	keys_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	keys_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud.add_child(keys_label)
	var bat_bg := ColorRect.new()
	bat_bg.color = Color(0, 0, 0, 0.5)
	bat_bg.position = Vector2(40, 125)
	bat_bg.size = Vector2(180, 10)
	hud.add_child(bat_bg)
	battery_bar = ColorRect.new()
	battery_bar.position = Vector2(40, 125)
	battery_bar.size = Vector2(180, 10)
	hud.add_child(battery_bar)
	var st_bg := ColorRect.new()
	st_bg.color = Color(0, 0, 0, 0.5)
	st_bg.position = Vector2(40, 145)
	st_bg.size = Vector2(180, 6)
	hud.add_child(st_bg)
	stamina_bar = ColorRect.new()
	stamina_bar.color = Color(0.7, 0.7, 0.75, 0.7)
	stamina_bar.position = Vector2(40, 145)
	stamina_bar.size = Vector2(180, 6)
	hud.add_child(stamina_bar)
	var hint := Label.new()
	hint.text = "المصباح / الركض"
	hint.position = Vector2(232, 118)
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.6))
	hud.add_child(hint)

	msg_label = _center_label(34, Color(0.88, 0.85, 0.8))
	msg_label.anchor_top = 0.2
	msg_label.anchor_bottom = 0.32
	msg_label.theme = theme
	ui.add_child(msg_label)
	big_label = _center_label(96, Color(0.75, 0.0, 0.0))
	big_label.anchor_top = 0.35
	big_label.anchor_bottom = 0.55
	big_label.theme = theme
	ui.add_child(big_label)

	# ---- title
	title_panel = ColorRect.new()
	(title_panel as ColorRect).color = Color(0, 0, 0, 1)
	title_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_panel.theme = theme
	title_panel.visible = false
	ui.add_child(title_panel)
	var t1 := _center_label(92, Color(0.7, 0.02, 0.02))
	t1.text = "لا تنظر خلفك"
	t1.anchor_top = 0.18
	t1.anchor_bottom = 0.32
	title_panel.add_child(t1)
	var t2 := _center_label(28, Color(0.6, 0.58, 0.55))
	t2.text = "الجناح رقم ٧ أُغلق منذ ثلاثين عاماً.\nلم يخرج منه أحد.\nحتى الآن."
	t2.anchor_top = 0.34
	t2.anchor_bottom = 0.5
	title_panel.add_child(t2)
	var t3 := _center_label(24, Color(0.5, 0.5, 0.5))
	t3.text = "يسار الشاشة: عصا الحركة (اسحب بعيداً للركض)\nيمين الشاشة: اسحب للنظر\nزر «ضوء»: المصباح   ·   زر «التفت»: استدارة سريعة\n\nاجمع ٥ مفاتيح ثم اهرب من باب المخرج\nالمصباح يكشفك له من بعيد...\n\nاستخدم سماعات الرأس وأطفئ الأنوار"
	t3.anchor_top = 0.52
	t3.anchor_bottom = 0.8
	title_panel.add_child(t3)
	title_hint = _center_label(36, Color(0.85, 0.8, 0.75))
	title_hint.text = "المس الشاشة للبدء"
	title_hint.anchor_top = 0.84
	title_hint.anchor_bottom = 0.92
	title_panel.add_child(title_hint)

func _center_label(fs: int, col: Color) -> Label:
	var l := Label.new()
	l.anchor_left = 0.05
	l.anchor_right = 0.95
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

func _show_end(title: String, sub: String, btn_text: String) -> void:
	end_panel = Control.new()
	end_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_panel.theme = title_panel.theme
	ui.add_child(end_panel)
	var a := _center_label(84, Color(0.75, 0.0, 0.0))
	a.text = title
	a.anchor_top = 0.25
	a.anchor_bottom = 0.4
	end_panel.add_child(a)
	var b := _center_label(30, Color(0.7, 0.68, 0.65))
	b.text = sub
	b.anchor_top = 0.42
	b.anchor_bottom = 0.55
	end_panel.add_child(b)
	var btn := Button.new()
	btn.text = btn_text
	btn.add_theme_font_size_override("font_size", 40)
	btn.anchor_left = 0.2
	btn.anchor_right = 0.8
	btn.anchor_top = 0.65
	btn.anchor_bottom = 0.73
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.25, 0.02, 0.02)
	sb.border_color = Color(0.6, 0.1, 0.1)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.pressed.connect(func():
		quick_restart = true
		get_tree().reload_current_scene())
	end_panel.add_child(btn)
	var menu := Button.new()
	menu.text = "القائمة الرئيسية"
	menu.flat = true
	menu.add_theme_font_size_override("font_size", 28)
	menu.anchor_left = 0.25
	menu.anchor_right = 0.75
	menu.anchor_top = 0.76
	menu.anchor_bottom = 0.82
	menu.pressed.connect(func():
		quick_restart = false
		get_tree().reload_current_scene())
	end_panel.add_child(menu)

func _show_msg(text: String, t: float) -> void:
	msg_label.text = text
	_msg_time = t

func _show_big(text: String, t: float) -> void:
	big_label.text = text
	_big_time = t

func _update_effects(delta: float) -> void:
	_msg_time -= delta
	msg_label.modulate.a = clampf(_msg_time * 1.5, 0.0, 1.0)
	_big_time -= delta
	big_label.visible = _big_time > 0.0
	glitch = maxf(glitch - delta * 1.6, 0.0)
	red_flash = maxf(red_flash - delta * 1.5, 0.0)
	if phase == Phase.PLAYING:
		fade = maxf(fade - delta * 0.6, 0.0)
	overlay_mat.set_shader_parameter("fear", fear)
	overlay_mat.set_shader_parameter("glitch", glitch)
	overlay_mat.set_shader_parameter("red_flash", red_flash)
	overlay_mat.set_shader_parameter("fade", fade)

# ============================================================== helpers
func _wait(t: float) -> Signal:
	return get_tree().create_timer(t).timeout

func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _ray_clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _play2d(sound: String, vol := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = Sfx.get_sound(sound)
	p.volume_db = vol
	p.pitch_scale = pitch
	p.add_to_group("sfx")
	add_child(p)
	p.play()
	if not Sfx.get_sound(sound).loop_mode == AudioStreamWAV.LOOP_FORWARD:
		p.finished.connect(p.queue_free)
	return p

func _play3d(sound: String, pos: Vector3, vol := 0.0, pitch := 1.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = Sfx.get_sound(sound)
	p.volume_db = vol
	p.pitch_scale = pitch
	p.unit_size = 4.0
	p.max_distance = 40.0
	p.add_to_group("sfx")
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
