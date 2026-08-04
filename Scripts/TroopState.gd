extends Node

signal training_updated

## Flat totals kept in sync for march/legacy callers.
var infantry: int = 0
var marksmen: int = 0
var cavalry: int = 0

## Per-tier idle pools: { tier_int: count }
var infantry_by_tier: Dictionary = {}
var marksmen_by_tier: Dictionary = {}
var cavalry_by_tier: Dictionary = {}

## Legacy flat wounded totals (kept in sync with wounded_*_by_tier).
var wounded_infantry: int = 0
var wounded_marksmen: int = 0
var wounded_cavalry: int = 0

## Persistent per-tier wounded pools (Wildling PvE Phase 3).
## Shape: { tier_int: count }
var wounded_infantry_by_tier: Dictionary = {}
var wounded_marksmen_by_tier: Dictionary = {}
var wounded_cavalry_by_tier: Dictionary = {}

var hospital_capacity: int = 1000
## Legacy flat Sanctuary fields (CampaignManager / old UI). Beta overflow uses tier maps; no capacity delete.
var sanctuary_capacity: int = 500
var sanctuary_troops: int = 0

## Persistent Sanctuary overflow pools (Phase 5). Shape: { tier_int: count }
var sanctuary_infantry_by_tier: Dictionary = {}
var sanctuary_marksmen_by_tier: Dictionary = {}
var sanctuary_cavalry_by_tier: Dictionary = {}

## One job slot per troop type.
var infantry_training_active: bool = false
var marksmen_training_active: bool = false
var cavalry_training_active: bool = false

var infantry_training_ready: bool = false
var marksmen_training_ready: bool = false
var cavalry_training_ready: bool = false

var infantry_training_amount: int = 0
var marksmen_training_amount: int = 0
var cavalry_training_amount: int = 0

var infantry_finish_time: int = 0
var marksmen_finish_time: int = 0
var cavalry_finish_time: int = 0

var infantry_training_start_time: int = 0
var marksmen_training_start_time: int = 0
var cavalry_training_start_time: int = 0

## "train" | "promote" | ""
var infantry_job_type: String = ""
var marksmen_job_type: String = ""
var cavalry_job_type: String = ""

var infantry_target_tier: int = 1
var marksmen_target_tier: int = 1
var cavalry_target_tier: int = 1

## Promotion only (0 when training).
var infantry_source_tier: int = 0
var marksmen_source_tier: int = 0
var cavalry_source_tier: int = 0


func _ready() -> void:
	load_troops()
	check_finished_training()


func _process(_delta: float) -> void:
	check_finished_training()


func _tier_map(troop_type: String) -> Dictionary:
	match _canon(troop_type):
		"Infantry":
			return infantry_by_tier
		"Marksmen":
			return marksmen_by_tier
		"Cavalry":
			return cavalry_by_tier
		_:
			return {}


func _set_tier_map(troop_type: String, map: Dictionary) -> void:
	match _canon(troop_type):
		"Infantry":
			infantry_by_tier = map
		"Marksmen":
			marksmen_by_tier = map
		"Cavalry":
			cavalry_by_tier = map


func _canon(troop_type: String) -> String:
	var clean: String = troop_type.strip_edges().to_lower()
	match clean:
		"infantry":
			return "Infantry"
		"marksmen", "marksman":
			return "Marksmen"
		"cavalry":
			return "Cavalry"
		_:
			return troop_type


func _resync_totals() -> void:
	infantry = _sum_map(infantry_by_tier)
	marksmen = _sum_map(marksmen_by_tier)
	cavalry = _sum_map(cavalry_by_tier)


func _sum_map(map: Dictionary) -> int:
	var total: int = 0
	for key: Variant in map.keys():
		total += maxi(0, int(map[key]))
	return total


func get_tier_count(troop_type: String, tier: int) -> int:
	var map: Dictionary = _tier_map(troop_type)
	return maxi(0, int(map.get(tier, map.get(str(tier), 0))))


func get_troop_count(troop_type: String) -> int:
	_resync_totals()
	match _canon(troop_type):
		"Infantry":
			return infantry
		"Marksmen":
			return marksmen
		"Cavalry":
			return cavalry
		_:
			return 0


func get_available_count(troop_type: String) -> int:
	return get_troop_count(troop_type)


func add_tier_troops(troop_type: String, tier: int, amount: int) -> void:
	if amount <= 0 or tier <= 0:
		return
	var map: Dictionary = _tier_map(troop_type).duplicate()
	var key: int = tier
	map[key] = get_tier_count(troop_type, tier) + amount
	_set_tier_map(troop_type, map)
	_resync_totals()


func remove_tier_troops(troop_type: String, tier: int, amount: int) -> bool:
	if amount <= 0:
		return true
	var have: int = get_tier_count(troop_type, tier)
	if have < amount:
		return false
	var map: Dictionary = _tier_map(troop_type).duplicate()
	var left: int = have - amount
	if left <= 0:
		map.erase(tier)
		map.erase(str(tier))
	else:
		map[tier] = left
	_set_tier_map(troop_type, map)
	_resync_totals()
	return true


