extends Node

## Canonical city construction / building-upgrade queue.
## Default: 1 active construction.
## Paid (future IAP, no payment here):
##   OPTION A — Temporary Secondary Construction Queue ($4.99, 30 days)
##   OPTION B — Permanent Secondary Construction Queue ($9.99)
## Either → construction_queue_limit = 2 (do NOT stack). Max = 2.
##
## Lifecycle:
##   can_start_construction → start_construction (NO level apply)
##   → timer / offline end_unix
##   → complete_construction (ONLY place that applies target level)
##
## Phase 0B1: user://buildings.cfg canonical [building_id] is disk authority.
## GameState *_level fields are derived mirrors.

signal construction_jobs_changed
signal construction_completed(building_id: String, new_level: int)

const SAVE_PATH := "user://construction_queue.cfg"
const BUILDINGS_CFG := "user://buildings.cfg"
const SAVEGAME_PATH := "user://savegame.save"
const BUILDINGS_JSON := "res://data/buildings.json"
const CONSTRUCTION_QUEUE_MAX: int = 2
const TEMP_SECONDARY_CONSTRUCTION_DAYS: int = 30

const META_SECTION := "meta"
const FLAG_AUTHORITY := "buildings_authority_v1"
const FLAG_GAMESTATE := "gamestate_levels_merged_v1"
const FLAG_SAVEGAME := "savegame_building_levels_merged_v1"
const FLAG_LEGACY := "legacy_sections_preserved_v1"
const REPORT_SOFT_CONFLICTS := "soft_conflicts"
const REPORT_QUARANTINE := "quarantine_jobs"
const REPORT_ORPHANS := "orphan_ids"

## Job shape:
## {
##   building_id, from_level, target_level,
##   start_unix, end_unix, total_duration
## }
var active_jobs: Array = []
## Jobs removed from the active queue for review (do not block slots).
var quarantined_jobs: Array = []

var permanent_secondary_construction_queue: bool = false
var temporary_secondary_construction_queue_expires_unix: int = 0
var _save_accum: float = 0.0

## Path overrides for Phase 0B1 self-tests (default = production paths).
var _buildings_path: String = BUILDINGS_CFG
var _queue_path: String = SAVE_PATH
var _savegame_path: String = SAVEGAME_PATH
var _buildings_json_path: String = BUILDINGS_JSON
## Test hook: force post-write verification failure (flags must stay unset).
var _force_verify_fail: bool = false

var _authority_migrated: bool = false
var _gamestate_merged: bool = false
var _savegame_merged: bool = false
var _legacy_preserved: bool = false
var _migration_report: Dictionary = {}
var _catalog_max_cache: Dictionary = {}
var _last_backup_buildings: String = ""
var _last_backup_queue: String = ""


func _ready() -> void:
	refresh_account_save_paths()
	load_construction_state()
	_normalize_loaded_jobs()
	_run_phase0b1_migration_once()
	_migrate_from_building_cfg()
	_resolve_due_jobs()


## Refresh buildings/queue/savegame paths from AccountSavePaths when not in Phase0B1 sandbox.
func refresh_account_save_paths() -> void:
	if str(_buildings_path).begins_with("user://phase0b1_test"):
		return
	if not has_node("/root/AccountSavePaths"):
		_buildings_path = BUILDINGS_CFG
		_queue_path = SAVE_PATH
		_savegame_path = SAVEGAME_PATH
		return
	_buildings_path = AccountSavePaths.path_for("buildings.cfg")
	_queue_path = AccountSavePaths.path_for("construction_queue.cfg")
	_savegame_path = AccountSavePaths.path_for("savegame.save")


func get_buildings_path() -> String:
	return _buildings_path


func get_queue_path() -> String:
	return _queue_path


func _process(delta: float) -> void:
	_tick_jobs(delta)


# =============================================================================
# Phase 0B1 — Authority API
# =============================================================================

func get_canonical_building_level(building_id: String) -> int:
	var bid: String = normalize_building_id(building_id)
	if bid.is_empty():
		return 1
	var save := ConfigFile.new()
	if save.load(_buildings_path) != OK:
		return 1
	if not save.has_section_key(bid, "level"):
		return 1
	var parsed: int = _parse_valid_positive_level(save.get_value(bid, "level", null))
	if parsed < 1:
		return 1
	return _clamp_level_for_building(bid, parsed)


func has_completed_buildings_authority_migration() -> bool:
	return _authority_migrated


func has_completed_savegame_building_migration() -> bool:
	return _savegame_merged


func has_completed_gamestate_building_migration() -> bool:
	return _gamestate_merged


func get_migration_report() -> Dictionary:
	return _migration_report.duplicate(true)


func get_last_backup_paths() -> Dictionary:
	return {
		"buildings": _last_backup_buildings,
		"queue": _last_backup_queue,
	}


## Normalize aliases / display forms to canonical building_id.
func normalize_building_id(raw_id: String) -> String:
	var normalized := raw_id.strip_edges().to_lower().replace(" ", "_")
	if normalized.is_empty():
		return ""
	var aliases := {
		"citadel": "castle",
		"crystal_citadel": "castle",
		"citadel_of_emerald_spires": "castle",
		"citadel_keep": "castle",
		"keep": "castle",
		"lumbermill": "lumber_mill",
		"lumber_yard": "lumber_mill",
		"lumberyard": "lumber_mill",
		"woodmill": "lumber_mill",
		"timber_woodmill": "lumber_mill",
		"stone_quarry": "quarry",
		"slate_quarry": "quarry",
		"ironmine": "iron_mine",
		"deep_iron_shaft": "iron_mine",
		"deep-iron_shaft": "iron_mine",
		"deep_iron": "iron_mine",
		"research_center": "academy",
		"research_building": "academy",
		"research_hall": "academy",
		"research": "academy",
		"medical_tent": "hospital",
		"infirmary": "hospital",
		"sacred_hospital": "hospital",
		"trade_post": "trading_post",
		"vault_warehouse": "warehouse",
		"imperial_embassy": "embassy",
		"wanderers_farm": "farm",
		"grave_sanctuary": "sanctuary",
		"sentry_watchtower": "watchtower",
		"watch_tower": "watchtower",
		"hallofheroes": "hall_of_heroes",
		"infantrybarracks": "infantry_barracks",
		"marksmencamp": "marksmen_camp",
		"cavalrystable": "cavalry_stable",
		"dragonroost": "dragon_roost",
		"runeforge": "rune_forge",
		"valorshine": "valor_shine",
		"valor_shrine": "valor_shine",
		"arcanetower": "arcane_tower",
	}
	if aliases.has(normalized):
		return str(aliases[normalized])
	# Display-name forms commonly used as ConfigFile sections.
	var display := {
		"farm": "farm",
		"lumbermill": "lumber_mill",
		"quarry": "quarry",
		"ironmine": "iron_mine",
		"warehouse": "warehouse",
		"academy": "academy",
		"hospital": "hospital",
		"embassy": "embassy",
		"trading_post": "trading_post",
		"tradingpost": "trading_post",
		"watchtower": "watchtower",
		"watch_tower": "watchtower",
		"hall_of_heroes": "hall_of_heroes",
		"hallofheroes": "hall_of_heroes",
		"infantry_barracks": "infantry_barracks",
		"infantrybarracks": "infantry_barracks",
		"marksmen_camp": "marksmen_camp",
		"marksmencamp": "marksmen_camp",
		"cavalry_stable": "cavalry_stable",
		"cavalrystable": "cavalry_stable",
		"sanctuary": "sanctuary",
		"castle": "castle",
		"wall": "wall",
		"tavern": "tavern",
		"dragon_roost": "dragon_roost",
		"dragonroost": "dragon_roost",
		"rune_forge": "rune_forge",
		"runeforge": "rune_forge",
		"valor_shine": "valor_shine",
		"arcane_tower": "arcane_tower",
		"arcanetower": "arcane_tower",
	}
	# Title-case / spaced section names → snake.
	var spaced := raw_id.strip_edges().to_lower()
	match spaced:
		"farm":
			return "farm"
		"lumber mill", "lumbermill":
			return "lumber_mill"
		"iron mine", "ironmine":
			return "iron_mine"
		"watch tower", "watchtower":
			return "watchtower"
		"hall of heroes":
			return "hall_of_heroes"
		"infantry barracks":
			return "infantry_barracks"
		"marksmen camp":
			return "marksmen_camp"
		"cavalry stable":
			return "cavalry_stable"
		"trading post":
			return "trading_post"
		"dragon roost":
			return "dragon_roost"
		"rune forge":
			return "rune_forge"
		"valor shine", "valor shrine":
			return "valor_shine"
		"arcane tower":
			return "arcane_tower"
		"castle", "citadel keep":
			return "castle"
		"wanderers farm":
			return "farm"
		"sacred hospital":
			return "hospital"
		"grave sanctuary":
			return "sanctuary"
	if display.has(normalized):
		return str(display[normalized])
	return normalized


