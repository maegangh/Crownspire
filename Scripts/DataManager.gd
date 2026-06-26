extends Node

var buildings = {}
var troops = {}
var research = {}
var heroes = []
var monsters = {}
var alliance = {}
var hero_skills = {}
var city_layout = {}
var world_map_spawns = {}
var monster_spawns = {}

func _ready():
	load_buildings()
	load_troops()
	load_research()
	load_heroes()
	load_monsters()
	load_alliance()
	load_hero_skills()
	load_city_layout()
	load_world_map_spawns()
	load_monster_spawns()

func load_json(path: String):
	if !FileAccess.file_exists(path):
		print("Missing file: ", path)
		return {}

	var file = FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())

	if data == null:
		print("Failed to parse JSON: ", path)
		return {}

	return data

func load_buildings():
	buildings = load_json("res://data/buildings.json")
	if buildings.size() > 0:
		print("Buildings Loaded")

func load_troops():
	troops = load_json("res://data/troops.json")
	if troops.size() > 0:
		print("Troops Loaded")

func load_research():
	research = load_json("res://data/research.json")
	if research.size() > 0:
		print("Research Loaded")

func load_heroes():
	var data = load_json("res://data/heroes.json")
	if data is Array:
		heroes = data
	else:
		heroes = []

	if heroes.size() > 0:
		print("Heroes Loaded")

func load_monsters():
	monsters = load_json("res://data/monsters.json")
	if monsters.size() > 0:
		print("Monsters Loaded")

func load_alliance():
	alliance = load_json("res://data/alliance.json")
	if alliance.size() > 0:
		print("Alliance Loaded")

func load_hero_skills():
	hero_skills = load_json("res://data/hero_skills.json")
	if hero_skills.size() > 0:
		print("Hero Skills Loaded")

func load_city_layout():
	city_layout = load_json("res://data/city_layout.json")
	if city_layout.size() > 0:
		print("City Layout Loaded")

func load_world_map_spawns():
	world_map_spawns = load_json("res://data/world_map_spawn_database.json")
	if world_map_spawns.size() > 0:
		print("World Map Spawns Loaded")

func load_monster_spawns():
	monster_spawns = load_json("res://data/monster_spawns.json")
	if monster_spawns.size() > 0:
		print("Monster Spawns Loaded")

func get_all_heroes():
	return heroes

func get_hero(hero_id: String):
	for hero in heroes:
		if hero.has("id") and hero["id"] == hero_id:
			return hero
	return {}

func get_hero_skills():
	return hero_skills

func get_world_map_spawns():
	return world_map_spawns

func get_monster_spawns():
	return monster_spawns

func get_city_layout():
	return city_layout

func get_alliance_data():
	return alliance

func get_troop(troop_id: String):
	for troop in troops:
		if troop.has("id") and troop["id"] == troop_id:
			return troop
	return {}

func get_building_id_mapping(building_id: String) -> String:
	var clean_id = building_id.to_lower().strip_edges()

	match clean_id:
		"citadel_keep", "castle", "citadel", "keep":
			return "castle"
		"warehouse", "vault_warehouse":
			return "warehouse"
		"research_hall", "academy", "research":
			return "academy"
		"embassy", "imperial_embassy":
			return "embassy"
		"hall_of_heroes":
			return "hall_of_heroes"
		"trading_post":
			return "trading_post"
		"farm", "wanderers_farm":
			return "farm"
		"lumber_mill", "woodmill", "timber_woodmill":
			return "lumber_mill"
		"quarry", "slate_quarry":
			return "quarry"
		"iron_mine", "deep_iron_shaft", "deep-iron_shaft", "deep_iron":
			return "iron_mine"
		"hospital", "sacred_hospital":
			return "hospital"
		"sanctuary", "grave_sanctuary":
			return "sanctuary"
		"infantry_barracks":
			return "infantry_barracks"
		"marksmen_camp":
			return "marksmen_camp"
		"cavalry_stable":
			return "cavalry_stable"
		"watchtower", "sentry_watchtower":
			return "watchtower"
		_:
			return clean_id

func get_building_level_data(building_id: String, level: int) -> Dictionary:
	var mapped_id = get_building_id_mapping(building_id)

	if not buildings.has(mapped_id):
		return {}

	var building_data = buildings[mapped_id]

	if not building_data.has("levels"):
		return {}

	var levels_dict = building_data["levels"]
	var level_str = str(level)

	if not levels_dict.has(level_str):
		return {}

	return levels_dict[level_str]

func get_building_cost(building_id: String, level: int) -> Dictionary:
	var level_data = get_building_level_data(building_id, level)

	if level_data.has("costs"):
		return level_data["costs"]

	return {
		"food": 0,
		"wood": 0,
		"stone": 0,
		"iron": 0,
		"valor": 0
	}

func get_building_build_time(building_id: String, level: int) -> int:
	var level_data = get_building_level_data(building_id, level)

	if level_data.has("buildTimeSec"):
		return int(level_data["buildTimeSec"])

	return 0

func get_building_prerequisites(building_id: String, level: int) -> Array:
	var level_data = get_building_level_data(building_id, level)

	if level_data.has("prerequisites"):
		return level_data["prerequisites"]

	return []

func get_building_power_gain(building_id: String, level: int) -> int:
	var level_data = get_building_level_data(building_id, level)

	if level_data.has("powerGained"):
		return int(level_data["powerGained"])

	return 0
