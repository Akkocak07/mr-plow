extends Node3D

const SNOW_GRID_SIZE := 13
const SNOW_TILE_SPACING := 1.4
const SNOW_TILE_SIZE := 1.34

var player: CharacterBody3D
var camera: Camera3D
var snow_root: Node3D
var active_snow: Array[Node3D] = []

var snow_cleared: int = 0
var total_snow: int = 0
var money: int = 0
var clear_radius: float = 1.05
var payout_per_tile: int = 1
var current_tool: String = "Einfache Schneeschaufel"
var upgrade_level: int = -1
var completion_announced := false

var snow_label: Label
var money_label: Label
var tool_label: Label
var upgrade_label: Label
var status_label: Label

var upgrades := [
	{
		"name": "Breite Schneeschaufel",
		"cost": 20,
		"radius": 1.65,
		"payout": 1
	},
	{
		"name": "Elektrische Schneefräse",
		"cost": 60,
		"radius": 2.45,
		"payout": 2
	},
	{
		"name": "Profi-Schneeräumer",
		"cost": 160,
		"radius": 3.40,
		"payout": 4
	}
]


func _ready() -> void:
	_create_environment()
	_create_ground()
	_create_scenery()
	_create_player()
	_create_camera()
	_create_hud()
	_create_snow_root()
	_generate_snow()
	_update_hud()
	status_label.text = "Halte Leertaste oder linke Maustaste gedrückt, um Schnee zu räumen."


func _process(delta: float) -> void:
	if is_instance_valid(player) and is_instance_valid(camera):
		var target_position := player.global_position + Vector3(0.0, 10.0, 10.0)
		camera.global_position = camera.global_position.lerp(
			target_position,
			min(delta * 5.0, 1.0)
		)
		camera.look_at(player.global_position + Vector3(0.0, 0.0, -1.2), Vector3.UP)

	var shovel_pressed := (
		Input.is_key_pressed(KEY_SPACE)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	)

	if shovel_pressed:
		_clear_nearby_snow()

	if active_snow.is_empty() and not completion_announced:
		completion_announced = true
		status_label.text = "Grundstück vollständig geräumt! Drücke R für neuen Schnee."


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_U:
			_buy_next_upgrade()
		elif event.keycode == KEY_R:
			_generate_snow()
			status_label.text = "Neuer Schnee ist gefallen."


func _create_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.42, 0.56, 0.68)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.82, 0.88, 0.95)
	environment.ambient_light_energy = 0.75
	world_environment.environment = environment
	add_child(world_environment)

	var sunlight := DirectionalLight3D.new()
	sunlight.name = "Sun"
	sunlight.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sunlight.light_energy = 1.25
	sunlight.shadow_enabled = true
	add_child(sunlight)


func _create_ground() -> void:
	var ground_material := _make_material(Color(0.18, 0.23, 0.20), 0.95)
	_create_static_box(
		"Ground",
		Vector3(32.0, 0.30, 32.0),
		Vector3(0.0, -0.15, 0.0),
		ground_material
	)

	var driveway_material := _make_material(Color(0.20, 0.22, 0.25), 0.92)
	_create_visual_box(
		self,
		"Driveway",
		Vector3(20.0, 0.04, 20.0),
		Vector3(0.0, 0.02, 0.0),
		driveway_material
	)


func _create_scenery() -> void:
	var house_material := _make_material(Color(0.52, 0.18, 0.13), 0.85)
	var roof_material := _make_material(Color(0.10, 0.11, 0.14), 0.95)
	var door_material := _make_material(Color(0.30, 0.17, 0.08), 0.90)
	var tree_material := _make_material(Color(0.10, 0.31, 0.16), 0.90)
	var trunk_material := _make_material(Color(0.30, 0.18, 0.08), 0.95)
	var fence_material := _make_material(Color(0.62, 0.58, 0.48), 0.95)

	_create_static_box(
		"House",
		Vector3(7.0, 4.0, 5.0),
		Vector3(-10.8, 2.0, -9.8),
		house_material
	)
	_create_visual_box(
		self,
		"Roof",
		Vector3(7.6, 0.8, 5.6),
		Vector3(-10.8, 4.35, -9.8),
		roof_material
	)
	_create_visual_box(
		self,
		"Door",
		Vector3(1.2, 2.3, 0.15),
		Vector3(-8.5, 1.15, -7.25),
		door_material
	)

	for tree_position in [
		Vector3(11.5, 0.0, -10.5),
		Vector3(12.5, 0.0, 9.0),
		Vector3(-12.0, 0.0, 10.5)
	]:
		_create_visual_box(
			self,
			"TreeTrunk",
			Vector3(0.55, 2.2, 0.55),
			tree_position + Vector3(0.0, 1.1, 0.0),
			trunk_material
		)
		_create_visual_box(
			self,
			"TreeTop",
			Vector3(2.5, 3.0, 2.5),
			tree_position + Vector3(0.0, 3.0, 0.0),
			tree_material
		)

	for x in range(-7, 8):
		if x % 2 == 0:
			_create_visual_box(
				self,
				"FencePost",
				Vector3(0.18, 1.0, 0.18),
				Vector3(float(x) * 2.0, 0.5, 14.2),
				fence_material
			)


