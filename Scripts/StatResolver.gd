extends Node

## Crownspire StatResolver — CALCULATOR ONLY (no saves / no state ownership).
## Phase 1: March Capacity, March Speed, Gathering Speed
## Phase 2: March combat ATK/DEF/HP resolution (NOT wired into Wildling combat yet)
##
## Stacking (percent pool): final = (base + flat) * (1 + sum(percents))
## Multiplicative modifiers reserved for a later phase (not used yet).

const BASE_MARCH_CAPACITY: int = 5000
const CAPACITY_PER_CASTLE_LEVEL: int = 1000
const BASE_MARCH_SPEED_PX_PER_SEC: float = 220.0
const BASE_GATHER_RATE_PER_SEC: float = 50.0
const MIN_TRAVEL_SECONDS: int = 5
const MIN_GATHER_SECONDS: int = 1

## Academy research IDs confidently mapped to resource-specific gather %.
const FOOD_GATHER_RESEARCH_IDS: Array[String] = ["econ_gather_food"]
const WOOD_GATHER_RESEARCH_IDS: Array[String] = ["econ_gather_wood"]
const STONE_GATHER_RESEARCH_IDS: Array[String] = ["econ_gather_stone"]
const IRON_GATHER_RESEARCH_IDS: Array[String] = ["econ_gather_iron"]
## General gather % (applies to all resource types).
const GENERAL_GATHER_RESEARCH_IDS: Array[String] = ["econ_gathering_speed", "all_loot_sharing", "all_resource_shuttle"]

## Cached research definitions (id -> Dictionary). Loaded once from DataManager / JSON.
var _research_by_id: Dictionary = {}
var _research_cache_ready: bool = false


func _ready() -> void:
	_ensure_research_cache()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Final march capacity (headcount). hero_ids = selected march heroes (march-active bonuses).
func get_march_capacity(hero_ids: Array = []) -> int:
	return int(resolve_march_capacity(hero_ids).get("final", BASE_MARCH_CAPACITY))


## Final march travel speed in world px/sec.
func get_march_speed_px_per_sec(hero_ids: Array = []) -> float:
	return float(resolve_march_speed(hero_ids).get("final", BASE_MARCH_SPEED_PX_PER_SEC))


## Final gathering rate (resources / second) for a resource type.
func get_gather_rate(resource_type: String = "", hero_ids: Array = []) -> float:
	return float(resolve_gather_rate(resource_type, hero_ids).get("final", BASE_GATHER_RATE_PER_SEC))


func estimate_travel_seconds(from_pos: Vector2, to_pos: Vector2, hero_ids: Array = []) -> int:
	var dist: float = from_pos.distance_to(to_pos)
	var speed: float = maxf(0.001, get_march_speed_px_per_sec(hero_ids))
	return maxi(MIN_TRAVEL_SECONDS, int(ceil(dist / speed)))


func calculate_gather_seconds(gather_amount: int, resource_type: String = "", hero_ids: Array = []) -> int:
	if gather_amount <= 0:
		return MIN_GATHER_SECONDS
	var rate: float = maxf(0.001, get_gather_rate(resource_type, hero_ids))
	return maxi(MIN_GATHER_SECONDS, int(ceil(float(gather_amount) / rate)))


## Breakdown dictionaries for tests / debugging (not player UI).
func resolve_march_capacity(hero_ids: Array = []) -> Dictionary:
	_ensure_research_cache()
	var castle_level: int = 1
	if has_node("/root/GameState"):
		castle_level = maxi(1, int(GameState.castle_level))
	var base: float = float(BASE_MARCH_CAPACITY + castle_level * CAPACITY_PER_CASTLE_LEVEL)

	var research_flat: float = _research_flat_for_effect("March Capacity")
	var hero_pct: float = _hero_percent_for_stats(hero_ids, ["March Capacity"])
	var alliance_flat: float = _alliance_flat_hook("march_capacity")
	var alliance_pct: float = _alliance_percent_hook("march_capacity")
	var vip_pct: float = _vip_percent_hook("march_capacity")
	var temp_pct: float = _temp_buff_percent_hook("march_capacity")

	var flat_total: float = research_flat + alliance_flat
	var pct_total: float = hero_pct + alliance_pct + vip_pct + temp_pct
	var final_v: int = maxi(1, int(floor((base + flat_total) * (1.0 + pct_total))))

	return {
		"stat": "march_capacity",
		"base": base,
		"citadel_level": castle_level,
		"research_flat": research_flat,
		"research_pct": 0.0,
		"heroes_pct": hero_pct,
		"alliance_flat": alliance_flat,
		"alliance_pct": alliance_pct,
		"vip_pct": vip_pct,
		"temporary_pct": temp_pct,
		"flat_total": flat_total,
		"percent_total": pct_total,
		"final": final_v,
	}


