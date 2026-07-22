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

var current_contract: Dictionary = {}
var contract_name: String = "Standard Residential"
var contract_description: String = ""
var contract_payout_multiplier: float = 1.0
var contract_depth_bonus: float = 0.0
var contract_target_factor: float = 1.0
var contract_extra_cars: int = 0
var contract_precision_multiplier: float = 1.5

var level_elapsed: float = 0.0
var target_time: float = 120.0
var combo_tiles: int = 0
var combo_multiplier: float = 1.0
var combo_time_left: float = 0.0
var max_combo_multiplier: float = 1.0
var level_money_earned: int = 0
var level_precision_tiles: int = 0
var best_times: Dictionary = {}
var level_generation_id: int = 0

var hud_root: Control
var progress_bar: ProgressBar
var progress_value_label: Label
var timer_label: Label
var contract_label: Label
var combo_label: Label
var bonus_label: Label
var pause_overlay: ColorRect
var confirmation_overlay: ColorRect
var confirm_return_to_pause: bool = false

var level_label: Label
var money_label: Label
var tool_label: Label
var upgrade_label: Label
var layout_label: Label
var status_label: Label
var level_banner: Label

var upgrades: Array[Dictionary] = [
	{
		"name": "Wide Snow Shovel",
		"cost": 70,
		"radius": 0.96,
		"distance": 1.35,
		"payout": 1,
		"interval": 0.23,
		"model": 1
	},
	{
		"name": "Electric Snow Blower",
		"cost": 260,
		"radius": 1.50,
		"distance": 1.55,
		"payout": 2,
		"interval": 0.13,
		"model": 2
	},
	{
		"name": "Compact Snow Plow",
		"cost": 900,
		"radius": 2.25,
		"distance": 1.80,
		"payout": 4,
		"interval": 0.08,
		"model": 3
	}
]