func get_known_building_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id: String in _catalog_building_ids():
		out.append(id)
	for id: String in _noncatalog_building_ids():
		if out.find(id) < 0:
			out.append(id)
	return out


func _id_list_has(ids: PackedStringArray, building_id: String) -> bool:
	return ids.find(building_id) >= 0


func _catalog_building_ids() -> PackedStringArray:
	return PackedStringArray([
		"castle", "warehouse", "academy", "embassy", "hall_of_heroes", "trading_post",
		"farm", "lumber_mill", "quarry", "iron_mine", "hospital", "sanctuary",
		"infantry_barracks", "marksmen_camp", "cavalry_stable", "watchtower",
	])


func _noncatalog_building_ids() -> PackedStringArray:
	return PackedStringArray([
		"wall", "tavern", "dragon_roost", "rune_forge", "valor_shine", "arcane_tower",
	])


func _is_known_building_id(building_id: String) -> bool:
	var bid: String = normalize_building_id(building_id)
	if bid.is_empty():
		return false
	if _id_list_has(_catalog_building_ids(), bid):
		return true
	return _id_list_has(_noncatalog_building_ids(), bid)


func _gamestate_field_for(building_id: String) -> String:
	var map := {
		"castle": "castle_level",
		"farm": "farm_level",
		"lumber_mill": "lumber_mill_level",
		"quarry": "quarry_level",
		"iron_mine": "iron_mine_level",
		"warehouse": "warehouse_level",
		"academy": "academy_level",
		"hospital": "hospital_level",
		"embassy": "embassy_level",
		"trading_post": "trading_post_level",
		"watchtower": "watchtower_level",
		"hall_of_heroes": "hall_of_heroes_level",
		"infantry_barracks": "infantry_barracks_level",
		"marksmen_camp": "marksmen_camp_level",
		"cavalry_stable": "cavalry_stable_level",
	}
	return str(map.get(building_id, ""))


func _savegame_key_for(building_id: String) -> String:
	# Legacy savegame only persisted a subset.
	var map := {
		"castle": "castle_level",
		"farm": "farm_level",
		"lumber_mill": "lumber_mill_level",
		"quarry": "quarry_level",
		"iron_mine": "iron_mine_level",
		"warehouse": "warehouse_level",
	}
	return str(map.get(building_id, ""))


# =============================================================================
# Phase 0B1 — Transactional migration
# =============================================================================

func _run_phase0b1_migration_once() -> void:
	_load_migration_flags_from_disk()
	if _authority_migrated:
		# Still refresh mirror from disk authority when already migrated.
		_sync_gamestate_mirrors_from_authority()
		return
	var result: Dictionary = _execute_phase0b1_migration()
	if not bool(result.get("ok", false)):
		push_error("[ConstructionState] Phase0B1 migration failed: %s — flags unset; will retry" % str(result.get("reason", "unknown")))
	else:
		print("[ConstructionState] Phase0B1 buildings_authority_v1 committed backups=%s" % str(get_last_backup_paths()))


func _load_migration_flags_from_disk() -> void:
	var save := ConfigFile.new()
	if save.load(_buildings_path) != OK:
		_authority_migrated = false
		_gamestate_merged = false
		_savegame_merged = false
		_legacy_preserved = false
		return
	_authority_migrated = bool(save.get_value(META_SECTION, FLAG_AUTHORITY, false))
	_gamestate_merged = bool(save.get_value(META_SECTION, FLAG_GAMESTATE, false))
	_savegame_merged = bool(save.get_value(META_SECTION, FLAG_SAVEGAME, false))
	_legacy_preserved = bool(save.get_value(META_SECTION, FLAG_LEGACY, false))


func _execute_phase0b1_migration() -> Dictionary:
	var mem_jobs: Array = active_jobs.duplicate(true)
	var mem_quarantine: Array = quarantined_jobs.duplicate(true)
	var mem_perm: bool = permanent_secondary_construction_queue
	var mem_temp: int = temporary_secondary_construction_queue_expires_unix
	var gs_snap: Dictionary = {}
	if has_node("/root/GameState") and GameState.has_method("snapshot_building_level_mirrors"):
		gs_snap = GameState.snapshot_building_level_mirrors()

	_last_backup_buildings = ""
	_last_backup_queue = ""
	_migration_report = {
		"soft_conflicts": [],
		"quarantine_jobs": [],
		"orphan_ids": [],
		"legacy_init": [],
		"completed_levels": {},
	}

	# 1–4. Backups must succeed before any authority write.
	var bak_b: Dictionary = _backup_user_file(_buildings_path)
	if not bool(bak_b.get("ok", false)):
		return _fail_migration("backup_buildings_failed", mem_jobs, mem_quarantine, mem_perm, mem_temp, gs_snap)
	_last_backup_buildings = str(bak_b.get("path", ""))

	var bak_q: Dictionary = _backup_user_file(_queue_path)
	if not bool(bak_q.get("ok", false)):
		return _fail_migration("backup_queue_failed", mem_jobs, mem_quarantine, mem_perm, mem_temp, gs_snap)
	_last_backup_queue = str(bak_q.get("path", ""))

	# 5. Load sources + compute proposal.
	var cfg := ConfigFile.new()
	var cfg_loaded: bool = cfg.load(_buildings_path) == OK
	var savegame_data: Dictionary = _load_savegame_building_levels()
	var savegame_evaluated: bool = bool(savegame_data.get("evaluated", false))
	if not savegame_evaluated:
		return _fail_migration("savegame_eval_failed", mem_jobs, mem_quarantine, mem_perm, mem_temp, gs_snap)

	var proposal: Dictionary = _compute_canonical_levels(cfg, cfg_loaded, savegame_data.get("levels", {}) as Dictionary)
	var completed: Dictionary = proposal.get("completed", {}) as Dictionary
	_migration_report["soft_conflicts"] = proposal.get("soft_conflicts", [])
	_migration_report["orphan_ids"] = proposal.get("orphan_ids", [])
	_migration_report["legacy_init"] = proposal.get("legacy_init", [])
	_migration_report["completed_levels"] = completed.duplicate(true)

	# Job reconcile against verified proposal (in memory first).
	var job_result: Dictionary = _reconcile_jobs_for_migration(completed, proposal.get("trusted", {}) as Dictionary)
	active_jobs = job_result.get("active", []) as Array
	quarantined_jobs = job_result.get("quarantine", []) as Array
	_migration_report["quarantine_jobs"] = quarantined_jobs.duplicate(true)
	_migration_report["stale_removed"] = job_result.get("stale_removed", [])

	# 6–7. Write buildings WITHOUT success flags.
	if not _write_buildings_authority(cfg, cfg_loaded, completed, false):
		return _fail_migration("write_buildings_failed", mem_jobs, mem_quarantine, mem_perm, mem_temp, gs_snap)

	# 8. Persist queue jobs/quarantine only (entitlement fields unchanged in memory).
	if not _save_construction_state_internal():
		return _fail_migration("write_queue_failed", mem_jobs, mem_quarantine, mem_perm, mem_temp, gs_snap)

	# 9. Verify authority levels (flags still false).
	if _force_verify_fail or not _verify_buildings_levels(completed, false):
		return _fail_migration("verify_buildings_failed", mem_jobs, mem_quarantine, mem_perm, mem_temp, gs_snap)

	# 10. Mirror sync.
	if has_node("/root/GameState") and GameState.has_method("apply_building_level_mirrors"):
		GameState.apply_building_level_mirrors(completed)
	else:
		return _fail_migration("gamestate_mirror_missing", mem_jobs, mem_quarantine, mem_perm, mem_temp, gs_snap)

	# 11. Commit flags only after verified write + mirror.
	if not _write_buildings_authority(cfg, true, completed, true):
		return _fail_migration("flag_commit_write_failed", mem_jobs, mem_quarantine, mem_perm, mem_temp, gs_snap)
	if not _verify_buildings_levels(completed, true):
		return _fail_migration("flag_commit_verify_failed", mem_jobs, mem_quarantine, mem_perm, mem_temp, gs_snap)

	_authority_migrated = true
	_gamestate_merged = true
	_savegame_merged = true
	_legacy_preserved = true
	return {"ok": true, "reason": "", "report": _migration_report.duplicate(true)}


