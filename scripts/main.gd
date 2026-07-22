extends Node3D

const SAVE_PATH := "user://mr_plow_progress.json"
const BASE_GRID_SIZE := 29
const MAX_GRID_SIZE := 35
const SNOW_TILE_SPACING := 0.68
const SNOW_TILE_SIZE := 0.74
const SNOW_BASE_HEIGHT := 0.16
const SNOW_BASE_Y := 0.055

var player
var persistent_effects_root: Node3D
var level_root: Node3D
var scenery_root: Node3D
var snow_root: Node3D

var active_snow: Array[Node3D] = []
var blockers: Array[Dictionary] = []
var snow_materials: Array[ShaderMaterial] = []

var rng := RandomNumberGenerator.new()
var spray_mesh: SphereMesh

var level_number: int = 1
var current_grid_size: int = BASE_GRID_SIZE
var current_area_half: float = 9.5
var current_house_count: int = 0
var current_car_count: int = 0
var current_level_seed: int = 0

var snow_cleared: int = 0
var total_snow: int = 0
var money: int = 0

var upgrade_level: int = -1
var current_tool_name := "Basic Snow Shovel"
var clear_radius: float = 0.62
var clear_distance: float = 1.20
var payout_per_tile: int = 1
var action_interval: float = 0.28
var action_cooldown: float = 0.0

var level_transitioning := false
var completion_announced := false

var level_label: Label
var snow_label: Label
var money_label: Label
var tool_label: Label
var upgrade_label: Label
var layout_label: Label
var status_label: Label
var level_banner: Label

var upgrades: Array[Dictionary] = [
	{
		"name": "Wide Snow Shovel",
		"cost": 200,
		"radius": 0.96,
		"distance": 1.35,
		"payout": 1,
		"interval": 0.23,
		"model": 1
	},
	{
		"name": "Electric Snow Blower",
		"cost": 400,
		"radius": 1.50,
		"distance": 1.55,
		"payout": 2,
		"interval": 0.13,
		"model": 2
	},
	{
		"name": "Compact Snow Plow",
		"cost": 2000,
		"radius": 2.25,
		"distance": 1.80,
		"payout": 4,
		"interval": 0.08,
		"model": 3
	}
]


func _ready() -> void:
	rng.randomize()
	_create_snow_materials()
	_load_progress()
	_apply_upgrade_state()
	_create_environment()
	_create_player()
	_create_hud()
	_create_effects_root()
	_create_spray_resources()
	_start_level(level_number)


func _process(delta: float) -> void:
	action_cooldown = maxf(action_cooldown - delta, 0.0)

	if level_transitioning:
		return

	var shovel_pressed := (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		or Input.is_key_pressed(KEY_SPACE)
	)

	if shovel_pressed and action_cooldown <= 0.0:
		action_cooldown = action_interval
		_clear_snow_in_front()
		player.play_tool_action()

	if active_snow.is_empty() and not completion_announced:
		completion_announced = true
		_finish_level()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return

	if event.keycode == KEY_U:
		_buy_next_upgrade()
	elif event.keycode == KEY_R and not level_transitioning:
		_generate_snow()
		status_label.text = "Fresh snow was generated for this property."


func _start_level(new_level: int) -> void:
	level_number = maxi(new_level, 1)
	level_transitioning = false
	completion_announced = false
	action_cooldown = 0.0

	current_level_seed = (
		int(Time.get_ticks_msec())
		+ level_number * 7919
		+ rng.randi_range(1, 999999)
	)
	rng.seed = current_level_seed

	current_grid_size = mini(
		BASE_GRID_SIZE + (level_number - 1) * 2,
		MAX_GRID_SIZE
	)
	current_area_half = (
		float(current_grid_size - 1)
		* SNOW_TILE_SPACING
		* 0.5
	)
	current_house_count = mini(
		1 + int(float(level_number - 1) / 3.0),
		3
	)
	current_car_count = mini(
		1 + int(float(level_number - 1) / 1.4),
		6
	)

	_clear_old_level()
	_create_level_root()
	_create_level_ground()
	_generate_houses(current_house_count)
	_generate_cars(current_car_count)
	_generate_small_obstacles()
	_generate_snow()

	var spawn_position := Vector3(
		0.0,
		1.0,
		current_area_half - 1.35
	)
	player.reset_for_level(spawn_position)
	player.set_tool_model(upgrade_level + 1)

	status_label.text = (
		"Clear all accessible snow. Cars and buildings are solid obstacles."
	)
	_show_level_banner(
		"LEVEL %d\n%d HOUSES  |  %d CARS"
		% [
			level_number,
			current_house_count,
			current_car_count
		]
	)
	_update_hud()
	_save_progress()


func _clear_old_level() -> void:
	active_snow.clear()
	blockers.clear()

	if is_instance_valid(level_root):
		level_root.free()

	if is_instance_valid(persistent_effects_root):
		for child in persistent_effects_root.get_children():
			child.free()