var contracts: Array[Dictionary] = [
	{
		"name": "Standard Residential",
		"description": "A balanced driveway with normal snowfall.",
		"payout_multiplier": 1.0,
		"depth_bonus": 0.0,
		"target_factor": 1.0,
		"extra_cars": 0,
		"precision_multiplier": 1.5
	},
	{
		"name": "Heavy Overnight Snow",
		"description": "Deeper snow, a longer target time, and better pay.",
		"payout_multiplier": 1.25,
		"depth_bonus": 0.055,
		"target_factor": 1.16,
		"extra_cars": 0,
		"precision_multiplier": 1.5
	},
	{
		"name": "Morning Rush",
		"description": "Finish quickly before the residents leave for work.",
		"payout_multiplier": 1.35,
		"depth_bonus": 0.01,
		"target_factor": 0.78,
		"extra_cars": 1,
		"precision_multiplier": 1.6
	},
	{
		"name": "Crowded Driveway",
		"description": "More parked vehicles create narrow cleaning routes.",
		"payout_multiplier": 1.20,
		"depth_bonus": 0.025,
		"target_factor": 1.08,
		"extra_cars": 2,
		"precision_multiplier": 1.75
	},
	{
		"name": "Careful Around Vehicles",
		"description": "Precision snow near obstacles is worth much more.",
		"payout_multiplier": 1.10,
		"depth_bonus": 0.015,
		"target_factor": 1.04,
		"extra_cars": 2,
		"precision_multiplier": 2.25
	}
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
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
	if get_tree().paused:
		return

	action_cooldown = maxf(action_cooldown - delta, 0.0)

	if level_transitioning:
		return

	level_elapsed += delta

	if combo_time_left > 0.0:
		combo_time_left = maxf(combo_time_left - delta, 0.0)
		if combo_time_left <= 0.0:
			combo_tiles = 0
			combo_multiplier = 1.0

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

	_update_dynamic_hud()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return

	if event.keycode == KEY_ESCAPE:
		if is_instance_valid(confirmation_overlay) and confirmation_overlay.visible:
			_cancel_new_game()
		elif is_instance_valid(pause_overlay) and pause_overlay.visible:
			_resume_game()
		else:
			_open_pause_menu()
		return

	if get_tree().paused:
		return

	if event.keycode == KEY_U:
		_buy_next_upgrade()

func _start_level(new_level: int) -> void:
	level_generation_id += 1
	level_number = maxi(new_level, 1)
	level_transitioning = false
	completion_announced = false
	action_cooldown = 0.0
	level_elapsed = 0.0
	combo_tiles = 0
	combo_multiplier = 1.0
	combo_time_left = 0.0
	max_combo_multiplier = 1.0
	level_money_earned = 0
	level_precision_tiles = 0

	current_level_seed = (
		int(Time.get_ticks_msec())
		+ level_number * 7919
		+ rng.randi_range(1, 999999)
	)
	rng.seed = current_level_seed

	_select_contract()

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
		1 + int(float(level_number - 1) / 1.4)
		+ contract_extra_cars,
		7
	)

	_clear_old_level()
	_create_level_root()
	_create_level_ground()
	_generate_houses(current_house_count)
	_generate_cars(current_car_count)
	_generate_small_obstacles()
	_generate_snow()

	target_time = maxf(
		65.0,
		(
			float(total_snow) * 0.17
			+ float(current_car_count) * 8.0
			+ float(current_house_count) * 13.0
		) * contract_target_factor
	)

	var spawn_position := Vector3(
		0.0,
		1.0,
		current_area_half - 1.35
	)
	player.reset_for_level(spawn_position)
	player.set_tool_model(upgrade_level + 1)

	status_label.text = contract_description
	_show_level_banner(
		"LEVEL %d\n%s"
		% [
			level_number,
			contract_name.to_upper()
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
	level_precision_tiles = 0

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
				+ contract_depth_bonus
				+ drift_height
				+ rolling_height
				+ random_height,
				0.11,
				0.43
			)
			var is_precision: bool = _point_is_precision_snow(
				tile_position
			)

			var tile := Node3D.new()
			tile.name = "Snow_%02d_%02d" % [x, z]
			tile.position = Vector3(
				tile_position.x,
				0.0,
				tile_position.y
			)
			tile.set_meta("precision", is_precision)
			snow_root.add_child(tile)

			var material_index: int = (
				x
				+ z
				+ rng.randi_range(0, 2)
			) % snow_materials.size()

			if is_precision:
				material_index = 2

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
	var precision_now: int = 0
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
			var is_precision: bool = bool(
				tile.get_meta("precision", false)
			)
			if is_precision:
				precision_now += 1

			active_snow.remove_at(index)
			_animate_removed_snow(tile, forward)
			snow_cleared += 1
			cleared_now += 1

	if cleared_now <= 0:
		return

	combo_tiles += cleared_now
	combo_time_left = 1.85
	combo_multiplier = 1.0 + minf(
		floorf(float(combo_tiles) / 18.0) * 0.25,
		2.0
	)
	max_combo_multiplier = maxf(
		max_combo_multiplier,
		combo_multiplier
	)

	var base_value: float = (
		float(cleared_now)
		* float(payout_per_tile)
		* float(level_payout_bonus)
		* contract_payout_multiplier
		* combo_multiplier
	)
	var precision_extra_value: float = (
		float(precision_now)
		* float(payout_per_tile)
		* float(level_payout_bonus)
		* contract_payout_multiplier
		* combo_multiplier
		* (contract_precision_multiplier - 1.0)
	)
	var earned: int = int(floorf(
		base_value + precision_extra_value + 0.5
	))

	money += earned
	level_money_earned += earned
	level_precision_tiles += precision_now

	_spawn_snow_spray(
		clearing_center,
		forward,
		cleared_now
	)

	if precision_now > 0:
		status_label.text = (
			"Precision bonus: %d obstacle-edge sections. +%d"
			% [precision_now, earned]
		)
	else:
		status_label.text = (
			"%d snow sections cleared. +%d"
			% [cleared_now, earned]
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

	var time_ratio: float = level_elapsed / maxf(target_time, 1.0)
	var star_rating: int = 1

	if time_ratio <= 0.85:
		star_rating = 3
	elif time_ratio <= 1.15:
		star_rating = 2

	var time_difference: float = maxf(
		target_time - level_elapsed,
		0.0
	)
	var time_bonus: int = int(floorf(
		time_difference * 2.5 + 0.5
	))
	var completion_bonus: int = (
		70
		+ level_number * 35
		+ current_car_count * 18
		+ current_house_count * 24
		+ star_rating * 65
		+ time_bonus
	)

	money += completion_bonus
	level_money_earned += completion_bonus

	var best_key := str(level_number)
	var previous_best: float = float(
		best_times.get(best_key, -1.0)
	)
	if previous_best < 0.0 or level_elapsed < previous_best:
		best_times[best_key] = level_elapsed

	status_label.text = (
		"Job complete. %d-star rating, +%d completion bonus."
		% [star_rating, completion_bonus]
	)
	_show_level_banner(
		"LEVEL %d COMPLETE\n%s\nTIME %s  |  +%d"
		% [
			level_number,
			_star_text(star_rating),
			_format_time(level_elapsed),
			completion_bonus
		]
	)
	_update_hud()

	level_number += 1
	_save_progress()

	var completed_generation_id: int = level_generation_id
	await get_tree().create_timer(3.3, false).timeout

	if completed_generation_id != level_generation_id:
		return

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
	canvas.layer = 10
	add_child(canvas)

	hud_root = Control.new()
	hud_root.name = "HUDRoot"
	hud_root.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(hud_root)

	var job_panel := PanelContainer.new()
	job_panel.name = "JobPanel"
	job_panel.offset_left = 18.0
	job_panel.offset_top = 18.0
	job_panel.offset_right = 398.0
	job_panel.offset_bottom = 182.0
	job_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(
			Color(0.035, 0.055, 0.080, 0.92),
			Color(0.22, 0.52, 0.78, 0.55),
			14
		)
	)
	hud_root.add_child(job_panel)

	var job_layout := _create_panel_vbox(job_panel, 16, 5)

	var job_header := Label.new()
	job_header.text = "CURRENT JOB"
	job_header.add_theme_font_size_override("font_size", 13)
	job_header.add_theme_color_override(
		"font_color",
		Color(0.45, 0.74, 0.96)
	)
	job_layout.add_child(job_header)

	level_label = Label.new()
	level_label.add_theme_font_size_override("font_size", 25)
	level_label.add_theme_color_override(
		"font_color",
		Color(0.96, 0.98, 1.0)
	)
	job_layout.add_child(level_label)

	contract_label = Label.new()
	contract_label.add_theme_font_size_override("font_size", 17)
	contract_label.add_theme_color_override(
		"font_color",
		Color(0.82, 0.90, 0.98)
	)
	contract_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	job_layout.add_child(contract_label)

	layout_label = Label.new()
	layout_label.add_theme_font_size_override("font_size", 13)
	layout_label.add_theme_color_override(
		"font_color",
		Color(0.62, 0.70, 0.79)
	)
	job_layout.add_child(layout_label)

	var progress_panel := PanelContainer.new()
	progress_panel.name = "ProgressPanel"
	progress_panel.anchor_left = 0.5
	progress_panel.anchor_right = 0.5
	progress_panel.offset_left = -250.0
	progress_panel.offset_top = 18.0
	progress_panel.offset_right = 250.0
	progress_panel.offset_bottom = 128.0
	progress_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(
			Color(0.035, 0.055, 0.080, 0.92),
			Color(0.22, 0.52, 0.78, 0.45),
			14
		)
	)
	hud_root.add_child(progress_panel)

	var progress_layout := _create_panel_vbox(
		progress_panel,
		15,
		7
	)

	progress_value_label = Label.new()
	progress_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_value_label.add_theme_font_size_override(
		"font_size",
		18
	)
	progress_value_label.add_theme_color_override(
		"font_color",
		Color(0.93, 0.97, 1.0)
	)
	progress_layout.add_child(progress_value_label)

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0.0, 17.0)
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.show_percentage = false
	progress_bar.add_theme_stylebox_override(
		"background",
		_make_panel_style(
			Color(0.01, 0.02, 0.035, 0.82),
			Color(0.16, 0.24, 0.34, 0.8),
			8
		)
	)
	progress_bar.add_theme_stylebox_override(
		"fill",
		_make_panel_style(
			Color(0.20, 0.63, 0.88, 1.0),
			Color(0.50, 0.82, 1.0, 0.9),
			8
		)
	)
	progress_layout.add_child(progress_bar)

	timer_label = Label.new()
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 14)
	timer_label.add_theme_color_override(
		"font_color",
		Color(0.70, 0.79, 0.88)
	)
	progress_layout.add_child(timer_label)

	var stats_panel := PanelContainer.new()
	stats_panel.name = "StatsPanel"
	stats_panel.anchor_left = 1.0
	stats_panel.anchor_right = 1.0
	stats_panel.offset_left = -350.0
	stats_panel.offset_top = 18.0
	stats_panel.offset_right = -18.0
	stats_panel.offset_bottom = 206.0
	stats_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(
			Color(0.035, 0.055, 0.080, 0.92),
			Color(0.22, 0.52, 0.78, 0.55),
			14
		)
	)
	hud_root.add_child(stats_panel)

	var stats_layout := _create_panel_vbox(
		stats_panel,
		15,
		6
	)

	money_label = Label.new()
	money_label.add_theme_font_size_override("font_size", 27)
	money_label.add_theme_color_override(
		"font_color",
		Color(0.45, 0.92, 0.65)
	)
	stats_layout.add_child(money_label)

	combo_label = Label.new()
	combo_label.add_theme_font_size_override("font_size", 20)
	combo_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.78, 0.28)
	)
	stats_layout.add_child(combo_label)

	tool_label = Label.new()
	tool_label.add_theme_font_size_override("font_size", 14)
	tool_label.add_theme_color_override(
		"font_color",
		Color(0.78, 0.85, 0.92)
	)
	tool_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_layout.add_child(tool_label)

	upgrade_label = Label.new()
	upgrade_label.add_theme_font_size_override("font_size", 13)
	upgrade_label.add_theme_color_override(
		"font_color",
		Color(0.55, 0.72, 0.88)
	)
	upgrade_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_layout.add_child(upgrade_label)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_END
	button_row.add_theme_constant_override("separation", 8)
	stats_layout.add_child(button_row)

	var menu_button := Button.new()
	menu_button.text = "MENU"
	menu_button.custom_minimum_size = Vector2(94.0, 34.0)
	_style_button(menu_button, false)
	menu_button.pressed.connect(_open_pause_menu)
	button_row.add_child(menu_button)

	var new_game_button := Button.new()
	new_game_button.text = "NEW GAME"
	new_game_button.custom_minimum_size = Vector2(118.0, 34.0)
	_style_button(new_game_button, true)
	new_game_button.pressed.connect(_request_new_game)
	button_row.add_child(new_game_button)

	var status_panel := PanelContainer.new()
	status_panel.name = "StatusPanel"
	status_panel.anchor_top = 1.0
	status_panel.anchor_bottom = 1.0
	status_panel.offset_left = 18.0
	status_panel.offset_top = -118.0
	status_panel.offset_right = 690.0
	status_panel.offset_bottom = -18.0
	status_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(
			Color(0.035, 0.055, 0.080, 0.90),
			Color(0.18, 0.36, 0.52, 0.45),
			14
		)
	)
	hud_root.add_child(status_panel)

	var status_layout := _create_panel_vbox(
		status_panel,
		14,
		4
	)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override(
		"font_color",
		Color(0.92, 0.95, 0.98)
	)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_layout.add_child(status_label)

	bonus_label = Label.new()
	bonus_label.add_theme_font_size_override("font_size", 13)
	bonus_label.add_theme_color_override(
		"font_color",
		Color(0.58, 0.76, 0.91)
	)
	status_layout.add_child(bonus_label)

	var controls := Label.new()
	controls.text = (
		"WASD Move   |   Mouse Look   |   Left Click / Space Shovel"
		+ "   |   U Upgrade   |   Esc Menu"
	)
	controls.add_theme_font_size_override("font_size", 12)
	controls.add_theme_color_override(
		"font_color",
		Color(0.52, 0.60, 0.68)
	)
	status_layout.add_child(controls)

	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 27)
	crosshair.add_theme_color_override(
		"font_color",
		Color(0.92, 0.97, 1.0, 0.86)
	)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-8.0, -18.0)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(crosshair)

	level_banner = Label.new()
	level_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_banner.add_theme_font_size_override("font_size", 34)
	level_banner.add_theme_color_override(
		"font_color",
		Color(0.96, 0.98, 1.0)
	)
	level_banner.add_theme_color_override(
		"font_shadow_color",
		Color(0.0, 0.0, 0.0, 0.85)
	)
	level_banner.add_theme_constant_override(
		"shadow_offset_x",
		3
	)
	level_banner.add_theme_constant_override(
		"shadow_offset_y",
		3
	)
	level_banner.set_anchors_preset(Control.PRESET_CENTER)
	level_banner.position = Vector2(-320.0, -100.0)
	level_banner.size = Vector2(640.0, 200.0)
	level_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_banner.visible = false
	hud_root.add_child(level_banner)

	_create_pause_menu()
	_create_new_game_confirmation()

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

	var percentage: float = 0.0
	if total_snow > 0:
		percentage = (
			float(snow_cleared)
			/ float(total_snow)
			* 100.0
		)

	level_label.text = "LEVEL %d" % level_number
	contract_label.text = contract_name
	layout_label.text = "%d houses  |  %d cars  |  seed %d" % [
		current_house_count,
		current_car_count,
		current_level_seed
	]

	progress_bar.value = percentage
	progress_value_label.text = (
		"PROPERTY CLEARED  %d%%"
		% int(floorf(percentage + 0.5))
	)

	money_label.text = "$%d" % money
	combo_label.text = "COMBO  x%.2f" % combo_multiplier
	tool_label.text = "%s  |  %.2f m clearing width" % [
		current_tool_name,
		clear_radius * 2.0
	]

	var next_index: int = upgrade_level + 1
	if next_index < upgrades.size():
		var next_upgrade: Dictionary = upgrades[next_index]
		upgrade_label.text = (
			"Next upgrade [U]: %s – $%d"
			% [
				str(next_upgrade["name"]),
				int(next_upgrade["cost"])
			]
		)
	else:
		upgrade_label.text = "All equipment upgrades unlocked."

	_update_dynamic_hud()

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
		"upgrade_level": upgrade_level,
		"best_times": best_times
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

	var parsed: Variant = JSON.parse_string(
		file.get_as_text()
	)
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

	var loaded_best_times: Variant = data.get(
		"best_times",
		{}
	)
	if typeof(loaded_best_times) == TYPE_DICTIONARY:
		var loaded_dictionary: Dictionary = loaded_best_times
		best_times = loaded_dictionary.duplicate(true)


