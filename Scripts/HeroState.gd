extends Node

## Owned hero roster + shard progress (separate from DataManager catalog).
## Persist: user://heroes.cfg (or isolated smoke path).

signal heroes_changed

const SAVE_PATH: String = "user://heroes.cfg"
const SMOKE_SAVE_PATH: String = "user://heroes_smoke_test.cfg"
const POOLS_PATH: String = "res://data/hero_recruitment_pools.json"
const SAVE_VERSION: int = 3
const SHARDS_TO_UNLOCK: int = 10
const CLEANUP_KEY: String = "prebeta_autoown_cleared_v1"
const STARTER_KEY: String = "starter_maegan_granted_v1"
const STARTER_HERO_ID: String = "maegan"
## Canonical City Wall defensive hero capacity (beta).
const MAX_WALL_DEFENDERS: int = 3

var royal_tickets: int = 5
var mythic_tickets: int = 1
## Legacy alias used by older UI; maps to royal_tickets.
var hero_tickets: int:
	get:
		return royal_tickets
	set(value):
		royal_tickets = value

var recruited_heroes: Array[Dictionary] = []
var current_hero_index: int = -1

var campaign_chapter: int = 1
var campaign_stage: int = 1
var campaign_progress: int = 0

var hero_shards: Dictionary = {}
var hero_xp: int = 0

var royal_free_ready_unix: int = 0
var mythic_free_ready_unix: int = 0

## Persistent City Wall defensive assignments (owned hero ids only).
var wall_defender_ids: Array[String] = []

var _save_path_override: String = ""
var _pools: Dictionary = {}
var _cleanup_done: bool = false
var _starter_maegan_granted: bool = false


func _ready() -> void:
	_load_pools()
	load_heroes()


func get_save_path() -> String:
	if _save_path_override != "":
		return _save_path_override
	if has_node("/root/AccountSavePaths"):
		return AccountSavePaths.path_for("heroes.cfg")
	return SAVE_PATH