func _fail_migration(
	reason: String,
	mem_jobs: Array,
	mem_quarantine: Array,
	mem_perm: bool,
	mem_temp: int,
	gs_snap: Dictionary
) -> Dictionary:
	active_jobs = mem_jobs
	quarantined_jobs = mem_quarantine
	permanent_secondary_construction_queue = mem_perm
	temporary_secondary_construction_queue_expires_unix = mem_temp
	_authority_migrated = false
	_gamestate_merged = false
	_savegame_merged = false
	_legacy_preserved = false
	if has_node("/root/GameState") and GameState.has_method("restore_building_level_mirrors") and not gs_snap.is_empty():
		GameState.restore_building_level_mirrors(gs_snap)
	_migration_report["failure"] = reason
	push_error("[ConstructionState] Phase0B1 abort: %s (flags unset; backups retained)" % reason)
	return {"ok": false, "reason": reason, "report": _migration_report.duplicate(true)}


func _backup_user_file(src_path: String) -> Dictionary:
	if not FileAccess.file_exists(src_path):
		return {"ok": true, "path": "", "absent": true}
	var unix: int = int(Time.get_unix_time_from_system())
	var bak_path: String = "%s.bak_0b1_%d" % [src_path, unix]
	var src := FileAccess.open(src_path, FileAccess.READ)
	if src == null:
		return {"ok": false, "path": "", "reason": "open_src_failed"}
	var data: PackedByteArray = src.get_buffer(src.get_length())
	src.close()
	var dst := FileAccess.open(bak_path, FileAccess.WRITE)
	if dst == null:
		return {"ok": false, "path": "", "reason": "open_dst_failed"}
	dst.store_buffer(data)
	dst.close()
	if not FileAccess.file_exists(bak_path):
		return {"ok": false, "path": "", "reason": "bak_missing_after_write"}
	return {"ok": true, "path": bak_path, "absent": false}


func _load_savegame_building_levels() -> Dictionary:
	var out_levels: Dictionary = {}
	if not FileAccess.file_exists(_savegame_path):
		return {"evaluated": true, "levels": out_levels, "absent": true}
	var file := FileAccess.open(_savegame_path, FileAccess.READ)
	if file == null:
		return {"evaluated": false, "levels": out_levels}
	var content: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		# Corrupt savegame: evaluated=false blocks savegame flag commit.
		return {"evaluated": false, "levels": out_levels}
	var data: Dictionary = parsed as Dictionary
	for bid: String in _catalog_building_ids():
		var key: String = _savegame_key_for(bid)
		if key.is_empty() or not data.has(key):
			continue
		var lv: int = _parse_valid_positive_level(data.get(key, null))
		if lv >= 1:
			out_levels[bid] = _clamp_level_for_building(bid, lv)
	return {"evaluated": true, "levels": out_levels, "absent": false}


func _compute_canonical_levels(cfg: ConfigFile, cfg_loaded: bool, savegame_levels: Dictionary) -> Dictionary:
	var completed: Dictionary = {}
	var trusted: Dictionary = {}
	var soft_conflicts: Array = []
	var orphan_ids: Array = []
	var legacy_init: Array = []

	var sections: PackedStringArray = PackedStringArray()
	if cfg_loaded:
		for s: String in cfg.get_sections():
			sections.append(s)

	# Classify unknown sections (Category D).
	for section: String in sections:
		if section == META_SECTION or section == "orphans":
			continue
		var mapped: String = normalize_building_id(section)
		if _is_known_building_id(mapped) or mapped == section and _is_known_building_id(section):
			continue
		# Section name that does not resolve to a known building.
		if not _is_known_building_id(section) and not _is_known_building_id(mapped):
			orphan_ids.append(section)
			continue
		if mapped != section and not _is_known_building_id(mapped):
			orphan_ids.append(section)

	for bid: String in get_known_building_ids():
		var canon_lv: int = -1
		var has_canonical: bool = false
		if cfg_loaded and cfg.has_section_key(bid, "level"):
			var raw_c: int = _parse_valid_positive_level(cfg.get_value(bid, "level", null))
			if raw_c >= 1:
				canon_lv = _clamp_level_for_building(bid, raw_c)
				has_canonical = true

		var legacy_vals: Array = []
		var legacy_sources: Array = []
		if cfg_loaded:
			for section: String in sections:
				if section == META_SECTION or section == bid or section == "orphans":
					continue
				var mapped: String = normalize_building_id(section)
				if mapped != bid:
					continue
				if not cfg.has_section_key(section, "level"):
					continue
				var lv: int = _parse_valid_positive_level(cfg.get_value(section, "level", null))
				if lv < 1:
					continue
				lv = _clamp_level_for_building(bid, lv)
				legacy_vals.append(lv)
				legacy_sources.append({"section": section, "level": lv})

		var chosen: int = -1
		var is_trusted: bool = false

		if has_canonical:
			chosen = canon_lv
			is_trusted = true
			for entry: Variant in legacy_sources:
				var e: Dictionary = entry as Dictionary
				if int(e.get("level", 0)) > chosen:
					soft_conflicts.append({
						"building_id": bid,
						"kind": "display_above_canonical",
						"canonical": chosen,
						"legacy_section": str(e.get("section", "")),
						"legacy_level": int(e.get("level", 0)),
					})
		elif not legacy_vals.is_empty():
			var max_legacy: int = 1
			for v: Variant in legacy_vals:
				max_legacy = maxi(max_legacy, int(v))
			chosen = max_legacy
			is_trusted = true
			legacy_init.append({
				"building_id": bid,
				"chosen": chosen,
				"sources": legacy_sources,
			})
			if legacy_vals.size() > 1:
				soft_conflicts.append({
					"building_id": bid,
					"kind": "legacy_siblings_disagree",
					"chosen": chosen,
					"sources": legacy_sources,
				})
		else:
			# Soft sources only when no cfg evidence.
			var soft_lv: int = -1
			var soft_from: String = ""
			if has_node("/root/GameState"):
				var field: String = _gamestate_field_for(bid)
				if not field.is_empty() and field in GameState:
					var gsv: int = _parse_valid_positive_level(GameState.get(field))
					if gsv >= 1:
						soft_lv = _clamp_level_for_building(bid, gsv)
						soft_from = "gamestate"
			if savegame_levels.has(bid):
				var sgv: int = int(savegame_levels[bid])
				if sgv >= 1:
					if soft_lv < 0 or sgv > soft_lv:
						soft_lv = _clamp_level_for_building(bid, sgv)
						soft_from = "savegame"
					elif sgv < soft_lv:
						soft_conflicts.append({
							"building_id": bid,
							"kind": "soft_source_disagree",
							"kept": soft_lv,
							"other": sgv,
						})
			if soft_lv >= 1:
				chosen = soft_lv
				is_trusted = true
				legacy_init.append({
					"building_id": bid,
					"chosen": chosen,
					"sources": [{"section": soft_from, "level": chosen}],
				})
			else:
				chosen = 1
				is_trusted = true

		# Soft GameState/savegame higher than cfg evidence → conflict only.
		if has_canonical or not legacy_vals.is_empty():
			if has_node("/root/GameState"):
				var field2: String = _gamestate_field_for(bid)
				if not field2.is_empty() and field2 in GameState:
					var g2: int = _parse_valid_positive_level(GameState.get(field2))
					if g2 >= 1:
						g2 = _clamp_level_for_building(bid, g2)
						if g2 > chosen:
							soft_conflicts.append({
								"building_id": bid,
								"kind": "gamestate_above_cfg",
								"canonical": chosen,
								"gamestate": g2,
							})
			if savegame_levels.has(bid):
				var s2: int = int(savegame_levels[bid])
				if s2 > chosen:
					soft_conflicts.append({
						"building_id": bid,
						"kind": "savegame_above_cfg",
						"canonical": chosen,
						"savegame": s2,
					})

		completed[bid] = chosen
		trusted[bid] = is_trusted

	return {
		"completed": completed,
		"trusted": trusted,
		"soft_conflicts": soft_conflicts,
		"orphan_ids": orphan_ids,
		"legacy_init": legacy_init,
	}