func _create_level_root() -> void:
	level_root = Node3D.new()
	level_root.name = "Level_%03d" % level_number
	add_child(level_root)

	scenery_root = Node3D.new()
	scenery_root.name = "Scenery"
	level_root.add_child(scenery_root)

	snow_root = Node3D.new()
	snow_root.name = "RemovableSnow"
	level_root.add_child(snow_root)


func _create_level_ground() -> void:
	var outer_size: float = current_area_half * 2.0 + 16.0
	var driveway_size: float = current_area_half * 2.0 + 0.9

	var ground_material := _make_material(
		Color(0.09, 0.14, 0.11),
		0.97,
		0.0
	)
	_create_static_box(
		level_root,
		"Ground",
		Vector3(outer_size, 0.30, outer_size),
		Vector3(0.0, -0.15, 0.0),
		Vector3.ZERO,
		ground_material
	)

	var driveway_material := _make_material(
		Color(0.14, 0.16, 0.19),
		0.94,
		0.02
	)
	_create_visual_box(
		scenery_root,
		"Driveway",
		Vector3(driveway_size, 0.05, driveway_size),
		Vector3(0.0, 0.025, 0.0),
		Vector3.ZERO,
		driveway_material
	)

	var groove_material := _make_material(
		Color(0.08, 0.09, 0.11),
		0.97,
		0.0
	)
	for groove_x in [-4.6, -3.9, 3.9, 4.6]:
		_create_visual_box(
			scenery_root,
			"DrivewayGroove",
			Vector3(0.12, 0.012, driveway_size - 0.5),
			Vector3(groove_x, 0.058, 0.0),
			Vector3.ZERO,
			groove_material
		)

	_create_outer_snow(outer_size, driveway_size)


func _create_outer_snow(
	outer_size: float,
	driveway_size: float
) -> void:
	var side_width: float = (
		outer_size - driveway_size
	) * 0.5
	var side_offset: float = (
		driveway_size * 0.5
		+ side_width * 0.5
	)

	_create_visual_box(
		scenery_root,
		"OuterSnowNorth",
		Vector3(outer_size, 0.19, side_width),
		Vector3(0.0, 0.095, -side_offset),
		Vector3.ZERO,
		snow_materials[0]
	)
	_create_visual_box(
		scenery_root,
		"OuterSnowSouth",
		Vector3(outer_size, 0.19, side_width),
		Vector3(0.0, 0.095, side_offset),
		Vector3.ZERO,
		snow_materials[1]
	)
	_create_visual_box(
		scenery_root,
		"OuterSnowWest",
		Vector3(side_width, 0.19, driveway_size),
		Vector3(-side_offset, 0.095, 0.0),
		Vector3.ZERO,
		snow_materials[0]
	)
	_create_visual_box(
		scenery_root,
		"OuterSnowEast",
		Vector3(side_width, 0.19, driveway_size),
		Vector3(side_offset, 0.095, 0.0),
		Vector3.ZERO,
		snow_materials[2]
	)

	for side_x in [
		-current_area_half - 0.45,
		current_area_half + 0.45
	]:
		for z_index in range(
			-int(current_area_half),
			int(current_area_half) + 1,
			2
		):
			var bank := _create_visual_sphere(
				scenery_root,
				"SnowBank",
				Vector3(
					side_x,
					rng.randf_range(0.10, 0.22),
					float(z_index)
				),
				snow_materials[
					rng.randi_range(
						0,
						snow_materials.size() - 1
					)
				]
			)
			bank.scale = Vector3(
				rng.randf_range(1.0, 1.8),
				rng.randf_range(0.20, 0.42),
				rng.randf_range(0.75, 1.35)
			)


func _generate_houses(count: int) -> void:
	var house_colors: Array[Color] = [
		Color(0.48, 0.13, 0.10),
		Color(0.18, 0.31, 0.43),
		Color(0.45, 0.35, 0.21),
		Color(0.31, 0.42, 0.28),
		Color(0.43, 0.24, 0.35)
	]
	var sides: Array[int] = [0, 1, 2]

	for index in range(count):
		var side_index: int = (
			index + rng.randi_range(0, 2)
		) % sides.size()
		var side: int = sides[side_index]
		var width: float = rng.randf_range(4.8, 6.3)
		var depth: float = rng.randf_range(4.1, 5.4)
		var height: float = rng.randf_range(3.7, 4.7)
		var center := Vector2.ZERO
		var angle: float = 0.0

		if side == 0:
			center = Vector2(
				rng.randf_range(
					-current_area_half + 3.0,
					current_area_half - 3.0
				),
				-current_area_half + 1.25
			)
		elif side == 1:
			center = Vector2(
				-current_area_half + 1.25,
				rng.randf_range(
					-current_area_half + 3.0,
					current_area_half - 3.0
				)
			)
			angle = PI * 0.5
		else:
			center = Vector2(
				current_area_half - 1.25,
				rng.randf_range(
					-current_area_half + 3.0,
					current_area_half - 3.0
				)
			)
			angle = -PI * 0.5

		var half_size := Vector2(
			width * 0.5 + 0.28,
			depth * 0.5 + 0.28
		)
		var attempts: int = 0

		while not _can_place_obstacle(
			center,
			half_size,
			angle,
			1.0
		) and attempts < 30:
			attempts += 1

			if side == 0:
				center.x = rng.randf_range(
					-current_area_half + 3.0,
					current_area_half - 3.0
				)
			else:
				center.y = rng.randf_range(
					-current_area_half + 3.0,
					current_area_half - 3.0
				)

		_add_blocker(
			center,
			half_size,
			angle,
			"house"
		)
		_create_house_model(
			center,
			Vector3(width, height, depth),
			angle,
			house_colors[
				rng.randi_range(
					0,
					house_colors.size() - 1
				)
			],
			index
		)


