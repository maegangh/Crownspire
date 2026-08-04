extends Node

## Runtime Alliance Lair instance registry (Phase 5.4).
## Catalog lives in WildlingLairDatabase / wildling_lairs.json.
## Defeat/respawn is client-synced via RallyBackend completion notifications.
## Authority note: encounter resolve still uses Phase 5.3 leader-client combat.

signal lairs_changed
signal lair_defeated(lair_id: String)
signal lair_respawned(lair_id: String)

const SAVE_PATH := "user://alliance_lairs_runtime.cfg"
const SCHEMA_VERSION := 1

var _instances: Dictionary = {} ## lair_id -> runtime dict
var _kingdom_id: String = "kingdom_dev_001"
var _reward_claims: Dictionary = {} ## "rally_id|user" or "solo|march_id" -> true


func _ready() -> void:
	_kingdom_id = _resolve_kingdom_id()
	_load_runtime()
	call_deferred("_bind_rally")


func _process(_delta: float) -> void:
	_tick_respawns()


func clear_spawn_registry() -> void:
	## Called before a fresh map spawn; keeps defeat timers that still apply.
	var keep: Dictionary = {}
	var now: int = int(Time.get_unix_time_from_system())
	for lid in _instances.keys():
		var inst: Dictionary = _instances[lid]
		if not bool(inst.get("active", true)) and int(inst.get("respawn_at", 0)) > now:
			keep[lid] = inst
	_instances = keep


func register_spawned_lair(payload: Dictionary) -> Dictionary:
	var lid: String = str(payload.get("lair_id", "")).strip_edges()
	if lid == "":
		return {"ok": false, "error": "Missing lair_id"}
	var level: int = int(payload.get("lair_level", payload.get("level", 1)))
	var def: Dictionary = {}
	if typeof(payload.get("level_def", null)) == TYPE_DICTIONARY:
		def = (payload.get("level_def", {}) as Dictionary).duplicate(true)
	if def.is_empty():
		def = WildlingLairDatabase.get_level_def(level)
	var max_hp: int = int(payload.get("max_hp", def.get("max_hp", 5000)))
	var now: int = int(Time.get_unix_time_from_system())
	var existing: Dictionary = _instances.get(lid, {}) as Dictionary
	var active: bool = true
	var current_hp: int = max_hp
	var respawn_at: int = 0
	if not existing.is_empty():
		# Preserve defeat/respawn across map reload.
		if not bool(existing.get("active", true)) and int(existing.get("respawn_at", 0)) > now:
			active = false
			current_hp = 0
			respawn_at = int(existing.get("respawn_at", 0))
		elif bool(existing.get("active", true)):
			current_hp = clampi(int(existing.get("current_hp", max_hp)), 0, max_hp)
	var inst := {
		"lair_id": lid,
		"lair_type": str(payload.get("lair_type", def.get("lair_type", "alliance_lair"))),
		"level": level,
		"display_name": str(payload.get("display_name", def.get("display_name", "Alliance Lair"))),
		"kingdom_id": str(payload.get("kingdom_id", _kingdom_id)),
		"world_x": float(payload.get("world_x", payload.get("world_position", {}).get("x", 0.0))),
		"world_y": float(payload.get("world_y", payload.get("world_position", {}).get("y", 0.0))),
		"max_hp": max_hp,
		"current_hp": current_hp if active else 0,
		"recommended_power": int(payload.get("recommended_power", def.get("recommended_power", 0))),
		"difficulty": str(payload.get("difficulty", def.get("difficulty", "Normal"))),
		"rally_required": bool(payload.get("rally_required", def.get("rally_required", true))),
		"reward_table_id": str(payload.get("reward_table_id", def.get("reward_table_id", ""))),
		"respawn_seconds": int(payload.get("respawn_seconds", def.get("respawn_seconds", WildlingLairDatabase.default_respawn_seconds()))),
		"active": active,
		"respawn_at": respawn_at,
		"species": str(payload.get("species", def.get("species", ""))),
		"visual_variant": str(payload.get("visual_variant", def.get("visual_variant", ""))),
		"catalog_id": str(def.get("id", "")),
		"schema_version": SCHEMA_VERSION,
		"level_def": def.duplicate(true),
	}
	_instances[lid] = inst
	_save_runtime()
	lairs_changed.emit()
	return {"ok": true, "lair": inst.duplicate(true)}


func get_lair(lair_id: String) -> Dictionary:
	var lid: String = lair_id.strip_edges()
	if not _instances.has(lid):
		return {}
	return (_instances[lid] as Dictionary).duplicate(true)