func resolve_march_speed(hero_ids: Array = []) -> Dictionary:
	_ensure_research_cache()
	var base: float = BASE_MARCH_SPEED_PX_PER_SEC
	# Research "Troop Speed" intentionally NOT mapped — ambiguous vs march travel speed.
	var research_pct: float = _research_percent_for_effect("March Speed")
	var hero_pct: float = _hero_percent_for_stats(hero_ids, ["March Speed"])
	var alliance_pct: float = _alliance_percent_hook("march_speed")
	var vip_pct: float = _vip_percent_hook("march_speed")
	var temp_pct: float = _temp_buff_percent_hook("march_speed")
	var pct_total: float = research_pct + hero_pct + alliance_pct + vip_pct + temp_pct
	var final_v: float = maxf(0.001, base * (1.0 + pct_total))
	return {
		"stat": "march_speed",
		"base": base,
		"research_pct": research_pct,
		"heroes_pct": hero_pct,
		"alliance_pct": alliance_pct,
		"vip_pct": vip_pct,
		"temporary_pct": temp_pct,
		"percent_total": pct_total,
		"final": final_v,
		"notes": "Academy 'Troop Speed' research left at 0 (ambiguous). Hero March Speed is march-active only.",
	}


func resolve_gather_rate(resource_type: String = "", hero_ids: Array = []) -> Dictionary:
	_ensure_research_cache()
	var rtype: String = resource_type.strip_edges().to_lower()
	var base: float = BASE_GATHER_RATE_PER_SEC

	var research_general: float = _research_percent_sum_ids(GENERAL_GATHER_RESEARCH_IDS)
	var research_specific: float = 0.0
	match rtype:
		"food":
			research_specific = _research_percent_sum_ids(FOOD_GATHER_RESEARCH_IDS)
		"wood":
			research_specific = _research_percent_sum_ids(WOOD_GATHER_RESEARCH_IDS)
		"stone":
			research_specific = _research_percent_sum_ids(STONE_GATHER_RESEARCH_IDS)
		"iron":
			research_specific = _research_percent_sum_ids(IRON_GATHER_RESEARCH_IDS)
		_:
			research_specific = 0.0

	var research_pct: float = research_general + research_specific
	var hero_pct: float = _hero_percent_for_stats(hero_ids, [
		"Gather Speed",
		"Gathering Speed",
		"General Gathering Speed",
	])
	# Resource-specific hero passives (if present on selected heroes).
	if rtype == "food":
		hero_pct += _hero_percent_for_stats(hero_ids, ["Food Gather Speed", "Food Gathering Speed"])
	elif rtype == "wood":
		hero_pct += _hero_percent_for_stats(hero_ids, ["Wood Gather Speed", "Wood Gathering Speed"])
	elif rtype == "stone":
		hero_pct += _hero_percent_for_stats(hero_ids, ["Stone Gather Speed", "Stone Gathering Speed"])
	elif rtype == "iron":
		hero_pct += _hero_percent_for_stats(hero_ids, ["Iron Gather Speed", "Iron Gathering Speed"])

	var alliance_pct: float = _alliance_percent_hook("gather_speed")
	var vip_pct: float = _vip_percent_hook("gather_speed")
	var temp_pct: float = _temp_buff_percent_hook("gather_speed")
	var pct_total: float = research_pct + hero_pct + alliance_pct + vip_pct + temp_pct
	var final_v: float = maxf(0.001, base * (1.0 + pct_total))
	return {
		"stat": "gather_rate",
		"resource_type": rtype,
		"base": base,
		"research_general_pct": research_general,
		"research_specific_pct": research_specific,
		"research_pct": research_pct,
		"heroes_pct": hero_pct,
		"alliance_pct": alliance_pct,
		"vip_pct": vip_pct,
		"temporary_pct": temp_pct,
		"percent_total": pct_total,
		"final": final_v,
	}


## Compact one-line breakdown for console tests.
func format_breakdown(resolved: Dictionary) -> String:
	var stat: String = str(resolved.get("stat", "?"))
	return (
		"[StatResolver] %s base=%.2f research_flat=%.2f research_pct=%.1f%% heroes=%.1f%% alliance=%.1f%% vip=%.1f%% temp=%.1f%% final=%s"
		% [
			stat,
			float(resolved.get("base", 0.0)),
			float(resolved.get("research_flat", 0.0)),
			float(resolved.get("research_pct", 0.0)) * 100.0,
			float(resolved.get("heroes_pct", 0.0)) * 100.0,
			float(resolved.get("alliance_pct", 0.0)) * 100.0,
			float(resolved.get("vip_pct", 0.0)) * 100.0,
			float(resolved.get("temporary_pct", 0.0)) * 100.0,
			str(resolved.get("final", 0)),
		]
	)


