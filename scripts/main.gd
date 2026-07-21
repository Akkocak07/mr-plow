extends Node3D

const SNOW_GRID_SIZE := 15
const SNOW_TILE_SPACING := 1.30
const SNOW_TILE_SIZE := 1.24

var player
var snow_root: Node3D
var active_snow: Array[Node3D] = []

var snow_cleared: int = 0
var total_snow: int = 0
var money: int = 0
var upgrade_level: int = -1
var current_tool_name := "Einfache Schneeschaufel"
var clear_radius: float = 0.72
var clear_distance: float = 1.25
var payout_per_tile: int = 1
var action_interval: float = 0.30
var action_cooldown: float = 0.0
var completion_announced := false

var snow_label: Label
var money_label: Label
var tool_label: Label
var upgrade_label: Label
var status_label: Label

var upgrades := [
	{
		"name": "Breite Schneeschaufel",
		"cost": 25,
		"radius": 1.10,
		"distance": 1.40,
		"payout": 1,
		"interval": 0.25,
		"model": 1
	},
	{
		"name": "Elektrische Schneefräse",
		"cost": 75,
		"radius": 1.75,
		"distance": 1.60,
		"payout": 2,
		"interval": 0.15,
		"model": 2
	},
	{
		"name": "Kompakter Schneepflug",
		"cost": 190,
		"radius": 2.55,
		"distance": 1.85,
		"payout": 4,
		"interval": 0.09,
		"model": 3
	}
]


func _ready() -> void:
	_create_environment()
	_create_ground()
	_create_scenery()
	_create_player()
	_create_hud()
	_create_snow_root()
	_generate_snow()
	_update_hud()
	status_label.text = "Bewege die Maus zum Umschauen. Halte die linke Maustaste zum Räumen."


func _process(delta: float) -> void:
	action_cooldown = max(action_cooldown - delta, 0.0)

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
	environment.background_color = Color(0.37, 0.50, 0.64)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.82, 0.88, 0.96)
	environment.ambient_light_energy = 0.82
	world_environment.environment = environment
	add_child(world_environment)

	var sunlight := DirectionalLight3D.new()
	sunlight.name = "WinterSun"
	sunlight.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	sunlight.light_energy = 0.2
	sunlight.shadow_enabled = true
	add_child(sunlight)


func _create_ground() -> void:
	var ground_material := _make_material(Color(0.13, 0.18, 0.15), 0.96, 0.0)
	_create_static_box(
		"Ground",
		Vector3(34.0, 0.30, 34.0),
		Vector3(0.0, -0.15, 0.0),
		ground_material
	)

	var driveway_material := _make_material(Color(0.18, 0.20, 0.23), 0.92, 0.03)
	_create_visual_box(
		self,
		"Driveway",
		Vector3(21.0, 0.05, 21.0),
		Vector3(0.0, 0.025, 0.0),
		driveway_material
	)


func _create_scenery() -> void:
	var house_material := _make_material(Color(0.48, 0.15, 0.11), 0.85, 0.0)
	var roof_material := _make_material(Color(0.08, 0.09, 0.12), 0.94, 0.03)
	var door_material := _make_material(Color(0.27, 0.13, 0.06), 0.90, 0.0)
	var window_material := _make_material(Color(0.30, 0.62, 0.78), 0.24, 0.12)
	var tree_material := _make_material(Color(0.08, 0.28, 0.14), 0.92, 0.0)
	var trunk_material := _make_material(Color(0.27, 0.15, 0.06), 0.95, 0.0)
	var fence_material := _make_material(Color(0.59, 0.54, 0.43), 0.94, 0.0)

	_create_static_box(
		"House",
		Vector3(7.5, 4.2, 5.5),
		Vector3(-11.5, 2.1, -10.0),
		house_material
	)

	_create_visual_box(
		self,
		"Roof",
		Vector3(8.1, 0.85, 6.1),
		Vector3(-11.5, 4.55, -10.0),
		roof_material
	)

	_create_visual_box(
		self,
		"Door",
		Vector3(1.15, 2.35, 0.14),
		Vector3(-8.85, 1.18, -7.18),
		door_material
	)

	for window_x in [-12.7, -10.5]:
		_create_visual_box(
			self,
			"Window",
			Vector3(1.25, 1.20, 0.12),
			Vector3(window_x, 2.35, -7.17),
			window_material
		)

	for tree_position in [
		Vector3(11.8, 0.0, -11.0),
		Vector3(12.6, 0.0, 9.4),
		Vector3(-12.5, 0.0, 10.8)
	]:
		_create_visual_box(
			self,
			"TreeTrunk",
			Vector3(0.55, 2.25, 0.55),
			tree_position + Vector3(0.0, 1.12, 0.0),
			trunk_material
		)
		_create_visual_box(
			self,
			"TreeTopLower",
			Vector3(2.9, 2.2, 2.9),
			tree_position + Vector3(0.0, 2.80, 0.0),
			tree_material
		)
		_create_visual_box(
			self,
			"TreeTopUpper",
			Vector3(2.1, 1.8, 2.1),
			tree_position + Vector3(0.0, 4.20, 0.0),
			tree_material
		)

	for x in range(-7, 8):
		if x % 2 == 0:
			_create_visual_box(
				self,
				"FencePost",
				Vector3(0.18, 1.05, 0.18),
				Vector3(float(x) * 2.0, 0.52, 14.5),
				fence_material
			)

	_create_visual_box(
		self,
		"FenceRail",
		Vector3(28.0, 0.15, 0.15),
		Vector3(0.0, 0.72, 14.5),
		fence_material
	)