func _create_house_model(
	center: Vector2,
	size: Vector3,
	angle: float,
	wall_color: Color,
	index: int
) -> void:
	var house := StaticBody3D.new()
	house.name = "House_%02d" % index
	house.position = Vector3(center.x, 0.0, center.y)
	house.rotation.y = angle
	scenery_root.add_child(house)

	var wall_material := _make_material(
		wall_color,
		0.86,
		0.0
	)
	var roof_material := _make_material(
		Color(0.07, 0.08, 0.10),
		0.94,
		0.03
	)
	var door_material := _make_material(
		Color(0.25, 0.11, 0.04),
		0.90,
		0.0
	)
	var window_material := _make_material(
		Color(0.22, 0.52, 0.73),
		0.22,
		0.14
	)

	_create_visual_box(
		house,
		"HouseBody",
		size,
		Vector3(0.0, size.y * 0.5, 0.0),
		Vector3.ZERO,
		wall_material
	)
	_create_visual_box(
		house,
		"Roof",
		Vector3(
			size.x + 0.55,
			0.72,
			size.z + 0.55
		),
		Vector3(0.0, size.y + 0.34, 0.0),
		Vector3.ZERO,
		roof_material
	)
	_create_visual_box(
		house,
		"RoofSnow",
		Vector3(
			size.x + 0.72,
			0.17,
			size.z + 0.72
		),
		Vector3(0.0, size.y + 0.79, 0.0),
		Vector3.ZERO,
		snow_materials[
			rng.randi_range(0, snow_materials.size() - 1)
		]
	)
	_create_visual_box(
		house,
		"FrontDoor",
		Vector3(1.05, 2.20, 0.14),
		Vector3(
			size.x * 0.25,
			1.10,
			size.z * 0.5 + 0.075
		),
		Vector3.ZERO,
		door_material
	)

	for window_x in [
		-size.x * 0.25,
		size.x * 0.05
	]:
		_create_visual_box(
			house,
			"Window",
			Vector3(1.05, 1.10, 0.12),
			Vector3(
				window_x,
				2.25,
				size.z * 0.5 + 0.07
			),
			Vector3.ZERO,
			window_material
		)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = Vector3(
		0.0,
		size.y * 0.5,
		0.0
	)
	house.add_child(collision)

	var porch_light := OmniLight3D.new()
	porch_light.position = Vector3(
		size.x * 0.25,
		2.55,
		size.z * 0.5 + 0.35
	)
	porch_light.light_color = Color(1.0, 0.72, 0.42)
	porch_light.light_energy = 1.8
	porch_light.omni_range = 5.5
	house.add_child(porch_light)


func _generate_cars(count: int) -> void:
	var car_colors: Array[Color] = [
		Color(0.62, 0.07, 0.06),
		Color(0.05, 0.19, 0.42),
		Color(0.16, 0.18, 0.21),
		Color(0.54, 0.56, 0.59),
		Color(0.12, 0.38, 0.22),
		Color(0.48, 0.24, 0.07)
	]

	for index in range(count):
		var half_size := Vector2(
			rng.randf_range(0.94, 1.08),
			rng.randf_range(1.85, 2.15)
		)
		var center := Vector2.ZERO
		var angle: float = 0.0
		var found_position := false

		for _attempt in range(100):
			center = Vector2(
				rng.randf_range(
					-current_area_half + 2.0,
					current_area_half - 2.0
				),
				rng.randf_range(
					-current_area_half + 2.0,
					current_area_half - 3.0
				)
			)

			var parking_direction: int = rng.randi_range(0, 3)
			angle = float(parking_direction) * PI * 0.5
			angle += deg_to_rad(
				rng.randf_range(-12.0, 12.0)
			)

			if _can_place_obstacle(
				center,
				half_size,
				angle,
				0.75
			):
				found_position = true
				break

		if not found_position:
			continue

		_add_blocker(
			center,
			half_size + Vector2(0.12, 0.15),
			angle,
			"car"
		)
		_create_car_model(
			center,
			half_size,
			angle,
			car_colors[
				rng.randi_range(
					0,
					car_colors.size() - 1
				)
			],
			index
		)