func _select_contract() -> void:
	var maximum_index: int = contracts.size() - 1

	if level_number <= 1:
		maximum_index = mini(maximum_index, 1)
	elif level_number <= 3:
		maximum_index = mini(maximum_index, 3)

	var selected_index: int = rng.randi_range(
		0,
		maximum_index
	)
	current_contract = contracts[selected_index]

	contract_name = str(
		current_contract.get(
			"name",
			"Standard Residential"
		)
	)
	contract_description = str(
		current_contract.get(
			"description",
			"Clear all accessible snow."
		)
	)
	contract_payout_multiplier = float(
		current_contract.get(
			"payout_multiplier",
			1.0
		)
	)
	contract_depth_bonus = float(
		current_contract.get(
			"depth_bonus",
			0.0
		)
	)
	contract_target_factor = float(
		current_contract.get(
			"target_factor",
			1.0
		)
	)
	contract_extra_cars = int(
		current_contract.get(
			"extra_cars",
			0
		)
	)
	contract_precision_multiplier = float(
		current_contract.get(
			"precision_multiplier",
			1.5
		)
	)


func _point_is_precision_snow(point: Vector2) -> bool:
	for blocker in blockers:
		var center: Vector2 = blocker["center"]
		var half_size: Vector2 = blocker["half_size"]
		var angle: float = float(blocker["angle"])
		var local_point: Vector2 = (
			point - center
		).rotated(-angle)

		var distance_x: float = maxf(
			absf(local_point.x) - half_size.x,
			0.0
		)
		var distance_y: float = maxf(
			absf(local_point.y) - half_size.y,
			0.0
		)
		var edge_distance: float = Vector2(
			distance_x,
			distance_y
		).length()

		if edge_distance <= 0.64:
			return true

	return false