func _create_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0.0, 1.0, 7.5)
	player.set_script(load("res://scripts/player.gd"))
	add_child(player)

	var collision := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.45
	capsule_shape.height = 1.8
	collision.shape = capsule_shape
	player.add_child(collision)

	var body_mesh := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.45
	capsule_mesh.height = 1.8
	capsule_mesh.material = _make_material(Color(0.92, 0.48, 0.08), 0.70)
	body_mesh.mesh = capsule_mesh
	player.add_child(body_mesh)

	var shovel_handle := _create_visual_box(
		player,
		"ShovelHandle",
		Vector3(0.12, 1.6, 0.12),
		Vector3(0.58, -0.05, -0.48),
		_make_material(Color(0.36, 0.20, 0.08), 0.90)
	)
	shovel_handle.rotation_degrees.z = -24.0

	var shovel_blade := _create_visual_box(
		player,
		"ShovelBlade",
		Vector3(0.75, 0.12, 0.60),
		Vector3(0.85, -0.75, -0.68),
		_make_material(Color(0.12, 0.22, 0.34), 0.65)
	)
	shovel_blade.rotation_degrees.z = -24.0


func _create_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.global_position = player.global_position + Vector3(0.0, 10.0, 10.0)
	add_child(camera)
	camera.look_at(player.global_position, Vector3.UP)


func _create_snow_root() -> void:
	snow_root = Node3D.new()
	snow_root.name = "Snow"
	add_child(snow_root)


func _generate_snow() -> void:
	for child in snow_root.get_children():
		child.queue_free()

	active_snow.clear()
	snow_cleared = 0
	completion_announced = false

	var snow_material := _make_material(Color(0.88, 0.95, 1.0), 0.58)
	var offset := float(SNOW_GRID_SIZE - 1) * SNOW_TILE_SPACING * 0.5

	for x in range(SNOW_GRID_SIZE):
		for z in range(SNOW_GRID_SIZE):
			var tile := Node3D.new()
			tile.name = "Snow_%02d_%02d" % [x, z]
			tile.position = Vector3(
				float(x) * SNOW_TILE_SPACING - offset,
				0.13,
				float(z) * SNOW_TILE_SPACING - offset
			)
			snow_root.add_child(tile)

			_create_visual_box(
				tile,
				"Mesh",
				Vector3(SNOW_TILE_SIZE, 0.18, SNOW_TILE_SIZE),
				Vector3.ZERO,
				snow_material
			)
			active_snow.append(tile)

	total_snow = active_snow.size()
	_update_hud()


func _clear_nearby_snow() -> void:
	if not is_instance_valid(player):
		return

	var player_position_2d := Vector2(player.global_position.x, player.global_position.z)
	var cleared_now := 0

	for index in range(active_snow.size() - 1, -1, -1):
		var tile := active_snow[index]
		if not is_instance_valid(tile):
			active_snow.remove_at(index)
			continue

		var tile_position_2d := Vector2(tile.global_position.x, tile.global_position.z)
		if player_position_2d.distance_to(tile_position_2d) <= clear_radius:
			active_snow.remove_at(index)
			tile.queue_free()
			snow_cleared += 1
			money += payout_per_tile
			cleared_now += 1

	if cleared_now > 0:
		status_label.text = "%d Schneefeld(er) geräumt." % cleared_now
		_update_hud()


func _buy_next_upgrade() -> void:
	var next_index := upgrade_level + 1

	if next_index >= upgrades.size():
		status_label.text = "Du besitzt bereits das beste Gerät."
		return

	var upgrade: Dictionary = upgrades[next_index]
	var cost: int = upgrade["cost"]

	if money < cost:
		status_label.text = "Für %s fehlen dir noch %d Geld." % [
			upgrade["name"],
			cost - money
		]
		return

	money -= cost
	upgrade_level = next_index
	current_tool = upgrade["name"]
	clear_radius = upgrade["radius"]
	payout_per_tile = upgrade["payout"]

	status_label.text = "%s gekauft!" % current_tool
	_update_hud()


func _update_hud() -> void:
	if not is_instance_valid(snow_label):
		return

	snow_label.text = "Geräumter Schnee: %d / %d" % [snow_cleared, total_snow]
	money_label.text = "Geld: %d" % money
	tool_label.text = "Gerät: %s | Räumbreite: %.1f" % [current_tool, clear_radius]

	var next_index := upgrade_level + 1
	if next_index < upgrades.size():
		var next_upgrade: Dictionary = upgrades[next_index]
		upgrade_label.text = "Nächstes Upgrade [U]: %s – %d Geld" % [
			next_upgrade["name"],
			next_upgrade["cost"]
		]
	else:
		upgrade_label.text = "Alle Upgrades gekauft."


func _create_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(430.0, 0.0)
	canvas.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 5)
	margin.add_child(layout)

	var title := Label.new()
	title.text = "MR. PLOW – PROTOTYP"
	title.add_theme_font_size_override("font_size", 22)
	layout.add_child(title)

	snow_label = Label.new()
	layout.add_child(snow_label)

	money_label = Label.new()
	layout.add_child(money_label)

	tool_label = Label.new()
	layout.add_child(tool_label)

	upgrade_label = Label.new()
	layout.add_child(upgrade_label)

	var controls := Label.new()
	controls.text = "WASD: Laufen | Leertaste/Maus: Räumen | U: Upgrade | R: Neuer Schnee"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(controls)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 16)
	layout.add_child(status_label)


func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _create_visual_box(
	parent: Node,
	node_name: String,
	size: Vector3,
	position: Vector3,
	material: StandardMaterial3D
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = position

	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = material

	mesh_instance.mesh = box_mesh
	parent.add_child(mesh_instance)
	return mesh_instance


func _create_static_box(
	node_name: String,
	size: Vector3,
	position: Vector3,
	material: StandardMaterial3D
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	add_child(body)

	_create_visual_box(
		body,
		"Mesh",
		size,
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
