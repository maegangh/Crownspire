extends Node

var buildings = {}
var troops = {}
var research = {}
var heroes = []
var monsters = {}
var alliance = {}
var alliance_research = []
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
	load_alliance_research()
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

func load_alliance_research():
	var data = load_json("res://data/alliance_research.json")
	if typeof(data) == TYPE_ARRAY:
		alliance_research = data
	else:
		alliance_research = []
	if alliance_research.size() > 0:
		print("Alliance Research Loaded: ", alliance_research.size(), " categories")

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

## Canonical Alliance Research tree (Economy / Military / Territory / Support).
func get_alliance_research_data() -> Array:
	return alliance_research

func get_alliance_research_def(research_id: String) -> Dictionary:
	for category_block: Variant in alliance_research:
		if typeof(category_block) != TYPE_DICTIONARY:
			continue
		var researches: Array = category_block.get("researches", [])
		for research_def: Variant in researches:
			if typeof(research_def) == TYPE_DICTIONARY and str(research_def.get("id", "")) == research_id:
				var result: Dictionary = research_def.duplicate(true)
				result["category"] = str(category_block.get("category", ""))
				result["prerequisites"] = normalize_alliance_research_prerequisites(result.get("prerequisites", []))
				if not result.has("required_alliance_level"):
					var costs: Dictionary = result.get("costs", {})
					result["required_alliance_level"] = int(costs.get("requiredAllianceLevel", 1))
				if not result.has("tier"):
					result["tier"] = 1
				if not result.has("branch"):
					result["branch"] = str(result.get("category", "general")).to_lower()
				if not result.has("research_points"):
					result["research_points"] = 100
				if typeof(result.get("contribution_rewards", null)) != TYPE_DICTIONARY:
					result["contribution_rewards"] = {
						"personal_contribution": 120,
						"alliance_coins": 120,
					}
				# Migrate legacy multi-resource contribution_cost → single resource fields.
				if str(result.get("contribution_resource", "")) == "" \
						and typeof(result.get("contribution_cost", null)) == TYPE_DICTIONARY:
					var legacy: Dictionary = result.get("contribution_cost", {})
					var best_id: String = "food"
					var best_amount: int = -1
					for candidate: String in ["food", "wood", "stone", "iron"]:
						var amount: int = int(legacy.get(candidate, 0))
						if amount > best_amount:
							best_amount = amount
							best_id = candidate
					result["contribution_resource"] = best_id
					result["contribution_amount"] = max(1, best_amount if best_amount > 0 else 10000)
				if str(result.get("contribution_resource", "")) == "":
					result["contribution_resource"] = "food"
				if not result.has("contribution_amount"):
					result["contribution_amount"] = 10000
				return result
	return {}


## Normalizes legacy string prereqs and object prereqs into {research_id, required_level}.
func normalize_alliance_research_prerequisites(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return result
	for item: Variant in raw:
		if typeof(item) == TYPE_DICTIONARY:
			var research_id: String = str(item.get("research_id", item.get("id", "")))
			if research_id == "":
				continue
			result.append({
				"research_id": research_id,
				"required_level": max(1, int(item.get("required_level", item.get("level", 1)))),
			})
		elif typeof(item) == TYPE_STRING and str(item) != "":
			result.append({"research_id": str(item), "required_level": 1})
	return result

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