func _update_dynamic_hud() -> void:
	if not is_instance_valid(timer_label):
		return

	var best_key := str(level_number)
	var best_time: float = float(
		best_times.get(best_key, -1.0)
	)
	var best_text := "--:--"

	if best_time >= 0.0:
		best_text = _format_time(best_time)

	timer_label.text = "TIME %s   |   TARGET %s   |   BEST %s" % [
		_format_time(level_elapsed),
		_format_time(target_time),
		best_text
	]

	combo_label.text = "COMBO  x%.2f" % combo_multiplier
	bonus_label.text = (
		"Job earnings: $%d   |   Precision sections: %d"
		+ "   |   Best combo: x%.2f"
	) % [
		level_money_earned,
		level_precision_tiles,
		max_combo_multiplier
	]


func _format_time(seconds_value: float) -> String:
	var safe_seconds: int = maxi(
		int(floorf(seconds_value)),
		0
	)
	var minutes: int = int(float(safe_seconds) / 60.0)
	var seconds: int = safe_seconds % 60
	return "%02d:%02d" % [minutes, seconds]


func _star_text(star_rating: int) -> String:
	match star_rating:
		3:
			return "THREE-STAR SERVICE"
		2:
			return "TWO-STAR SERVICE"
		_:
			return "JOB COMPLETED"