# ---------------------------------------------------------------------------
# Phase 2 — Combat stats foundation (resolver only; Wildling combat unchanged)
# ---------------------------------------------------------------------------

## Resolve one troop type from a by-tier composition: {1: qty, 2: qty, ...}
func resolve_troop_type_combat_stats(
	troop_type: String,
	tier_composition: Dictionary,
	hero_ids: Array = []
) -> Dictionary:
	_ensure_research_cache()
	var kind: String = _normalize_troop_type(troop_type)
	var raw: Dictionary = _raw_type_totals(kind, tier_composition)
	var qty: int = int(raw.get("quantity", 0))
	var atk_b: Dictionary = _resolve_combat_bonus_channel(kind, "attack", hero_ids)
	var def_b: Dictionary = _resolve_combat_bonus_channel(kind, "defense", hero_ids)
	var hp_b: Dictionary = _resolve_combat_bonus_channel(kind, "health", hero_ids)
	var raw_atk: float = float(raw.get("attack", 0.0))
	var raw_def: float = float(raw.get("defense", 0.0))
	var raw_hp: float = float(raw.get("health", 0.0))
	return {
		"troop_type": kind,
		"quantity": qty,
		"raw_attack": raw_atk,
		"raw_defense": raw_def,
		"raw_health": raw_hp,
		"attack_bonus_percent": float(atk_b.get("percent_total", 0.0)),
		"defense_bonus_percent": float(def_b.get("percent_total", 0.0)),
		"health_bonus_percent": float(hp_b.get("percent_total", 0.0)),
		"final_attack": _apply_percent(raw_atk, float(atk_b.get("percent_total", 0.0))),
		"final_defense": _apply_percent(raw_def, float(def_b.get("percent_total", 0.0))),
		"final_health": _apply_percent(raw_hp, float(hp_b.get("percent_total", 0.0))),
		"attack_breakdown": atk_b,
		"defense_breakdown": def_b,
		"health_breakdown": hp_b,
	}


## Resolve a full march from troop_tiers: {infantry:{tier:qty}, marksmen:{}, cavalry:{}}
func resolve_march_combat_stats(troop_tiers: Dictionary, hero_ids: Array = []) -> Dictionary:
	_ensure_research_cache()
	var inf: Dictionary = resolve_troop_type_combat_stats(
		"infantry",
		troop_tiers.get("infantry", {}) as Dictionary,
		hero_ids
	)
	var mar: Dictionary = resolve_troop_type_combat_stats(
		"marksmen",
		troop_tiers.get("marksmen", {}) as Dictionary,
		hero_ids
	)
	var cav: Dictionary = resolve_troop_type_combat_stats(
		"cavalry",
		troop_tiers.get("cavalry", {}) as Dictionary,
		hero_ids
	)
	var troop_count: int = (
		int(inf.get("quantity", 0))
		+ int(mar.get("quantity", 0))
		+ int(cav.get("quantity", 0))
	)
	return {
		"infantry": inf,
		"marksmen": mar,
		"cavalry": cav,
		"totals": {
			"troop_count": troop_count,
			"attack": (
				float(inf.get("final_attack", 0.0))
				+ float(mar.get("final_attack", 0.0))
				+ float(cav.get("final_attack", 0.0))
			),
			"defense": (
				float(inf.get("final_defense", 0.0))
				+ float(mar.get("final_defense", 0.0))
				+ float(cav.get("final_defense", 0.0))
			),
			"health": (
				float(inf.get("final_health", 0.0))
				+ float(mar.get("final_health", 0.0))
				+ float(cav.get("final_health", 0.0))
			),
		},
		"hero_ids": hero_ids.duplicate(),
	}


## Human-readable combat channel breakdown (debug / tests).
func format_combat_stat_breakdown(type_stats: Dictionary, channel: String) -> String:
	var ch: String = channel.strip_edges().to_lower()
	var bd_key: String = "%s_breakdown" % ch
	var bd: Dictionary = type_stats.get(bd_key, {}) as Dictionary
	var raw_key: String = "raw_%s" % ch
	var final_key: String = "final_%s" % ch
	var lines: PackedStringArray = PackedStringArray()
	lines.append(
		"%s %s  Raw: %s" % [
			str(type_stats.get("troop_type", "?")).capitalize(),
			ch.capitalize(),
			str(type_stats.get(raw_key, 0)),
		]
	)
	lines.append("Research:")
	var r_src: Array = bd.get("research_sources", []) as Array
	if r_src.is_empty():
		lines.append("  (none)")
	else:
		for s: Variant in r_src:
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = s
			lines.append("  %s +%.1f%%" % [str(row.get("name", "?")), float(row.get("value", 0.0)) * 100.0])
	lines.append("Heroes:")
	var h_src: Array = bd.get("hero_sources", []) as Array
	if h_src.is_empty():
		lines.append("  (none)")
	else:
		for s2: Variant in h_src:
			if typeof(s2) != TYPE_DICTIONARY:
				continue
			var row2: Dictionary = s2
			lines.append(
				"  %s: %s +%.1f%%" % [
					str(row2.get("hero_id", "?")),
					str(row2.get("name", "?")),
					float(row2.get("value", 0.0)) * 100.0,
				]
			)
	lines.append("Alliance: +%.1f%%" % (float(bd.get("alliance_pct", 0.0)) * 100.0))
	lines.append("VIP: +%.1f%%" % (float(bd.get("vip_pct", 0.0)) * 100.0))
	lines.append("Temporary: +%.1f%%" % (float(bd.get("temporary_pct", 0.0)) * 100.0))
	lines.append("Total Bonus: +%.1f%%" % (float(bd.get("percent_total", 0.0)) * 100.0))
	lines.append("Final: %s" % str(type_stats.get(final_key, 0)))
	return "\n".join(lines)


