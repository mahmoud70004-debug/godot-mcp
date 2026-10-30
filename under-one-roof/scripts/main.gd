extends Node2D
## The playable game: wires the world, Gideon, the HUD and the story director together.

const PLAYER_SCENE := preload("res://scenes/player.tscn")

@onready var world = $World
@onready var hud = $HUD
@onready var touch = $Touch
@onready var dialogue = $Dialogue
@onready var panels = $Panels
@onready var journal = $Journal
@onready var fader = $Fader
@onready var day_night: CanvasModulate = $DayNight

var player: CharacterBody2D
var _indoor := false
var _lantern: Sprite2D

# outdoor light over the day: [hour, color]
const LIGHT := [
	[0.0, Color(0.36, 0.40, 0.66)], [5.0, Color(0.42, 0.46, 0.72)], [6.5, Color(0.95, 0.86, 0.82)],
	[8.0, Color(1, 1, 1)], [16.5, Color(1, 1, 1)], [18.5, Color(1.0, 0.86, 0.72)],
	[20.0, Color(0.66, 0.62, 0.84)], [21.5, Color(0.40, 0.44, 0.70)], [24.0, Color(0.36, 0.40, 0.66)],
]


func _ready() -> void:
	Director.main = self
	player = PLAYER_SCENE.instantiate()
	world.entities.add_child(player)
	world.player_ref = player
	hud.player = player
	player.target_changed.connect(func(a): hud.set_prompt(Director.prompt_for(a)))
	touch.action_pressed.connect(func(): player.interact())
	touch.menu_pressed.connect(_toggle_journal)
	hud.journal_requested.connect(_toggle_journal)
	Game.flags_changed.connect(func():
		player.call_deferred("_pick_target")
		hud.call_deferred("set_prompt", Director.prompt_for(player.target)))

	_lantern = _make_lantern()
	player.add_child(_lantern)
	Game.inventory_changed.connect(_refresh_outfit)
	_refresh_outfit()
	Director._zone_id = ""

	fader._black.modulate.a = 1.0
	Game.input_locked = false
	Game.time_running = true
	if Game.pending_load:
		Game.pending_load = false
		player.global_position = Game.player_pos
		player.face("down")
		world.refresh()
		Director._update_zone(true)
		player.camera.reset_smoothing()
		await fader.fade_in(0.8)
	else:
		player.global_position = world.spot_pos("game_start")
		player.face("down")
		Director._update_zone(true)
		player.camera.reset_smoothing()
		Director.intro()


func set_indoor(on: bool) -> void:
	_indoor = on


func _process(_delta: float) -> void:
	var h := fmod(Game.minutes / 60.0, 24.0)
	var c := Color.WHITE
	for i in LIGHT.size() - 1:
		var a = LIGHT[i]
		var b = LIGHT[i + 1]
		if h >= a[0] and h <= b[0]:
			c = a[1].lerp(b[1], (h - a[0]) / (b[0] - a[0]))
			break
	if _indoor:
		# warm, slightly dim interiors so hearths and candles glow
		c = Color(0.9, 0.82, 0.72).lerp(c, 0.2)
		if h >= 20.0 or h < 6.0:
			c = Color(0.66, 0.56, 0.5)
	day_night.color = c
	_lantern.visible = not _indoor and (h >= 19.5 or h < 5.5) and Game.count("lantern") > 0


func _make_lantern() -> Sprite2D:
	var g := Sprite2D.new()
	var tex := GradientTexture2D.new()
	tex.width = 160
	tex.height = 160
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.55, 0.5))
	grad.set_color(1, Color(1.0, 0.7, 0.3, 0.0))
	tex.gradient = grad
	g.texture = tex
	g.position = Vector2(0, -10)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = mat
	g.z_index = 5
	g.visible = false
	return g


## Runa's jacket changes how Gideon looks.
func _refresh_outfit() -> void:
	var sheet := "gideon_outfit" if Game.count("outfit") > 0 else "gideon"
	player.sprite.texture = load("res://assets/chars/%s.png" % sheet)


func _toggle_journal() -> void:
	if journal.is_open():
		journal.close()
	elif not Game.input_locked and not Director.busy:
		journal.open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		_toggle_journal()