## Remove from lowest tiers first (march deploy).
## Returns the exact tier breakdown taken: { "1": qty, "2": qty, ... } (string keys).
## Does not mutate if amount cannot be fulfilled (returns empty Dictionary).
func plan_tier_allocation(troop_type: String, amount: int) -> Dictionary:
	var out: Dictionary = {}
	if amount <= 0:
		return out
	if get_troop_count(troop_type) < amount:
		return {}
	var remaining: int = amount
	var map: Dictionary = _tier_map(troop_type).duplicate()
	var tiers: Array = map.keys()
	tiers.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for key: Variant in tiers:
		var tier: int = int(key)
		var have: int = maxi(0, int(map[key]))
		var take: int = mini(have, remaining)
		if take > 0:
			out[str(tier)] = take
			remaining -= take
		if remaining <= 0:
			break
	if remaining > 0:
		return {}
	return out


## Remove from lowest tiers first (march deploy).
func _remove_any_tiers(troop_type: String, amount: int) -> bool:
	if amount <= 0:
		return true
	var plan: Dictionary = plan_tier_allocation(troop_type, amount)
	if plan.is_empty() and amount > 0:
		return false
	for tier_key: Variant in plan.keys():
		if not remove_tier_troops(troop_type, int(tier_key), int(plan[tier_key])):
			return false
	return true


## Return survivors into tier 1 (legacy flat return path).
func _add_any(troop_type: String, amount: int) -> void:
	if amount <= 0:
		return
	add_tier_troops(troop_type, 1, amount)


func _wounded_tier_map(troop_type: String) -> Dictionary:
	match _canon(troop_type):
		"Infantry":
			return wounded_infantry_by_tier
		"Marksmen":
			return wounded_marksmen_by_tier
		"Cavalry":
			return wounded_cavalry_by_tier
		_:
			return {}


func _set_wounded_tier_map(troop_type: String, map: Dictionary) -> void:
	match _canon(troop_type):
		"Infantry":
			wounded_infantry_by_tier = map
		"Marksmen":
			wounded_marksmen_by_tier = map
		"Cavalry":
			wounded_cavalry_by_tier = map


func _resync_wounded_totals() -> void:
	wounded_infantry = _sum_tier_map(wounded_infantry_by_tier)
	wounded_marksmen = _sum_tier_map(wounded_marksmen_by_tier)
	wounded_cavalry = _sum_tier_map(wounded_cavalry_by_tier)


func _sum_tier_map(map: Dictionary) -> int:
	var total: int = 0
	for k: Variant in map.keys():
		total += int(map[k])
	return total


## Add wounded troops by tier composition. Does NOT touch available troops.
## composition: { "infantry": {1: n, ...}, "marksmen": {}, "cavalry": {} }
func add_wounded_by_tiers(composition: Dictionary) -> void:
	if typeof(composition) != TYPE_DICTIONARY:
		return
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = composition.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			continue
		var display: String = "Infantry"
		if kind == "marksmen":
			display = "Marksmen"
		elif kind == "cavalry":
			display = "Cavalry"
		var map: Dictionary = _wounded_tier_map(display).duplicate(true)
		for tk: Variant in by_tier.keys():
			var amt: int = int(by_tier[tk])
			if amt <= 0:
				continue
			var tier: int = int(tk)
			map[tier] = int(map.get(tier, 0)) + amt
		_set_wounded_tier_map(display, map)
	_resync_wounded_totals()
	save_troops()
	training_updated.emit()


func get_wounded_by_tiers() -> Dictionary:
	return {
		"infantry": _serialize_tier_map(wounded_infantry_by_tier),
		"marksmen": _serialize_tier_map(wounded_marksmen_by_tier),
		"cavalry": _serialize_tier_map(wounded_cavalry_by_tier),
	}


func get_wounded_count(troop_type: String = "") -> int:
	_resync_wounded_totals()
	if troop_type == "":
		return wounded_infantry + wounded_marksmen + wounded_cavalry
	match _canon(troop_type):
		"Infantry":
			return wounded_infantry
		"Marksmen":
			return wounded_marksmen
		"Cavalry":
			return wounded_cavalry
		_:
			return 0


func get_wounded_tier_count(troop_type: String, tier: int) -> int:
	var map: Dictionary = _wounded_tier_map(troop_type)
	return maxi(0, int(map.get(tier, map.get(str(tier), 0))))


## True if every requested type/tier amount is available in wounded pools.
func can_remove_wounded_by_tiers(composition: Dictionary) -> bool:
	if typeof(composition) != TYPE_DICTIONARY:
		return false
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = composition.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			continue
		var display: String = "Infantry"
		if kind == "marksmen":
			display = "Marksmen"
		elif kind == "cavalry":
			display = "Cavalry"
		for tk: Variant in by_tier.keys():
			var need: int = int(by_tier[tk])
			if need <= 0:
				continue
			if get_wounded_tier_count(display, int(tk)) < need:
				return false
	return true