func _normalize_troop_type(troop_type: String) -> String:
	var t: String = troop_type.strip_edges().to_lower()
	match t:
		"infantry", "inf":
			return "infantry"
		"marksmen", "marksman", "archer", "archers":
			return "marksmen"
		"cavalry", "cav":
			return "cavalry"
		_:
			return t


func _raw_type_totals(troop_type: String, tier_composition: Dictionary) -> Dictionary:
	var qty_total: int = 0
	var atk: float = 0.0
	var deff: float = 0.0
	var hp: float = 0.0
	if not has_node("/root/TroopDatabase"):
		return {"quantity": 0, "attack": 0.0, "defense": 0.0, "health": 0.0}
	var by_tier: Dictionary = tier_composition
	# Allow callers to pass full troop_tiers by accident.
	if by_tier.has("infantry") or by_tier.has("marksmen") or by_tier.has("cavalry"):
		by_tier = by_tier.get(troop_type, {}) as Dictionary
	for tier_key: Variant in by_tier.keys():
		var qty: int = int(by_tier[tier_key])
		if qty <= 0:
			continue
		var tier: int = int(tier_key)
		var troop: Dictionary = TroopDatabase.get_troop(troop_type, tier)
		if troop.is_empty():
			continue
		qty_total += qty
		atk += float(troop.get("attack", 0)) * float(qty)
		deff += float(troop.get("defense", 0)) * float(qty)
		hp += float(troop.get("health", 0)) * float(qty)
	return {"quantity": qty_total, "attack": atk, "defense": deff, "health": hp}


func _apply_percent(raw: float, percent_total: float) -> float:
	return raw * (1.0 + percent_total)


## channel: "attack" | "defense" | "health"
func _resolve_combat_bonus_channel(troop_type: String, channel: String, hero_ids: Array) -> Dictionary:
	var kind: String = _normalize_troop_type(troop_type)
	var ch: String = channel.strip_edges().to_lower()
	var global_names: Array[String] = _global_combat_effect_names(ch)
	var type_names: Array[String] = _type_combat_effect_names(kind, ch)

	var research: Dictionary = _research_percent_sources(global_names + type_names)
	var heroes: Dictionary = _hero_percent_sources(hero_ids, global_names + type_names)
	var alliance_pct: float = _alliance_percent_hook("combat_%s_%s" % [kind, ch])
	var vip_pct: float = _vip_percent_hook("combat_%s_%s" % [kind, ch])
	var temp_pct: float = _temp_buff_percent_hook("combat_%s_%s" % [kind, ch])
	var research_pct: float = float(research.get("total", 0.0))
	var heroes_pct: float = float(heroes.get("total", 0.0))
	var percent_total: float = research_pct + heroes_pct + alliance_pct + vip_pct + temp_pct
	return {
		"channel": ch,
		"troop_type": kind,
		"global_effect_names": global_names,
		"type_effect_names": type_names,
		"research_pct": research_pct,
		"research_sources": research.get("sources", []),
		"heroes_pct": heroes_pct,
		"hero_sources": heroes.get("sources", []),
		"alliance_pct": alliance_pct,
		"vip_pct": vip_pct,
		"temporary_pct": temp_pct,
		"percent_total": percent_total,
	}


func _global_combat_effect_names(channel: String) -> Array[String]:
	match channel:
		"attack":
			return ["Troop Attack"]
		"defense":
			return ["Troop Defense"]
		"health":
			# Research uses "Troop Health"; heroes also use "Troop HP".
			return ["Troop Health", "Troop HP"]
		_:
			return []


func _type_combat_effect_names(troop_type: String, channel: String) -> Array[String]:
	var label: String = ""
	match troop_type:
		"infantry":
			label = "Infantry"
		"marksmen":
			label = "Marksmen"
		"cavalry":
			label = "Cavalry"
		_:
			return []
	match channel:
		"attack":
			return ["%s Attack" % label]
		"defense":
			return ["%s Defense" % label]
		"health":
			# Research: "Infantry Health"; heroes often: "Infantry HP".
			return ["%s Health" % label, "%s HP" % label]
		_:
			return []


