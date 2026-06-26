extends Node2D

@export var wildling_scene: PackedScene
@export var wolf_texture: Texture2D
@export var bear_texture: Texture2D
@export var boar_texture: Texture2D
@export var spider_texture: Texture2D
@export var troll_texture: Texture2D
@export var dragon_texture: Texture2D

func _ready():
	spawn_wildlings()

func spawn_wildlings():
	var spawn_points = [
	Vector2(0, 0),
	Vector2(300, 0),
	Vector2(600, 0),
	Vector2(0, 300),
	Vector2(300, 300),
	Vector2(600, 300)
]


	var levels = [1, 3, 6, 11, 16, 21]

	for i in range(spawn_points.size()):
		var wildling = wildling_scene.instantiate()
		$WildlingSpawns.add_child(wildling)
		wildling.position = spawn_points[i]
		print("Spawned wildling ", i, " at ", spawn_points[i])
		setup_wildling(wildling, levels[i])
		

func setup_wildling(wildling, level):
	var texture = wolf_texture

	if level <= 5:
		texture = wolf_texture
	elif level <= 10:
		texture = bear_texture
	elif level <= 15:
		texture = boar_texture
	elif level <= 20:
		texture = spider_texture
	elif level <= 25:
		texture = troll_texture
	else:
		texture = dragon_texture

	wildling.get_node("Sprite2D").texture = texture

	var click_area = wildling.get_node("Area2D")
	click_area.level = level
	click_area.power = get_power_for_level(level)
	click_area.card_texture = get_card_for_level(level)
	
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
	if level <= 5:
		return load("res://assets/UI/wildling_cards/wolf_card.png")
	elif level <= 10:
		return load("res://assets/UI/wildling_cards/bear_card.png")
	elif level <= 15:
		return load("res://assets/UI/wildling_cards/boar_card.png")
	elif level <= 20:
		return load("res://assets/UI/wildling_cards/spider_card.png")
	elif level <= 25:
		return load("res://assets/UI/wildling_cards/troll_card.png")
	else:
		return load("res://assets/UI/wildling_cards/dragon_card.png")