## Remove wounded by exact tiers (healing reservation). Does not touch available troops.
func remove_wounded_by_tiers(composition: Dictionary) -> bool:
	if not can_remove_wounded_by_tiers(composition):
		return false
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = composition.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			continue
		var display: String = "Infantry"
		if kind == "marksmen":
			display = "Marksmen"
		elif kind == "cavalry":
			display = "Cavalry"
		var map: Dictionary = _wounded_tier_map(display).duplicate(true)
		for tk: Variant in by_tier.keys():
			var take: int = int(by_tier[tk])
			if take <= 0:
				continue
			var tier: int = int(tk)
			var have: int = int(map.get(tier, map.get(str(tier), 0)))
			var left: int = have - take
			map.erase(tier)
			map.erase(str(tier))
			if left > 0:
				map[tier] = left
		_set_wounded_tier_map(display, map)
	_resync_wounded_totals()
	save_troops()
	training_updated.emit()
	return true


## Canonical capacity from HealingState (hospital level × 1000). Fallback local field.
func get_hospital_capacity() -> int:
	if has_node("/root/HealingState") and HealingState.has_method("get_hospital_capacity"):
		hospital_capacity = HealingState.get_hospital_capacity()
	return hospital_capacity


## Waiting wounded + troops reserved in the active Hospital healing job.
func get_hospital_occupancy() -> int:
	var waiting: int = get_wounded_count()
	var healing: int = 0
	if has_node("/root/HealingState") and HealingState.has_method("get_healing_occupancy"):
		healing = HealingState.get_healing_occupancy()
	return waiting + healing


func get_hospital_available_capacity() -> int:
	return maxi(0, get_hospital_capacity() - get_hospital_occupancy())


func _sanctuary_tier_map(troop_type: String) -> Dictionary:
	match _canon(troop_type):
		"Infantry":
			return sanctuary_infantry_by_tier
		"Marksmen":
			return sanctuary_marksmen_by_tier
		"Cavalry":
			return sanctuary_cavalry_by_tier
		_:
			return {}


func _set_sanctuary_tier_map(troop_type: String, map: Dictionary) -> void:
	match _canon(troop_type):
		"Infantry":
			sanctuary_infantry_by_tier = map
		"Marksmen":
			sanctuary_marksmen_by_tier = map
		"Cavalry":
			sanctuary_cavalry_by_tier = map


func _resync_sanctuary_totals() -> void:
	sanctuary_troops = (
		_sum_tier_map(sanctuary_infantry_by_tier)
		+ _sum_tier_map(sanctuary_marksmen_by_tier)
		+ _sum_tier_map(sanctuary_cavalry_by_tier)
	)


func get_sanctuary_by_tiers() -> Dictionary:
	return {
		"infantry": _serialize_tier_map(sanctuary_infantry_by_tier),
		"marksmen": _serialize_tier_map(sanctuary_marksmen_by_tier),
		"cavalry": _serialize_tier_map(sanctuary_cavalry_by_tier),
	}


func get_sanctuary_count() -> int:
	_resync_sanctuary_totals()
	return sanctuary_troops


func get_sanctuary_tier_count(troop_type: String, tier: int) -> int:
	var map: Dictionary = _sanctuary_tier_map(troop_type)
	return maxi(0, int(map.get(tier, map.get(str(tier), 0))))


func add_sanctuary_by_tiers(composition: Dictionary) -> void:
	if typeof(composition) != TYPE_DICTIONARY:
		return
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = composition.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			continue
		var display: String = "Infantry"
		if kind == "marksmen":
			display = "Marksmen"
		elif kind == "cavalry":
			display = "Cavalry"
		var map: Dictionary = _sanctuary_tier_map(display).duplicate(true)
		for tk: Variant in by_tier.keys():
			var amt: int = int(by_tier[tk])
			if amt <= 0:
				continue
			var tier: int = int(tk)
			map[tier] = int(map.get(tier, 0)) + amt
		_set_sanctuary_tier_map(display, map)
	_resync_sanctuary_totals()
	save_troops()
	training_updated.emit()


