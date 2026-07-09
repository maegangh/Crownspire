extends Node2D

@export var wildling_scene: PackedScene
@export var resource_scene: PackedScene

@export var wolf_texture: Texture2D
@export var bear_texture: Texture2D
@export var boar_texture: Texture2D
@export var spider_texture: Texture2D
@export var troll_texture: Texture2D
@export var dragon_texture: Texture2D

@export var food_texture: Texture2D
@export var wood_texture: Texture2D
@export var stone_texture: Texture2D
@export var iron_texture: Texture2D
@export var crystal_texture: Texture2D

@onready var wildling_spawns: Node2D = $WildlingSpawns
@onready var resource_spawns: Node2D = $ResourceSpawns

var wildling_spawn_data := [
	{"level": 1, "pos": Vector2(-600, -350)},
	{"level": 3, "pos": Vector2(180, -360)},
	{"level": 6, "pos": Vector2(-720, 120)},
	{"level": 11, "pos": Vector2(120, 160)},
	{"level": 16, "pos": Vector2(-520, 560)},
	{"level": 21, "pos": Vector2(40, 620)},
	{"level": 26, "pos": Vector2(620, 520)}
]

var resource_spawn_data := [
	{"type": "food", "level": 1, "pos": Vector2(-850, -100)},
	{"type": "food", "level": 4, "pos": Vector2(-420, 420)},
	{"type": "wood", "level": 2, "pos": Vector2(-100, -650)},
	{"type": "wood", "level": 5, "pos": Vector2(360, -520)},
	{"type": "stone", "level": 3, "pos": Vector2(720, -120)},
	{"type": "stone", "level": 6, "pos": Vector2(260, 360)},
	{"type": "iron", "level": 4, "pos": Vector2(-650, 720)},
	{"type": "iron", "level": 7, "pos": Vector2(-120, 820)},
	{"type": "crystal", "level": 5, "pos": Vector2(760, 760)}
]

func _ready() -> void:
	spawn_wildlings()
	spawn_resources()

func spawn_wildlings() -> void:
	if wildling_scene == null:
		push_error("WorldMap ERROR: wildling_scene is not assigned.")
		return

	for child in wildling_spawns.get_children():
		child.queue_free()

	for data in wildling_spawn_data:
		var wildling = wildling_scene.instantiate()
		wildling_spawns.add_child(wildling)
		wildling.position = data["pos"]
		setup_wildling(wildling, data["level"])

func spawn_resources() -> void:
	if resource_scene == null:
		push_error("WorldMap ERROR: resource_scene is not assigned.")
		return

	for child in resource_spawns.get_children():
		child.queue_free()

	for data in resource_spawn_data:
		var node = resource_scene.instantiate()
		resource_spawns.add_child(node)
		node.position = data["pos"]
		setup_resource(node, data["type"], data["level"])

func setup_resource(node: Node, resource_type: String, level: int) -> void:
	var sprite := node.get_node_or_null("Sprite2D")
	if sprite == null:
		push_error("ResourceNode missing Sprite2D.")
		return

	sprite.texture = get_resource_texture(resource_type)
	node.scale = Vector2(0.08, 0.08)

	var click_area = node.get_node_or_null("ClickArea")
	if click_area != null:
		click_area.resource_type = resource_type
		click_area.level = level
		click_area.amount = get_resource_amount(level)

func get_resource_texture(resource_type: String) -> Texture2D:
	match resource_type:
		"food": return food_texture
		"wood": return wood_texture
		"stone": return stone_texture
		"iron": return iron_texture
		"crystal": return crystal_texture
	return null

func get_resource_amount(level: int) -> int:
	var amounts := {
		1: 10000,
		2: 25000,
		3: 50000,
		4: 100000,
		5: 200000,
		6: 400000,
		7: 800000
	}
	return amounts.get(level, 10000)

func setup_wildling(wildling: Node, level: int) -> void:
	var sprite := wildling.get_node_or_null("Sprite2D")
	if sprite == null:
		push_error("Wildling scene missing Sprite2D.")
		return

	sprite.texture = get_texture_for_level(level)

	var click_area = wildling.get_node_or_null("ClickArea")
	if click_area == null:
		push_error("Wildling scene missing ClickArea.")
		return

	click_area.level = level
	click_area.power = get_power_for_level(level)
	click_area.card_texture = get_card_for_level(level)

func get_texture_for_level(level: int) -> Texture2D:
	if level <= 5: return wolf_texture
	elif level <= 10: return bear_texture
	elif level <= 15: return spider_texture
	elif level <= 20: return boar_texture
	elif level <= 25: return troll_texture
	return dragon_texture

func get_power_for_level(level: int) -> int:
	if level == 1: return 100
	if level == 2: return 250
	if level == 3: return 500
	if level == 4: return 750
	if level == 5: return 1000
	if level <= 10: return 1500 + ((level - 6) * 500)
	if level <= 15: return 7500 + ((level - 11) * 2500)
	if level <= 20: return 25000 + ((level - 16) * 5000)
	if level <= 25: return 60000 + ((level - 21) * 10000)
	return 120000 + ((level - 26) * 20000)

func get_card_for_level(level: int) -> Texture2D:
	if level <= 5: return load("res://assets/UI/wildling_cards/wolf_card.png")
	elif level <= 10: return load("res://assets/UI/wildling_cards/bear_card.png")
	elif level <= 15: return load("res://assets/UI/wildling_cards/spider_card.png")
	elif level <= 20: return load("res://assets/UI/wildling_cards/boar_card.png")
	elif level <= 25: return load("res://assets/UI/wildling_cards/troll_card.png")
	return load("res://assets/UI/wildling_cards/dragon_card.png")
