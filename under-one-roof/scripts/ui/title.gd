extends Node2D
## Title screen: the village drifts by behind the game's name.

@onready var camera: Camera2D = $Camera

var _t := 0.0
var _ui: CanvasLayer


func _ready() -> void:
	Game.flags = {"ch1": true}
	Game.minutes = 9 * 60
	Game.input_locked = true
	Game.time_running = false
	Audio.music("village")
	Audio.ambience("sea")
	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	UI.full_rect(root)
	_ui.add_child(root)
	var shade := ColorRect.new()
	UI.full_rect(shade)
	shade.color = Color(0.05, 0.04, 0.06, 0.25)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.offset_left = -170
	v.offset_right = 170
	v.offset_top = -150
	v.offset_bottom = 150
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	root.add_child(v)
	var title := UI.label("تحت سقف واحد", 46, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_font_override("font", load("res://assets/fonts/Lalezar.ttf"))
	title.add_theme_color_override("font_outline_color", UI.WOOD_DARK)
	title.add_theme_constant_override("outline_size", 10)
	v.add_child(title)
	var sub := UI.label("UNDER ONE ROOF", 15, UI.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	sub.add_theme_color_override("font_outline_color", UI.WOOD_DARK)
	sub.add_theme_constant_override("outline_size", 6)
	v.add_child(sub)
	var place := UI.label("هرافنفيك، آيسلندا — 1887", 13, UI.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	place.add_theme_color_override("font_outline_color", UI.WOOD_DARK)
	place.add_theme_constant_override("outline_size", 6)
	v.add_child(place)
	v.add_child(Control.new())

	if Game.has_save():
		var cont := UI.button("متابعة الرحلة", 16)
		cont.focus_mode = Control.FOCUS_ALL
		cont.pressed.connect(_continue)
		v.add_child(cont)
		cont.call_deferred("grab_focus")
	var new := UI.button("لعبة جديدة", 16)
	new.focus_mode = Control.FOCUS_ALL
	new.pressed.connect(_new_game)
	v.add_child(new)
	if not Game.has_save():
		new.call_deferred("grab_focus")
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var quit := UI.button("خروج", 14)
		quit.focus_mode = Control.FOCUS_ALL
		quit.pressed.connect(func(): get_tree().quit())
		v.add_child(quit)

	var foot := UI.label("قصة عن عائلة، وثروة، وحقيقة مدفونة.", 12, UI.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	foot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	foot.offset_left = -200
	foot.offset_right = 200
	foot.offset_top = -28
	foot.offset_bottom = -8
	foot.add_theme_color_override("font_outline_color", UI.WOOD_DARK)
	foot.add_theme_constant_override("outline_size", 5)
	root.add_child(foot)


func _process(delta: float) -> void:
	_t += delta
	camera.position = Vector2(1000 + sin(_t * 0.05) * 520, 700 + sin(_t * 0.08) * 220)


func _new_game() -> void:
	Audio.sfx("select")
	Game.new_game()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _continue() -> void:
	Audio.sfx("select")
	if Game.load_game():
		get_tree().change_scene_to_file("res://scenes/main.tscn")