func remove_sanctuary_by_tiers(composition: Dictionary) -> bool:
	if typeof(composition) != TYPE_DICTIONARY:
		return false
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = composition.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			continue
		var display: String = "Infantry"
		if kind == "marksmen":
			display = "Marksmen"
		elif kind == "cavalry":
			display = "Cavalry"
		for tk: Variant in by_tier.keys():
			var need: int = int(by_tier[tk])
			if need <= 0:
				continue
			if get_sanctuary_tier_count(display, int(tk)) < need:
				return false
	for kind2: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier2: Dictionary = composition.get(kind2, {}) as Dictionary
		if typeof(by_tier2) != TYPE_DICTIONARY:
			continue
		var display2: String = "Infantry"
		if kind2 == "marksmen":
			display2 = "Marksmen"
		elif kind2 == "cavalry":
			display2 = "Cavalry"
		var map: Dictionary = _sanctuary_tier_map(display2).duplicate(true)
		for tk2: Variant in by_tier2.keys():
			var take: int = int(by_tier2[tk2])
			if take <= 0:
				continue
			var tier: int = int(tk2)
			var have: int = int(map.get(tier, map.get(str(tier), 0)))
			var left: int = have - take
			map.erase(tier)
			map.erase(str(tier))
			if left > 0:
				map[tier] = left
		_set_sanctuary_tier_map(display2, map)
	_resync_sanctuary_totals()
	save_troops()
	training_updated.emit()
	return true


func _empty_tier_composition() -> Dictionary:
	return {"infantry": {}, "marksmen": {}, "cavalry": {}}


func _count_tier_composition(composition: Dictionary) -> int:
	var total: int = 0
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = composition.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			continue
		for tk: Variant in by_tier.keys():
			total += maxi(0, int(by_tier[tk]))
	return total


func _add_to_composition(dest: Dictionary, kind: String, tier: int, amount: int) -> void:
	if amount <= 0:
		return
	var by_tier: Dictionary = (dest.get(kind, {}) as Dictionary).duplicate(true)
	by_tier[str(tier)] = int(by_tier.get(str(tier), by_tier.get(tier, 0))) + amount
	dest[kind] = by_tier


## Canonical casualty routing (Phase 5).
## Hospital fills first (available = capacity − waiting − healing job).
## Overflow → Sanctuary (no capacity delete). Deterministic order:
## Infantry → Marksmen → Cavalry; lowest tier first within type.
## Returns { hospital, sanctuary, hospital_count, sanctuary_count, available_before }.
func route_wounded_by_tiers(casualty_tiers: Dictionary) -> Dictionary:
	var hospital_part: Dictionary = _empty_tier_composition()
	var sanctuary_part: Dictionary = _empty_tier_composition()
	var available: int = get_hospital_available_capacity()
	var available_before: int = available

	if typeof(casualty_tiers) != TYPE_DICTIONARY:
		return {
			"hospital": hospital_part,
			"sanctuary": sanctuary_part,
			"hospital_count": 0,
			"sanctuary_count": 0,
			"available_before": available_before,
		}

	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = casualty_tiers.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY or by_tier.is_empty():
			continue
		var tiers: Array = by_tier.keys()
		tiers.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
		for tk: Variant in tiers:
			var tier: int = int(tk)
			var qty: int = maxi(0, int(by_tier[tk]))
			if qty <= 0:
				continue
			var to_h: int = mini(qty, available)
			var to_s: int = qty - to_h
			_add_to_composition(hospital_part, kind, tier, to_h)
			_add_to_composition(sanctuary_part, kind, tier, to_s)
			available -= to_h

	var h_count: int = _count_tier_composition(hospital_part)
	var s_count: int = _count_tier_composition(sanctuary_part)
	if h_count > 0:
		add_wounded_by_tiers(hospital_part)
	if s_count > 0:
		add_sanctuary_by_tiers(sanctuary_part)
		if has_node("/root/SanctuaryState") and SanctuaryState.has_method("enqueue_recovery"):
			SanctuaryState.enqueue_recovery(sanctuary_part)

	return {
		"hospital": hospital_part,
		"sanctuary": sanctuary_part,
		"hospital_count": h_count,
		"sanctuary_count": s_count,
		"available_before": available_before,
	}


func deploy_troops(infantry_count: int, marksmen_count: int, cavalry_count: int) -> bool:
	if get_troop_count("Infantry") < infantry_count:
		return false
	if get_troop_count("Marksmen") < marksmen_count:
		return false
	if get_troop_count("Cavalry") < cavalry_count:
		return false
	_remove_any_tiers("Infantry", infantry_count)
	_remove_any_tiers("Marksmen", marksmen_count)
	_remove_any_tiers("Cavalry", cavalry_count)
	save_troops()
	training_updated.emit()
	return true