func _reconcile_jobs_for_migration(completed: Dictionary, trusted: Dictionary) -> Dictionary:
	var keep: Array = []
	var quarantine: Array = quarantined_jobs.duplicate(true)
	var stale_removed: Array = []

	for job_v: Variant in active_jobs:
		if typeof(job_v) != TYPE_DICTIONARY:
			quarantine.append({"reason": "non_dict_job", "job": job_v})
			continue
		var job: Dictionary = (job_v as Dictionary).duplicate(true)
		var raw_bid: String = str(job.get("building_id", ""))
		var bid: String = normalize_building_id(raw_bid)
		job["building_id"] = bid
		var from_lv: int = int(job.get("from_level", 0))
		var target_lv: int = int(job.get("target_level", 0))

		if not _is_known_building_id(bid):
			job["quarantine_reason"] = "unknown_building_id"
			quarantine.append(job)
			continue
		if not _is_structurally_valid_job(from_lv, target_lv):
			job["quarantine_reason"] = "invalid_job_structure"
			quarantine.append(job)
			continue

		var completed_lv: int = int(completed.get(bid, 1))
		var is_trusted: bool = bool(trusted.get(bid, false))
		# Soft conflict alone does NOT invalidate canonical trust.
		if not is_trusted:
			job["quarantine_reason"] = "untrusted_completed_level"
			quarantine.append(job)
			continue
		if completed_lv < from_lv:
			job["quarantine_reason"] = "completed_below_from_level"
			quarantine.append(job)
			continue
		if completed_lv >= target_lv:
			# Silent stale removal — no rewards / economy / entitlement changes.
			stale_removed.append(job.duplicate(true))
			continue
		if completed_lv == from_lv:
			keep.append(job)
			continue
		# completed between from and target is impossible when target==from+1;
		# keep quarantine as safety.
		job["quarantine_reason"] = "completed_inconsistent_with_job"
		quarantine.append(job)

	return {
		"active": keep,
		"quarantine": quarantine,
		"stale_removed": stale_removed,
	}


func _is_structurally_valid_job(from_level: int, target_level: int) -> bool:
	if from_level < 1:
		return false
	return target_level == from_level + 1


func _write_buildings_authority(
	base_cfg: ConfigFile,
	cfg_was_loaded: bool,
	completed: Dictionary,
	commit_flags: bool
) -> bool:
	var save := ConfigFile.new()
	if cfg_was_loaded:
		# Reload original disk to preserve legacy sections.
		if save.load(_buildings_path) != OK:
			save = ConfigFile.new()
	elif FileAccess.file_exists(_buildings_path):
		save.load(_buildings_path)

	for bid: String in completed.keys():
		var lv: int = int(completed[bid])
		save.set_value(bid, "level", lv)
		# Do not invent upgrading=true; clear stale upgrading on canonical id only.
		var upgrading: bool = false
		if save.has_section_key(bid, "upgrading"):
			# Keep upgrading true only if an active job remains for this id.
			upgrading = _find_job_index(bid) >= 0
		save.set_value(bid, "upgrading", upgrading)
		if not upgrading:
			save.set_value(bid, "upgrade_finish_time", 0)

	# Preserve orphan review list (Category D) without deleting unknown sections.
	if not (_migration_report.get("orphan_ids", []) as Array).is_empty():
		save.set_value("orphans", "json", JSON.stringify(_migration_report.get("orphan_ids", [])))

	save.set_value(META_SECTION, REPORT_SOFT_CONFLICTS, JSON.stringify(_migration_report.get("soft_conflicts", [])))
	save.set_value(META_SECTION, REPORT_QUARANTINE, JSON.stringify(_migration_report.get("quarantine_jobs", [])))
	save.set_value(META_SECTION, REPORT_ORPHANS, JSON.stringify(_migration_report.get("orphan_ids", [])))

	if commit_flags:
		save.set_value(META_SECTION, FLAG_AUTHORITY, true)
		save.set_value(META_SECTION, FLAG_GAMESTATE, true)
		save.set_value(META_SECTION, FLAG_SAVEGAME, true)
		save.set_value(META_SECTION, FLAG_LEGACY, true)
	else:
		save.set_value(META_SECTION, FLAG_AUTHORITY, false)
		save.set_value(META_SECTION, FLAG_GAMESTATE, false)
		save.set_value(META_SECTION, FLAG_SAVEGAME, false)
		save.set_value(META_SECTION, FLAG_LEGACY, false)

	var err: Error = save.save(_buildings_path)
	return err == OK


func _verify_buildings_levels(completed: Dictionary, expect_flags: bool) -> bool:
	if _force_verify_fail:
		return false
	var save := ConfigFile.new()
	if save.load(_buildings_path) != OK:
		return false
	for bid: String in completed.keys():
		if not save.has_section_key(bid, "level"):
			return false
		var disk_lv: int = _parse_valid_positive_level(save.get_value(bid, "level", null))
		if disk_lv != int(completed[bid]):
			return false
	var f_auth: bool = bool(save.get_value(META_SECTION, FLAG_AUTHORITY, false))
	var f_gs: bool = bool(save.get_value(META_SECTION, FLAG_GAMESTATE, false))
	var f_sg: bool = bool(save.get_value(META_SECTION, FLAG_SAVEGAME, false))
	var f_leg: bool = bool(save.get_value(META_SECTION, FLAG_LEGACY, false))
	if expect_flags:
		return f_auth and f_gs and f_sg and f_leg
	return (not f_auth) and (not f_gs) and (not f_sg) and (not f_leg)


func _sync_gamestate_mirrors_from_authority() -> void:
	if not has_node("/root/GameState"):
		return
	if not GameState.has_method("apply_building_level_mirrors"):
		return
	var levels: Dictionary = {}
	for bid: String in get_known_building_ids():
		var field: String = _gamestate_field_for(bid)
		if field.is_empty():
			continue
		levels[bid] = get_canonical_building_level(bid)
	GameState.apply_building_level_mirrors(levels)


func _parse_valid_positive_level(value: Variant) -> int:
	if value == null:
		return -1
	var t: int = typeof(value)
	if t == TYPE_STRING:
		var s: String = str(value).strip_edges()
		if s.is_empty() or not s.is_valid_int():
			return -1
		var n: int = int(s)
		return n if n >= 1 else -1
	if t == TYPE_INT or t == TYPE_FLOAT:
		var n2: int = int(value)
		return n2 if n2 >= 1 else -1
	return -1


func _clamp_level_for_building(building_id: String, level: int) -> int:
	var bid: String = normalize_building_id(building_id)
	if not _id_list_has(_catalog_building_ids(), bid):
		# Non-catalog: preserve valid positive level; no invented maximum.
		return level
	var max_lv: int = _get_catalog_max_level(bid)
	if max_lv < 1:
		return level
	return clampi(level, 1, max_lv)


func _get_catalog_max_level(building_id: String) -> int:
	var bid: String = normalize_building_id(building_id)
	if _catalog_max_cache.has(bid):
		return int(_catalog_max_cache[bid])
	_ensure_catalog_max_cache()
	return int(_catalog_max_cache.get(bid, 0))


