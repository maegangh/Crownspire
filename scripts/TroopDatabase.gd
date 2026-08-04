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


## Highest unlocked tier for this type at the given building level.
## Unlock ladder comes from troops.json unlockRequirement ("… Lv. N").
func get_best_unlocked_troop(troop_type: String, building_level: int = 1) -> Dictionary:
	var clean_type: String = _normalize_type(troop_type)
	var best: Dictionary = {}
	var best_tier: int = 0
	var level: int = maxi(1, building_level)

	for troop: Dictionary in troops:
		if _normalize_type(str(troop.get("troopType", troop.get("type", "")))) != clean_type:
			continue
		var tier: int = int(troop.get("tier", 1))
		var required: int = parse_unlock_level(str(troop.get("unlockRequirement", "")))
		if level < required:
			continue
		if tier >= best_tier:
			best_tier = tier
			best = troop

	if best.is_empty():
		return get_troop(clean_type, 1)
	return best


func get_highest_unlocked_tier(troop_type: String, building_level: int = 1) -> int:
	var troop: Dictionary = get_best_unlocked_troop(troop_type, building_level)
	return int(troop.get("tier", 1))


func is_tier_unlocked(troop_type: String, tier: int, building_level: int) -> bool:
	var troop: Dictionary = get_troop(troop_type, tier)
	if troop.is_empty():
		return false
	return building_level >= parse_unlock_level(str(troop.get("unlockRequirement", "")))


## All tiers for a type, sorted ascending (T1..T12).
func get_tiers_for_type(troop_type: String) -> Array[Dictionary]:
	var clean_type: String = _normalize_type(troop_type)
	var rows: Array[Dictionary] = []
	for troop: Dictionary in troops:
		if _normalize_type(str(troop.get("troopType", troop.get("type", "")))) != clean_type:
			continue
		rows.append(troop)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("tier", 0)) < int(b.get("tier", 0))
	)
	return rows


func get_unlock_requirement_text(troop_type: String, tier: int) -> String:
	var troop: Dictionary = get_troop(troop_type, tier)
	if troop.is_empty():
		return "Unknown requirement"
	var req: String = str(troop.get("unlockRequirement", "")).strip_edges()
	return req if req != "" else "Locked"


func parse_unlock_level(requirement: String) -> int:
	var req: String = requirement.strip_edges()
	if req.is_empty():
		return 1
	var idx: int = req.rfind("Lv.")
	if idx < 0:
		idx = req.rfind("Lv ")
	if idx < 0:
		return 1
	var tail: String = req.substr(idx + 3).strip_edges()
	var digits: String = ""
	for i: int in range(tail.length()):
		var ch: String = tail[i]
		if ch >= "0" and ch <= "9":
			digits += ch
		elif digits != "":
			break
	if digits == "":
		return 1
	return maxi(1, int(digits))


## Per-batch training capacity from building level (shared by all three training buildings).
## Lv.1 = 100, then +50 per additional level.
func get_training_capacity(building_level: int) -> int:
	var level: int = maxi(1, building_level)
	return 100 + (level - 1) * 50


## Resource-only affordability for 1-unit trainingCost (no capacity cap).
## Same resource loop used by get_max_trainable — not a separate formula.
func get_affordable_trainable_count(troop_type: String, tier: int) -> int:
	return _max_units_affordable_for_cost(get_training_cost(troop_type, tier, 1))


## Max amount limited by capacity and currently affordable resources.
func get_max_trainable(troop_type: String, tier: int, building_level: int) -> int:
	var capacity: int = get_training_capacity(building_level)
	if capacity <= 0:
		return 0
	return maxi(0, mini(capacity, get_affordable_trainable_count(troop_type, tier)))