func get_all_lairs() -> Array:
	var out: Array = []
	for lid in _instances.keys():
		out.append((_instances[lid] as Dictionary).duplicate(true))
	return out


func is_lair_active(lair_id: String) -> bool:
	var inst: Dictionary = get_lair(lair_id)
	if inst.is_empty():
		return false
	return bool(inst.get("active", false))


func validate_rally_target(lair_id: String) -> Dictionary:
	var lid: String = lair_id.strip_edges()
	if lid == "":
		return {"ok": false, "error": "Missing lair target."}
	if not _instances.has(lid):
		return {"ok": false, "error": "Alliance Lair not found on this kingdom map."}
	var inst: Dictionary = _instances[lid]
	if not bool(inst.get("active", false)):
		var remain: int = maxi(0, int(inst.get("respawn_at", 0)) - int(Time.get_unix_time_from_system()))
		if remain > 0:
			return {"ok": false, "error": "This Alliance Lair is defeated. Respawns in %d:%02d." % [int(remain / 60), remain % 60]}
		return {"ok": false, "error": "This Alliance Lair is inactive."}
	return {"ok": true, "lair": inst.duplicate(true)}


func validate_solo_attack(lair_id: String) -> Dictionary:
	var check: Dictionary = validate_rally_target(lair_id)
	if not bool(check.get("ok", false)):
		return check
	var inst: Dictionary = check.get("lair", {})
	if bool(inst.get("rally_required", true)):
		return {"ok": false, "error": "This Alliance Lair must be attacked by a Rally."}
	return check


func build_ui_payload(lair_id: String) -> Dictionary:
	var inst: Dictionary = get_lair(lair_id)
	if inst.is_empty():
		return {}
	return {
		"lair_id": inst.get("lair_id", ""),
		"lair_type": inst.get("lair_type", "alliance_lair"),
		"target_id": inst.get("lair_id", ""),
		"target_type": "wildling_lair",
		"target_name": "%s Lv.%d" % [str(inst.get("display_name", "Alliance Lair")), int(inst.get("level", 1))],
		"lair_level": int(inst.get("level", 1)),
		"level": int(inst.get("level", 1)),
		"display_name": inst.get("display_name", "Alliance Lair"),
		"kingdom_id": inst.get("kingdom_id", _kingdom_id),
		"world_x": float(inst.get("world_x", 0.0)),
		"world_y": float(inst.get("world_y", 0.0)),
		"world_position": {"x": float(inst.get("world_x", 0.0)), "y": float(inst.get("world_y", 0.0))},
		"x": float(inst.get("world_x", 0.0)),
		"y": float(inst.get("world_y", 0.0)),
		"max_hp": int(inst.get("max_hp", 0)),
		"current_hp": int(inst.get("current_hp", 0)),
		"recommended_power": int(inst.get("recommended_power", 0)),
		"difficulty": str(inst.get("difficulty", "")),
		"rally_required": bool(inst.get("rally_required", true)),
		"reward_table_id": str(inst.get("reward_table_id", "")),
		"respawn_seconds": int(inst.get("respawn_seconds", 120)),
		"active": bool(inst.get("active", false)),
		"species": str(inst.get("species", "")),
		"visual_variant": str(inst.get("visual_variant", "")),
		"creature_title": WildlingLairDatabase.creature_title(inst.get("level_def", {})),
		"level_def": inst.get("level_def", {}),
		"schema_version": SCHEMA_VERSION,
	}


## MVP: victory defeats the entire lair. Defeat does not apply partial HP.
func apply_battle_outcome(lair_id: String, victory: bool, _damage_dealt: int = 0) -> void:
	var lid: String = lair_id.strip_edges()
	if not _instances.has(lid):
		return
	var inst: Dictionary = _instances[lid]
	if not bool(inst.get("active", false)):
		return
	if victory:
		inst["active"] = false
		inst["current_hp"] = 0
		inst["respawn_at"] = int(Time.get_unix_time_from_system()) + int(inst.get("respawn_seconds", 120))
		_instances[lid] = inst
		_save_runtime()
		lair_defeated.emit(lid)
		lairs_changed.emit()
		_refresh_world_node(lid)
	else:
		# Encounter model: defeat leaves lair active at full HP.
		inst["current_hp"] = int(inst.get("max_hp", 0))
		_instances[lid] = inst
		_save_runtime()
		lairs_changed.emit()