func _create_panel_vbox(
	panel: PanelContainer,
	margin_size: int,
	separation: int
) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(
		"margin_left",
		margin_size
	)
	margin.add_theme_constant_override(
		"margin_right",
		margin_size
	)
	margin.add_theme_constant_override(
		"margin_top",
		margin_size
	)
	margin.add_theme_constant_override(
		"margin_bottom",
		margin_size
	)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override(
		"separation",
		separation
	)
	margin.add_child(layout)
	return layout


func _make_panel_style(
	background_color: Color,
	border_color: Color,
	radius: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _style_button(
	button: Button,
	danger: bool
) -> void:
	var normal_color := Color(0.08, 0.16, 0.23, 0.96)
	var hover_color := Color(0.12, 0.28, 0.40, 1.0)
	var pressed_color := Color(0.06, 0.12, 0.18, 1.0)
	var border_color := Color(0.30, 0.62, 0.84, 0.75)
	var font_color := Color(0.90, 0.96, 1.0)

	if danger:
		normal_color = Color(0.34, 0.09, 0.10, 0.96)
		hover_color = Color(0.55, 0.13, 0.14, 1.0)
		pressed_color = Color(0.25, 0.05, 0.06, 1.0)
		border_color = Color(0.92, 0.36, 0.38, 0.80)
		font_color = Color(1.0, 0.92, 0.92)

	button.add_theme_stylebox_override(
		"normal",
		_make_panel_style(
			normal_color,
			border_color,
			8
		)
	)
	button.add_theme_stylebox_override(
		"hover",
		_make_panel_style(
			hover_color,
			border_color,
			8
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_panel_style(
			pressed_color,
			border_color,
			8
		)
	)
	button.add_theme_stylebox_override(
		"focus",
		_make_panel_style(
			hover_color,
			Color(0.75, 0.90, 1.0, 1.0),
			8
		)
	)
	button.add_theme_color_override(
		"font_color",
		font_color
	)
	button.add_theme_color_override(
		"font_hover_color",
		font_color
	)
	button.add_theme_color_override(
		"font_pressed_color",
		font_color
	)
	button.add_theme_font_size_override(
		"font_size",
		14
	)


func _create_pause_menu() -> void:
	pause_overlay = ColorRect.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	pause_overlay.color = Color(0.005, 0.012, 0.022, 0.78)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_overlay.visible = false
	hud_root.add_child(pause_overlay)

	var menu_panel := PanelContainer.new()
	menu_panel.anchor_left = 0.5
	menu_panel.anchor_top = 0.5
	menu_panel.anchor_right = 0.5
	menu_panel.anchor_bottom = 0.5
	menu_panel.offset_left = -220.0
	menu_panel.offset_top = -195.0
	menu_panel.offset_right = 220.0
	menu_panel.offset_bottom = 195.0
	menu_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(
			Color(0.035, 0.055, 0.080, 0.98),
			Color(0.30, 0.62, 0.84, 0.72),
			18
		)
	)
	pause_overlay.add_child(menu_panel)

	var layout := _create_panel_vbox(
		menu_panel,
		28,
		14
	)
	layout.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "MR. PLOW"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override(
		"font_color",
		Color(0.94, 0.98, 1.0)
	)
	layout.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Game paused"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override(
		"font_color",
		Color(0.57, 0.72, 0.84)
	)
	layout.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 10.0)
	layout.add_child(spacer)

	var resume_button := Button.new()
	resume_button.text = "RESUME"
	resume_button.custom_minimum_size = Vector2(0.0, 46.0)
	_style_button(resume_button, false)
	resume_button.pressed.connect(_resume_game)
	layout.add_child(resume_button)

	var new_game_button := Button.new()
	new_game_button.text = "NEW GAME"
	new_game_button.custom_minimum_size = Vector2(0.0, 46.0)
	_style_button(new_game_button, true)
	new_game_button.pressed.connect(_request_new_game)
	layout.add_child(new_game_button)

	var quit_button := Button.new()
	quit_button.text = "QUIT"
	quit_button.custom_minimum_size = Vector2(0.0, 46.0)
	_style_button(quit_button, false)
	quit_button.pressed.connect(_quit_game)
	layout.add_child(quit_button)

	var hint := Label.new()
	hint.text = "Esc resumes the game"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override(
		"font_color",
		Color(0.48, 0.57, 0.65)
	)
	layout.add_child(hint)


