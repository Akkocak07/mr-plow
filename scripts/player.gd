extends CharacterBody3D

@export var movement_speed: float = 5.5
@export var acceleration: float = 22.0
@export var gravity_strength: float = 24.0
@export var mouse_sensitivity: float = 0.0022

var camera: Camera3D
var tool_anchor: Node3D
var tool_model_root: Node3D

var camera_pitch: float = 0.0
var tool_action_time: float = 0.0
var walk_time: float = 0.0
var base_tool_position := Vector3(0.48, -0.40, -0.92)
var base_tool_rotation := Vector3(
	deg_to_rad(-4.0),
	deg_to_rad(-7.0),
	deg_to_rad(-8.0)
)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_create_camera()
	_create_tool_anchor()
	set_tool_model(0)


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

	var local_direction := Vector3(input_vector.x, 0.0, input_vector.y)
	var world_direction := transform.basis * local_direction
	world_direction.y = 0.0

	if world_direction.length() > 0.0:
		world_direction = world_direction.normalized()

	velocity.x = move_toward(
		velocity.x,
		world_direction.x * movement_speed,
		acceleration * delta
	)
	velocity.z = move_toward(
		velocity.z,
		world_direction.z * movement_speed,
		acceleration * delta
	)

	if not is_on_floor():
		velocity.y -= gravity_strength * delta
	else:
		velocity.y = 0.0

	move_and_slide()

	if input_vector.length() > 0.05 and is_on_floor():
		walk_time += delta * 9.0
	else:
		walk_time = lerpf(walk_time, 0.0, minf(delta * 8.0, 1.0))


func _process(delta: float) -> void:
	if not is_instance_valid(tool_anchor):
		return

	tool_action_time = maxf(tool_action_time - delta, 0.0)

	var movement_amount: float = Vector2(velocity.x, velocity.z).length()
	var bob_strength: float = clampf(movement_amount / movement_speed, 0.0, 1.0)
	var bob := Vector3(
		cos(walk_time * 0.5) * 0.012,
		sin(walk_time) * 0.018,
		0.0
	) * bob_strength

	var action_offset := Vector3.ZERO
	var action_rotation := Vector3.ZERO

	if tool_action_time > 0.0:
		var progress: float = 1.0 - (tool_action_time / 0.24)
		var swing: float = sin(progress * PI)
		action_offset = Vector3(-0.06 * swing, -0.13 * swing, -0.20 * swing)
		action_rotation = Vector3(
			deg_to_rad(-24.0) * swing,
			0.0,
			deg_to_rad(8.0) * swing
		)

	tool_anchor.position = base_tool_position + bob + action_offset
	tool_anchor.rotation = base_tool_rotation + action_rotation


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_y(-event.relative.x * mouse_sensitivity)
			camera_pitch = clampf(
				camera_pitch - event.relative.y * mouse_sensitivity,
				deg_to_rad(-82.0),
				deg_to_rad(82.0)
			)
			camera.rotation.x = camera_pitch

	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func play_tool_action() -> void:
	tool_action_time = 0.24


func get_forward_direction() -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	return forward.normalized()


func set_tool_model(model_index: int) -> void:
	if not is_instance_valid(tool_model_root):
		return

	for child in tool_model_root.get_children():
		child.queue_free()

	match model_index:
		0:
			_build_basic_shovel()
		1:
			_build_wide_shovel()
		2:
			_build_snow_blower()
		3:
			_build_compact_plow()
		_:
			_build_basic_shovel()


func _create_camera() -> void:
	camera = Camera3D.new()
	camera.name = "FirstPersonCamera"
	camera.position = Vector3(0.0, 0.62, 0.0)
	camera.current = true
	camera.near = 0.04
	camera.fov = 76.0
	add_child(camera)


func _create_tool_anchor() -> void:
	tool_anchor = Node3D.new()
	tool_anchor.name = "ToolAnchor"
	tool_anchor.position = base_tool_position
	tool_anchor.rotation = base_tool_rotation
	camera.add_child(tool_anchor)

	tool_model_root = Node3D.new()
	tool_model_root.name = "ToolModel"
	tool_anchor.add_child(tool_model_root)


func _build_basic_shovel() -> void:
	var wood := _material(Color(0.42, 0.23, 0.08), 0.90, 0.0)
	var metal := _material(Color(0.20, 0.28, 0.38), 0.48, 0.35)

	var handle := _box(
		tool_model_root,
		"WoodenHandle",
		Vector3(0.075, 1.10, 0.075),
		Vector3(0.0, 0.08, 0.0),
		wood
	)
	handle.rotation_degrees.z = -18.0

	var grip := _box(
		tool_model_root,
		"Grip",
		Vector3(0.30, 0.07, 0.07),
		Vector3(-0.18, 0.58, 0.0),
		wood
	)
	grip.rotation_degrees.z = -18.0

	var blade := _box(
		tool_model_root,
		"Blade",
		Vector3(0.50, 0.08, 0.38),
		Vector3(0.18, -0.48, -0.04),
		metal
	)
	blade.rotation_degrees.z = -18.0


