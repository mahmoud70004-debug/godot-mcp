class_name DangerFeedback
extends Node
## V24: the frame tightens with danger. Twice a second it reads how close the nearest awake hunter
## is (chasing / winding up / attacking, within REACH m) and how low the player's health is, and
## eases the retro_post `danger` uniform towards the larger of the two (vignette closes and
## breathes in a dark blood tone). No physics, no allocations per frame beyond one float lerp.

const REACH := 22.0
const NEAR := 6.0
## Health ratio under which the frame starts to close (full at 0.15).
const LOW_HEALTH := 0.5
const EASE_IN := 2.5
const EASE_OUT := 0.8

var _material: ShaderMaterial
var _player: Node3D
var _target := 0.0
var _value := 0.0
var _clock := 0.0


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	var post := get_parent().find_child("PostProcess", false, false)
	var screen := post.get_node_or_null("Screen") as CanvasItem if post else null
	_material = screen.material as ShaderMaterial if screen else null
	set_process(_material != null)


func _process(delta: float) -> void:
	_clock -= delta
	if _clock <= 0.0:
		_clock = 0.5
		_target = _read_danger()
	var rate := EASE_IN if _target > _value else EASE_OUT
	var next := move_toward(_value, _target, rate * delta)
	if absf(next - _value) > 0.002:
		_value = next
		_material.set_shader_parameter("danger", _value)
	elif _value != _target and absf(_target - _value) <= 0.002:
		_value = _target
		_material.set_shader_parameter("danger", _value)


func _read_danger() -> float:
	if _player == null or not is_instance_valid(_player):
		return 0.0
	var danger := 0.0
	var health := _player.get("health") as HealthComponent
	if health != null and not health.is_dead:
		danger = (1.0 - smoothstep(0.15, LOW_HEALTH, health.get_ratio())) * 0.85
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.state == Enemy.State.IDLE or enemy.state == Enemy.State.DEAD:
			continue
		var d := enemy.global_position.distance_to(_player.global_position)
		danger = maxf(danger, (1.0 - smoothstep(NEAR, REACH, d)) * 0.9)
	return danger