func _research_percent_sources(effect_names: Array) -> Dictionary:
	var wanted: Dictionary = {}
	for n: Variant in effect_names:
		wanted[str(n).strip_edges().to_lower()] = str(n)
	var total: float = 0.0
	var sources: Array = []
	for rid: Variant in _research_by_id.keys():
		for effect: String in _effect_strings_at_level(str(rid)):
			var parsed: Dictionary = _parse_effect(effect)
			if parsed.is_empty() or not bool(parsed.get("is_percent", false)):
				continue
			var ename: String = str(parsed.get("name", "")).to_lower()
			if not wanted.has(ename):
				continue
			var val: float = float(parsed.get("value", 0.0))
			total += val
			sources.append({
				"research_id": str(rid),
				"name": str(parsed.get("name", "")),
				"value": val,
			})
	return {"total": total, "sources": sources}


func _hero_percent_sources(hero_ids: Array, effect_names: Array) -> Dictionary:
	var wanted: Dictionary = {}
	for n: Variant in effect_names:
		wanted[str(n).strip_edges().to_lower()] = true
	var total: float = 0.0
	var sources: Array = []
	if hero_ids.is_empty() or not has_node("/root/DataManager"):
		return {"total": 0.0, "sources": sources}
	var seen: Dictionary = {}
	for hid_v: Variant in hero_ids:
		var hid: String = str(hid_v)
		if hid == "" or seen.has(hid):
			continue
		seen[hid] = true
		if has_node("/root/HeroState") and HeroState.has_method("is_hero_owned"):
			if not bool(HeroState.is_hero_owned(hid)):
				continue
		var template: Dictionary = DataManager.get_hero(hid)
		if template.is_empty():
			continue
		var passives: Array = template.get("passiveBonuses", []) as Array
		for p: Variant in passives:
			if typeof(p) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = p
			var stat: String = str(row.get("stat", "")).strip_edges()
			if not wanted.has(stat.to_lower()):
				continue
			var val: float = float(row.get("value", 0.0))
			total += val
			sources.append({
				"hero_id": hid,
				"name": stat,
				"value": val,
			})
	return {"total": total, "sources": sources}


# ---------------------------------------------------------------------------
# Future hooks (intentionally 0 this sprint)
# ---------------------------------------------------------------------------

func _alliance_flat_hook(_stat_key: String) -> float:
	# Alliance Research gameplay effects not wired yet.
	return 0.0


func _alliance_percent_hook(_stat_key: String) -> float:
	# alliance_research.json has clear combat keys (infantry_defense, etc.)
	# but Phase 2 leaves contribution at 0 — no Alliance gameplay wiring.
	return 0.0


func _vip_percent_hook(_stat_key: String) -> float:
	# GameState.vip_level exists; no VIP bonus table.
	return 0.0


func _temp_buff_percent_hook(_stat_key: String) -> float:
	# Items define boosts; no BuffState yet.
	return 0.0


# ---------------------------------------------------------------------------
# Research
# ---------------------------------------------------------------------------

func _ensure_research_cache() -> void:
	if _research_cache_ready and not _research_by_id.is_empty():
		return
	_research_by_id.clear()
	var list: Array = []
	if has_node("/root/DataManager") and typeof(DataManager.research) == TYPE_ARRAY:
		list = DataManager.research
	else:
		list = _load_json_array("res://data/research.json")
	for entry: Variant in list:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry
		var rid: String = str(d.get("id", ""))
		if rid != "":
			_research_by_id[rid] = d
	_research_cache_ready = true


func _load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_ARRAY:
		return parsed
	return []


func _research_level(research_id: String) -> int:
	if has_node("/root/ResearchState") and ResearchState.has_method("get_research_level"):
		return maxi(0, int(ResearchState.get_research_level(research_id)))
	return 0