func _load_pools() -> void:
	_pools = {}
	if not FileAccess.file_exists(POOLS_PATH):
		return
	var file := FileAccess.open(POOLS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_pools = parsed


func get_recruitment_pools() -> Dictionary:
	return _pools.duplicate(true)


func get_tier_config(tier_id: String) -> Dictionary:
	var tiers: Dictionary = _pools.get("tiers", {})
	return tiers.get(tier_id, {}).duplicate(true)


func is_pool_configured(tier_id: String) -> bool:
	var tier: Dictionary = get_tier_config(tier_id)
	var ids: Array = tier.get("active_hero_ids", [])
	return not ids.is_empty()


func get_shards_to_unlock() -> int:
	return int(_pools.get("unlock_shards_required", SHARDS_TO_UNLOCK))


## DEBUG ONLY — grants test tickets for recruitment QA. No-op outside debug builds.
func debug_grant_test_tickets(royal_amount: int = 10, mythic_amount: int = 10) -> Dictionary:
	if not OS.is_debug_build():
		return {"ok": false, "error": "Debug ticket grants are unavailable in release builds."}
	royal_tickets += maxi(0, royal_amount)
	mythic_tickets += maxi(0, mythic_amount)
	save_heroes()
	heroes_changed.emit()
	return {
		"ok": true,
		"royal_tickets": royal_tickets,
		"mythic_tickets": mythic_tickets,
		"royal_granted": maxi(0, royal_amount),
		"mythic_granted": maxi(0, mythic_amount),
	}


func get_shard_reward_table() -> Array:
	var table: Array = _pools.get("shard_rewards", [])
	if typeof(table) == TYPE_ARRAY and not table.is_empty():
		return table.duplicate(true)
	# Safe fallback matching launch distribution.
	return [
		{"amount": 1, "weight": 80},
		{"amount": 5, "weight": 15},
		{"amount": 10, "weight": 5},
	]


func get_shard_reward_chances() -> Array[Dictionary]:
	var table: Array = get_shard_reward_table()
	var total_w: int = 0
	for entry_v: Variant in table:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		total_w += max(0, int((entry_v as Dictionary).get("weight", 0)))
	var result: Array[Dictionary] = []
	for entry_v: Variant in table:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var w: int = max(0, int(entry.get("weight", 0)))
		var pct: float = (float(w) / float(total_w)) * 100.0 if total_w > 0 else 0.0
		result.append({
			"amount": int(entry.get("amount", 0)),
			"weight": w,
			"percent": pct,
		})
	return result


## Effective selection weight for a hero in a tier (does not rebalance).
func get_effective_hero_weight(tier: Dictionary, rarity: String) -> int:
	var weights: Dictionary = tier.get("weights_by_rarity", {})
	var w: int = int(weights.get(rarity, 10))
	if w <= 0:
		w = 1
	return w


func get_pool_hero_chances(tier_id: String) -> Array[Dictionary]:
	var tier: Dictionary = get_tier_config(tier_id)
	var ids: Array = tier.get("active_hero_ids", [])
	var rows: Array[Dictionary] = []
	var total_w: int = 0
	for id_v: Variant in ids:
		var hid: String = str(id_v)
		var template: Dictionary = {}
		if has_node("/root/DataManager"):
			template = DataManager.get_hero(hid)
		if template.is_empty():
			continue
		var rarity: String = str(template.get("rarity", "Rare"))
		var w: int = get_effective_hero_weight(tier, rarity)
		total_w += w
		rows.append({
			"id": hid,
			"name": str(template.get("name", hid)),
			"rarity": rarity,
			"weight": w,
			"portrait": str(template.get("portrait", "")),
			"template": template,
		})
	for row: Dictionary in rows:
		var w: int = int(row.get("weight", 0))
		row["percent"] = (float(w) / float(total_w)) * 100.0 if total_w > 0 else 0.0
	return rows


# --- Ownership ---

func is_hero_owned(hero_id: String) -> bool:
	return get_hero_index(hero_id) != -1


func get_owned_heroes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hero: Dictionary in recruited_heroes:
		result.append(hero.duplicate(true))
	return result


func get_owned_hero(hero_id: String) -> Dictionary:
	var index: int = get_hero_index(hero_id)
	if index == -1:
		return {}
	return recruited_heroes[index].duplicate(true)


func get_hero_index(hero_id: String) -> int:
	for i in range(recruited_heroes.size()):
		var hero: Dictionary = recruited_heroes[i]
		if str(hero.get("id", "")) == hero_id:
			return i
	return -1


func get_hero_progress(hero_id: String) -> Dictionary:
	var index: int = get_hero_index(hero_id)
	if index != -1:
		return recruited_heroes[index].duplicate(true)
	return _default_progress(hero_id)


func get_or_create_hero(hero_id: String) -> Dictionary:
	return get_hero_progress(hero_id)


func _default_progress(hero_id: String) -> Dictionary:
	return {
		"id": hero_id,
		"level": 1,
		"starLevel": 5,
		"starProgress": 0,
		"xp": 0,
		"ascension": 0,
		"on_march": false,
	}


func _make_owned_entry(hero_id: String, template: Dictionary = {}, unlock_source: String = "shards") -> Dictionary:
	var name_value: String = str(template.get("name", hero_id.capitalize()))
	return {
		"id": hero_id,
		"name": name_value,
		"level": 1,
		"starLevel": int(template.get("starLevel", 5)),
		"starProgress": int(template.get("starProgress", 0)),
		"xp": 0,
		"ascension": 0,
		"on_march": false,
		"unlock_source": unlock_source,
	}


## Heroes with shard progress who are not yet owned (0 shards excluded).
func get_shard_progress_heroes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var need: int = get_shards_to_unlock()
	for hero_id: Variant in hero_shards.keys():
		var hid: String = str(hero_id)
		if is_hero_owned(hid):
			continue
		var count: int = int(hero_shards[hero_id])
		if count <= 0:
			continue
		var template: Dictionary = {}
		if has_node("/root/DataManager"):
			template = DataManager.get_hero(hid)
		result.append({
			"id": hid,
			"name": str(template.get("name", hid.capitalize())),
			"rarity": str(template.get("rarity", "")),
			"shards": count,
			"shards_required": need,
			"can_unlock": count >= need,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("shards", 0)) > int(b.get("shards", 0))
	)
	return result


func can_unlock_hero(hero_id: String) -> bool:
	if is_hero_owned(hero_id):
		return false
	return get_hero_shards(hero_id) >= get_shards_to_unlock()


## Explicit unlock at 10/10 shards. Does not spend shards (kept for ascension).
func unlock_hero_from_shards(hero_id: String) -> Dictionary:
	if hero_id.is_empty():
		return {"ok": false, "error": "Invalid hero id."}
	if is_hero_owned(hero_id):
		return {"ok": false, "error": "Hero already owned."}
	var need: int = get_shards_to_unlock()
	var have: int = get_hero_shards(hero_id)
	if have < need:
		return {"ok": false, "error": "Need %d shards (have %d)." % [need, have]}

	var template: Dictionary = {}
	if has_node("/root/DataManager"):
		template = DataManager.get_hero(hero_id)
	var entry: Dictionary = _make_owned_entry(hero_id, template, "shards")
	recruited_heroes.append(entry)
	current_hero_index = recruited_heroes.size() - 1
	save_heroes()
	heroes_changed.emit()
	return {"ok": true, "hero": entry.duplicate(true), "shards_remaining": have}


## Legacy name — only unlocks via shard threshold (explicit).
func recruit_hero(hero_id: String) -> Dictionary:
	return unlock_hero_from_shards(hero_id)


## One-time starter grant. Never called from Heroes UI navigation.
func grant_starter_maegan() -> Dictionary:
	if _starter_maegan_granted:
		return {"ok": true, "already_granted": true, "hero_id": STARTER_HERO_ID}
	if is_hero_owned(STARTER_HERO_ID):
		_starter_maegan_granted = true
		save_heroes()
		return {"ok": true, "already_owned": true, "hero_id": STARTER_HERO_ID}

	var tickets_before_royal: int = royal_tickets
	var tickets_before_mythic: int = mythic_tickets
	var template: Dictionary = {}
	if has_node("/root/DataManager"):
		template = DataManager.get_hero(STARTER_HERO_ID)
	var entry: Dictionary = _make_owned_entry(STARTER_HERO_ID, template, "starter")
	recruited_heroes.append(entry)
	current_hero_index = recruited_heroes.size() - 1
	_starter_maegan_granted = true
	# Never consume tickets or shards for the starter grant.
	royal_tickets = tickets_before_royal
	mythic_tickets = tickets_before_mythic
	save_heroes()
	heroes_changed.emit()
	print("[HeroState] Starter hero granted: maegan")
	return {"ok": true, "granted": true, "hero": entry.duplicate(true)}


func _ensure_starter_maegan() -> void:
	grant_starter_maegan()


## One shard draw from a configured tier pool. Never auto-owns.
func draw_recruitment(tier_id: String, use_free: bool = false) -> Dictionary:
	var tier: Dictionary = get_tier_config(tier_id)
	if tier.is_empty():
		return {"ok": false, "error": "Unknown recruitment tier."}
	if not is_pool_configured(tier_id):
		return {
			"ok": false,
			"error": "Recruitment pool not configured yet.",
			"pool_pending": true,
		}

	var now: int = int(Time.get_unix_time_from_system())
	if use_free:
		var ready_at: int = royal_free_ready_unix if tier_id == "royal" else mythic_free_ready_unix
		if now < ready_at:
			return {"ok": false, "error": "Free recruit not ready."}
	else:
		if tier_id == "royal":
			if royal_tickets <= 0:
				return {"ok": false, "error": "Not enough Royal Tickets."}
			royal_tickets -= 1
		else:
			if mythic_tickets <= 0:
				return {"ok": false, "error": "Not enough Mythic Tickets."}
			mythic_tickets -= 1

	var pick: Dictionary = _pick_pool_hero(tier)
	if pick.is_empty():
		# Refund ticket if pick failed after spend.
		if not use_free:
			if tier_id == "royal":
				royal_tickets += 1
			else:
				mythic_tickets += 1
		return {"ok": false, "error": "No valid heroes in pool."}

	var hero_id: String = str(pick.get("id", ""))
	var rarity: String = str(pick.get("rarity", "Rare"))
	var shard_amount: int = _roll_shard_amount()
	add_hero_shards(hero_id, shard_amount)

	if use_free:
		var cooldown: int = int(tier.get("free_cooldown_seconds", 0))
		var next_ready: int = now + max(0, cooldown)
		if tier_id == "royal":
			royal_free_ready_unix = next_ready
		else:
			mythic_free_ready_unix = next_ready

	var total: int = get_hero_shards(hero_id)
	var need: int = get_shards_to_unlock()
	save_heroes()
	heroes_changed.emit()
	return {
		"ok": true,
		"reward_type": "hero_shards",
		"tier_id": tier_id,
		"hero_id": hero_id,
		"name": str(pick.get("name", hero_id)),
		"rarity": rarity,
		"shard_amount": shard_amount,
		"shards_total": total,
		"shards_required": need,
		"was_unlock_ready": (not is_hero_owned(hero_id)) and total >= need,
		"already_owned": is_hero_owned(hero_id),
	}


func draw_recruitment_multi(tier_id: String, count: int) -> Dictionary:
	var results: Array = []
	for _i in range(maxi(1, count)):
		var one: Dictionary = draw_recruitment(tier_id, false)
		if not one.get("ok", false):
			return {
				"ok": false,
				"error": str(one.get("error", "Draw failed.")),
				"results": results,
				"pool_pending": bool(one.get("pool_pending", false)),
			}
		results.append(one)
	return {"ok": true, "results": results}


func _pick_pool_hero(tier: Dictionary) -> Dictionary:
	var ids: Array = tier.get("active_hero_ids", [])
	if ids.is_empty() or not has_node("/root/DataManager"):
		return {}
	var weighted: Array[Dictionary] = []
	var total_w: int = 0
	for id_v: Variant in ids:
		var hid: String = str(id_v)
		var template: Dictionary = DataManager.get_hero(hid)
		if template.is_empty():
			continue
		var rarity: String = str(template.get("rarity", "Rare"))
		var w: int = get_effective_hero_weight(tier, rarity)
		weighted.append({"template": template, "w": w})
		total_w += w
	if weighted.is_empty() or total_w <= 0:
		return {}
	var roll: int = randi() % total_w
	var cursor: int = 0
	for entry: Dictionary in weighted:
		cursor += int(entry.get("w", 1))
		if roll < cursor:
			return entry.get("template", {})
	return weighted[weighted.size() - 1].get("template", {})


## Independent shard-quantity roll after hero selection. Amounts: 1 / 5 / 10.
func _roll_shard_amount() -> int:
	var table: Array = get_shard_reward_table()
	var total_w: int = 0
	var entries: Array[Dictionary] = []
	for entry_v: Variant in table:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var w: int = max(0, int(entry.get("weight", 0)))
		if w <= 0:
			continue
		entries.append(entry)
		total_w += w
	if entries.is_empty() or total_w <= 0:
		return 1
	var roll: int = randi() % total_w
	var cursor: int = 0
	for entry: Dictionary in entries:
		cursor += int(entry.get("weight", 0))
		if roll < cursor:
			return int(entry.get("amount", 1))
	return int(entries[entries.size() - 1].get("amount", 1))


func get_free_recruit_ready_unix(tier_id: String) -> int:
	if tier_id == "mythic":
		return mythic_free_ready_unix
	return royal_free_ready_unix


func get_free_seconds_remaining(tier_id: String) -> int:
	var ready: int = get_free_recruit_ready_unix(tier_id)
	var now: int = int(Time.get_unix_time_from_system())
	return max(0, ready - now)


## Deprecated auto-own path — redirects to shard draw when pool ready.
func recruit_random_hero() -> Dictionary:
	return draw_recruitment("royal", false)


func save_hero_progress(hero_id: String, hero_data: Dictionary) -> void:
	var index: int = get_hero_index(hero_id)
	if index == -1:
		return
	recruited_heroes[index] = hero_data
	save_heroes()
	heroes_changed.emit()


func get_level_cap(star_level: int) -> int:
	return clamp(star_level, 5, 12) * 10


func get_star_power_multiplier(star_level: int, star_progress: int) -> float:
	var safe_star_level: int = clamp(star_level, 5, 12)
	var safe_star_progress: int = clamp(star_progress, 0, 5)
	var extra_stars: int = safe_star_level - 5
	return 1.0 + (float(extra_stars) * 0.10) + (float(safe_star_progress) * 0.02)


func get_level_up_cost(level: int) -> int:
	return max(1, level) * 100


func get_star_upgrade_cost(star_level: int) -> int:
	match star_level:
		5:
			return 50
		6:
			return 100
		7:
			return 150
		8:
			return 200
		9:
			return 250
		10:
			return 300
		11:
			return 400
	return 999999


func get_hero_xp() -> int:
	return hero_xp


func add_hero_xp(amount: int) -> void:
	hero_xp += max(0, amount)
	save_heroes()


func spend_hero_xp(amount: int) -> bool:
	var safe_amount: int = max(0, amount)
	if hero_xp < safe_amount:
		return false
	hero_xp -= safe_amount
	save_heroes()
	return true


func get_hero_shards(hero_id: String) -> int:
	return int(hero_shards.get(hero_id, 0))


func add_hero_shards(hero_id: String, amount: int) -> void:
	if not hero_shards.has(hero_id):
		hero_shards[hero_id] = 0
	hero_shards[hero_id] = int(hero_shards[hero_id]) + max(0, amount)
	save_heroes()


func spend_hero_shards(hero_id: String, amount: int) -> bool:
	var safe_amount: int = max(0, amount)
	if get_hero_shards(hero_id) < safe_amount:
		return false
	hero_shards[hero_id] = get_hero_shards(hero_id) - safe_amount
	save_heroes()
	return true


func level_up_hero(hero_id: String) -> bool:
	if not is_hero_owned(hero_id):
		return false
	var index: int = get_hero_index(hero_id)
	var hero: Dictionary = recruited_heroes[index]
	var current_level: int = int(hero.get("level", 1))
	var star_level: int = int(hero.get("starLevel", 5))
	var max_level: int = get_level_cap(star_level)
	if current_level >= max_level:
		return false
	var cost: int = get_level_up_cost(current_level)
	if not spend_hero_xp(cost):
		return false
	hero["level"] = current_level + 1
	recruited_heroes[index] = hero
	save_heroes()
	heroes_changed.emit()
	return true


func ascend_hero(hero_id: String) -> bool:
	if not is_hero_owned(hero_id):
		return false
	var index: int = get_hero_index(hero_id)
	var hero: Dictionary = recruited_heroes[index]
	var star_level: int = int(hero.get("starLevel", 5))
	var star_progress: int = int(hero.get("starProgress", 0))
	if star_level >= 12:
		return false
	var cost: int = get_star_upgrade_cost(star_level)
	if not spend_hero_shards(hero_id, cost):
		return false
	star_progress += 1
	if star_progress >= 5:
		star_progress = 0
		star_level += 1
	hero["starLevel"] = star_level
	hero["starProgress"] = star_progress
	recruited_heroes[index] = hero
	save_heroes()
	heroes_changed.emit()
	return true


func is_hero_on_march(hero_id: String) -> bool:
	var index: int = get_hero_index(hero_id)
	if index == -1:
		return false
	return bool(recruited_heroes[index].get("on_march", false))


func set_hero_on_march(hero_id: String, on_march: bool) -> void:
	var index: int = get_hero_index(hero_id)
	if index == -1:
		return
	recruited_heroes[index]["on_march"] = on_march
	save_heroes()
	heroes_changed.emit()


func is_hero_wall_defender(hero_id: String) -> bool:
	return hero_id in wall_defender_ids


## Centralized: free for outbound marches (not on march, not Wall defense).
func is_hero_available_for_march(hero_id: String) -> bool:
	if not is_hero_owned(hero_id):
		return false
	if is_hero_on_march(hero_id):
		return false
	if is_hero_wall_defender(hero_id):
		return false
	return true


func get_available_heroes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hero: Dictionary in recruited_heroes:
		var hid: String = str(hero.get("id", ""))
		if is_hero_available_for_march(hid):
			result.append(hero.duplicate(true))
	return result


func get_wall_defender_ids() -> Array[String]:
	return wall_defender_ids.duplicate()


func get_max_wall_defenders() -> int:
	return MAX_WALL_DEFENDERS


## Replace Wall defender list. Only owned, not-on-march heroes. Persists.
func set_wall_defenders(hero_ids: Array) -> Dictionary:
	var cleaned: Array[String] = []
	for hid_v: Variant in hero_ids:
		var hid: String = str(hid_v).strip_edges()
		if hid.is_empty() or hid in cleaned:
			continue
		if not is_hero_owned(hid):
			return {"ok": false, "error": "Hero not owned: %s" % hid}
		if is_hero_on_march(hid):
			return {"ok": false, "error": "%s is on a march." % hid}
		cleaned.append(hid)
		if cleaned.size() > MAX_WALL_DEFENDERS:
			return {"ok": false, "error": "Max %d Wall defenders." % MAX_WALL_DEFENDERS}
	wall_defender_ids = cleaned
	save_heroes()
	heroes_changed.emit()
	return {"ok": true, "wall_defender_ids": get_wall_defender_ids()}


## Informational City Defense Power (sum of assigned defender display power).
func get_city_defense_power() -> int:
	var total: int = 0
	for hid: String in wall_defender_ids:
		total += get_hero_display_power(hid)
	return total


func get_hero_display_power(hero_id: String) -> int:
	var owned: Dictionary = get_owned_hero(hero_id)
	if owned.is_empty():
		return 0
	var template: Dictionary = {}
	if has_node("/root/DataManager"):
		template = DataManager.get_hero(hero_id)
	var level: int = int(owned.get("level", 1))
	var star_level: int = int(owned.get("starLevel", template.get("starLevel", 5)))
	var star_progress: int = int(owned.get("starProgress", template.get("starProgress", 0)))
	var level_factor: float = 1.0 + (float(level - 1) * 0.25)
	var star_multiplier: float = get_star_power_multiplier(star_level, star_progress)
	var attack: float = float(template.get("baseAttack", owned.get("baseAttack", 100))) * level_factor * star_multiplier
	var defense: float = float(template.get("baseDefense", owned.get("baseDefense", 100))) * level_factor * star_multiplier
	var health: float = float(template.get("baseHealth", owned.get("baseHealth", 1000))) * level_factor * star_multiplier
	var leadership: float = float(template.get("leadership", owned.get("leadership", 50))) * level_factor * star_multiplier
	return int((attack + defense) * 12.0 + (health * 0.5) + leadership)


# --- Save / load / cleanup ---

func save_heroes() -> void:
	var save := ConfigFile.new()
	save.set_value("meta", "save_version", SAVE_VERSION)
	save.set_value("meta", CLEANUP_KEY, true if _cleanup_done else false)
	save.set_value("meta", STARTER_KEY, true if _starter_maegan_granted else false)
	save.set_value("roster", "heroes_json", JSON.stringify(recruited_heroes))
	save.set_value("roster", "royal_tickets", royal_tickets)
	save.set_value("roster", "mythic_tickets", mythic_tickets)
	save.set_value("roster", "hero_tickets", royal_tickets) # legacy mirror
	save.set_value("roster", "current_hero_index", current_hero_index)
	save.set_value("roster", "hero_xp", hero_xp)
	save.set_value("roster", "hero_shards_json", JSON.stringify(hero_shards))
	save.set_value("roster", "royal_free_ready_unix", royal_free_ready_unix)
	save.set_value("roster", "mythic_free_ready_unix", mythic_free_ready_unix)
	save.set_value("city_defense", "wall_defender_ids_json", JSON.stringify(wall_defender_ids))
	save.save(get_save_path())
	if has_node("/root/AccountCloudSave"):
		AccountCloudSave.mark_dirty("heroes")


func load_heroes() -> void:
	recruited_heroes.clear()
	hero_shards.clear()
	wall_defender_ids.clear()
	_starter_maegan_granted = false
	var save := ConfigFile.new()
	if save.load(get_save_path()) != OK:
		royal_tickets = 5
		mythic_tickets = 1
		hero_xp = 0
		current_hero_index = -1
		royal_free_ready_unix = 0
		mythic_free_ready_unix = 0
		_cleanup_done = true
		_ensure_starter_maegan()
		return

	var version: int = int(save.get_value("meta", "save_version", 1))
	_cleanup_done = bool(save.get_value("meta", CLEANUP_KEY, false))
	_starter_maegan_granted = bool(save.get_value("meta", STARTER_KEY, false))

	var raw: String = str(save.get_value("roster", "heroes_json", "[]"))
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) == TYPE_ARRAY:
		for item: Variant in parsed:
			if typeof(item) == TYPE_DICTIONARY:
				recruited_heroes.append(item)

	royal_tickets = int(save.get_value("roster", "royal_tickets", save.get_value("roster", "hero_tickets", 5)))
	mythic_tickets = int(save.get_value("roster", "mythic_tickets", 1))
	current_hero_index = int(save.get_value("roster", "current_hero_index", -1))
	hero_xp = int(save.get_value("roster", "hero_xp", 0))
	royal_free_ready_unix = int(save.get_value("roster", "royal_free_ready_unix", 0))
	mythic_free_ready_unix = int(save.get_value("roster", "mythic_free_ready_unix", 0))

	var shards_raw: String = str(save.get_value("roster", "hero_shards_json", "{}"))
	var shards_parsed: Variant = JSON.parse_string(shards_raw)
	if typeof(shards_parsed) == TYPE_DICTIONARY:
		hero_shards = shards_parsed

	var wall_raw: String = str(save.get_value("city_defense", "wall_defender_ids_json", "[]"))
	var wall_parsed: Variant = JSON.parse_string(wall_raw)
	if typeof(wall_parsed) == TYPE_ARRAY:
		for hid_v: Variant in wall_parsed:
			var hid: String = str(hid_v).strip_edges()
			if hid != "" and hid not in wall_defender_ids:
				wall_defender_ids.append(hid)

	if current_hero_index >= recruited_heroes.size():
		current_hero_index = recruited_heroes.size() - 1

	_run_prebeta_autoown_cleanup(version)
	_ensure_starter_maegan()
	_sanitize_wall_defenders()