func _create_car_model(
	center: Vector2,
	half_size: Vector2,
	angle: float,
	body_color: Color,
	index: int
) -> void:
	var car := StaticBody3D.new()
	car.name = "Car_%02d" % index
	car.position = Vector3(center.x, 0.0, center.y)
	car.rotation.y = angle
	scenery_root.add_child(car)

	var body_material := _make_material(
		body_color,
		0.44,
		0.24
	)
	var window_material := _make_material(
		Color(0.08, 0.16, 0.22),
		0.18,
		0.24
	)
	var wheel_material := _make_material(
		Color(0.025, 0.028, 0.032),
		0.92,
		0.0
	)
	var metal_material := _make_material(
		Color(0.52, 0.56, 0.60),
		0.30,
		0.62
	)
	var light_material := _make_material(
		Color(0.95, 0.90, 0.62),
		0.20,
		0.02
	)

	var car_width: float = half_size.x * 2.0
	var car_length: float = half_size.y * 2.0

	_create_visual_box(
		car,
		"LowerBody",
		Vector3(car_width, 0.55, car_length),
		Vector3(0.0, 0.53, 0.0),
		Vector3.ZERO,
		body_material
	)
	_create_visual_box(
		car,
		"Cabin",
		Vector3(
			car_width * 0.78,
			0.58,
			car_length * 0.46
		),
		Vector3(
			0.0,
			1.04,
			-car_length * 0.04
		),
		Vector3.ZERO,
		body_material
	)
	_create_visual_box(
		car,
		"FrontWindow",
		Vector3(
			car_width * 0.68,
			0.40,
			0.08
		),
		Vector3(
			0.0,
			1.08,
			car_length * 0.19
		),
		Vector3(
			deg_to_rad(-17.0),
			0.0,
			0.0
		),
		window_material
	)
	_create_visual_box(
		car,
		"RearWindow",
		Vector3(
			car_width * 0.66,
			0.38,
			0.08
		),
		Vector3(
			0.0,
			1.06,
			-car_length * 0.27
		),
		Vector3(
			deg_to_rad(15.0),
			0.0,
			0.0
		),
		window_material
	)

	for side_x in [
		-car_width * 0.52,
		car_width * 0.52
	]:
		for wheel_z in [
			-car_length * 0.29,
			car_length * 0.29
		]:
			var wheel := _create_visual_cylinder(
				car,
				"Wheel",
				0.27,
				0.27,
				0.18,
				Vector3(side_x, 0.31, wheel_z),
				wheel_material
			)
			wheel.rotation_degrees.z = 90.0

	for light_x in [
		-car_width * 0.29,
		car_width * 0.29
	]:
		_create_visual_box(
			car,
			"Headlight",
			Vector3(0.24, 0.16, 0.06),
			Vector3(
				light_x,
				0.61,
				car_length * 0.51
			),
			Vector3.ZERO,
			light_material
		)
		_create_visual_box(
			car,
			"RearTrim",
			Vector3(0.22, 0.12, 0.05),
			Vector3(
				light_x,
				0.57,
				-car_length * 0.51
			),
			Vector3.ZERO,
			metal_material
		)

	var roof_snow := _create_visual_sphere(
		car,
		"RoofSnow",
		Vector3(0.0, 1.42, -car_length * 0.04),
		snow_materials[
			rng.randi_range(0, snow_materials.size() - 1)
		]
	)
	roof_snow.scale = Vector3(
		car_width * 0.78,
		rng.randf_range(0.12, 0.20),
		car_length * 0.28
	)

	var collision := CollisionShape3D.new()
	var collision_shape := BoxShape3D.new()
	collision_shape.size = Vector3(
		car_width,
		1.35,
		car_length
	)
	collision.shape = collision_shape
	collision.position = Vector3(0.0, 0.68, 0.0)
	car.add_child(collision)


func _generate_small_obstacles() -> void:
	var obstacle_count: int = mini(
		1 + int(float(level_number) / 2.0),
		4
	)
	var bin_material := _make_material(
		Color(0.10, 0.24, 0.17),
		0.82,
		0.04
	)

	for index in range(obstacle_count):
		var center := Vector2(
			rng.randf_range(
				-current_area_half + 1.5,
				current_area_half - 1.5
			),
			rng.randf_range(
				-current_area_half + 1.5,
				current_area_half - 3.0
			)
		)
		var half_size := Vector2(0.42, 0.42)

		if not _can_place_obstacle(
			center,
			half_size,
			0.0,
			0.55
		):
			continue

		_add_blocker(
			center,
			half_size,
			0.0,
			"bin"
		)

		_create_static_box(
			scenery_root,
			"TrashBin_%02d" % index,
			Vector3(0.70, 1.10, 0.70),
			Vector3(center.x, 0.55, center.y),
			Vector3.ZERO,
			bin_material
		)
		_create_visual_box(
			scenery_root,
			"TrashBinSnow",
			Vector3(0.78, 0.10, 0.78),
			Vector3(center.x, 1.15, center.y),
			Vector3.ZERO,
			snow_materials[
				rng.randi_range(
					0,
					snow_materials.size() - 1
				)
			]
		)


