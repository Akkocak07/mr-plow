extends CharacterBody3D

@export var speed := 5.0
@export var gravity := 20.0

func _physics_process(delta):
	var input = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)

	var direction = Vector3(input.x, 0, input.y)

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	if !is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	move_and_slide()