func _sanitize_wall_defenders() -> void:
	var cleaned: Array[String] = []
	for hid: String in wall_defender_ids:
		if not is_hero_owned(hid):
			continue
		if is_hero_on_march(hid):
			continue
		if hid in cleaned:
			continue
		cleaned.append(hid)
		if cleaned.size() >= MAX_WALL_DEFENDERS:
			break
	if cleaned.size() != wall_defender_ids.size():
		wall_defender_ids = cleaned
		save_heroes()
	else:
		wall_defender_ids = cleaned


## One-time removal of heroes granted by the broken auto-own Tavern draw.
func _run_prebeta_autoown_cleanup(loaded_version: int) -> void:
	if _cleanup_done:
		return

	var removed_ids: Array[String] = []
	var kept: Array[Dictionary] = []
	for hero: Dictionary in recruited_heroes:
		var hid: String = str(hero.get("id", ""))
		var unlock_source: String = str(hero.get("unlock_source", ""))
		# Legitimate grants keep ownership.
		if unlock_source in ["shards", "starter"]:
			kept.append(hero)
			continue
		# Pre-beta auto-own signature: level-1 stubs with no unlock_source.
		var level: int = int(hero.get("level", 1))
		var xp: int = int(hero.get("xp", 0))
		var ascension: int = int(hero.get("ascension", 0))
		if level <= 1 and xp == 0 and ascension == 0 and unlock_source == "":
			removed_ids.append(hid)
			continue
		kept.append(hero)

	if removed_ids.is_empty() and loaded_version >= SAVE_VERSION:
		_cleanup_done = true
		save_heroes()
		return

	if not removed_ids.is_empty():
		print("[HeroState] Pre-beta auto-own cleanup removed: ", removed_ids)
		# Restore starter tickets if broken draws burned them and shards are empty.
		if hero_shards.is_empty() and royal_tickets < 5:
			royal_tickets = 5
		recruited_heroes = kept
		current_hero_index = recruited_heroes.size() - 1

	_cleanup_done = true
	save_heroes()
	heroes_changed.emit()


