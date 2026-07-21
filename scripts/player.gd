extends CharacterBody3D

@export var speed: float = 6.0
@export var acceleration: float = 24.0
@export var gravity_strength: float = 24.0


func _physics_process(delta: float) -> void:
	var input_vector := Vector2.ZERO

	if Input.is_key_pressed(KEY_A):
		input_vector.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_vector.x += 1.0
	if Input.is_key_pressed(KEY_W):
		input_vector.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_vector.y += 1.0

	if input_vector.length() > 1.0:
		input_vector = input_vector.normalized()

	var direction := Vector3(input_vector.x, 0.0, input_vector.y)

	velocity.x = move_toward(
		velocity.x,
		direction.x * speed,
		acceleration * delta
	)
	velocity.z = move_toward(
		velocity.z,
		direction.z * speed,
		acceleration * delta
	)

	if not is_on_floor():
		velocity.y -= gravity_strength * delta
	else:
		velocity.y = 0.0

	if direction.length() > 0.05:
		var look_target := global_position + direction
		look_target.y = global_position.y
		look_at(look_target, Vector3.UP)

	move_and_slide()