func _can_place_obstacle(
	center: Vector2,
	half_size: Vector2,
	_angle: float,
	extra_gap: float
) -> bool:
	var spawn_point := Vector2(
		0.0,
		current_area_half - 1.35
	)
	var radius: float = half_size.length()

	if center.distance_to(spawn_point) < radius + 2.3:
		return false

	for blocker in blockers:
		var other_center: Vector2 = blocker["center"]
		var other_half: Vector2 = blocker["half_size"]
		var other_radius: float = other_half.length()

		if center.distance_to(other_center) < (
			radius + other_radius + extra_gap
		):
			return false

	return true


func _add_blocker(
	center: Vector2,
	half_size: Vector2,
	angle: float,
	kind: String
) -> void:
	blockers.append(
		{
			"center": center,
			"half_size": half_size,
			"angle": angle,
			"kind": kind
		}
	)


func _point_is_blocked(point: Vector2) -> bool:
	for blocker in blockers:
		var center: Vector2 = blocker["center"]
		var half_size: Vector2 = blocker["half_size"]
		var angle: float = float(blocker["angle"])
		var local_point: Vector2 = (
			point - center
		).rotated(-angle)

		if (
			absf(local_point.x) <= half_size.x
			and absf(local_point.y) <= half_size.y
		):
			return true

	return false


func _generate_snow() -> void:
	for child in snow_root.get_children():
		child.free()

	active_snow.clear()
	snow_cleared = 0
	completion_announced = false

	var offset: float = (
		float(current_grid_size - 1)
		* SNOW_TILE_SPACING
		* 0.5
	)
	var spawn_point := Vector2(
		0.0,
		current_area_half - 1.35
	)

	for x in range(current_grid_size):
		for z in range(current_grid_size):
			var tile_position := Vector2(
				float(x) * SNOW_TILE_SPACING - offset,
				float(z) * SNOW_TILE_SPACING - offset
			)

			if _point_is_blocked(tile_position):
				continue

			if tile_position.distance_to(spawn_point) < 0.72:
				continue

			var normalized_x: float = (
				float(x)
				/ float(current_grid_size - 1)
				* 2.0
				- 1.0
			)
			var normalized_z: float = (
				float(z)
				/ float(current_grid_size - 1)
				* 2.0
				- 1.0
			)
			var edge_factor: float = maxf(
				absf(normalized_x),
				absf(normalized_z)
			)
			var drift_height: float = (
				pow(edge_factor, 4.0)
				* (0.11 + float(level_number) * 0.006)
			)
			var rolling_height: float = (
				sin(float(x) * 0.62) * 0.014
				+ cos(float(z) * 0.49) * 0.017
				+ sin(float(x + z) * 0.31) * 0.011
			)
			var random_height: float = rng.randf_range(
				-0.024,
				0.046
			)
			var level_depth_bonus: float = minf(
				float(level_number - 1) * 0.008,
				0.07
			)
			var snow_height: float = clampf(
				SNOW_BASE_HEIGHT
				+ level_depth_bonus
				+ drift_height
				+ rolling_height
				+ random_height,
				0.11,
				0.37
			)

			var tile := Node3D.new()
			tile.name = "Snow_%02d_%02d" % [x, z]
			tile.position = Vector3(
				tile_position.x,
				0.0,
				tile_position.y
			)
			snow_root.add_child(tile)

			var material_index: int = (
				x
				+ z
				+ rng.randi_range(0, 2)
			) % snow_materials.size()

			var snow_mesh := _create_visual_box(
				tile,
				"SnowMesh",
				Vector3(
					SNOW_TILE_SIZE,
					snow_height,
					SNOW_TILE_SIZE
				),
				Vector3(
					0.0,
					SNOW_BASE_Y + snow_height * 0.5,
					0.0
				),
				Vector3.ZERO,
				snow_materials[material_index]
			)

			var box_mesh: BoxMesh = snow_mesh.mesh as BoxMesh
			if box_mesh != null:
				box_mesh.subdivide_width = 2
				box_mesh.subdivide_depth = 2

			if rng.randf() < 0.14:
				var lump := _create_visual_sphere(
					tile,
					"SnowLump",
					Vector3(
						rng.randf_range(-0.16, 0.16),
						SNOW_BASE_Y + snow_height + 0.012,
						rng.randf_range(-0.16, 0.16)
					),
					snow_materials[material_index]
				)
				lump.scale = Vector3(
					rng.randf_range(0.25, 0.40),
					rng.randf_range(0.08, 0.15),
					rng.randf_range(0.25, 0.40)
				)

			active_snow.append(tile)

	total_snow = active_snow.size()
	_update_hud()