## Deploy exact tier composition.
## composition: { "infantry": {"1": 100, "2": 50}, "marksmen": {...}, "cavalry": {...} }
func deploy_troops_by_tiers(composition: Dictionary) -> bool:
	var types: Array[String] = ["infantry", "marksmen", "cavalry"]
	for kind: String in types:
		var by_tier: Dictionary = composition.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			by_tier = {}
		for tier_key: Variant in by_tier.keys():
			var need: int = int(by_tier[tier_key])
			if need <= 0:
				continue
			var display: String = kind.capitalize()
			if kind == "infantry":
				display = "Infantry"
			elif kind == "marksmen":
				display = "Marksmen"
			elif kind == "cavalry":
				display = "Cavalry"
			if get_tier_count(display, int(tier_key)) < need:
				return false
	for kind2: String in types:
		var by_tier2: Dictionary = composition.get(kind2, {}) as Dictionary
		if typeof(by_tier2) != TYPE_DICTIONARY:
			continue
		var display2: String = kind2.capitalize()
		if kind2 == "infantry":
			display2 = "Infantry"
		elif kind2 == "marksmen":
			display2 = "Marksmen"
		elif kind2 == "cavalry":
			display2 = "Cavalry"
		for tier_key2: Variant in by_tier2.keys():
			var take: int = int(by_tier2[tier_key2])
			if take <= 0:
				continue
			if not remove_tier_troops(display2, int(tier_key2), take):
				return false
	save_troops()
	training_updated.emit()
	return true


## Restore exact tier composition (gather marches).
func return_troops_by_tiers(composition: Dictionary) -> void:
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = composition.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			continue
		var display: String = kind.capitalize()
		if kind == "infantry":
			display = "Infantry"
		elif kind == "marksmen":
			display = "Marksmen"
		elif kind == "cavalry":
			display = "Cavalry"
		for tier_key: Variant in by_tier.keys():
			var amt: int = int(by_tier[tier_key])
			if amt > 0:
				add_tier_troops(display, int(tier_key), amt)
	save_troops()
	training_updated.emit()


func return_troops(infantry_count: int, marksmen_count: int, cavalry_count: int) -> void:
	_add_any("Infantry", maxi(0, infantry_count))
	_add_any("Marksmen", maxi(0, marksmen_count))
	_add_any("Cavalry", maxi(0, cavalry_count))
	save_troops()
	training_updated.emit()


func has_active_job(troop_type: String) -> bool:
	return is_training_active(troop_type) or is_training_ready(troop_type)


## Start training selected tier. Does not spend resources (caller spends first).
func start_training(troop_type: String, amount: int, duration_sec: int = -1, target_tier: int = 1) -> bool:
	var canon: String = _canon(troop_type)
	if amount <= 0 or target_tier <= 0:
		return false
	if has_active_job(canon):
		return false
	var time_needed: int = duration_sec if duration_sec >= 0 else amount * 2
	time_needed = maxi(1, time_needed)
	var now: int = int(Time.get_unix_time_from_system())
	_set_job(canon, "train", amount, target_tier, 0, now, now + time_needed)
	save_troops()
	training_updated.emit()
	if has_node("/root/GameEvents"):
		GameEvents.emit_troop_training_started(canon, target_tier, amount)
	return true


## Promote source→target. Reserves/removes source troops immediately.
func start_promotion(
	troop_type: String,
	amount: int,
	duration_sec: int,
	source_tier: int,
	target_tier: int
) -> bool:
	var canon: String = _canon(troop_type)
	if amount <= 0 or source_tier <= 0 or target_tier <= source_tier:
		return false
	if has_active_job(canon):
		return false
	if get_tier_count(canon, source_tier) < amount:
		return false
	if not remove_tier_troops(canon, source_tier, amount):
		return false
	var time_needed: int = maxi(1, duration_sec)
	var now: int = int(Time.get_unix_time_from_system())
	_set_job(canon, "promote", amount, target_tier, source_tier, now, now + time_needed)
	save_troops()
	training_updated.emit()
	if has_node("/root/GameEvents"):
		GameEvents.emit_troop_training_started(canon, target_tier, amount)
	return true


func _set_job(
	canon: String,
	job_type: String,
	amount: int,
	target_tier: int,
	source_tier: int,
	start_time: int,
	finish_time: int
) -> void:
	match canon:
		"Infantry":
			infantry_training_active = true
			infantry_training_ready = false
			infantry_training_amount = amount
			infantry_job_type = job_type
			infantry_target_tier = target_tier
			infantry_source_tier = source_tier
			infantry_training_start_time = start_time
			infantry_finish_time = finish_time
		"Marksmen":
			marksmen_training_active = true
			marksmen_training_ready = false
			marksmen_training_amount = amount
			marksmen_job_type = job_type
			marksmen_target_tier = target_tier
			marksmen_source_tier = source_tier
			marksmen_training_start_time = start_time
			marksmen_finish_time = finish_time
		"Cavalry":
			cavalry_training_active = true
			cavalry_training_ready = false
			cavalry_training_amount = amount
			cavalry_job_type = job_type
			cavalry_target_tier = target_tier
			cavalry_source_tier = source_tier
			cavalry_training_start_time = start_time
			cavalry_finish_time = finish_time


func check_finished_training() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var changed: bool = false
	if infantry_training_active and now >= infantry_finish_time:
		infantry_training_active = false
		infantry_training_ready = true
		changed = true
	if marksmen_training_active and now >= marksmen_finish_time:
		marksmen_training_active = false
		marksmen_training_ready = true
		changed = true
	if cavalry_training_active and now >= cavalry_finish_time:
		cavalry_training_active = false
		cavalry_training_ready = true
		changed = true
	if changed:
		save_troops()
		training_updated.emit()


