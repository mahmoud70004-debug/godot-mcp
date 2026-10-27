class_name HitboxComponent
extends Area3D
## Deals damage to every HurtboxComponent it overlaps while active.
## Each hurtbox is hit at most once per activation (one swing = one hit).

signal hit_landed(hurtbox: HurtboxComponent)

var _active := false
var _damage := 0.0
var _knockback := 0.0
var _source: Node3D
var _already_hit: Array[HurtboxComponent] = []


func _ready() -> void:
	monitoring = true
	monitorable = false


func activate(damage: float, knockback: float, source: Node3D) -> void:
	_damage = damage
	_knockback = knockback
	_source = source
	_already_hit.clear()
	_active = true


func deactivate() -> void:
	_active = false


func is_active() -> bool:
	return _active


func _physics_process(_delta: float) -> void:
	if not _active:
		return
	for area in get_overlapping_areas():
		var hurtbox := area as HurtboxComponent
		if hurtbox == null or _already_hit.has(hurtbox) or hurtbox.owner == _source:
			continue
		_already_hit.append(hurtbox)
		hurtbox.receive_hit(DamageInfo.new(_damage, _source, _knockback))
		hit_landed.emit(hurtbox)