func _clear_snow_in_front() -> void:
	if not is_instance_valid(player):
		return

	var forward: Vector3 = player.get_forward_direction()
	var clearing_center: Vector3 = (
		player.global_position
		+ forward * clear_distance
	)
	var center_2d := Vector2(
		clearing_center.x,
		clearing_center.z
	)
	var cleared_now: int = 0
	var level_payout_bonus: int = 1 + int(
		float(level_number - 1) / 4.0
	)

	for index in range(active_snow.size() - 1, -1, -1):
		var tile: Node3D = active_snow[index]

		if not is_instance_valid(tile):
			active_snow.remove_at(index)
			continue

		var tile_2d := Vector2(
			tile.global_position.x,
			tile.global_position.z
		)

		if center_2d.distance_to(tile_2d) <= clear_radius:
			active_snow.remove_at(index)
			_animate_removed_snow(tile, forward)
			snow_cleared += 1
			money += payout_per_tile * level_payout_bonus
			cleared_now += 1

	if cleared_now > 0:
		_spawn_snow_spray(
			clearing_center,
			forward,
			cleared_now
		)
		status_label.text = (
			"%d snow sections cleared."
			% cleared_now
		)
		_update_hud()


func _animate_removed_snow(
	tile: Node3D,
	forward: Vector3
) -> void:
	var side := Vector3(-forward.z, 0.0, forward.x)
	var target_position: Vector3 = (
		tile.position
		+ forward * rng.randf_range(0.45, 0.90)
		+ side * rng.randf_range(-0.38, 0.38)
		+ Vector3(
			0.0,
			rng.randf_range(0.18, 0.38),
			0.0
		)
	)
	var target_rotation := tile.rotation_degrees + Vector3(
		rng.randf_range(-25.0, 25.0),
		rng.randf_range(-35.0, 35.0),
		rng.randf_range(-25.0, 25.0)
	)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		tile,
		"position",
		target_position,
		0.22
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_property(
		tile,
		"rotation_degrees",
		target_rotation,
		0.22
	)
	tween.tween_property(
		tile,
		"scale",
		Vector3(0.12, 0.05, 0.12),
		0.22
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_IN
	)
	tween.finished.connect(Callable(tile, "queue_free"))


func _spawn_snow_spray(
	center: Vector3,
	forward: Vector3,
	cleared_count: int
) -> void:
	var particle_count: int = mini(
		8 + cleared_count * 2,
		28
	)
	var side := Vector3(-forward.z, 0.0, forward.x)

	for _particle_index in range(particle_count):
		var particle := MeshInstance3D.new()
		particle.name = "SnowSpray"
		particle.mesh = spray_mesh
		particle.position = (
			center
			+ side * rng.randf_range(-0.40, 0.40)
			+ forward * rng.randf_range(-0.15, 0.22)
			+ Vector3(
				0.0,
				rng.randf_range(0.05, 0.18),
				0.0
			)
		)
		var particle_scale: float = rng.randf_range(
			0.45,
			1.25
		)
		particle.scale = Vector3.ONE * particle_scale
		persistent_effects_root.add_child(particle)

		var target_position: Vector3 = (
			particle.position
			+ forward * rng.randf_range(0.55, 1.35)
			+ side * rng.randf_range(-0.65, 0.65)
			+ Vector3(
				0.0,
				rng.randf_range(0.35, 0.95),
				0.0
			)
		)
		var duration: float = rng.randf_range(0.28, 0.46)

		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(
			particle,
			"position",
			target_position,
			duration
		).set_trans(
			Tween.TRANS_QUAD
		).set_ease(
			Tween.EASE_OUT
		)
		tween.tween_property(
			particle,
			"scale",
			Vector3.ZERO,
			duration
		).set_trans(
			Tween.TRANS_QUAD
		).set_ease(
			Tween.EASE_IN
		)
		tween.finished.connect(
			Callable(particle, "queue_free")
		)


func _finish_level() -> void:
	if level_transitioning:
		return

	level_transitioning = true
	var completion_bonus: int = (
		75
		+ level_number * 35
		+ current_car_count * 20
		+ current_house_count * 25
	)
	money += completion_bonus

	status_label.text = (
		"Level complete. Completion bonus: %d."
		% completion_bonus
	)
	_show_level_banner(
		"LEVEL %d COMPLETE\nBONUS: %d"
		% [level_number, completion_bonus]
	)
	_update_hud()

	level_number += 1
	_save_progress()

	await get_tree().create_timer(2.8).timeout
	_start_level(level_number)