func _ensure_catalog_max_cache() -> void:
	if not _catalog_max_cache.is_empty():
		return
	if not FileAccess.file_exists(_buildings_json_path):
		return
	var file := FileAccess.open(_buildings_json_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var root: Dictionary = parsed as Dictionary
	for bid: String in _catalog_building_ids():
		if not root.has(bid):
			continue
		var entry: Variant = root[bid]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var levels: Variant = (entry as Dictionary).get("levels", {})
		if typeof(levels) != TYPE_DICTIONARY:
			continue
		var max_lv: int = 1
		for key: Variant in (levels as Dictionary).keys():
			var n: int = int(str(key))
			if n > max_lv:
				max_lv = n
		_catalog_max_cache[bid] = max_lv


# =============================================================================
# Entitlement / limits
# =============================================================================

func has_permanent_secondary_construction_queue() -> bool:
	return permanent_secondary_construction_queue


func has_temporary_secondary_construction_queue_active() -> bool:
	if has_permanent_secondary_construction_queue():
		return false
	if temporary_secondary_construction_queue_expires_unix <= 0:
		return false
	return int(Time.get_unix_time_from_system()) < temporary_secondary_construction_queue_expires_unix


func has_secondary_construction_queue() -> bool:
	return has_permanent_secondary_construction_queue() or has_temporary_secondary_construction_queue_active()


func get_construction_queue_limit() -> int:
	if has_secondary_construction_queue():
		return CONSTRUCTION_QUEUE_MAX
	return 1


func grant_permanent_secondary_construction_queue() -> void:
	permanent_secondary_construction_queue = true
	temporary_secondary_construction_queue_expires_unix = 0
	save_construction_state()
	construction_jobs_changed.emit()


func grant_temporary_secondary_construction_queue(days: int = TEMP_SECONDARY_CONSTRUCTION_DAYS) -> void:
	if has_permanent_secondary_construction_queue():
		return
	var now: int = int(Time.get_unix_time_from_system())
	var add_secs: int = maxi(1, days) * 24 * 60 * 60
	var base: int = now
	if temporary_secondary_construction_queue_expires_unix > now:
		base = temporary_secondary_construction_queue_expires_unix
	temporary_secondary_construction_queue_expires_unix = base + add_secs
	save_construction_state()
	construction_jobs_changed.emit()


# =============================================================================
# Queue queries
# =============================================================================

func get_active_construction_jobs() -> Array:
	return active_jobs.duplicate(true)


func get_quarantined_construction_jobs() -> Array:
	return quarantined_jobs.duplicate(true)


func get_used_construction_queues() -> int:
	return active_jobs.size()


func has_free_construction_queue() -> bool:
	return get_used_construction_queues() < get_construction_queue_limit()


func can_start_construction(building_id: String) -> Dictionary:
	var bid: String = normalize_building_id(building_id)
	if bid.is_empty():
		return {"ok": false, "reason": "Invalid building."}
	if _find_job_index(bid) >= 0:
		return {"ok": false, "reason": "Already upgrading."}
	if not has_free_construction_queue():
		return {"ok": false, "reason": "Construction Queue Full"}
	return {"ok": true, "reason": ""}


## Universal cap: non-castle buildings may not exceed completed canonical castle level.
## Uses completed castle level only — an in-progress castle job does not raise the cap.
func check_castle_level_cap(building_id: String, target_level: int) -> Dictionary:
	var bid: String = normalize_building_id(building_id)
	if bid.is_empty():
		return {"ok": false, "reason": "Invalid building."}
	if bid == "castle":
		return {"ok": true, "reason": ""}

	var required_castle: int = maxi(1, int(target_level))
	var castle_level: int = get_canonical_building_level("castle")
	if required_castle > castle_level:
		return {
			"ok": false,
			"reason": (
				"Citadel Keep Lv. %d required (current Lv. %d)."
				% [required_castle, castle_level]
			),
			"required_castle_level": required_castle,
			"current_castle_level": castle_level,
		}
	return {
		"ok": true,
		"reason": "",
		"required_castle_level": required_castle,
		"current_castle_level": castle_level,
	}


func get_job_for(building_id: String) -> Dictionary:
	var idx: int = _find_job_index(normalize_building_id(building_id))
	if idx < 0:
		return {}
	return _job_public_view(active_jobs[idx] as Dictionary)


func is_building_upgrading(building_id: String) -> bool:
	return _find_job_index(normalize_building_id(building_id)) >= 0


func get_remaining_seconds(building_id: String) -> float:
	var job: Dictionary = get_job_for(building_id)
	if job.is_empty():
		return 0.0
	return float(job.get("time_remaining", 0.0))


# =============================================================================
# Lifecycle
# =============================================================================

func start_construction(building_id: String, from_level: int, target_level: int, duration_sec: float) -> Dictionary:
	return try_start_construction(building_id, from_level, target_level, duration_sec)


func try_start_construction(building_id: String, a = null, b = null, c = null) -> Dictionary:
	var bid: String = normalize_building_id(building_id)
	var from_level: int = 1
	var target_level: int = 2
	var duration_sec: float = 30.0

	if c != null:
		from_level = int(a)
		target_level = int(b)
		duration_sec = float(c)
	elif b != null:
		target_level = int(a)
		duration_sec = float(b)
		from_level = maxi(1, target_level - 1)
	else:
		return {"ok": false, "reason": "Invalid start_construction args."}

	var gate: Dictionary = can_start_construction(bid)
	if not bool(gate.get("ok", false)):
		return gate

	var cap: Dictionary = check_castle_level_cap(bid, target_level)
	if not bool(cap.get("ok", false)):
		return {"ok": false, "reason": str(cap.get("reason", "Citadel level too low."))}

	var dur: float = maxf(1.0, duration_sec)
	var now: int = int(Time.get_unix_time_from_system())
	var end_unix: int = now + int(ceil(dur))
	active_jobs.append({
		"building_id": bid,
		"from_level": from_level,
		"target_level": target_level,
		"start_unix": now,
		"end_unix": end_unix,
		"total_duration": dur,
		"time_remaining": float(end_unix - now),
	})
	save_construction_state()
	_sync_resource_manager_flags(bid, true, float(end_unix - now))
	construction_jobs_changed.emit()
	if has_node("/root/GameEvents"):
		GameEvents.emit_building_upgrade_started(bid, target_level)
	return {"ok": true, "reason": "", "end_unix": end_unix}


func finish_construction_now(building_id: String) -> Dictionary:
	var idx: int = _find_job_index(normalize_building_id(building_id))
	if idx < 0:
		return {"ok": false, "reason": "No active construction for this building."}
	return complete_construction(building_id)


func speedup_construction(building_id: String, seconds: int) -> Dictionary:
	var bid: String = normalize_building_id(building_id)
	var idx: int = _find_job_index(bid)
	if idx < 0:
		return {"ok": false, "reason": "No active construction for this building."}
	var sec: int = maxi(0, seconds)
	if sec <= 0:
		return {"ok": false, "reason": "Invalid speedup duration."}

	var job: Dictionary = active_jobs[idx] as Dictionary
	var now: int = int(Time.get_unix_time_from_system())
	var end_unix: int = int(job.get("end_unix", now)) - sec
	job["end_unix"] = end_unix
	job["time_remaining"] = maxf(0.0, float(end_unix - now))
	active_jobs[idx] = job
	save_construction_state()
	_sync_resource_manager_flags(bid, true, float(job["time_remaining"]))
	construction_jobs_changed.emit()

	if end_unix <= now:
		var done: Dictionary = complete_construction(bid)
		done["completed"] = true
		done["remaining"] = 0.0
		return done

	return {
		"ok": true,
		"reason": "",
		"completed": false,
		"remaining": float(job["time_remaining"]),
		"end_unix": end_unix,
	}


func complete_construction(building_id: String) -> Dictionary:
	var idx: int = _find_job_index(normalize_building_id(building_id))
	if idx < 0:
		return {"ok": false, "reason": "No active construction for this building."}
	return _complete_job_at(idx)


func cancel_construction(building_id: String) -> Dictionary:
	var idx: int = _find_job_index(normalize_building_id(building_id))
	if idx < 0:
		return {}
	var job: Dictionary = (active_jobs[idx] as Dictionary).duplicate(true)
	active_jobs.remove_at(idx)
	save_construction_state()
	_sync_resource_manager_flags(str(job.get("building_id", "")), false, 0.0)
	construction_jobs_changed.emit()
	return job


## DEBUG ONLY — restore Citadel Keep to Level 1 for Shift+F9 FTUE retest.
## Touches only castle completed level + any active castle construction job.
## Does not reset other buildings, resources, troops, research, or account identity.
func debug_reset_citadel_for_ftue_retest() -> bool:
	if not OS.is_debug_build():
		push_warning("[ConstructionState] debug_reset_citadel_for_ftue_retest blocked (not a debug build)")
		return false
	var bid: String = "castle"
	if _find_job_index(bid) >= 0:
		cancel_construction(bid)
	_write_building_level(bid, 1)
	_sync_gamestate_mirror_one(bid, 1)
	_notify_city_level(bid, 1)
	_sync_resource_manager_flags(bid, false, 0.0)
	save_construction_state()
	var now_level: int = get_canonical_building_level(bid)
	if now_level != 1:
		push_warning("[ConstructionState] Citadel debug reset failed — canonical level is %d" % now_level)
		return false
	print("[ConstructionState] Debug FTUE retest: Citadel restored to Level 1")
	return true


# =============================================================================
# Tick / offline resolve
# =============================================================================

func _tick_jobs(delta: float) -> void:
	if active_jobs.is_empty():
		return
	_resolve_due_jobs()
	if active_jobs.is_empty():
		return
	var now: int = int(Time.get_unix_time_from_system())
	for i: int in range(active_jobs.size()):
		var job: Dictionary = active_jobs[i]
		var end_unix: int = int(job.get("end_unix", now))
		job["time_remaining"] = maxf(0.0, float(end_unix - now))
		active_jobs[i] = job
	_save_accum += delta
	if _save_accum >= 2.0:
		_save_accum = 0.0
		save_construction_state()


func _resolve_due_jobs() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var due: PackedStringArray = PackedStringArray()
	for job: Variant in active_jobs:
		if typeof(job) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = job as Dictionary
		var end_unix: int = int(d.get("end_unix", 0))
		if end_unix <= 0:
			if float(d.get("time_remaining", 1.0)) <= 0.0:
				due.append(str(d.get("building_id", "")))
		elif now >= end_unix:
			due.append(str(d.get("building_id", "")))
	for bid: String in due:
		var idx: int = _find_job_index(bid)
		if idx >= 0:
			_complete_job_at(idx)


## ONLY place that mutates building level on disk / city nodes with rewards.
func _complete_job_at(idx: int) -> Dictionary:
	if idx < 0 or idx >= active_jobs.size():
		return {"ok": false, "reason": "Invalid job"}
	var job: Dictionary = active_jobs[idx] as Dictionary
	var bid: String = normalize_building_id(str(job.get("building_id", "")))
	var new_level: int = int(job.get("target_level", 1))
	var from_level: int = int(job.get("from_level", maxi(1, new_level - 1)))

	active_jobs.remove_at(idx)
	save_construction_state()

	_write_building_level(bid, new_level)
	_sync_gamestate_mirror_one(bid, new_level)
	_sync_resource_manager_flags(bid, false, 0.0)
	_notify_city_level(bid, new_level)
	construction_completed.emit(bid, new_level)
	construction_jobs_changed.emit()
	if has_node("/root/GameEvents"):
		GameEvents.emit_building_upgraded(bid, new_level)
	return {
		"ok": true,
		"new_level": new_level,
		"from_level": from_level,
		"building_id": bid,
	}


func _job_public_view(job: Dictionary) -> Dictionary:
	var out: Dictionary = job.duplicate(true)
	var now: int = int(Time.get_unix_time_from_system())
	var end_unix: int = int(out.get("end_unix", now))
	out["time_remaining"] = maxf(0.0, float(end_unix - now))
	return out


func _find_job_index(building_id: String) -> int:
	var bid: String = normalize_building_id(building_id)
	for i: int in range(active_jobs.size()):
		if normalize_building_id(str((active_jobs[i] as Dictionary).get("building_id", ""))) == bid:
			return i
	return -1


func _write_building_level(building_id: String, new_level: int) -> void:
	var bid: String = normalize_building_id(building_id)
	var level: int = _clamp_level_for_building(bid, maxi(1, new_level))
	var save := ConfigFile.new()
	save.load(_buildings_path)
	save.set_value(bid, "level", level)
	save.set_value(bid, "upgrading", false)
	save.set_value(bid, "upgrade_finish_time", 0)
	save.save(_buildings_path)


func _sync_gamestate_mirror_one(building_id: String, level: int) -> void:
	if not has_node("/root/GameState"):
		return
	if GameState.has_method("apply_building_level_mirrors"):
		GameState.apply_building_level_mirrors({normalize_building_id(building_id): level})


func _sync_resource_manager_flags(building_id: String, upgrading: bool, duration_sec: float) -> void:
	# Phase 0B3-A: scene-local upgrade status + flags-only persist.
	# Must never change completed building_level or write a completed level to cfg.
	var tree := get_tree()
	if tree == null:
		return
	var scene: Node = tree.current_scene
	if scene == null:
		return
	var bid: String = normalize_building_id(building_id)
	for node: Node in scene.find_children("*", "Node", true, false):
		if node.get("building_id") == null:
			continue
		if normalize_building_id(str(node.get("building_id"))) != bid:
			continue
		if "upgrading" in node:
			node.set("upgrading", upgrading)
		if "upgrade_finish_time" in node:
			if upgrading:
				node.set("upgrade_finish_time", int(Time.get_unix_time_from_system()) + int(ceil(duration_sec)))
			else:
				node.set("upgrade_finish_time", 0)
		# ResourceManager.save_building_level is flags-only (no `level` key) as of 0B3-A.
		if node.has_method("save_building_level"):
			node.call("save_building_level")
		if (not upgrading) and node.has_method("load_building_level"):
			node.call_deferred("load_building_level")
		if (not upgrading) and node.has_method("update_level_label"):
			node.call_deferred("update_level_label")
		break


func _notify_city_level(building_id: String, new_level: int) -> void:
	# Phase 0B3-A: notify City nodes of an already-written canonical level.
	# Does not write buildings.cfg levels, award completion, or emit building_upgraded
	# (those remain owned by _write_building_level / _complete_job_at).
	var tree := get_tree()
	if tree == null:
		return
	tree.call_group("city_buildings", "refresh_level_display")
	var scene: Node = tree.current_scene
	if scene == null:
		return
	var bid: String = normalize_building_id(building_id)
	for node: Node in scene.find_children("*", "Node", true, false):
		if node.get("building_id") != null and normalize_building_id(str(node.get("building_id"))) == bid:
			if "building_level" in node:
				node.set("building_level", new_level)
			if "upgrading" in node:
				node.set("upgrading", false)
			if "upgrade_finish_time" in node:
				node.set("upgrade_finish_time", 0)
			if node.has_method("update_level_label"):
				node.call("update_level_label")
			# Flags-only status persist (no completed-level write) as of 0B3-A.
			if node.has_method("save_building_level"):
				node.call("save_building_level")
			break


func _normalize_loaded_jobs() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	for i: int in range(active_jobs.size()):
		var job: Dictionary = active_jobs[i] as Dictionary
		job["building_id"] = normalize_building_id(str(job.get("building_id", "")))
		if int(job.get("end_unix", 0)) <= 0:
			var rem: float = float(job.get("time_remaining", 60.0))
			var total: float = float(job.get("total_duration", rem))
			job["start_unix"] = now - int(maxi(0, int(total - rem)))
			job["end_unix"] = now + int(ceil(maxf(1.0, rem)))
			if int(job.get("from_level", 0)) <= 0:
				job["from_level"] = maxi(1, int(job.get("target_level", 2)) - 1)
		active_jobs[i] = job


func _migrate_from_building_cfg() -> void:
	if not active_jobs.is_empty():
		return
	var save := ConfigFile.new()
	if save.load(_buildings_path) != OK:
		return
	var now: int = int(Time.get_unix_time_from_system())
	for section: String in save.get_sections():
		if section == META_SECTION or section == "orphans":
			continue
		var upgrading: bool = bool(save.get_value(section, "upgrading", false))
		if not upgrading:
			continue
		var bid: String = normalize_building_id(section)
		if bid.is_empty() or not _is_known_building_id(bid):
			continue
		if _find_job_index(bid) >= 0:
			continue
		var finish: int = int(save.get_value(section, "upgrade_finish_time", 0))
		var lvl: int = int(save.get_value(section, "level", 1))
		if finish <= now:
			finish = now + 60
		active_jobs.append({
			"building_id": bid,
			"from_level": lvl,
			"target_level": lvl + 1,
			"start_unix": now,
			"end_unix": finish,
			"total_duration": float(finish - now),
			"time_remaining": float(finish - now),
		})
	if not active_jobs.is_empty():
		save_construction_state()
		construction_jobs_changed.emit()


func save_construction_state() -> void:
	_save_construction_state_internal()


func _save_construction_state_internal() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(_queue_path)
	# Entitlement metadata: preserve current in-memory values only (Phase 0B1 must not alter policy).
	cfg.set_value("meta", "permanent_secondary_construction_queue", permanent_secondary_construction_queue)
	cfg.set_value("meta", "temporary_secondary_construction_queue_expires_unix", temporary_secondary_construction_queue_expires_unix)
	cfg.set_value("meta", "secondary_construction_queue_owned", has_secondary_construction_queue())
	cfg.set_value("jobs", "json", JSON.stringify(active_jobs))
	cfg.set_value("quarantine", "json", JSON.stringify(quarantined_jobs))
	var err: Error = cfg.save(_queue_path)
	return err == OK


func load_construction_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_queue_path) != OK:
		return
	permanent_secondary_construction_queue = bool(cfg.get_value(
		"meta", "permanent_secondary_construction_queue", false
	))
	temporary_secondary_construction_queue_expires_unix = int(cfg.get_value(
		"meta", "temporary_secondary_construction_queue_expires_unix", 0
	))
	var legacy: bool = bool(cfg.get_value("meta", "secondary_construction_queue_owned", false))
	if legacy and not permanent_secondary_construction_queue and temporary_secondary_construction_queue_expires_unix <= 0:
		if not cfg.has_section_key("meta", "permanent_secondary_construction_queue"):
			permanent_secondary_construction_queue = true
	var jobs_raw: Variant = JSON.parse_string(str(cfg.get_value("jobs", "json", "[]")))
	if typeof(jobs_raw) == TYPE_ARRAY:
		active_jobs = jobs_raw as Array
	var q_raw: Variant = JSON.parse_string(str(cfg.get_value("quarantine", "json", "[]")))
	if typeof(q_raw) == TYPE_ARRAY:
		quarantined_jobs = q_raw as Array


