extends Node

const TROOPS_PATH: String = "res://data/troops.json"

var troops: Array[Dictionary] = []
var troops_by_id: Dictionary = {}
var troops_by_type_tier: Dictionary = {}


func _ready() -> void:
	load_troops()


func load_troops() -> void:
	troops.clear()
	troops_by_id.clear()
	troops_by_type_tier.clear()

	if not FileAccess.file_exists(TROOPS_PATH):
		push_error("TroopDatabase: Missing file: " + TROOPS_PATH)
		return

	var file: FileAccess = FileAccess.open(TROOPS_PATH, FileAccess.READ)
	if file == null:
		push_error("TroopDatabase: Could not open " + TROOPS_PATH)
		return

	var text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)

	if typeof(parsed) != TYPE_ARRAY:
		push_error("TroopDatabase: troops.json must be an array.")
		return

	for item: Variant in parsed:
		if typeof(item) != TYPE_DICTIONARY:
			continue

		var troop: Dictionary = item
		var troop_id: String = str(troop.get("id", ""))
		var troop_type: String = _normalize_type(str(troop.get("troopType", troop.get("type", ""))))
		var tier: int = int(troop.get("tier", 1))

		if troop_id == "" or troop_type == "":
			continue

		troops.append(troop)
		troops_by_id[troop_id] = troop
		troops_by_type_tier[_make_key(troop_type, tier)] = troop

	print("TroopDatabase Loaded: ", troops.size(), " troops")


func get_troop_by_id(troop_id: String) -> Dictionary:
	return troops_by_id.get(troop_id, {})


func get_troop(troop_type: String, tier: int = 1) -> Dictionary:
	var clean_type: String = _normalize_type(troop_type)
	return troops_by_type_tier.get(_make_key(clean_type, tier), {})


func get_best_unlocked_troop(troop_type: String) -> Dictionary:
	# Beta default: use tier 1 until building-level unlock checks are connected.
	return get_troop(troop_type, 1)


func get_display_name(troop_type: String, tier: int = 1) -> String:
	var troop: Dictionary = get_troop(troop_type, tier)
	return str(troop.get("name", troop_type.capitalize()))


func get_training_cost(troop_type: String, tier: int = 1, amount: int = 1) -> Dictionary:
	var troop: Dictionary = get_troop(troop_type, tier)
	var base_cost: Dictionary = troop.get("trainingCost", {})
	var total: Dictionary = {
		"food": int(base_cost.get("food", 0)) * amount,
		"wood": int(base_cost.get("wood", 0)) * amount,
		"stone": int(base_cost.get("stone", 0)) * amount,
		"iron": int(base_cost.get("iron", 0)) * amount,
		"valor": int(base_cost.get("valor", 0)) * amount
	}
	return total


func get_training_time(troop_type: String, tier: int = 1, amount: int = 1) -> int:
	var troop: Dictionary = get_troop(troop_type, tier)
	var base_time: int = int(troop.get("trainingTimeSec", 1))
	return max(base_time * amount, 1)


func get_power_gain(troop_type: String, tier: int = 1, amount: int = 1) -> int:
	var troop: Dictionary = get_troop(troop_type, tier)
	var base_power: int = int(troop.get("power", 0))
	return base_power * amount


func can_afford(cost: Dictionary) -> bool:
	var food_cost: int = int(cost.get("food", 0))
	var wood_cost: int = int(cost.get("wood", 0))
	var stone_cost: int = int(cost.get("stone", 0))
	var iron_cost: int = int(cost.get("iron", 0))

	return (
		GameState.food >= food_cost
		and GameState.wood >= wood_cost
		and GameState.stone >= stone_cost
		and GameState.iron >= iron_cost
	)


func spend_training_cost(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false

	var food_cost: int = int(cost.get("food", 0))
	var wood_cost: int = int(cost.get("wood", 0))
	var stone_cost: int = int(cost.get("stone", 0))
	var iron_cost: int = int(cost.get("iron", 0))

	GameState.spend_resources(food_cost, wood_cost, stone_cost, iron_cost)
	return true


func format_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []

	var food: int = int(cost.get("food", 0))
	var wood: int = int(cost.get("wood", 0))
	var stone: int = int(cost.get("stone", 0))
	var iron: int = int(cost.get("iron", 0))
	var valor: int = int(cost.get("valor", 0))

	if food > 0:
		parts.append("Food: " + str(food))
	if wood > 0:
		parts.append("Wood: " + str(wood))
	if stone > 0:
		parts.append("Stone: " + str(stone))
	if iron > 0:
		parts.append("Iron: " + str(iron))
	if valor > 0:
		parts.append("Valor: " + str(valor))

	if parts.is_empty():
		return "Free"

	return " | ".join(parts)


func get_missing_cost_text(cost: Dictionary) -> String:
	var missing: Array[String] = []

	var food_cost: int = int(cost.get("food", 0))
	var wood_cost: int = int(cost.get("wood", 0))
	var stone_cost: int = int(cost.get("stone", 0))
	var iron_cost: int = int(cost.get("iron", 0))

	if GameState.food < food_cost:
		missing.append("Food: " + str(food_cost - GameState.food))
	if GameState.wood < wood_cost:
		missing.append("Wood: " + str(wood_cost - GameState.wood))
	if GameState.stone < stone_cost:
		missing.append("Stone: " + str(stone_cost - GameState.stone))
	if GameState.iron < iron_cost:
		missing.append("Iron: " + str(iron_cost - GameState.iron))

	if missing.is_empty():
		return ""

	return "Missing " + " | ".join(missing)


func _make_key(troop_type: String, tier: int) -> String:
	return _normalize_type(troop_type) + "_t" + str(tier)


func _normalize_type(troop_type: String) -> String:
	var clean: String = troop_type.strip_edges().to_lower()

	match clean:
		"infantry", "infantry barracks", "barracks":
			return "infantry"
		"marksmen", "marksman", "archer", "archers", "marksmen camp":
			return "marksmen"
		"cavalry", "cavalry stable", "stable":
			return "cavalry"
		_:
			return clean