func _buy_next_upgrade() -> void:
	if level_transitioning:
		return

	var next_index: int = upgrade_level + 1

	if next_index >= upgrades.size():
		status_label.text = "The best snow removal tool is already owned."
		return

	var upgrade: Dictionary = upgrades[next_index]
	var cost: int = int(upgrade["cost"])

	if money < cost:
		status_label.text = "You need %d more for %s." % [
			cost - money,
			str(upgrade["name"])
		]
		return

	money -= cost
	upgrade_level = next_index
	_apply_upgrade_state()
	player.set_tool_model(upgrade_level + 1)

	status_label.text = "%s purchased." % current_tool_name
	_update_hud()
	_save_progress()


func _apply_upgrade_state() -> void:
	current_tool_name = "Basic Snow Shovel"
	clear_radius = 0.62
	clear_distance = 1.20
	payout_per_tile = 1
	action_interval = 0.28

	if upgrade_level < 0:
		return

	var maximum_index: int = mini(
		upgrade_level,
		upgrades.size() - 1
	)

	for index in range(maximum_index + 1):
		var upgrade: Dictionary = upgrades[index]
		current_tool_name = str(upgrade["name"])
		clear_radius = float(upgrade["radius"])
		clear_distance = float(upgrade["distance"])
		payout_per_tile = int(upgrade["payout"])
		action_interval = float(upgrade["interval"])


func _create_snow_materials() -> void:
	snow_materials.append(
		_create_snow_material(
			Color(0.91, 0.96, 1.00),
			0.018
		)
	)
	snow_materials.append(
		_create_snow_material(
			Color(0.95, 0.98, 1.00),
			0.024
		)
	)
	snow_materials.append(
		_create_snow_material(
			Color(0.86, 0.93, 0.99),
			0.020
		)
	)


func _create_snow_material(
	color: Color,
	bump_strength: float
) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 snow_color : source_color = vec4(0.93, 0.97, 1.0, 1.0);
uniform float bump_strength = 0.02;