func collect_training(troop_type: String) -> bool:
	var canon: String = _canon(troop_type)
	if not is_training_ready(canon):
		return false
	var amount: int = get_training_amount(canon)
	var target_tier: int = get_job_target_tier(canon)
	var job_type: String = get_job_type(canon)
	if amount <= 0 or target_tier <= 0:
		_clear_job(canon)
		save_troops()
		training_updated.emit()
		return false

	add_tier_troops(canon, target_tier, amount)
	_clear_job(canon)
	save_troops()
	training_updated.emit()

	# Awarded on collect (troops actually granted) — not when timer merely ends.
	if has_node("/root/GameEvents") and job_type == "train":
		GameEvents.emit_troop_training_completed(canon, target_tier, amount)
	return true


func _clear_job(canon: String) -> void:
	match canon:
		"Infantry":
			infantry_training_amount = 0
			infantry_finish_time = 0
			infantry_training_start_time = 0
			infantry_training_ready = false
			infantry_training_active = false
			infantry_job_type = ""
			infantry_target_tier = 1
			infantry_source_tier = 0
		"Marksmen":
			marksmen_training_amount = 0
			marksmen_finish_time = 0
			marksmen_training_start_time = 0
			marksmen_training_ready = false
			marksmen_training_active = false
			marksmen_job_type = ""
			marksmen_target_tier = 1
			marksmen_source_tier = 0
		"Cavalry":
			cavalry_training_amount = 0
			cavalry_finish_time = 0
			cavalry_training_start_time = 0
			cavalry_training_ready = false
			cavalry_training_active = false
			cavalry_job_type = ""
			cavalry_target_tier = 1
			cavalry_source_tier = 0


func speedup_training(troop_type: String, seconds: int) -> void:
	var canon: String = _canon(troop_type)
	if not is_training_active(canon):
		return
	match canon:
		"Infantry":
			infantry_finish_time = maxi(int(Time.get_unix_time_from_system()), infantry_finish_time - seconds)
		"Marksmen":
			marksmen_finish_time = maxi(int(Time.get_unix_time_from_system()), marksmen_finish_time - seconds)
		"Cavalry":
			cavalry_finish_time = maxi(int(Time.get_unix_time_from_system()), cavalry_finish_time - seconds)
	save_troops()
	check_finished_training()
	training_updated.emit()


func is_training_active(troop_type: String) -> bool:
	match _canon(troop_type):
		"Infantry":
			return infantry_training_active
		"Marksmen":
			return marksmen_training_active
		"Cavalry":
			return cavalry_training_active
		_:
			return false


func is_training_ready(troop_type: String) -> bool:
	match _canon(troop_type):
		"Infantry":
			return infantry_training_ready
		"Marksmen":
			return marksmen_training_ready
		"Cavalry":
			return cavalry_training_ready
		_:
			return false


func get_training_amount(troop_type: String) -> int:
	match _canon(troop_type):
		"Infantry":
			return infantry_training_amount
		"Marksmen":
			return marksmen_training_amount
		"Cavalry":
			return cavalry_training_amount
		_:
			return 0


func get_training_start_time(troop_type: String) -> int:
	match _canon(troop_type):
		"Infantry":
			return infantry_training_start_time
		"Marksmen":
			return marksmen_training_start_time
		"Cavalry":
			return cavalry_training_start_time
		_:
			return 0


func get_training_finish_time(troop_type: String) -> int:
	match _canon(troop_type):
		"Infantry":
			return infantry_finish_time
		"Marksmen":
			return marksmen_finish_time
		"Cavalry":
			return cavalry_finish_time
		_:
			return 0


func get_job_type(troop_type: String) -> String:
	match _canon(troop_type):
		"Infantry":
			return infantry_job_type
		"Marksmen":
			return marksmen_job_type
		"Cavalry":
			return cavalry_job_type
		_:
			return ""


func get_job_target_tier(troop_type: String) -> int:
	match _canon(troop_type):
		"Infantry":
			return infantry_target_tier
		"Marksmen":
			return marksmen_target_tier
		"Cavalry":
			return cavalry_target_tier
		_:
			return 1


func get_job_source_tier(troop_type: String) -> int:
	match _canon(troop_type):
		"Infantry":
			return infantry_source_tier
		"Marksmen":
			return marksmen_source_tier
		"Cavalry":
			return cavalry_source_tier
		_:
			return 0


func get_training_time_left(troop_type: String) -> float:
	var now: int = int(Time.get_unix_time_from_system())
	return maxf(0.0, float(get_training_finish_time(troop_type) - now))


func building_id_for_troop_type(troop_type: String) -> String:
	match _canon(troop_type):
		"Infantry":
			return "infantry_barracks"
		"Marksmen":
			return "marksmen_camp"
		"Cavalry":
			return "cavalry_stable"
		_:
			return ""


