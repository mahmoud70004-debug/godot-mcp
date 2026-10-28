extends CharacterBody3D

var move_input := Vector2.ZERO
var defending := false
var input_locked := false
var camera: Camera3D
var blade: Node3D
var swing_timer := 0.0
const SPEED := 3.5
const LOOK_SENSITIVITY := 0.003

func _ready() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.7
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.85
	add_child(collision)
	camera = Camera3D.new()
	camera.position.y = 1.55
	camera.fov = 72.0
	camera.current = true
	add_child(camera)
	_create_sword()

func _create_sword() -> void:
	blade = Node3D.new()
	blade.position = Vector3(0.48, -0.43, -0.85)
	blade.rotation_degrees = Vector3(-12, -12, -16)
	camera.add_child(blade)
	_piece(Vector3(0.10, 0.65, 0.035), Vector3(0, 0.32, 0), Color("a8aca2"))
	_piece(Vector3(0.30, 0.055, 0.07), Vector3(0, -0.01, 0), Color("81704e"))
	_piece(Vector3(0.075, 0.25, 0.07), Vector3(0, -0.15, 0), Color("403428"))

func _piece(size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mesh.material = mat
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	blade.add_child(instance)

func look(relative: Vector2) -> void:
	rotate_y(-relative.x * LOOK_SENSITIVITY)
	camera.rotation.x = clampf(camera.rotation.x - relative.y * LOOK_SENSITIVITY, -1.15, 1.15)

func swing() -> bool:
	if swing_timer > 0.0:
		return false
	swing_timer = 0.4
	return true

func _physics_process(delta: float) -> void:
	var keyboard := Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	var input := Vector2.ZERO if input_locked else (move_input + keyboard).limit_length(1.0)
	var direction := global_transform.basis * Vector3(input.x, 0, input.y)
	var speed := SPEED * (0.55 if defending else 1.0)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.1
	move_and_slide()
	if swing_timer > 0.0:
		swing_timer = maxf(0.0, swing_timer - delta)
	blade.rotation_degrees.z = -16.0 - sin((swing_timer / 0.4) * PI) * 65.0 if swing_timer > 0.0 else (-55.0 if defending else -16.0)