varying vec3 world_vertex;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	vec3 original_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	if (NORMAL.y > 0.45) {
		float wave =
			sin(original_world.x * 4.1)
			+ sin(original_world.z * 3.7)
			+ sin((original_world.x + original_world.z) * 2.2);

		VERTEX.y += wave * bump_strength;
	}

	world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float broad = hash21(floor(world_vertex.xz * 8.0));
	float fine = hash21(floor(world_vertex.xz * 52.0));
	float normal_x = hash21(floor(world_vertex.xz * 31.0));
	float normal_z = hash21(floor(world_vertex.zx * 37.0));

	ALBEDO = snow_color.rgb * mix(0.93, 1.04, broad);
	ROUGHNESS = mix(0.74, 0.94, fine);
	SPECULAR = mix(0.28, 0.52, 1.0 - fine);

	NORMAL = normalize(
		NORMAL
		+ vec3(
			(normal_x - 0.5) * 0.08,
			0.0,
			(normal_z - 0.5) * 0.08
		)
	);
}
"""

	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("snow_color", color)
	material.set_shader_parameter(
		"bump_strength",
		bump_strength
	)
	return material


func _create_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.27, 0.39, 0.53)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.77, 0.85, 0.96)
	environment.ambient_light_energy = 0.72
	world_environment.environment = environment
	add_child(world_environment)

	var sunlight := DirectionalLight3D.new()
	sunlight.name = "WinterSun"
	sunlight.rotation_degrees = Vector3(-48.0, -31.0, 0.0)
	sunlight.light_color = Color(0.92, 0.95, 1.0)
	sunlight.light_energy = 1.45
	sunlight.shadow_enabled = true
	add_child(sunlight)


func _create_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0.0, 1.0, 8.0)
	player.set_script(load("res://scripts/player.gd"))

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.42
	capsule_shape.height = 1.80
	collision.shape = capsule_shape
	player.add_child(collision)

	add_child(player)
	player.set_tool_model(upgrade_level + 1)


func _create_effects_root() -> void:
	persistent_effects_root = Node3D.new()
	persistent_effects_root.name = "Effects"
	add_child(persistent_effects_root)


func _create_spray_resources() -> void:
	spray_mesh = SphereMesh.new()
	spray_mesh.radius = 0.055
	spray_mesh.height = 0.11
	spray_mesh.radial_segments = 8
	spray_mesh.rings = 4
	spray_mesh.material = snow_materials[1]


func _create_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(520.0, 0.0)
	canvas.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 4)
	margin.add_child(layout)

	var title := Label.new()
	title.text = "MR. PLOW – PROCEDURAL PROPERTIES"
	title.add_theme_font_size_override("font_size", 21)
	layout.add_child(title)

	level_label = Label.new()
	layout.add_child(level_label)

	snow_label = Label.new()
	layout.add_child(snow_label)

	money_label = Label.new()
	layout.add_child(money_label)

	tool_label = Label.new()
	layout.add_child(tool_label)

	upgrade_label = Label.new()
	upgrade_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(upgrade_label)

	layout_label = Label.new()
	layout.add_child(layout_label)

	var controls := Label.new()
	controls.text = (
		"WASD: Move | Mouse: Look | "
		+ "Left click/Space: Shovel | "
		+ "U: Upgrade | R: Fresh snow | Esc: Cursor"
	)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(controls)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 16)
	layout.add_child(status_label)

	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 28)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-8.0, -18.0)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(crosshair)

	level_banner = Label.new()
	level_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_banner.add_theme_font_size_override("font_size", 34)
	level_banner.set_anchors_preset(Control.PRESET_CENTER)
	level_banner.position = Vector2(-260.0, -75.0)
	level_banner.size = Vector2(520.0, 150.0)
	level_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_banner.visible = false
	canvas.add_child(level_banner)


func _show_level_banner(text: String) -> void:
	level_banner.text = text
	level_banner.visible = true
	level_banner.modulate.a = 0.0

	var tween := create_tween()
	tween.tween_property(
		level_banner,
		"modulate:a",
		1.0,
		0.25
	)
	tween.tween_interval(1.55)
	tween.tween_property(
		level_banner,
		"modulate:a",
		0.0,
		0.50
	)
	tween.finished.connect(_hide_level_banner)


func _hide_level_banner() -> void:
	level_banner.visible = false


func _update_hud() -> void:
	if not is_instance_valid(level_label):
		return

	var percentage: int = 0
	if total_snow > 0:
		percentage = int(
			float(snow_cleared)
			/ float(total_snow)
			* 100.0
		)

	level_label.text = "Level: %d" % level_number
	snow_label.text = (
		"Cleared snow: %d / %d (%d%%)"
		% [snow_cleared, total_snow, percentage]
	)
	money_label.text = "Money: %d" % money
	tool_label.text = "Tool: %s | Clearing width: %.2f m" % [
		current_tool_name,
		clear_radius * 2.0
	]
	layout_label.text = "Property layout: %d houses, %d cars | Seed: %d" % [
		current_house_count,
		current_car_count,
		current_level_seed
	]

	var next_index: int = upgrade_level + 1
	if next_index < upgrades.size():
		var next_upgrade: Dictionary = upgrades[next_index]
		upgrade_label.text = (
			"Next upgrade [U]: %s – %d"
			% [
				str(next_upgrade["name"]),
				int(next_upgrade["cost"])
			]
		)
	else:
		upgrade_label.text = "All equipment upgrades are unlocked."


func _save_progress() -> void:
	var file := FileAccess.open(
		SAVE_PATH,
		FileAccess.WRITE
	)
	if file == null:
		return

	var data := {
		"level": level_number,
		"money": money,
		"upgrade_level": upgrade_level
	}
	file.store_string(JSON.stringify(data))


func _load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(
		SAVE_PATH,
		FileAccess.READ
	)
	if file == null:
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var data: Dictionary = parsed
	level_number = maxi(
		1,
		int(data.get("level", 1))
	)
	money = maxi(
		0,
		int(data.get("money", 0))
	)
	upgrade_level = clampi(
		int(data.get("upgrade_level", -1)),
		-1,
		upgrades.size() - 1
	)


func _make_material(
	color: Color,
	roughness: float,
	metallic: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _create_visual_box(
	parent: Node,
	node_name: String,
	size: Vector3,
	position: Vector3,
	rotation_value: Vector3,
	material: Material
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = position
	mesh_instance.rotation = rotation_value

	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = material

	mesh_instance.mesh = box_mesh
	parent.add_child(mesh_instance)
	return mesh_instance


func _create_visual_sphere(
	parent: Node,
	node_name: String,
	position: Vector3,
	material: Material
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = position

	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.50
	sphere_mesh.height = 1.0
	sphere_mesh.radial_segments = 12
	sphere_mesh.rings = 6
	sphere_mesh.material = material

	mesh_instance.mesh = sphere_mesh
	parent.add_child(mesh_instance)
	return mesh_instance


func _create_visual_cylinder(
	parent: Node,
	node_name: String,
	top_radius: float,
	bottom_radius: float,
	height: float,
	position: Vector3,
	material: Material
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = position

	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = top_radius
	cylinder_mesh.bottom_radius = bottom_radius
	cylinder_mesh.height = height
	cylinder_mesh.radial_segments = 20
	cylinder_mesh.material = material

	mesh_instance.mesh = cylinder_mesh
	parent.add_child(mesh_instance)
	return mesh_instance


func _create_static_box(
	parent: Node,
	node_name: String,
	size: Vector3,
	position: Vector3,
	rotation_value: Vector3,
	material: Material
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.rotation = rotation_value
	parent.add_child(body)

	_create_visual_box(
		body,
		"Mesh",
		size,
		Vector3.ZERO,
		Vector3.ZERO,
		material
	)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	body.add_child(collision)

	return body
