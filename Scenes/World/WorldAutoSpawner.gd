extends Node2D

@export var resource_node_scene: PackedScene
@export var wildling_node_scene: PackedScene

@export var food_texture: Texture2D
@export var wood_texture: Texture2D
@export var stone_texture: Texture2D
@export var iron_texture: Texture2D
@export var crystal_texture: Texture2D

@export var wolf_texture: Texture2D
@export var bear_texture: Texture2D
@export var spider_texture: Texture2D
@export var boar_texture: Texture2D
@export var troll_texture: Texture2D
@export var dragon_texture: Texture2D

@export var wolf_card: Texture2D
@export var bear_card: Texture2D
@export var spider_card: Texture2D
@export var boar_card: Texture2D
@export var troll_card: Texture2D
@export var dragon_card: Texture2D

@export var resource_count: int = 40
@export var wildling_count: int = 30
@export var map_size: Vector2 = Vector2(4096, 4096)
@export var edge_margin: float = 300.0

@onready var resource_spawns: Node2D = $ResourceSpawns
@onready var wildling_spawns: Node2D = $WildlingSpawns

var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	spawn_resources()
	spawn_wildlings()

func random_map_position() -> Vector2:
	return Vector2(
		rng.randf_range(edge_margin, map_size.x - edge_margin),
		rng.randf_range(edge_margin, map_size.y - edge_margin)
	)

func spawn_resources() -> void:
	for i in range(resource_count):
		var resource_type: String = ["food", "wood", "stone", "iron", "crystal"][rng.randi_range(0, 4)]
		var level: int = rng.randi_range(1, 7)

		var node: Node2D = resource_node_scene.instantiate()
		resource_spawns.add_child(node)
		node.position = random_map_position()
		node.scale = Vector2(0.10, 0.10)
		node.z_index = 100

		var sprite: Sprite2D = node.get_node_or_null("Sprite2D")
		if sprite:
			sprite.texture = get_resource_texture(resource_type)

		var click = node.get_node_or_null("ClickArea")
		if click:
			click.resource_type = resource_type
			click.level = level
			click.amount = get_resource_amount(level)

func get_wildling_card(level: int) -> Texture2D:
	if level <= 5:
		return wolf_card
	elif level <= 10:
		return bear_card
	elif level <= 15:
		return spider_card
	elif level <= 20:
		return boar_card
	elif level <= 25:
		return troll_card
	else:
		return dragon_card

func spawn_wildlings() -> void:
	for i in range(wildling_count):
		var level: int = rng.randi_range(1, 30)

		var node: Node2D = wildling_node_scene.instantiate()
		wildling_spawns.add_child(node)
		node.position = random_map_position()
		node.scale = Vector2(0.68, 0.68)
		node.z_index = 100

		var sprite: Sprite2D = node.get_node_or_null("Sprite2D")
		if sprite:
			sprite.texture = get_wildling_texture(level)

		var click = node.get_node_or_null("ClickArea")
		if click:
			click.level = level
			click.power = level * 2500
			click.species = get_wildling_species(level)
			click.card_texture = get_wildling_card(level)

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
	return amounts[level]

func get_wildling_texture(level: int) -> Texture2D:
	if level <= 5: return wolf_texture
	if level <= 10: return bear_texture
	if level <= 15: return spider_texture
	if level <= 20: return boar_texture
	if level <= 25: return troll_texture
	return dragon_texture

func get_wildling_species(level: int) -> String:
	if level <= 5:
		return "wolf"
	elif level <= 10:
		return "bear"
	elif level <= 15:
		return "spider"
	elif level <= 20:
		return "boar"
	elif level <= 25:
		return "troll"
	else:
		return "dragon"

func is_position_clear(pos: Vector2, min_distance: float) -> bool:
	for node in get_tree().get_nodes_in_group("world_blockers"):
		if node.global_position.distance_to(pos) < min_distance:
			return false

	for node in resource_spawns.get_children():
		if node.global_position.distance_to(pos) < min_distance:
			return false

	for node in wildling_spawns.get_children():
		if node.global_position.distance_to(pos) < min_distance:
			return false

	return true