# --- Smoke ---

func begin_smoke_isolation() -> void:
	_save_path_override = SMOKE_SAVE_PATH
	recruited_heroes.clear()
	hero_shards.clear()
	wall_defender_ids.clear()
	royal_tickets = 5
	mythic_tickets = 1
	hero_xp = 0
	current_hero_index = -1
	royal_free_ready_unix = 0
	mythic_free_ready_unix = 0
	_cleanup_done = true
	_starter_maegan_granted = false
	if FileAccess.file_exists(SMOKE_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SMOKE_SAVE_PATH))


func end_smoke_isolation() -> void:
	_save_path_override = ""
	load_heroes()


func run_hero_roster_smoke_test() -> bool:
	begin_smoke_isolation()
	var ok: bool = true

	# Fresh isolated session: grant starter once.
	var tickets_r: int = royal_tickets
	var tickets_m: int = mythic_tickets
	var grant1: Dictionary = grant_starter_maegan()
	if not grant1.get("ok", false) or not is_hero_owned("maegan"):
		push_error("[HeroState] smoke: starter grant failed")
		ok = false
	if royal_tickets != tickets_r or mythic_tickets != tickets_m:
		push_error("[HeroState] smoke: starter grant consumed tickets")
		ok = false
	if get_owned_heroes().size() != 1:
		push_error("[HeroState] smoke: owned count should be 1 after starter")
		ok = false

	var grant2: Dictionary = grant_starter_maegan()
	if not bool(grant2.get("already_granted", false)) and not bool(grant2.get("already_owned", false)):
		push_error("[HeroState] smoke: second starter grant should no-op")
		ok = false
	if get_owned_heroes().size() != 1:
		push_error("[HeroState] smoke: duplicate starter ownership")
		ok = false

	# Viewing progress must not recruit.
	var progress: Dictionary = get_or_create_hero("lorelai")
	if is_hero_owned("lorelai"):
		push_error("[HeroState] smoke: view path recruited lorelai")
		ok = false
	if str(progress.get("id", "")) != "lorelai":
		push_error("[HeroState] smoke: default progress missing")
		ok = false

	# Pool IDs must match first drop.
	var royal_ids: Array = get_tier_config("royal").get("active_hero_ids", [])
	var mythic_ids: Array = get_tier_config("mythic").get("active_hero_ids", [])
	var expected_royal: Array = ["allanna", "tisha", "makenzi", "jas", "josh", "paul", "brady"]
	var expected_mythic: Array = ["maegan", "lorelai", "myshla", "lumi"]
	for id_v: Variant in expected_royal:
		if str(id_v) not in royal_ids:
			push_error("[HeroState] smoke: missing royal id %s" % str(id_v))
			ok = false
	if royal_ids.size() != expected_royal.size():
		push_error("[HeroState] smoke: royal pool size wrong")
		ok = false
	for id_v: Variant in expected_mythic:
		if str(id_v) not in mythic_ids:
			push_error("[HeroState] smoke: missing mythic id %s" % str(id_v))
			ok = false
	if mythic_ids.size() != expected_mythic.size():
		push_error("[HeroState] smoke: mythic pool size wrong")
		ok = false
	if "remi" in royal_ids or "remi" in mythic_ids:
		push_error("[HeroState] smoke: remi must not be in pools")
		ok = false

	# Shard unlock path for non-starter.
	add_hero_shards("lorelai", 7)
	if can_unlock_hero("lorelai"):
		push_error("[HeroState] smoke: 7 shards should not unlock")
		ok = false
	add_hero_shards("lorelai", 3)
	if not can_unlock_hero("lorelai"):
		push_error("[HeroState] smoke: 10 shards should unlock")
		ok = false
	var unlocked: Dictionary = unlock_hero_from_shards("lorelai")
	if not unlocked.get("ok", false) or not is_hero_owned("lorelai"):
		push_error("[HeroState] smoke: unlock_from_shards failed")
		ok = false
	if get_hero_shards("lorelai") < 10:
		push_error("[HeroState] smoke: shards should persist after unlock")
		ok = false

	# Mythic draw on owned Maegan awards shards only; amount is 1, 5, or 10.
	mythic_tickets = 5
	var draw: Dictionary = draw_recruitment("mythic", false)
	if not draw.get("ok", false):
		push_error("[HeroState] smoke: mythic draw failed: %s" % str(draw.get("error", "")))
		ok = false
	else:
		var hid: String = str(draw.get("hero_id", ""))
		if hid not in expected_mythic:
			push_error("[HeroState] smoke: mythic draw outside pool: %s" % hid)
			ok = false
		var amt: int = int(draw.get("shard_amount", 0))
		if amt not in [1, 5, 10]:
			push_error("[HeroState] smoke: invalid shard amount %d" % amt)
			ok = false
		if hid == "maegan" and not bool(draw.get("already_owned", false)):
			push_error("[HeroState] smoke: maegan draw should mark already_owned")
			ok = false
		if get_owned_heroes().size() != 2:
			push_error("[HeroState] smoke: draw must not auto-own a third hero")
			ok = false

	# 10x: ten independent hero + shard rolls.
	mythic_tickets = 20
	var multi: Dictionary = draw_recruitment_multi("mythic", 10)
	if not multi.get("ok", false):
		push_error("[HeroState] smoke: 10x draw failed")
		ok = false
	else:
		var multi_results: Array = multi.get("results", [])
		if multi_results.size() != 10:
			push_error("[HeroState] smoke: expected 10 independent results")
			ok = false
		for item_v: Variant in multi_results:
			if typeof(item_v) != TYPE_DICTIONARY:
				ok = false
				continue
			var item: Dictionary = item_v
			if int(item.get("shard_amount", 0)) not in [1, 5, 10]:
				push_error("[HeroState] smoke: 10x invalid shard amount")
				ok = false
			if str(item.get("hero_id", "")) not in expected_mythic:
				push_error("[HeroState] smoke: 10x hero outside pool")
				ok = false

	# Shard reward table must total 100 weight.
	var shard_chances: Array[Dictionary] = get_shard_reward_chances()
	var shard_weight_sum: int = 0
	for sc: Dictionary in shard_chances:
		shard_weight_sum += int(sc.get("weight", 0))
	if shard_weight_sum != 100:
		push_error("[HeroState] smoke: shard reward weights must total 100")
		ok = false

	# Debug ticket grant (dev builds only).
	if OS.is_debug_build():
		var r0: int = royal_tickets
		var m0: int = mythic_tickets
		var dbg: Dictionary = debug_grant_test_tickets(10, 10)
		if not dbg.get("ok", false):
			push_error("[HeroState] smoke: debug ticket grant failed")
			ok = false
		if royal_tickets != r0 + 10 or mythic_tickets != m0 + 10:
			push_error("[HeroState] smoke: debug grant amounts wrong")
			ok = false
		save_heroes()
		var owned_chk: int = get_owned_heroes().size()
		var shards_chk: Dictionary = hero_shards.duplicate(true)
		load_heroes()
		if royal_tickets < r0 + 10 or mythic_tickets < m0 + 10:
			push_error("[HeroState] smoke: debug tickets did not persist")
			ok = false
		if get_owned_heroes().size() != owned_chk:
			push_error("[HeroState] smoke: debug grant mutated ownership")
			ok = false
		for key: Variant in shards_chk.keys():
			if int(hero_shards.get(key, -1)) != int(shards_chk[key]):
				push_error("[HeroState] smoke: debug grant mutated shards")
				ok = false

	# Persist starter flag + roster.
	save_heroes()
	var owned_before: int = get_owned_heroes().size()
	recruited_heroes.clear()
	_starter_maegan_granted = false
	load_heroes()
	if not is_hero_owned("maegan"):
		push_error("[HeroState] smoke: maegan missing after reload")
		ok = false
	if get_owned_heroes().size() < owned_before:
		push_error("[HeroState] smoke: roster shrunk after reload")
		ok = false
	# Second load must not duplicate maegan.
	var count_maegan: int = 0
	for h: Dictionary in recruited_heroes:
		if str(h.get("id", "")) == "maegan":
			count_maegan += 1
	if count_maegan != 1:
		push_error("[HeroState] smoke: maegan duplicated after reload")
		ok = false

	# Wall defense assignment: persists, blocks marches, removable.
	var wall_set: Dictionary = set_wall_defenders(["maegan"])
	if not bool(wall_set.get("ok", false)):
		push_error("[HeroState] smoke: wall assign maegan failed")
		ok = false
	if not is_hero_wall_defender("maegan"):
		push_error("[HeroState] smoke: maegan not wall defender")
		ok = false
	if is_hero_available_for_march("maegan"):
		push_error("[HeroState] smoke: wall defender must be unavailable for marches")
		ok = false
	var avail_ids: Array[String] = []
	for h2: Dictionary in get_available_heroes():
		avail_ids.append(str(h2.get("id", "")))
	if "maegan" in avail_ids:
		push_error("[HeroState] smoke: get_available_heroes still lists wall defender")
		ok = false
	if get_city_defense_power() <= 0:
		push_error("[HeroState] smoke: city defense power should be > 0")
		ok = false
	save_heroes()
	wall_defender_ids.clear()
	load_heroes()
	if not is_hero_wall_defender("maegan"):
		push_error("[HeroState] smoke: wall defender lost after reload")
		ok = false
	var wall_clear: Dictionary = set_wall_defenders([])
	if not bool(wall_clear.get("ok", false)) or is_hero_wall_defender("maegan"):
		push_error("[HeroState] smoke: wall clear failed")
		ok = false
	if not is_hero_available_for_march("maegan"):
		push_error("[HeroState] smoke: maegan should be available after wall clear")
		ok = false

	if ok:
		print("[HeroState] Hero roster smoke test PASSED")
	end_smoke_isolation()
	return ok