func _create_new_game_confirmation() -> void:
	confirmation_overlay = ColorRect.new()
	confirmation_overlay.name = "NewGameConfirmation"
	confirmation_overlay.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	confirmation_overlay.color = Color(
		0.005,
		0.012,
		0.022,
		0.86
	)
	confirmation_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	confirmation_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	confirmation_overlay.visible = false
	hud_root.add_child(confirmation_overlay)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -245.0
	panel.offset_top = -145.0
	panel.offset_right = 245.0
	panel.offset_bottom = 145.0
	panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(
			Color(0.055, 0.045, 0.055, 0.99),
			Color(0.92, 0.36, 0.38, 0.82),
			18
		)
	)
	confirmation_overlay.add_child(panel)

	var layout := _create_panel_vbox(
		panel,
		26,
		13
	)
	layout.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "START A NEW GAME?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override(
		"font_color",
		Color(1.0, 0.92, 0.92)
	)
	layout.add_child(title)

	var warning := Label.new()
	warning.text = (
		"This resets your level, money, equipment, "
		+ "and saved best times."
	)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.add_theme_font_size_override("font_size", 15)
	warning.add_theme_color_override(
		"font_color",
		Color(0.82, 0.78, 0.80)
	)
	layout.add_child(warning)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	layout.add_child(buttons)

	var cancel_button := Button.new()
	cancel_button.text = "CANCEL"
	cancel_button.custom_minimum_size = Vector2(150.0, 44.0)
	_style_button(cancel_button, false)
	cancel_button.pressed.connect(_cancel_new_game)
	buttons.add_child(cancel_button)

	var confirm_button := Button.new()
	confirm_button.text = "RESET PROGRESS"
	confirm_button.custom_minimum_size = Vector2(190.0, 44.0)
	_style_button(confirm_button, true)
	confirm_button.pressed.connect(_confirm_new_game)
	buttons.add_child(confirm_button)