func _build_wide_shovel() -> void:
	var dark := _material(Color(0.08, 0.10, 0.13), 0.78, 0.05)
	var blue := _material(Color(0.06, 0.27, 0.62), 0.55, 0.10)
	var edge := _material(Color(0.52, 0.58, 0.65), 0.38, 0.48)

	var handle := _box(
		tool_model_root,
		"ReinforcedHandle",
		Vector3(0.10, 1.05, 0.10),
		Vector3(0.0, 0.06, 0.0),
		dark
	)
	handle.rotation_degrees.z = -15.0

	var grip_left := _box(
		tool_model_root,
		"GripLeft",
		Vector3(0.34, 0.08, 0.08),
		Vector3(-0.20, 0.56, 0.0),
		dark
	)
	grip_left.rotation_degrees.z = -15.0

	var blade := _box(
		tool_model_root,
		"WideBlade",
		Vector3(0.92, 0.10, 0.43),
		Vector3(0.20, -0.46, -0.05),
		blue
	)
	blade.rotation_degrees.z = -15.0

	var cutting_edge := _box(
		tool_model_root,
		"CuttingEdge",
		Vector3(0.96, 0.06, 0.08),
		Vector3(0.24, -0.62, -0.10),
		edge
	)
	cutting_edge.rotation_degrees.z = -15.0


func _build_snow_blower() -> void:
	var body_material := _material(Color(0.82, 0.16, 0.06), 0.55, 0.12)
	var dark := _material(Color(0.06, 0.07, 0.09), 0.80, 0.05)
	var metal := _material(Color(0.35, 0.42, 0.48), 0.34, 0.55)

	_box(
		tool_model_root,
		"MachineBody",
		Vector3(0.76, 0.48, 0.62),
		Vector3(0.0, -0.18, 0.0),
		body_material
	)

	var chute := _cylinder(
		tool_model_root,
		"Chute",
		0.13,
		0.13,
		0.50,
		Vector3(0.10, 0.22, -0.08),
		dark
	)
	chute.rotation_degrees.x = 18.0

	var auger := _cylinder(
		tool_model_root,
		"Auger",
		0.23,
		0.23,
		0.82,
		Vector3(0.0, -0.38, -0.22),
		metal
	)
	auger.rotation_degrees.z = 90.0

	for wheel_x in [-0.40, 0.40]:
		var wheel := _cylinder(
			tool_model_root,
			"Wheel",
			0.18,
			0.18,
			0.13,
			Vector3(wheel_x, -0.38, 0.10),
			dark
		)
		wheel.rotation_degrees.z = 90.0

	for handle_x in [-0.30, 0.30]:
		var handle := _box(
			tool_model_root,
			"Handle",
			Vector3(0.07, 0.72, 0.07),
			Vector3(handle_x, 0.28, 0.28),
			dark
		)
		handle.rotation_degrees.x = -22.0

	_box(
		tool_model_root,
		"HandleBar",
		Vector3(0.72, 0.07, 0.07),
		Vector3(0.0, 0.61, 0.43),
		dark
	)


func _build_compact_plow() -> void:
	var body_material := _material(Color(0.92, 0.57, 0.05), 0.52, 0.15)
	var blade_material := _material(Color(0.15, 0.25, 0.38), 0.36, 0.52)
	var dark := _material(Color(0.05, 0.06, 0.08), 0.82, 0.02)
	var light_material := _material(Color(0.95, 0.92, 0.68), 0.20, 0.05)

	_box(
		tool_model_root,
		"VehicleBody",
		Vector3(0.78, 0.48, 0.72),
		Vector3(0.0, -0.06, 0.10),
		body_material
	)

	_box(
		tool_model_root,
		"ControlPanel",
		Vector3(0.58, 0.12, 0.32),
		Vector3(0.0, 0.27, 0.22),
		dark
	)

	var plow_blade := _box(
		tool_model_root,
		"PlowBlade",
		Vector3(1.28, 0.46, 0.12),
		Vector3(0.0, -0.32, -0.46),
		blade_material
	)
	plow_blade.rotation_degrees.y = -10.0
	plow_blade.rotation_degrees.x = -8.0

	for wheel_x in [-0.43, 0.43]:
		var wheel := _cylinder(
			tool_model_root,
			"Wheel",
			0.20,
			0.20,
			0.15,
			Vector3(wheel_x, -0.34, 0.22),
			dark
		)
		wheel.rotation_degrees.z = 90.0

	for light_x in [-0.22, 0.22]:
		_box(
			tool_model_root,
			"Headlight",
			Vector3(0.16, 0.12, 0.05),
			Vector3(light_x, 0.08, -0.28),
			light_material
		)


func _material(
	color: Color,
	roughness: float,
	metallic: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _box(
	parent: Node,
	node_name: String,
	size: Vector3,
	position: Vector3,
	material: StandardMaterial3D
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position

	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material

	instance.mesh = mesh
	parent.add_child(instance)
	return instance


func _cylinder(
	parent: Node,
	node_name: String,
	top_radius: float,
	bottom_radius: float,
	height: float,
	position: Vector3,
	material: StandardMaterial3D
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 24
	mesh.material = material

	instance.mesh = mesh
	parent.add_child(instance)
	return instance