func grant_lair_rewards_once(claim_key: String, lair_or_level: Dictionary) -> Dictionary:
	var key: String = claim_key.strip_edges()
	if key == "":
		return {"ok": false, "error": "Missing claim key", "rewards": {}}
	if _reward_claims.has(key):
		return {"ok": true, "duplicate": true, "rewards": {}}
	var level: int = int(lair_or_level.get("level", lair_or_level.get("lair_level", 1)))
	var def: Dictionary = lair_or_level.get("level_def", {}) as Dictionary
	if def.is_empty():
		def = WildlingLairDatabase.get_level_def(level)
	var preview: Dictionary = def.get("reward_preview", {}) as Dictionary
	var granted: Dictionary = {}
	for rk in preview.keys():
		var amount: int = int(preview[rk])
		if amount <= 0:
			continue
		var k: String = str(rk)
		match k:
			"food":
				if has_node("/root/GameState"):
					GameState.add_food(amount)
				granted[k] = amount
			"wood":
				if has_node("/root/GameState"):
					GameState.add_wood(amount)
				granted[k] = amount
			"stone":
				if has_node("/root/GameState"):
					GameState.add_stone(amount)
				granted[k] = amount
			"iron":
				if has_node("/root/GameState"):
					GameState.add_iron(amount)
				granted[k] = amount
			"hero_xp":
				if has_node("/root/HeroState"):
					HeroState.add_hero_xp(amount)
				granted[k] = amount
			"speedup_min":
				# Phase 0A: BagState is the sole inventory authority.
				if has_node("/root/BagState"):
					BagState.add_item("speedup_1m", amount)
				granted[k] = amount
			_:
				if has_node("/root/BagState"):
					BagState.add_item(str(k), amount)
				granted[k] = amount
	_reward_claims[key] = true
	_save_runtime()
	return {"ok": true, "duplicate": false, "rewards": granted}


func _bind_rally() -> void:
	if not has_node("/root/RallyBackend"):
		return
	if not RallyBackend.rally_completed.is_connected(_on_rally_completed):
		RallyBackend.rally_completed.connect(_on_rally_completed)


func _on_rally_completed(rally: Dictionary) -> void:
	var lid: String = str(rally.get("lair_id", ""))
	var result: Dictionary = rally.get("result", {}) as Dictionary
	if lid == "":
		return
	apply_battle_outcome(lid, bool(result.get("victory", false)), int(result.get("damage_dealt", 0)))


func _tick_respawns() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var changed := false
	for lid in _instances.keys():
		var inst: Dictionary = _instances[lid]
		if bool(inst.get("active", true)):
			continue
		var at: int = int(inst.get("respawn_at", 0))
		if at > 0 and now >= at:
			inst["active"] = true
			inst["current_hp"] = int(inst.get("max_hp", 0))
			inst["respawn_at"] = 0
			_instances[lid] = inst
			changed = true
			lair_respawned.emit(str(lid))
			_refresh_world_node(str(lid))
	if changed:
		_save_runtime()
		lairs_changed.emit()


func _refresh_world_node(lair_id: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("wildling_lairs"):
		if node == null or not ("lair_id" in node):
			continue
		if str(node.get("lair_id")) != lair_id:
			continue
		if node.has_method("apply_runtime_state"):
			node.call("apply_runtime_state", get_lair(lair_id))


func _resolve_kingdom_id() -> String:
	if has_node("/root/AllianceBackend") and AllianceBackend.has_method("get_kingdom_id"):
		var kid: String = str(AllianceBackend.get_kingdom_id())
		if kid != "":
			return kid
	if has_node("/root/ChatManager") and ChatManager.has_method("get_kingdom_id"):
		var kid2: String = str(ChatManager.get_kingdom_id())
		if kid2 != "":
			return kid2
	return "kingdom_dev_001"


func get_kingdom_id() -> String:
	_kingdom_id = _resolve_kingdom_id()
	return _kingdom_id


func kingdom_spawn_seed() -> int:
	return int(hash("crownspire_alliance_lairs_v1_" + get_kingdom_id()))


func _save_runtime() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "kingdom_id", _kingdom_id)
	cfg.set_value("meta", "schema_version", SCHEMA_VERSION)
	cfg.set_value("state", "instances", _instances)
	cfg.set_value("state", "reward_claims", _reward_claims)
	cfg.save(SAVE_PATH)


func _load_runtime() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var kid: String = str(cfg.get_value("meta", "kingdom_id", ""))
	if kid != "" and kid != get_kingdom_id():
		# Different kingdom save — ignore instance positions; keep empty for fresh spawn.
		return
	var inst = cfg.get_value("state", "instances", {})
	if typeof(inst) == TYPE_DICTIONARY:
		_instances = inst
	var claims = cfg.get_value("state", "reward_claims", {})
	if typeof(claims) == TYPE_DICTIONARY:
		_reward_claims = claims