func _max_units_affordable_for_cost(unit_cost: Dictionary) -> int:
	## Shared affordability loop for train + promote unit costs.
	var max_by_res: int = 0x7fffffff
	var saw_cost: bool = false
	for key: String in ["food", "wood", "stone", "iron"]:
		var unit: int = int(unit_cost.get(key, 0))
		if unit <= 0:
			continue
		saw_cost = true
		var have: int = 0
		match key:
			"food":
				have = int(GameState.food)
			"wood":
				have = int(GameState.wood)
			"stone":
				have = int(GameState.stone)
			"iron":
				have = int(GameState.iron)
		max_by_res = mini(max_by_res, int(have / unit))
	# Free unit cost → unbounded by resources (capacity / ownership still bind).
	if not saw_cost:
		return 0x7fffffff
	return maxi(0, max_by_res)


## ---------------------------------------------------------------------------
## BETA PROMOTION FORMULA (no canonical promotionCost/promotionTime in troops.json)
##
## Audit finding: troops.json has trainingCost + trainingTimeSec only.
## There is NO promotionCost / promotionTime / promote field anywhere in data.
##
## Centralized beta rule (TroopDatabase only — not hidden in UI):
##   unit_cost  = max(0, target.trainingCost[res] - source.trainingCost[res])
##   unit_time  = max(1, target.trainingTimeSec - source.trainingTimeSec)
##   total      = unit * amount
##
## Promote any lower unlocked source tier → selected unlocked target tier.
## ---------------------------------------------------------------------------
const PROMOTION_FORMULA_VERSION: String = "beta_cost_delta_v1"


func get_promotion_cost(troop_type: String, source_tier: int, target_tier: int, amount: int = 1) -> Dictionary:
	var qty: int = maxi(0, amount)
	var src: Dictionary = get_training_cost(troop_type, source_tier, 1)
	var dst: Dictionary = get_training_cost(troop_type, target_tier, 1)
	return {
		"food": maxi(0, int(dst.get("food", 0)) - int(src.get("food", 0))) * qty,
		"wood": maxi(0, int(dst.get("wood", 0)) - int(src.get("wood", 0))) * qty,
		"stone": maxi(0, int(dst.get("stone", 0)) - int(src.get("stone", 0))) * qty,
		"iron": maxi(0, int(dst.get("iron", 0)) - int(src.get("iron", 0))) * qty,
		"valor": maxi(0, int(dst.get("valor", 0)) - int(src.get("valor", 0))) * qty,
	}


func get_promotion_time(troop_type: String, source_tier: int, target_tier: int, amount: int = 1) -> int:
	var qty: int = maxi(0, amount)
	if qty <= 0:
		return 0
	var src_unit: int = int(get_troop(troop_type, source_tier).get("trainingTimeSec", 1))
	var dst_unit: int = int(get_troop(troop_type, target_tier).get("trainingTimeSec", 1))
	var unit: int = maxi(1, dst_unit - src_unit)
	return maxi(1, unit * qty)


## Resource-only affordability for 1-unit promotion cost (no capacity / ownership cap).
func get_affordable_promotable_count(troop_type: String, source_tier: int, target_tier: int) -> int:
	return _max_units_affordable_for_cost(get_promotion_cost(troop_type, source_tier, target_tier, 1))


func get_max_promotable(
	troop_type: String,
	source_tier: int,
	target_tier: int,
	building_level: int,
	available_source: int
) -> int:
	var capacity: int = get_training_capacity(building_level)
	var limit: int = mini(capacity, maxi(0, available_source))
	if limit <= 0:
		return 0
	return maxi(0, mini(limit, get_affordable_promotable_count(troop_type, source_tier, target_tier)))


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

	return GameState.spend_resources(food_cost, wood_cost, stone_cost, iron_cost)


func refund_training_cost(cost: Dictionary) -> void:
	var food_cost: int = int(cost.get("food", 0))
	var wood_cost: int = int(cost.get("wood", 0))
	var stone_cost: int = int(cost.get("stone", 0))
	var iron_cost: int = int(cost.get("iron", 0))
	if food_cost > 0:
		GameState.add_food(food_cost)
	if wood_cost > 0:
		GameState.add_wood(wood_cost)
	if stone_cost > 0:
		GameState.add_stone(stone_cost)
	if iron_cost > 0:
		GameState.add_iron(iron_cost)


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