# =============================================================================
# Phase 0B1 self-tests (isolated under user://phase0b1_test/)
# =============================================================================

func debug_run_phase0b1_plan_tests() -> Dictionary:
	var results: Array = []
	var all_ok: bool = true
	var base: String = "user://phase0b1_test"
	_ensure_user_dir(base)

	# Isolate paths for every test.
	var prod_b: String = _buildings_path
	var prod_q: String = _queue_path
	var prod_s: String = _savegame_path
	var prod_jobs: Array = active_jobs.duplicate(true)
	var prod_qjobs: Array = quarantined_jobs.duplicate(true)
	var prod_perm: bool = permanent_secondary_construction_queue
	var prod_temp: int = temporary_secondary_construction_queue_expires_unix
	var prod_flags := [_authority_migrated, _gamestate_merged, _savegame_merged, _legacy_preserved]
	var prod_force: bool = _force_verify_fail

	var gs_snap: Dictionary = {}
	if has_node("/root/GameState") and GameState.has_method("snapshot_building_level_mirrors"):
		gs_snap = GameState.snapshot_building_level_mirrors()

	results.append(_test1_canonical_beats_display(base))
	results.append(_test2_legacy_init_when_absent(base))
	results.append(_test3_display_cannot_undo_upgrade(base))
	results.append(_test4_savegame_cannot_restore(base))
	results.append(_test5_verify_fail_flags_false(base))
	results.append(_test6_stale_job_no_rewards(base))
	results.append(_test7_uncertain_job_quarantine(base))
	results.append(_test8_noncatalog_no_clamp(base))
	results.append(_test9_entitlements_unchanged(base))
	results.append(_test10_cold_savegame_init(base))

	for r: Variant in results:
		if not bool((r as Dictionary).get("ok", false)):
			all_ok = false

	# Restore production state.
	_buildings_path = prod_b
	_queue_path = prod_q
	_savegame_path = prod_s
	active_jobs = prod_jobs
	quarantined_jobs = prod_qjobs
	permanent_secondary_construction_queue = prod_perm
	temporary_secondary_construction_queue_expires_unix = prod_temp
	_authority_migrated = prod_flags[0]
	_gamestate_merged = prod_flags[1]
	_savegame_merged = prod_flags[2]
	_legacy_preserved = prod_flags[3]
	_force_verify_fail = prod_force
	if has_node("/root/GameState") and GameState.has_method("restore_building_level_mirrors"):
		GameState.restore_building_level_mirrors(gs_snap)

	return {
		"ok": all_ok,
		"results": results,
		"backups_seen": _collect_test_backup_names(base),
	}