func get_training_job(troop_type: String) -> Dictionary:
	var canon: String = _canon(troop_type)
	var active: bool = is_training_active(canon)
	var ready: bool = is_training_ready(canon)
	if not active and not ready:
		return {}
	return {
		"troop_type": canon,
		"job_type": get_job_type(canon),
		"quantity": get_training_amount(canon),
		"source_tier": get_job_source_tier(canon),
		"target_tier": get_job_target_tier(canon),
		"start_time": get_training_start_time(canon),
		"finish_time": get_training_finish_time(canon),
		"remaining_sec": int(get_training_time_left(canon)) if active else 0,
		"active": active,
		"ready": ready,
		"building_id": building_id_for_troop_type(canon),
	}


func get_all_training_jobs() -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	for troop_type: String in ["Infantry", "Marksmen", "Cavalry"]:
		var job: Dictionary = get_training_job(troop_type)
		if not job.is_empty():
			jobs.append(job)
	return jobs


func _serialize_tier_map(map: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in map.keys():
		var count: int = int(map[key])
		if count > 0:
			out[str(int(key))] = count
	return out


func _deserialize_tier_map(raw: Variant, legacy_total: int) -> Dictionary:
	var out: Dictionary = {}
	if typeof(raw) == TYPE_DICTIONARY:
		for key: Variant in (raw as Dictionary).keys():
			var count: int = int((raw as Dictionary)[key])
			if count > 0:
				out[int(key)] = count
	if out.is_empty() and legacy_total > 0:
		out[1] = legacy_total
	return out


func save_troops() -> void:
	_resync_totals()
	var save: ConfigFile = ConfigFile.new()

	save.set_value("troops", "infantry", infantry)
	save.set_value("troops", "marksmen", marksmen)
	save.set_value("troops", "cavalry", cavalry)
	save.set_value("troops", "infantry_by_tier", _serialize_tier_map(infantry_by_tier))
	save.set_value("troops", "marksmen_by_tier", _serialize_tier_map(marksmen_by_tier))
	save.set_value("troops", "cavalry_by_tier", _serialize_tier_map(cavalry_by_tier))
	_resync_wounded_totals()
	save.set_value("troops", "wounded_infantry", wounded_infantry)
	save.set_value("troops", "wounded_marksmen", wounded_marksmen)
	save.set_value("troops", "wounded_cavalry", wounded_cavalry)
	save.set_value("troops", "wounded_infantry_by_tier", _serialize_tier_map(wounded_infantry_by_tier))
	save.set_value("troops", "wounded_marksmen_by_tier", _serialize_tier_map(wounded_marksmen_by_tier))
	save.set_value("troops", "wounded_cavalry_by_tier", _serialize_tier_map(wounded_cavalry_by_tier))
	_resync_sanctuary_totals()
	save.set_value("troops", "sanctuary_troops", sanctuary_troops)
	save.set_value("troops", "sanctuary_infantry_by_tier", _serialize_tier_map(sanctuary_infantry_by_tier))
	save.set_value("troops", "sanctuary_marksmen_by_tier", _serialize_tier_map(sanctuary_marksmen_by_tier))
	save.set_value("troops", "sanctuary_cavalry_by_tier", _serialize_tier_map(sanctuary_cavalry_by_tier))

	save.set_value("training", "infantry_active", infantry_training_active)
	save.set_value("training", "marksmen_active", marksmen_training_active)
	save.set_value("training", "cavalry_active", cavalry_training_active)

	save.set_value("training", "infantry_ready", infantry_training_ready)
	save.set_value("training", "marksmen_ready", marksmen_training_ready)
	save.set_value("training", "cavalry_ready", cavalry_training_ready)

	save.set_value("training", "infantry_amount", infantry_training_amount)
	save.set_value("training", "marksmen_amount", marksmen_training_amount)
	save.set_value("training", "cavalry_amount", cavalry_training_amount)

	save.set_value("training", "infantry_finish_time", infantry_finish_time)
	save.set_value("training", "marksmen_finish_time", marksmen_finish_time)
	save.set_value("training", "cavalry_finish_time", cavalry_finish_time)

	save.set_value("training", "infantry_start_time", infantry_training_start_time)
	save.set_value("training", "marksmen_start_time", marksmen_training_start_time)
	save.set_value("training", "cavalry_start_time", cavalry_training_start_time)

	save.set_value("training", "infantry_job_type", infantry_job_type)
	save.set_value("training", "marksmen_job_type", marksmen_job_type)
	save.set_value("training", "cavalry_job_type", cavalry_job_type)

	save.set_value("training", "infantry_target_tier", infantry_target_tier)
	save.set_value("training", "marksmen_target_tier", marksmen_target_tier)
	save.set_value("training", "cavalry_target_tier", cavalry_target_tier)

	save.set_value("training", "infantry_source_tier", infantry_source_tier)
	save.set_value("training", "marksmen_source_tier", marksmen_source_tier)
	save.set_value("training", "cavalry_source_tier", cavalry_source_tier)

	save.save("user://troops.cfg")


func load_troops() -> void:
	var save: ConfigFile = ConfigFile.new()
	if save.load("user://troops.cfg") != OK:
		return

	var legacy_inf: int = int(save.get_value("troops", "infantry", 0))
	var legacy_mar: int = int(save.get_value("troops", "marksmen", 0))
	var legacy_cav: int = int(save.get_value("troops", "cavalry", 0))

	infantry_by_tier = _deserialize_tier_map(save.get_value("troops", "infantry_by_tier", {}), legacy_inf)
	marksmen_by_tier = _deserialize_tier_map(save.get_value("troops", "marksmen_by_tier", {}), legacy_mar)
	cavalry_by_tier = _deserialize_tier_map(save.get_value("troops", "cavalry_by_tier", {}), legacy_cav)
	_resync_totals()

	var legacy_w_inf: int = int(save.get_value("troops", "wounded_infantry", 0))
	var legacy_w_mar: int = int(save.get_value("troops", "wounded_marksmen", 0))
	var legacy_w_cav: int = int(save.get_value("troops", "wounded_cavalry", 0))
	wounded_infantry_by_tier = _deserialize_tier_map(
		save.get_value("troops", "wounded_infantry_by_tier", {}), legacy_w_inf
	)
	wounded_marksmen_by_tier = _deserialize_tier_map(
		save.get_value("troops", "wounded_marksmen_by_tier", {}), legacy_w_mar
	)
	wounded_cavalry_by_tier = _deserialize_tier_map(
		save.get_value("troops", "wounded_cavalry_by_tier", {}), legacy_w_cav
	)
	_resync_wounded_totals()

	var legacy_sanct: int = int(save.get_value("troops", "sanctuary_troops", 0))
	sanctuary_infantry_by_tier = _deserialize_tier_map(
		save.get_value("troops", "sanctuary_infantry_by_tier", {}), 0
	)
	sanctuary_marksmen_by_tier = _deserialize_tier_map(
		save.get_value("troops", "sanctuary_marksmen_by_tier", {}), 0
	)
	sanctuary_cavalry_by_tier = _deserialize_tier_map(
		save.get_value("troops", "sanctuary_cavalry_by_tier", {}), 0
	)
	_resync_sanctuary_totals()
	# Legacy flat-only sanctuary: keep count visible but do not invent tier splits.
	if sanctuary_troops == 0 and legacy_sanct > 0:
		sanctuary_troops = legacy_sanct

	infantry_training_active = bool(save.get_value("training", "infantry_active", false))
	marksmen_training_active = bool(save.get_value("training", "marksmen_active", false))
	cavalry_training_active = bool(save.get_value("training", "cavalry_active", false))

	infantry_training_ready = bool(save.get_value("training", "infantry_ready", false))
	marksmen_training_ready = bool(save.get_value("training", "marksmen_ready", false))
	cavalry_training_ready = bool(save.get_value("training", "cavalry_ready", false))

	infantry_training_amount = int(save.get_value("training", "infantry_amount", 0))
	marksmen_training_amount = int(save.get_value("training", "marksmen_amount", 0))
	cavalry_training_amount = int(save.get_value("training", "cavalry_amount", 0))

	infantry_finish_time = int(save.get_value("training", "infantry_finish_time", 0))
	marksmen_finish_time = int(save.get_value("training", "marksmen_finish_time", 0))
	cavalry_finish_time = int(save.get_value("training", "cavalry_finish_time", 0))

	infantry_training_start_time = int(save.get_value("training", "infantry_start_time", 0))
	marksmen_training_start_time = int(save.get_value("training", "marksmen_start_time", 0))
	cavalry_training_start_time = int(save.get_value("training", "cavalry_start_time", 0))

	infantry_job_type = str(save.get_value("training", "infantry_job_type", "train" if infantry_training_active or infantry_training_ready else ""))
	marksmen_job_type = str(save.get_value("training", "marksmen_job_type", "train" if marksmen_training_active or marksmen_training_ready else ""))
	cavalry_job_type = str(save.get_value("training", "cavalry_job_type", "train" if cavalry_training_active or cavalry_training_ready else ""))

	infantry_target_tier = int(save.get_value("training", "infantry_target_tier", 1))
	marksmen_target_tier = int(save.get_value("training", "marksmen_target_tier", 1))
	cavalry_target_tier = int(save.get_value("training", "cavalry_target_tier", 1))

	infantry_source_tier = int(save.get_value("training", "infantry_source_tier", 0))
	marksmen_source_tier = int(save.get_value("training", "marksmen_source_tier", 0))
	cavalry_source_tier = int(save.get_value("training", "cavalry_source_tier", 0))
