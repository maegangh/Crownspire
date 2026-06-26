extends Node2D

@export var monster_scene: PackedScene
@export var max_monsters: int = 20

func _ready():
	spawn_monsters_from_json()

func spawn_monsters_from_json():
	var file = FileAccess.open("res://data/world_map_spawn_database.json", FileAccess.READ)

	if file == null:
		print("Could not open world map spawn database")
		return

	var text = file.get_as_text()
	var data = JSON.parse_string(text)

	if data == null:
		print("Could not parse world map spawn database")
		return

	var spawned = 0

	for item in data:
		if spawned >= max_monsters:
			print("Spawned monsters: ", spawned)
			return

		if item.get("type", "") == "monster_node":
			spawn_monster(item)
			spawned += 1

	print("Spawned monsters: ", spawned)

func spawn_monster(data):
	if monster_scene == null:
		print("Monster scene missing")
		return

	var monster = monster_scene.instantiate()
	add_child(monster)
	monster.setup(data)