func _ensure_user_dir(path: String) -> void:
	var abs_path: String = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path)


func _reset_test_sandbox(prefix: String) -> void:
	_buildings_path = "%s/buildings.cfg" % prefix
	_queue_path = "%s/construction_queue.cfg" % prefix
	_savegame_path = "%s/savegame.save" % prefix
	_force_verify_fail = false
	_authority_migrated = false
	_gamestate_merged = false
	_savegame_merged = false
	_legacy_preserved = false
	_migration_report = {}
	_catalog_max_cache.clear()
	active_jobs.clear()
	quarantined_jobs.clear()
	permanent_secondary_construction_queue = false
	temporary_secondary_construction_queue_expires_unix = 0
	_delete_if_exists(_buildings_path)
	_delete_if_exists(_queue_path)
	_delete_if_exists(_savegame_path)


func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_test_buildings(sections: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for section: String in sections.keys():
		var body: Dictionary = sections[section] as Dictionary
		for key: String in body.keys():
			cfg.set_value(section, key, body[key])
	cfg.save(_buildings_path)


func _write_test_queue(jobs: Array, perm: bool = false, temp_exp: int = 0) -> void:
	permanent_secondary_construction_queue = perm
	temporary_secondary_construction_queue_expires_unix = temp_exp
	active_jobs = jobs.duplicate(true)
	_save_construction_state_internal()


func _write_test_savegame(levels: Dictionary) -> void:
	var data: Dictionary = levels.duplicate(true)
	var f := FileAccess.open(_savegame_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _read_flag(flag_key: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(_buildings_path) != OK:
		return false
	return bool(cfg.get_value(META_SECTION, flag_key, false))


func _read_level(bid: String) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(_buildings_path) != OK:
		return -1
	return int(cfg.get_value(bid, "level", -1))


func _collect_test_backup_names(base: String) -> Array:
	var names: Array = []
	var abs_base: String = ProjectSettings.globalize_path(base)
	var dir := DirAccess.open(abs_base)
	if dir == null:
		return names
	dir.list_dir_begin()
	var fn: String = dir.get_next()
	while fn != "":
		if fn.contains(".bak_0b1_"):
			names.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	return names


func _test1_canonical_beats_display(base: String) -> Dictionary:
	var p: String = "%s/t1" % base
	_ensure_user_dir(p)
	_reset_test_sandbox(p)
	_write_test_buildings({
		"farm": {"level": 5, "upgrading": false, "upgrade_finish_time": 0},
		"Farm": {"level": 8, "upgrading": false, "upgrade_finish_time": 0},
	})
	_write_test_queue([])
	var res: Dictionary = _execute_phase0b1_migration()
	var ok: bool = bool(res.get("ok", false)) and _read_level("farm") == 5 and _read_flag(FLAG_AUTHORITY)
	var report: Dictionary = res.get("report", {}) as Dictionary
	var soft: Array = report.get("soft_conflicts", []) as Array
	var has_soft: bool = false
	for s: Variant in soft:
		if str((s as Dictionary).get("kind", "")) == "display_above_canonical":
			has_soft = true
	ok = ok and has_soft and _read_level("Farm") == 8
	return {"id": 1, "name": "canonical_beats_display", "ok": ok, "detail": "farm=%s Farm=%s" % [_read_level("farm"), _read_level("Farm")]}


func _test2_legacy_init_when_absent(base: String) -> Dictionary:
	var p: String = "%s/t2" % base
	_ensure_user_dir(p)
	_reset_test_sandbox(p)
	_write_test_buildings({
		"Farm": {"level": 3},
		"Wanderers Farm": {"level": 4},
	})
	_write_test_queue([])
	var res: Dictionary = _execute_phase0b1_migration()
	var ok: bool = bool(res.get("ok", false)) and _read_level("farm") == 4 and _read_flag(FLAG_AUTHORITY)
	# Second run must not re-raise.
	var res2: Dictionary = _execute_phase0b1_migration()
	# Already flagged path uses _run which skips; simulate by loading flags then execute.
	_load_migration_flags_from_disk()
	ok = ok and _authority_migrated and _read_level("farm") == 4
	ok = ok and _read_level("Farm") == 3
	return {"id": 2, "name": "legacy_init_absent_canonical", "ok": ok, "detail": "farm=%s res2_ok_skip=%s" % [_read_level("farm"), str(_authority_migrated)]}


func _test3_display_cannot_undo_upgrade(base: String) -> Dictionary:
	var p: String = "%s/t3" % base
	_ensure_user_dir(p)
	_reset_test_sandbox(p)
	_write_test_buildings({
		"farm": {"level": 4},
		"Farm": {"level": 4},
	})
	_write_test_queue([])
	var res: Dictionary = _execute_phase0b1_migration()
	if not bool(res.get("ok", false)):
		return {"id": 3, "name": "display_cannot_undo_upgrade", "ok": false, "detail": "migrate_failed"}
	# Simulate real completion write (authority path, no migration rewards).
	_write_building_level("farm", 5)
	_sync_gamestate_mirror_one("farm", 5)
	# Downgrade obsolete display section; re-migration must skip.
	var cfg := ConfigFile.new()
	cfg.load(_buildings_path)
	cfg.set_value("Farm", "level", 4)
	cfg.save(_buildings_path)
	_run_phase0b1_migration_once()
	var ok: bool = _read_level("farm") == 5 and _read_level("Farm") == 4
	return {"id": 3, "name": "display_cannot_undo_upgrade", "ok": ok, "detail": "farm=%s" % _read_level("farm")}


func _test4_savegame_cannot_restore(base: String) -> Dictionary:
	var p: String = "%s/t4" % base
	_ensure_user_dir(p)
	_reset_test_sandbox(p)
	_write_test_buildings({"castle": {"level": 2}})
	_write_test_savegame({"castle_level": 2, "farm_level": 1, "warehouse_level": 1, "lumber_mill_level": 1, "quarry_level": 1, "iron_mine_level": 1})
	_write_test_queue([])
	var res: Dictionary = _execute_phase0b1_migration()
	if not bool(res.get("ok", false)):
		return {"id": 4, "name": "savegame_cannot_restore", "ok": false, "detail": "migrate_failed"}
	_write_building_level("castle", 6)
	_sync_gamestate_mirror_one("castle", 6)
	# Emulate load_game gate.
	var skipped: bool = has_completed_savegame_building_migration()
	if not skipped:
		GameState.castle_level = 2
	var ok: bool = skipped and int(GameState.castle_level) == 6 and _read_level("castle") == 6
	return {"id": 4, "name": "savegame_cannot_restore", "ok": ok, "detail": "castle_disk=%s gs=%s" % [_read_level("castle"), GameState.castle_level]}


func _test5_verify_fail_flags_false(base: String) -> Dictionary:
	var p: String = "%s/t5" % base
	_ensure_user_dir(p)
	_reset_test_sandbox(p)
	_write_test_buildings({"farm": {"level": 2}})
	_write_test_queue([])
	_force_verify_fail = true
	var res: Dictionary = _execute_phase0b1_migration()
	var fail_ok: bool = (not bool(res.get("ok", false))) and (not _read_flag(FLAG_AUTHORITY)) and (not _authority_migrated)
	_force_verify_fail = false
	var res2: Dictionary = _execute_phase0b1_migration()
	var retry_ok: bool = bool(res2.get("ok", false)) and _read_flag(FLAG_AUTHORITY) and _read_level("farm") == 2
	return {"id": 5, "name": "verify_fail_retry", "ok": fail_ok and retry_ok, "detail": "fail=%s retry=%s" % [fail_ok, retry_ok]}


func _test6_stale_job_no_rewards(base: String) -> Dictionary:
	var p: String = "%s/t6" % base
	_ensure_user_dir(p)
	_reset_test_sandbox(p)
	_write_test_buildings({"farm": {"level": 4}})
	var now: int = int(Time.get_unix_time_from_system())
	_write_test_queue([{
		"building_id": "farm",
		"from_level": 3,
		"target_level": 4,
		"start_unix": now - 10,
		"end_unix": now + 9999,
		"total_duration": 10000.0,
		"time_remaining": 9999.0,
	}])
	var upgraded: Array = []
	var cb := func(bid: String, lvl: int) -> void:
		upgraded.append("%s:%d" % [bid, lvl])
	if has_node("/root/GameEvents") and GameEvents.has_signal("building_upgraded"):
		if not GameEvents.building_upgraded.is_connected(cb):
			GameEvents.building_upgraded.connect(cb)
	var res: Dictionary = _execute_phase0b1_migration()
	if has_node("/root/GameEvents") and GameEvents.building_upgraded.is_connected(cb):
		GameEvents.building_upgraded.disconnect(cb)
	var ok: bool = bool(res.get("ok", false)) and active_jobs.is_empty() and upgraded.is_empty() and _read_level("farm") == 4
	var report: Dictionary = res.get("report", {}) as Dictionary
	ok = ok and (report.get("stale_removed", []) as Array).size() == 1
	return {"id": 6, "name": "stale_job_no_rewards", "ok": ok, "detail": "jobs=%d rewards=%d" % [active_jobs.size(), upgraded.size()]}


func _test7_uncertain_job_quarantine(base: String) -> Dictionary:
	var p: String = "%s/t7" % base
	_ensure_user_dir(p)
	_reset_test_sandbox(p)
	_write_test_buildings({"farm": {"level": 2}})
	var now: int = int(Time.get_unix_time_from_system())
	# completed (2) < from (3) → quarantine, not silent delete.
	_write_test_queue([{
		"building_id": "farm",
		"from_level": 3,
		"target_level": 4,
		"start_unix": now,
		"end_unix": now + 500,
		"total_duration": 500.0,
		"time_remaining": 500.0,
	}])
	var res: Dictionary = _execute_phase0b1_migration()
	var ok: bool = bool(res.get("ok", false)) and active_jobs.is_empty() and quarantined_jobs.size() == 1
	ok = ok and str((quarantined_jobs[0] as Dictionary).get("quarantine_reason", "")) == "completed_below_from_level"
	ok = ok and get_used_construction_queues() == 0
	return {"id": 7, "name": "uncertain_job_quarantine", "ok": ok, "detail": "q=%d reason=%s" % [quarantined_jobs.size(), str((quarantined_jobs[0] as Dictionary).get("quarantine_reason", "")) if not quarantined_jobs.is_empty() else ""]}


func _test8_noncatalog_no_clamp(base: String) -> Dictionary:
	var p: String = "%s/t8" % base
	_ensure_user_dir(p)
	_reset_test_sandbox(p)
	_write_test_buildings({
		"wall": {"level": 7},
		"tavern": {"level": 0},
		"dragon_roost": {"level": 12},
	})
	_write_test_queue([])
	var res: Dictionary = _execute_phase0b1_migration()
	var ok: bool = bool(res.get("ok", false)) and _read_level("wall") == 7 and _read_level("dragon_roost") == 12
	# Corrupt/zero tavern rejected as source → defaults to 1, not clamped to 40.
	ok = ok and _read_level("tavern") == 1
	ok = ok and _read_level("wall") != 40
	return {"id": 8, "name": "noncatalog_no_arbitrary_clamp", "ok": ok, "detail": "wall=%s tavern=%s roost=%s" % [_read_level("wall"), _read_level("tavern"), _read_level("dragon_roost")]}


func _test9_entitlements_unchanged(base: String) -> Dictionary:
	var p: String = "%s/t9" % base
	_ensure_user_dir(p)
	_reset_test_sandbox(p)
	_write_test_buildings({"farm": {"level": 1}})
	var exp: int = int(Time.get_unix_time_from_system()) + 86400
	_write_test_queue([], true, exp)
	var before_perm: bool = permanent_secondary_construction_queue
	var before_temp: int = temporary_secondary_construction_queue_expires_unix
	var res: Dictionary = _execute_phase0b1_migration()
	var ok: bool = bool(res.get("ok", false))
	ok = ok and permanent_secondary_construction_queue == before_perm and before_perm == true
	ok = ok and temporary_secondary_construction_queue_expires_unix == before_temp
	# Reload disk and confirm entitlement keys unchanged.
	var cfg := ConfigFile.new()
	cfg.load(_queue_path)
	ok = ok and bool(cfg.get_value("meta", "permanent_secondary_construction_queue", false)) == true
	ok = ok and int(cfg.get_value("meta", "temporary_secondary_construction_queue_expires_unix", 0)) == exp
	return {"id": 9, "name": "entitlements_unchanged", "ok": ok, "detail": "perm=%s temp=%s" % [permanent_secondary_construction_queue, temporary_secondary_construction_queue_expires_unix]}


func _test10_cold_savegame_init(base: String) -> Dictionary:
	var p: String = "%s/t10" % base
	_ensure_user_dir(p)
	_reset_test_sandbox(p)
	# No buildings.cfg at all.
	_write_test_savegame({
		"castle_level": 1,
		"farm_level": 1,
		"lumber_mill_level": 1,
		"quarry_level": 1,
		"iron_mine_level": 1,
		"warehouse_level": 3,
	})
	_write_test_queue([])
	var res: Dictionary = _execute_phase0b1_migration()
	var ok: bool = bool(res.get("ok", false)) and _read_flag(FLAG_SAVEGAME) and _read_level("warehouse") == 3
	ok = ok and int(GameState.warehouse_level) == 3
	return {"id": 10, "name": "cold_savegame_init", "ok": ok, "detail": "warehouse=%s flag=%s" % [_read_level("warehouse"), _read_flag(FLAG_SAVEGAME)]}