func _open_pause_menu() -> void:
	if not is_instance_valid(pause_overlay):
		return
	if is_instance_valid(confirmation_overlay):
		confirmation_overlay.visible = false

	pause_overlay.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume_game() -> void:
	if is_instance_valid(pause_overlay):
		pause_overlay.visible = false
	if is_instance_valid(confirmation_overlay):
		confirmation_overlay.visible = false

	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _request_new_game() -> void:
	confirm_return_to_pause = (
		is_instance_valid(pause_overlay)
		and pause_overlay.visible
	)

	if is_instance_valid(pause_overlay):
		pause_overlay.visible = false
	if is_instance_valid(confirmation_overlay):
		confirmation_overlay.visible = true

	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _cancel_new_game() -> void:
	if is_instance_valid(confirmation_overlay):
		confirmation_overlay.visible = false

	if confirm_return_to_pause:
		if is_instance_valid(pause_overlay):
			pause_overlay.visible = true
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _confirm_new_game() -> void:
	if is_instance_valid(confirmation_overlay):
		confirmation_overlay.visible = false
	if is_instance_valid(pause_overlay):
		pause_overlay.visible = false

	get_tree().paused = false

	level_number = 1
	money = 0
	upgrade_level = -1
	best_times.clear()
	_apply_upgrade_state()

	if is_instance_valid(player):
		player.set_tool_model(0)

	_save_progress()
	_start_level(1)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()


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
