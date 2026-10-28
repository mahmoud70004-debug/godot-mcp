extends Node

const WorldScript = preload("res://scripts/world.gd")
const PlayerScript = preload("res://scripts/player.gd")
const HudScript = preload("res://scripts/hud.gd")

var world
var player
var hud
var inventory: Array[String] = []
var inventory_open := false
var notice := "Find a way through the silent village."
var notice_time := 7.0

func _ready() -> void:
	var container := SubViewportContainer.new()
	container.name = "RetroViewport"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(container)
	var viewport := SubViewport.new()
	viewport.name = "WorldViewport"
	viewport.size = Vector2i(480, 270)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	# Keep the 3D image low-resolution while the touch interface stays crisp.
	container.stretch_shrink = 2
	world = WorldScript.new()
	world.name = "ValdronOutskirts"
	viewport.add_child(world)
	player = PlayerScript.new()
	player.name = "Knight"
	world.add_child(player)
	player.position = Vector3(0, 0.05, 13)
	hud = HudScript.new()
	hud.name = "MobileHUD"
	hud.game = self
	add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	if notice_time > 0.0:
		notice_time -= delta
	if is_instance_valid(hud):
		hud.queue_redraw()

func show_notice(text: String, duration := 3.0) -> void:
	notice = text
	notice_time = duration

func interact() -> void:
	if inventory_open:
		return
	var item = world.get_nearby_item(player.global_position)
	if item != null:
		inventory.append(item.item_name)
		show_notice("FOUND: " + item.item_name + "  /  " + item.description, 6.0)
		item.queue_free()
	else:
		show_notice("Nothing within reach.")

func attack() -> void:
	if inventory_open:
		return
	if player.swing():
		if world.hit_enemy(player.global_position, -player.global_transform.basis.z):
			show_notice("The hollow recoils.")

func toggle_inventory() -> void:
	inventory_open = not inventory_open
	player.input_locked = inventory_open
	if inventory_open:
		player.move_input = Vector2.ZERO
		player.defending = false