func _create_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0.0, 1.0, 7.8)
	player.set_script(load("res://scripts/player.gd"))

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.42
	capsule_shape.height = 1.80
	collision.shape = capsule_shape
	player.add_child(collision)

	add_child(player)


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

	var snow_material := _make_material(Color(0.90, 0.96, 1.0), 0.62, 0.0)
	var offset := float(SNOW_GRID_SIZE - 1) * SNOW_TILE_SPACING * 0.5

	for x in range(SNOW_GRID_SIZE):
		for z in range(SNOW_GRID_SIZE):
			var tile := Node3D.new()
			tile.name = "Snow_%02d_%02d" % [x, z]
			tile.position = Vector3(
				float(x) * SNOW_TILE_SPACING - offset,
				0.14,
				float(z) * SNOW_TILE_SPACING - offset
			)
			snow_root.add_child(tile)

			_create_visual_box(
				tile,
				"SnowMesh",
				Vector3(SNOW_TILE_SIZE, 0.20, SNOW_TILE_SIZE),
				Vector3.ZERO,
				snow_material
			)

			active_snow.append(tile)

	total_snow = active_snow.size()
	_update_hud()


func _clear_snow_in_front() -> void:
	if not is_instance_valid(player):
		return

	var forward: Vector3 = player.get_forward_direction()
	var clearing_center: Vector3 = player.global_position + forward * clear_distance
	var center_2d := Vector2(clearing_center.x, clearing_center.z)
	var cleared_now := 0

	for index in range(active_snow.size() - 1, -1, -1):
		var tile := active_snow[index]

		if not is_instance_valid(tile):
			active_snow.remove_at(index)
			continue

		var tile_2d := Vector2(tile.global_position.x, tile.global_position.z)

		if center_2d.distance_to(tile_2d) <= clear_radius:
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
		status_label.text = "Du besitzt bereits das beste Räumgerät."
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
	current_tool_name = upgrade["name"]
	clear_radius = upgrade["radius"]
	clear_distance = upgrade["distance"]
	payout_per_tile = upgrade["payout"]
	action_interval = upgrade["interval"]

	player.set_tool_model(upgrade["model"])

	status_label.text = "%s gekauft. Das Modell wurde gewechselt." % current_tool_name
	_update_hud()


func _create_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(475.0, 0.0)
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
	title.text = "MR. PLOW – FIRST-PERSON-PROTOTYP"
	title.add_theme_font_size_override("font_size", 21)
	layout.add_child(title)

	snow_label = Label.new()
	layout.add_child(snow_label)

	money_label = Label.new()
	layout.add_child(money_label)

	tool_label = Label.new()
	layout.add_child(tool_label)

	upgrade_label = Label.new()
	upgrade_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(upgrade_label)

	var controls := Label.new()
	controls.text = "WASD: Laufen | Maus: Umschauen | Linksklick/Leertaste: Räumen | U: Upgrade | R: Schnee | Esc: Maus"
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


func _update_hud() -> void:
	if not is_instance_valid(snow_label):
		return

	snow_label.text = "Geräumter Schnee: %d / %d" % [snow_cleared, total_snow]
	money_label.text = "Geld: %d" % money
	tool_label.text = "Gerät: %s | Räumbreite: %.2f" % [
		current_tool_name,
		clear_radius
	]

	var next_index := upgrade_level + 1
	if next_index < upgrades.size():
		var next_upgrade: Dictionary = upgrades[next_index]
		upgrade_label.text = "Nächstes Upgrade [U]: %s – %d Geld" % [
			next_upgrade["name"],
			next_upgrade["cost"]
		]
	else:
		upgrade_label.text = "Alle Werkzeugmodelle freigeschaltet."


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