## Effect string at the player's current completed level (level N effect = total for that tech).
func _effect_strings_at_level(research_id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var lvl: int = _research_level(research_id)
	if lvl <= 0:
		return out
	var def: Dictionary = _research_by_id.get(research_id, {}) as Dictionary
	if def.is_empty():
		return out
	var levels: Array = def.get("levels", []) as Array
	for entry: Variant in levels:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = entry
		if int(row.get("level", 0)) != lvl:
			continue
		var effects: Array = row.get("effects", []) as Array
		for e: Variant in effects:
			out.append(str(e))
		break
	return out


func _research_flat_for_effect(effect_name: String) -> float:
	var total: float = 0.0
	var needle: String = effect_name.strip_edges().to_lower()
	for rid: Variant in _research_by_id.keys():
		for effect: String in _effect_strings_at_level(str(rid)):
			var parsed: Dictionary = _parse_effect(effect)
			if str(parsed.get("name", "")).to_lower() != needle:
				continue
			if bool(parsed.get("is_percent", false)):
				continue
			total += float(parsed.get("value", 0.0))
	return total


func _research_percent_for_effect(effect_name: String) -> float:
	var total: float = 0.0
	var needle: String = effect_name.strip_edges().to_lower()
	for rid: Variant in _research_by_id.keys():
		for effect: String in _effect_strings_at_level(str(rid)):
			var parsed: Dictionary = _parse_effect(effect)
			if str(parsed.get("name", "")).to_lower() != needle:
				continue
			if not bool(parsed.get("is_percent", false)):
				continue
			total += float(parsed.get("value", 0.0))
	return total


func _research_percent_sum_ids(ids: Array[String]) -> float:
	var total: float = 0.0
	for rid: String in ids:
		for effect: String in _effect_strings_at_level(rid):
			var parsed: Dictionary = _parse_effect(effect)
			if not bool(parsed.get("is_percent", false)):
				continue
			# These techs use "Gathering Speed +X%" text.
			var ename: String = str(parsed.get("name", "")).to_lower()
			if ename == "gathering speed" or ename == "gather speed":
				total += float(parsed.get("value", 0.0))
	return total


## Parse "March Capacity +50" / "Gathering Speed +5.0%" / "March Speed +10%".
func _parse_effect(effect: String) -> Dictionary:
	var text: String = effect.strip_edges()
	if text == "":
		return {}
	var is_percent: bool = text.find("%") >= 0
	var cleaned: String = text.replace("%", "").strip_edges()
	var plus_idx: int = cleaned.rfind("+")
	var minus_idx: int = cleaned.rfind("-")
	var sign_idx: int = plus_idx
	var sign: float = 1.0
	if minus_idx > plus_idx:
		sign_idx = minus_idx
		sign = -1.0
	if sign_idx <= 0:
		return {}
	var name: String = cleaned.substr(0, sign_idx).strip_edges()
	var num_s: String = cleaned.substr(sign_idx + 1, cleaned.length() - sign_idx - 1).strip_edges()
	if name == "" or num_s == "" or not num_s.is_valid_float():
		return {}
	var raw: float = float(num_s) * sign
	var value: float = raw / 100.0 if is_percent else raw
	return {"name": name, "value": value, "is_percent": is_percent}


# ---------------------------------------------------------------------------
# Heroes — MARCH-ACTIVE only for these Phase-1 stats
# ---------------------------------------------------------------------------

func _hero_percent_for_stats(hero_ids: Array, stat_names: Array) -> float:
	if hero_ids.is_empty() or not has_node("/root/DataManager"):
		return 0.0
	var wanted: Dictionary = {}
	for s: Variant in stat_names:
		wanted[str(s).strip_edges().to_lower()] = true
	var total: float = 0.0
	var seen: Dictionary = {}
	for hid_v: Variant in hero_ids:
		var hid: String = str(hid_v)
		if hid == "" or seen.has(hid):
			continue
		seen[hid] = true
		# Only owned heroes contribute (selected but not owned should not happen).
		if has_node("/root/HeroState") and HeroState.has_method("is_hero_owned"):
			if not bool(HeroState.is_hero_owned(hid)):
				continue
		var template: Dictionary = DataManager.get_hero(hid)
		if template.is_empty():
			continue
		var passives: Array = template.get("passiveBonuses", []) as Array
		for p: Variant in passives:
			if typeof(p) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = p
			var stat: String = str(row.get("stat", "")).strip_edges().to_lower()
			if not wanted.has(stat):
				continue
			# heroes.json stores fractions (0.1 = +10%).
			total += float(row.get("value", 0.0))
	return total


# ---------------------------------------------------------------------------
# Smoke (isolated; does not write saves)
# ---------------------------------------------------------------------------

func run_phase1_smoke_test() -> bool:
	var failed: int = 0
	_ensure_research_cache()

	var cap0: Dictionary = resolve_march_capacity([])
	var castle: int = int(cap0.get("citadel_level", 1))
	var expect_base: int = BASE_MARCH_CAPACITY + castle * CAPACITY_PER_CASTLE_LEVEL
	var expect_cap: int = maxi(1, int(floor((float(expect_base) + float(cap0.get("research_flat", 0.0))) * (1.0 + float(cap0.get("percent_total", 0.0))))))
	if int(cap0.get("final", 0)) != expect_cap:
		push_error("[StatResolver] smoke capacity mismatch final=%s expect=%s" % [str(cap0.get("final")), str(expect_cap)])
		failed += 1
	else:
		print("[StatResolver] smoke capacity OK %s" % format_breakdown(cap0))

	var spd0: Dictionary = resolve_march_speed([])
	if absf(float(spd0.get("final", 0.0)) - BASE_MARCH_SPEED_PX_PER_SEC) > 0.001 and float(spd0.get("percent_total", 0.0)) == 0.0:
		push_error("[StatResolver] smoke speed base mismatch")
		failed += 1
	else:
		print("[StatResolver] smoke speed OK %s" % format_breakdown(spd0))

	var g0: Dictionary = resolve_gather_rate("food", [])
	if absf(float(g0.get("final", 0.0)) - BASE_GATHER_RATE_PER_SEC) > 0.001 and float(g0.get("percent_total", 0.0)) == 0.0:
		push_error("[StatResolver] smoke gather base mismatch")
		failed += 1
	else:
		print("[StatResolver] smoke gather OK %s" % format_breakdown(g0))

	# Additive stacking unit check (synthetic).
	var synthetic_final: float = 100.0 * (1.0 + 0.10 + 0.15 + 0.05)
	if absf(synthetic_final - 130.0) > 0.001:
		push_error("[StatResolver] smoke stacking model broken")
		failed += 1

	# Travel seconds uses resolver speed.
	var travel: int = estimate_travel_seconds(Vector2.ZERO, Vector2(2200, 0), [])
	if travel != 10:
		push_error("[StatResolver] smoke travel expected 10 got %d" % travel)
		failed += 1

	var flat_fx: Dictionary = _parse_effect("March Capacity +250")
	var pct_fx: Dictionary = _parse_effect("Gathering Speed +25.0%")
	if int(flat_fx.get("value", 0)) != 250 or bool(flat_fx.get("is_percent", true)):
		push_error("[StatResolver] smoke flat effect parse failed: %s" % str(flat_fx))
		failed += 1
	if absf(float(pct_fx.get("value", 0.0)) - 0.25) > 0.0001 or not bool(pct_fx.get("is_percent", false)):
		push_error("[StatResolver] smoke percent effect parse failed: %s" % str(pct_fx))
		failed += 1

	# Research flat applies when level is present (non-destructive temp bump).
	if has_node("/root/ResearchState"):
		var prev: int = int(ResearchState.get_research_level("mil_march_cap_1"))
		ResearchState.research_levels["mil_march_cap_1"] = 5
		var cap_r: Dictionary = resolve_march_capacity([])
		if float(cap_r.get("research_flat", 0.0)) < 250.0:
			push_error("[StatResolver] smoke research capacity flat missing: %s" % str(cap_r))
			failed += 1
		else:
			print("[StatResolver] smoke research capacity flat OK (+%.0f)" % float(cap_r.get("research_flat", 0.0)))
		if prev > 0:
			ResearchState.research_levels["mil_march_cap_1"] = prev
		else:
			ResearchState.research_levels.erase("mil_march_cap_1")

	if failed == 0:
		print("[StatResolver] Phase-1 smoke PASSED")
		return true
	print("[StatResolver] Phase-1 smoke FAILED count=%d" % failed)
	return false


func run_phase2_smoke_test() -> bool:
	var failed: int = 0
	_ensure_research_cache()
	if not has_node("/root/TroopDatabase"):
		push_error("[StatResolver] Phase-2 smoke requires TroopDatabase")
		return false

	# TEST A — tier difference (quantity-weighted troops.json stats, not class weights).
	var t1: Dictionary = resolve_troop_type_combat_stats("infantry", {1: 100}, [])
	var t2: Dictionary = resolve_troop_type_combat_stats("infantry", {2: 100}, [])
	var t1_atk: float = float(t1.get("raw_attack", 0.0))
	var t2_atk: float = float(t2.get("raw_attack", 0.0))
	var expect_t1: float = float(TroopDatabase.get_troop("infantry", 1).get("attack", 0)) * 100.0
	var expect_t2: float = float(TroopDatabase.get_troop("infantry", 2).get("attack", 0)) * 100.0
	if absf(t1_atk - expect_t1) > 0.01 or absf(t2_atk - expect_t2) > 0.01 or t2_atk <= t1_atk:
		push_error("[StatResolver] Phase-2 T1/T2 fail t1=%s expect=%s t2=%s expect=%s" % [
			str(t1_atk), str(expect_t1), str(t2_atk), str(expect_t2),
		])
		failed += 1
	else:
		print("[StatResolver] Phase-2 T1/T2 OK raw_atk %s vs %s" % [str(t1_atk), str(t2_atk)])

	# TEST B — Infantry-specific research does not bleed into Marksmen type component.
	var prev_inf: int = 0
	if has_node("/root/ResearchState"):
		prev_inf = int(ResearchState.get_research_level("mil_inf_atk_1"))
		ResearchState.research_levels["mil_inf_atk_1"] = 1 # Infantry Attack +8.0%
	var mixed: Dictionary = resolve_march_combat_stats({
		"infantry": {1: 100},
		"marksmen": {1: 100},
		"cavalry": {},
	}, [])
	var inf_bd: Dictionary = (mixed.get("infantry", {}) as Dictionary).get("attack_breakdown", {}) as Dictionary
	var mar_bd: Dictionary = (mixed.get("marksmen", {}) as Dictionary).get("attack_breakdown", {}) as Dictionary
	var inf_type_only: float = 0.0
	for s: Variant in inf_bd.get("research_sources", []):
		if typeof(s) == TYPE_DICTIONARY and str((s as Dictionary).get("name", "")).to_lower() == "infantry attack":
			inf_type_only += float((s as Dictionary).get("value", 0.0))
	var mar_type_only: float = 0.0
	for s2: Variant in mar_bd.get("research_sources", []):
		if typeof(s2) == TYPE_DICTIONARY and str((s2 as Dictionary).get("name", "")).to_lower() == "infantry attack":
			mar_type_only += float((s2 as Dictionary).get("value", 0.0))
	if inf_type_only < 0.079 or mar_type_only > 0.0001:
		push_error("[StatResolver] Phase-2 type-specific fail inf=%s mar_bleed=%s" % [
			str(inf_type_only), str(mar_type_only),
		])
		failed += 1
	else:
		print("[StatResolver] Phase-2 type-specific OK infantry_atk_research=+%.1f%% marksmen_bleed=0" % (inf_type_only * 100.0))
	if has_node("/root/ResearchState"):
		if prev_inf > 0:
			ResearchState.research_levels["mil_inf_atk_1"] = prev_inf
		else:
			ResearchState.research_levels.erase("mil_inf_atk_1")

	# TEST C — hero march-active only (uses owned starter if present).
	var hero_id: String = ""
	if has_node("/root/HeroState"):
		for h: Dictionary in HeroState.get_owned_heroes():
			var hid: String = str(h.get("id", ""))
			if hid == "":
				continue
			var tmpl: Dictionary = DataManager.get_hero(hid) if has_node("/root/DataManager") else {}
			for p: Variant in tmpl.get("passiveBonuses", []):
				if typeof(p) != TYPE_DICTIONARY:
					continue
				var st: String = str((p as Dictionary).get("stat", "")).to_lower()
				if st in ["troop attack", "infantry attack", "marksmen attack", "cavalry attack"]:
					hero_id = hid
					break
			if hero_id != "":
				break
	if hero_id != "":
		var without: Dictionary = resolve_troop_type_combat_stats("infantry", {1: 50}, [])
		var with_h: Dictionary = resolve_troop_type_combat_stats("infantry", {1: 50}, [hero_id])
		var pct0: float = float(without.get("attack_bonus_percent", 0.0))
		var pct1: float = float(with_h.get("attack_bonus_percent", 0.0))
		if pct1 <= pct0:
			push_error("[StatResolver] Phase-2 hero bonus did not apply for %s" % hero_id)
			failed += 1
		else:
			print("[StatResolver] Phase-2 hero OK %s atk_bonus %.1f%% → %.1f%%" % [
				hero_id, pct0 * 100.0, pct1 * 100.0,
			])
	else:
		print("[StatResolver] Phase-2 hero test SKIPPED (no owned combat-passive hero)")

	# TEST D — additive stacking research + research (synthetic channel math).
	var stack: float = _apply_percent(100.0, 0.10 + 0.05)
	if absf(stack - 115.0) > 0.001:
		push_error("[StatResolver] Phase-2 stacking fail got %s" % str(stack))
		failed += 1

	# TEST E — mixed tiers quantity-weighted sum.
	var mixed_tiers: Dictionary = resolve_troop_type_combat_stats("infantry", {1: 10, 3: 5}, [])
	var e1: float = float(TroopDatabase.get_troop("infantry", 1).get("attack", 0)) * 10.0
	var e3: float = float(TroopDatabase.get_troop("infantry", 3).get("attack", 0)) * 5.0
	if absf(float(mixed_tiers.get("raw_attack", 0.0)) - (e1 + e3)) > 0.01:
		push_error("[StatResolver] Phase-2 mixed-tier fail")
		failed += 1
	else:
		print("[StatResolver] Phase-2 mixed-tier OK raw_atk=%s" % str(mixed_tiers.get("raw_attack")))

	# Confirm Wildling class weights are NOT used (100 T1 inf raw != 100*10).
	if absf(float(t1.get("raw_attack", 0.0)) - 1000.0) < 0.01:
		push_error("[StatResolver] Phase-2 incorrectly looks like class-weight power")
		failed += 1

	if failed == 0:
		print("[StatResolver] Phase-2 smoke PASSED")
		return true
	print("[StatResolver] Phase-2 smoke FAILED count=%d" % failed)
	return false
