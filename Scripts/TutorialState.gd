extends Node

## Local FTUE / tutorial progress owner.
## Observes GameEvents only — never gates gameplay success.

signal tutorial_started
signal step_changed(step_id: String)
signal step_completed(step_id: String)
signal tutorial_completed
signal tutorial_skipped

const SAVE_PATH := "user://tutorial.cfg"
const SMOKE_SAVE_PATH := "user://tutorial_smoke_test.cfg"
const GRANTS_PATH := "user://tutorial_grants.cfg"
const SMOKE_GRANTS_PATH := "user://tutorial_grants_smoke_test.cfg"
const STEPS_PATH := "res://data/tutorial_ftue.json"
const CURRENT_TUTORIAL_VERSION := 1
## One-time Citadel L2 kit — stored outside tutorial.cfg so ordinary F9 cannot re-farm it.
const CITADEL_KIT_FLAG := "citadel_upgrade_kit_granted_v1"
const CITADEL_KIT_MIN_FOOD := 2020
const CITADEL_KIT_MIN_WOOD := 2020
const CITADEL_KIT_MIN_STONE := 1430
const CITADEL_KIT_MIN_IRON := 840
const CITADEL_OBJECTIVE_STEPS := ["select_building", "start_building_upgrade", "complete_building_upgrade"]
## One-time research kit for Citadel Irrigation I (econ_food_prod_1) — food/wood only.
const RESEARCH_KIT_FLAG := "research_kit_granted_v1"
const RESEARCH_KIT_MIN_FOOD := 200
const RESEARCH_KIT_MIN_WOOD := 150
const RESEARCH_OBJECTIVE_STEPS := ["open_research", "start_research"]
const FTUE_RESEARCH_ID := "econ_food_prod_1"
## One-time Farm collect seed so collect_resources has a valid CollectIcon once.
const FARM_COLLECT_SEED_FLAG := "ftue_farm_collect_seed_v1"
const ResourceManagerScript = preload("res://Scripts/Managers/ResourceManager.gd")

var _save_path_override: String = ""
var _steps: Array[Dictionary] = []
var _step_by_id: Dictionary = {}

var tutorial_version: int = CURRENT_TUTORIAL_VERSION
var ftue_started: bool = false
var ftue_completed: bool = false
var current_step_id: String = ""
var completed_steps: PackedStringArray = PackedStringArray()
var skipped: bool = false

## True when this session loaded with no tutorial.cfg (before any write).
var _was_missing_save: bool = false
var _existing_gameplay_saves_detected: bool = false
var _busy_advancing: bool = false


func _ready() -> void:
	_maybe_enter_smoke_isolation()
	_load_step_definitions()
	load_tutorial_state()
	_connect_game_events()
	_log(
		"Ready | started=%s completed=%s step=%s missing_save=%s gameplay_saves=%s path=%s" % [
			str(ftue_started),
			str(ftue_completed),
			current_step_id if not current_step_id.is_empty() else "(none)",
			str(_was_missing_save),
			str(_existing_gameplay_saves_detected),
			get_save_path(),
		]
	)


func get_save_path() -> String:
	if _save_path_override != "":
		return _save_path_override
	return SAVE_PATH


func _maybe_enter_smoke_isolation() -> void:
	if OS.get_environment("CROWNSPIR_TUTORIAL_SMOKE") == "1":
		begin_smoke_isolation()


func begin_smoke_isolation() -> void:
	_save_path_override = SMOKE_SAVE_PATH
	if FileAccess.file_exists(SMOKE_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SMOKE_SAVE_PATH))
	_reset_runtime_defaults()


func end_smoke_isolation() -> void:
	_save_path_override = ""


# --- Query API (for future TutorialOverlay) -----------------------------------

func is_ftue_active() -> bool:
	return ftue_started and not ftue_completed and not skipped


func is_ftue_complete() -> bool:
	return ftue_completed


func get_current_step_id() -> String:
	return current_step_id


func get_current_step() -> Dictionary:
	if current_step_id.is_empty():
		return {}
	return _step_by_id.get(current_step_id, {}).duplicate(true)


func is_step_completed(step_id: String) -> bool:
	return completed_steps.has(step_id.strip_edges())


func get_tutorial_version() -> int:
	return tutorial_version


func was_first_run_save_missing() -> bool:
	return _was_missing_save


func has_existing_gameplay_saves() -> bool:
	return _existing_gameplay_saves_detected


## Production first-run: only when tutorial save is missing AND gameplay looks fresh.
## Ambiguous / developed accounts → false (favor NOT auto-starting).
func should_auto_start_ftue() -> bool:
	if ftue_started or ftue_completed or skipped:
		return false
	if not _was_missing_save:
		return false
	if not looks_like_fresh_player():
		_log("Auto-start skipped — gameplay does not look fresh")
		return false
	return true


## Conservative fresh-player heuristic from Sprint 1B audit defaults.
func looks_like_fresh_player() -> bool:
	if has_node("/root/GameState"):
		if int(GameState.food) != 1000 or int(GameState.wood) != 1000:
			return false
		if int(GameState.stone) != 1000 or int(GameState.iron) != 1000:
			return false
	if has_node("/root/TroopState"):
		var total: int = int(TroopState.infantry) + int(TroopState.marksmen) + int(TroopState.cavalry)
		if total > 0:
			return false
	if has_node("/root/ResearchState"):
		if not ResearchState.active_jobs.is_empty():
			return false
		if not ResearchState.research_levels.is_empty():
			for v: Variant in ResearchState.research_levels.values():
				if int(v) > 0:
					return false
	if has_node("/root/ConstructionState") and not ConstructionState.active_jobs.is_empty():
		return false
	# Phase 0B2-C: any canonical completed building level > 1 means progressed city.
	# Uses ConstructionState authority only (never display-name sections or job target levels).
	if has_node("/root/ConstructionState") and ConstructionState.has_method("get_known_building_ids") \
			and ConstructionState.has_method("get_canonical_building_level"):
		for bid: String in ConstructionState.get_known_building_ids():
			if int(ConstructionState.get_canonical_building_level(bid)) > 1:
				return false
	return true


## Begin FTUE observation. Safe to call multiple times (idempotent).
func begin_ftue() -> bool:
	if ftue_completed or skipped:
		return false
	if ftue_started and not current_step_id.is_empty():
		_maybe_skip_obsolete_citadel_upgrade_steps()
		_maybe_grant_citadel_kit_for_step(current_step_id)
		_maybe_grant_research_kit_for_step(current_step_id)
		_maybe_seed_ftue_farm_collect_for_step(current_step_id)
		return true
	ftue_started = true
	skipped = false
	if current_step_id.is_empty():
		current_step_id = _first_step_id()
	save_tutorial_state()
	_log("Started FTUE")
	_log("Step: %s" % current_step_id)
	_maybe_skip_obsolete_citadel_upgrade_steps()
	_maybe_grant_citadel_kit_for_step(current_step_id)
	_maybe_grant_research_kit_for_step(current_step_id)
	_maybe_seed_ftue_farm_collect_for_step(current_step_id)
	tutorial_started.emit()
	step_changed.emit(current_step_id)
	return true


## Future Skip Tutorial — marks complete/skipped; grants nothing.
func skip_ftue() -> void:
	if ftue_completed and skipped:
		return
	var prev: String = current_step_id
	ftue_started = true
	ftue_completed = true
	skipped = true
	if not prev.is_empty() and not completed_steps.has(prev):
		# Do not invent completions for unplayed steps — only mark skipped/complete.
		pass
	current_step_id = "ftue_complete"
	if not completed_steps.has("ftue_complete"):
		completed_steps.append("ftue_complete")
	save_tutorial_state()
	_log("FTUE skipped")
	tutorial_skipped.emit()
	tutorial_completed.emit()


## DEBUG ONLY — resets tutorial.cfg progress. Never touches other saves.
## Does NOT clear one-time Citadel/research kit grant flags (no resource farming via F9).
func debug_reset_ftue() -> bool:
	if not OS.is_debug_build():
		push_warning("[TUTORIAL] debug_reset_ftue blocked (not a debug build)")
		return false
	_reset_runtime_defaults()
	var path: String = get_save_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	save_tutorial_state()
	_log("Debug reset FTUE (tutorial save only; kit flags preserved)")
	return true


## DEBUG ONLY — full FTUE retest: restores Citadel to L1 (debug only), clears Citadel +
## research kit flags, tops Citadel minima, resets tutorial progress, and begins FTUE.
## Does not wipe unrelated account saves (other buildings/troops/research/identity).
func debug_full_ftue_retest() -> bool:
	if not OS.is_debug_build():
		push_warning("[TUTORIAL] debug_full_ftue_retest blocked (not a debug build)")
		return false
	if not _debug_prepare_citadel_for_ftue_retest():
		push_warning(
			"[TUTORIAL] Shift+F9 aborted — could not restore Citadel to Level 1. "
			+ "Use a fresh local test profile instead of wiping unrelated account data."
		)
		return false
	_clear_citadel_kit_grant_flag()
	_clear_research_kit_grant_flag()
	_clear_farm_collect_seed_flag()
	_apply_citadel_kit_top_up(true)
	_debug_clear_tutorial_l1_wildling_cooldown()
	if not debug_reset_ftue():
		return false
	var started: bool = begin_ftue()
	_log("Debug full FTUE retest prepared (Citadel L1 + kit flags reset + Citadel resources topped)")
	return started


## DEBUG ONLY — clear only the tutorial Level 1 wildling slot cooldown (not all wildlings).
func _debug_clear_tutorial_l1_wildling_cooldown() -> void:
	if not OS.is_debug_build():
		return
	var wss: Node = get_node_or_null("/root/WildlingSpawnState")
	if wss != null and wss.has_method("debug_clear_tutorial_l1_cooldown"):
		var cleared: bool = bool(wss.call("debug_clear_tutorial_l1_cooldown"))
		_log("Debug cleared tutorial L1 wildling cooldown=%s" % str(cleared))
	var tree := get_tree()
	if tree == null:
		return
	var scene: Node = tree.current_scene
	if scene != null and scene.has_method("debug_respawn_tutorial_l1_if_present"):
		scene.call("debug_respawn_tutorial_l1_if_present")


## DEBUG ONLY — Citadel L1 restore required so Shift+F9 can re-test L1→L2 (not L2→L3).
func _debug_prepare_citadel_for_ftue_retest() -> bool:
	if not OS.is_debug_build():
		return false
	if not has_node("/root/ConstructionState"):
		push_warning("[TUTORIAL] ConstructionState missing — cannot safely reset Citadel")
		return false
	if not ConstructionState.has_method("debug_reset_citadel_for_ftue_retest"):
		push_warning("[TUTORIAL] ConstructionState lacks debug_reset_citadel_for_ftue_retest")
		return false
	return bool(ConstructionState.debug_reset_citadel_for_ftue_retest())


## Idempotent top-up for Citadel L2 affordability. Production skip_ftue never calls this.
func try_grant_citadel_tutorial_resource_kit() -> Dictionary:
	if skipped:
		return {"ok": false, "reason": "skipped"}
	# Never fund a Level 3 purchase when the L2 objective is already satisfied.
	if _citadel_already_meets_ftue_objective():
		return {"ok": false, "reason": "citadel_objective_already_met"}
	if _is_citadel_kit_granted():
		return {"ok": true, "already_granted": true, "granted": {}}
	return _apply_citadel_kit_top_up(true)


func _maybe_grant_citadel_kit_for_step(step_id: String) -> void:
	var sid: String = step_id.strip_edges()
	if not CITADEL_OBJECTIVE_STEPS.has(sid):
		return
	var result: Dictionary = try_grant_citadel_tutorial_resource_kit()
	if bool(result.get("already_granted", false)):
		return
	if bool(result.get("ok", false)) and not bool(result.get("already_granted", false)):
		var granted: Dictionary = result.get("granted", {})
		if not granted.is_empty():
			_log("Citadel tutorial kit granted: %s" % str(granted))


## True when Citadel Keep already satisfies the FTUE "upgrade to Level 2" objective.
func _citadel_already_meets_ftue_objective() -> bool:
	if not has_node("/root/ConstructionState"):
		return false
	if not ConstructionState.has_method("get_canonical_building_level"):
		return false
	return int(ConstructionState.get_canonical_building_level("castle")) >= 2


## Production-safe: if castle is already ≥ L2, do not teach / fund Level 3 as "Level 2".
## Marks Citadel upgrade steps complete and advances to collect_resources.
## Returns true when current_step_id changed.
func reconcile_citadel_ftue_progress() -> bool:
	return _maybe_skip_obsolete_citadel_upgrade_steps()


func _maybe_skip_obsolete_citadel_upgrade_steps() -> bool:
	if skipped or ftue_completed:
		return false
	var sid: String = current_step_id.strip_edges()
	if sid.is_empty() or not CITADEL_OBJECTIVE_STEPS.has(sid):
		return false
	if not _citadel_already_meets_ftue_objective():
		return false
	for step_name: String in CITADEL_OBJECTIVE_STEPS:
		if not completed_steps.has(step_name):
			completed_steps.append(step_name)
	current_step_id = "collect_resources"
	save_tutorial_state()
	_log("Citadel already >= Level 2 — skipped obsolete L2 upgrade steps → collect_resources")
	return true


## Idempotent top-up for Citadel Irrigation I affordability. Production skip_ftue never calls this.
func try_grant_research_tutorial_resource_kit() -> Dictionary:
	if skipped:
		return {"ok": false, "reason": "skipped"}
	if _is_research_kit_granted():
		return {"ok": true, "already_granted": true, "granted": {}}
	return _apply_research_kit_top_up(true)


func _maybe_grant_research_kit_for_step(step_id: String) -> void:
	var sid: String = step_id.strip_edges()
	if not RESEARCH_OBJECTIVE_STEPS.has(sid):
		return
	var result: Dictionary = try_grant_research_tutorial_resource_kit()
	if bool(result.get("already_granted", false)):
		return
	if bool(result.get("ok", false)) and not bool(result.get("already_granted", false)):
		var granted: Dictionary = result.get("granted", {})
		if not granted.is_empty():
			_log("Research tutorial kit granted: %s" % str(granted))


func get_grants_path() -> String:
	if _save_path_override != "" and _save_path_override == SMOKE_SAVE_PATH:
		return SMOKE_GRANTS_PATH
	if OS.get_environment("CROWNSPIR_TUTORIAL_SMOKE") == "1":
		return SMOKE_GRANTS_PATH
	return GRANTS_PATH


func _is_grant_flag_set(flag_key: String) -> bool:
	var cfg := ConfigFile.new()
	var path: String = get_grants_path()
	if not FileAccess.file_exists(path):
		return false
	if cfg.load(path) != OK:
		return false
	return bool(cfg.get_value("grants", flag_key, false))


func _set_grant_flag(flag_key: String, granted: bool) -> void:
	var cfg := ConfigFile.new()
	var path: String = get_grants_path()
	if FileAccess.file_exists(path):
		cfg.load(path)
	cfg.set_value("grants", flag_key, granted)
	var err: Error = cfg.save(path)
	if err != OK:
		push_warning("[TUTORIAL] Failed to save grants %s (err=%d)" % [path, err])


func _is_citadel_kit_granted() -> bool:
	return _is_grant_flag_set(CITADEL_KIT_FLAG)


func _set_citadel_kit_granted(granted: bool) -> void:
	_set_grant_flag(CITADEL_KIT_FLAG, granted)


func _clear_citadel_kit_grant_flag() -> void:
	_set_citadel_kit_granted(false)


func _is_research_kit_granted() -> bool:
	return _is_grant_flag_set(RESEARCH_KIT_FLAG)


func _set_research_kit_granted(granted: bool) -> void:
	_set_grant_flag(RESEARCH_KIT_FLAG, granted)


func _clear_research_kit_grant_flag() -> void:
	_set_research_kit_granted(false)


func _is_farm_collect_seed_granted() -> bool:
	return _is_grant_flag_set(FARM_COLLECT_SEED_FLAG)


func _set_farm_collect_seed_granted(granted: bool) -> void:
	_set_grant_flag(FARM_COLLECT_SEED_FLAG, granted)


func _clear_farm_collect_seed_flag() -> void:
	_set_farm_collect_seed_granted(false)


## Idempotent: ensure Farm stored production meets the CollectIcon visibility threshold.
## Grant flag records that FTUE applied the seed, but must NOT skip re-ensuring the live
## CollectIcon — players can reach collect_resources with the flag set while stored is
## still below threshold (icon stays invisible, spotlight unresolved).
func try_seed_ftue_farm_collect() -> Dictionary:
	if skipped or ftue_completed:
		return {"ok": false, "reason": "skipped_or_completed"}
	var already_granted: bool = _is_farm_collect_seed_granted()
	var save_res: Dictionary = ResourceManagerScript.seed_ftue_farm_collect_in_save()
	if not bool(save_res.get("ok", false)):
		return save_res
	# Refresh live Farm node if City is open (prefer Buildings/Farm over find_child).
	var farm: Node = _find_live_city_farm()
	if farm != null and farm.has_method("seed_ftue_collect_threshold"):
		farm.call("seed_ftue_collect_threshold")
	elif farm != null and farm.has_method("_load_production_state"):
		farm.call("_load_production_state")
		farm.call("_apply_production_elapsed")
		farm.call("_refresh_collect_icon_from_stored")
	if not already_granted:
		_set_farm_collect_seed_granted(true)
		_log("FTUE Farm collect seed applied: %s" % str(save_res))
	elif bool(save_res.get("seeded", false)):
		_log("FTUE Farm collect seed re-applied (icon was not ready): %s" % str(save_res))
	return {
		"ok": true,
		"granted": not already_granted,
		"already_granted": already_granted,
		"details": save_res,
	}


func _find_live_city_farm() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene: Node = tree.current_scene
	if scene != null:
		var under_buildings: Node = scene.get_node_or_null("Buildings/Farm")
		if under_buildings != null:
			return under_buildings
	return tree.root.find_child("Farm", true, false)


func _maybe_seed_ftue_farm_collect_for_step(step_id: String) -> void:
	if step_id.strip_edges() != "collect_resources":
		return
	var result: Dictionary = try_seed_ftue_farm_collect()
	if bool(result.get("already_granted", false)):
		return
	if bool(result.get("ok", false)):
		_log("FTUE Farm collect ready for tutorial")


## Top up each resource only up to kit minima. When mark_granted, persist the one-time flag.
func _apply_citadel_kit_top_up(mark_granted: bool) -> Dictionary:
	if not has_node("/root/GameState"):
		return {"ok": false, "reason": "GameState missing"}
	var granted: Dictionary = {}
	var food_add: int = maxi(0, CITADEL_KIT_MIN_FOOD - int(GameState.food))
	var wood_add: int = maxi(0, CITADEL_KIT_MIN_WOOD - int(GameState.wood))
	var stone_add: int = maxi(0, CITADEL_KIT_MIN_STONE - int(GameState.stone))
	var iron_add: int = maxi(0, CITADEL_KIT_MIN_IRON - int(GameState.iron))
	if food_add > 0:
		GameState.add_food(food_add)
		granted["food"] = food_add
	if wood_add > 0:
		GameState.add_wood(wood_add)
		granted["wood"] = wood_add
	if stone_add > 0:
		GameState.add_stone(stone_add)
		granted["stone"] = stone_add
	if iron_add > 0:
		GameState.add_iron(iron_add)
		granted["iron"] = iron_add
	# add_* already saves; ensure one final persist + HUD signal if nothing was added.
	if granted.is_empty() and GameState.has_method("save_resources"):
		GameState.save_resources()
		if GameState.has_signal("resources_changed"):
			GameState.resources_changed.emit()
	if mark_granted:
		_set_citadel_kit_granted(true)
	return {"ok": true, "already_granted": false, "granted": granted}


## Top up food/wood only for Irrigation I. Never touches stone/iron. Deficit-only.
func _apply_research_kit_top_up(mark_granted: bool) -> Dictionary:
	if not has_node("/root/GameState"):
		return {"ok": false, "reason": "GameState missing"}
	var granted: Dictionary = {}
	var food_add: int = maxi(0, RESEARCH_KIT_MIN_FOOD - int(GameState.food))
	var wood_add: int = maxi(0, RESEARCH_KIT_MIN_WOOD - int(GameState.wood))
	if food_add > 0:
		GameState.add_food(food_add)
		granted["food"] = food_add
	if wood_add > 0:
		GameState.add_wood(wood_add)
		granted["wood"] = wood_add
	if granted.is_empty() and GameState.has_method("save_resources"):
		GameState.save_resources()
		if GameState.has_signal("resources_changed"):
			GameState.resources_changed.emit()
	if mark_granted:
		_set_research_kit_granted(true)
	return {"ok": true, "already_granted": false, "granted": granted}


## Overlay / intro gate — completes intro_welcome only.
func acknowledge_intro() -> bool:
	return advance_if_valid("intro_acknowledged", "")


## Generic advance helper for presentation layer / tests.
func advance_if_valid(event_name: String, target_id: String = "", payload: Dictionary = {}) -> bool:
	return _try_advance_for_event(event_name, target_id, payload)


# --- Persistence --------------------------------------------------------------

func load_tutorial_state() -> void:
	_existing_gameplay_saves_detected = _detect_existing_gameplay_saves()
	var path: String = get_save_path()
	_was_missing_save = not FileAccess.file_exists(path)
	if _was_missing_save:
		_reset_runtime_defaults()
		# Existing gameplay + missing tutorial: initialize safely in memory only.
		# Do not wipe resources/buildings/heroes. Do not auto-begin FTUE.
		if _existing_gameplay_saves_detected:
			_log("Missing tutorial.cfg with existing gameplay saves — safe defaults (FTUE not auto-started)")
		return

	var cfg := ConfigFile.new()
	var err: Error = cfg.load(path)
	if err != OK:
		_reset_runtime_defaults()
		return

	var loaded_version: int = int(cfg.get_value("meta", "tutorial_version", CURRENT_TUTORIAL_VERSION))
	tutorial_version = loaded_version
	ftue_started = bool(cfg.get_value("progress", "ftue_started", false))
	ftue_completed = bool(cfg.get_value("progress", "ftue_completed", false))
	skipped = bool(cfg.get_value("progress", "skipped", false))
	current_step_id = str(cfg.get_value("progress", "current_step_id", ""))
	completed_steps = PackedStringArray()
	var raw_steps: Variant = cfg.get_value("progress", "completed_steps", PackedStringArray())
	if typeof(raw_steps) == TYPE_PACKED_STRING_ARRAY:
		completed_steps = raw_steps
	elif typeof(raw_steps) == TYPE_ARRAY:
		for s: Variant in raw_steps:
			var sid: String = str(s).strip_edges()
			if not sid.is_empty() and not completed_steps.has(sid):
				completed_steps.append(sid)
	elif typeof(raw_steps) == TYPE_STRING:
		# Comma-separated fallback
		for part: String in str(raw_steps).split(",", false):
			var sid2: String = part.strip_edges()
			if not sid2.is_empty() and not completed_steps.has(sid2):
				completed_steps.append(sid2)

	_migrate_if_needed(loaded_version)
	_sanitize_loaded_progress()


func save_tutorial_state() -> void:
	var cfg := ConfigFile.new()
	var path: String = get_save_path()
	if FileAccess.file_exists(path):
		cfg.load(path)
	cfg.set_value("meta", "tutorial_version", tutorial_version)
	cfg.set_value("progress", "ftue_started", ftue_started)
	cfg.set_value("progress", "ftue_completed", ftue_completed)
	cfg.set_value("progress", "skipped", skipped)
	cfg.set_value("progress", "current_step_id", current_step_id)
	cfg.set_value("progress", "completed_steps", Array(completed_steps))
	var err: Error = cfg.save(path)
	if err != OK:
		push_warning("[TUTORIAL] Failed to save %s (err=%d)" % [path, err])


func _migrate_if_needed(loaded_version: int) -> void:
	## Never reset a completed tutorial when fields/version advance.
	if loaded_version >= CURRENT_TUTORIAL_VERSION:
		tutorial_version = CURRENT_TUTORIAL_VERSION
		return
	# v0 / missing → v1: keep completed/skipped flags; repair step pointer only.
	tutorial_version = CURRENT_TUTORIAL_VERSION
	if ftue_completed or skipped:
		if current_step_id.is_empty():
			current_step_id = "ftue_complete"
		save_tutorial_state()
		return
	if ftue_started and (current_step_id.is_empty() or not _step_by_id.has(current_step_id)):
		current_step_id = _first_incomplete_step_id()
	save_tutorial_state()


func _sanitize_loaded_progress() -> void:
	if ftue_completed or skipped:
		if current_step_id.is_empty():
			current_step_id = "ftue_complete"
		return
	if ftue_started:
		if current_step_id.is_empty() or not _step_by_id.has(current_step_id):
			current_step_id = _first_incomplete_step_id()
		elif completed_steps.has(current_step_id) and current_step_id != "ftue_complete":
			current_step_id = _resolve_next_after(current_step_id)


func _reset_runtime_defaults() -> void:
	tutorial_version = CURRENT_TUTORIAL_VERSION
	ftue_started = false
	ftue_completed = false
	current_step_id = ""
	completed_steps = PackedStringArray()
	skipped = false


func _detect_existing_gameplay_saves() -> bool:
	var paths: PackedStringArray = PackedStringArray([
		"user://resources.cfg",
		"user://buildings.cfg",
		"user://troops.cfg",
		"user://heroes.cfg",
		"user://quests.cfg",
		"user://research_queue.cfg",
		"user://construction_queue.cfg",
		"user://marches.cfg",
		"user://alliance.cfg",
		"user://bag.cfg",
	])
	for p: String in paths:
		if FileAccess.file_exists(p):
			return true
	return false


# --- Step definitions ---------------------------------------------------------

func _load_step_definitions() -> void:
	_steps.clear()
	_step_by_id.clear()
	if not FileAccess.file_exists(STEPS_PATH):
		push_error("[TUTORIAL] Missing step data: %s" % STEPS_PATH)
		return
	var file := FileAccess.open(STEPS_PATH, FileAccess.READ)
	if file == null:
		push_error("[TUTORIAL] Could not open %s" % STEPS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[TUTORIAL] tutorial_ftue.json must be a Dictionary")
		return
	var root: Dictionary = parsed
	var arr: Array = root.get("steps", []) as Array
	arr.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int((a as Dictionary).get("order", 0)) < int((b as Dictionary).get("order", 0))
	)
	for item: Variant in arr:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = (item as Dictionary).duplicate(true)
		var sid: String = str(step.get("step_id", "")).strip_edges()
		if sid.is_empty():
			continue
		_steps.append(step)
		_step_by_id[sid] = step


func _first_step_id() -> String:
	if _steps.is_empty():
		return ""
	return str(_steps[0].get("step_id", ""))


func _first_incomplete_step_id() -> String:
	for step: Dictionary in _steps:
		var sid: String = str(step.get("step_id", ""))
		if sid == "ftue_complete":
			continue
		if not completed_steps.has(sid):
			return sid
	return "ftue_complete"


func _resolve_next_after(step_id: String) -> String:
	var step: Dictionary = _step_by_id.get(step_id, {})
	var nxt: String = str(step.get("next_step_id", "")).strip_edges()
	if nxt.is_empty():
		return "ftue_complete"
	return nxt


# --- GameEvents subscriptions -------------------------------------------------

func _connect_game_events() -> void:
	if not has_node("/root/GameEvents"):
		return
	var ge: Node = GameEvents
	_safe_connect(ge, "building_selected", _on_building_selected)
	_safe_connect(ge, "building_upgrade_started", _on_building_upgrade_started)
	_safe_connect(ge, "building_upgraded", _on_building_upgraded)
	_safe_connect(ge, "research_started", _on_research_started)
	_safe_connect(ge, "research_completed", _on_research_completed)
	_safe_connect(ge, "troop_training_started", _on_troop_training_started)
	_safe_connect(ge, "troop_training_completed", _on_troop_training_completed)
	_safe_connect(ge, "world_opened", _on_world_opened)
	_safe_connect(ge, "wildling_selected", _on_wildling_selected)
	_safe_connect(ge, "march_dispatched", _on_march_dispatched)
	_safe_connect(ge, "wildling_defeated", _on_wildling_defeated)
	_safe_connect(ge, "resource_tile_selected", _on_resource_tile_selected)
	_safe_connect(ge, "gathering_started", _on_gathering_started)
	_safe_connect(ge, "gathering_completed", _on_gathering_completed)
	_safe_connect(ge, "alliance_opened", _on_alliance_opened)
	_safe_connect(ge, "resource_collected", _on_resource_collected)


func _safe_connect(ge: Node, signal_name: StringName, callable: Callable) -> void:
	if not ge.has_signal(signal_name):
		push_warning("[TUTORIAL] GameEvents missing signal: %s" % str(signal_name))
		return
	if not ge.is_connected(signal_name, callable):
		ge.connect(signal_name, callable)


func _on_building_selected(building_id: String) -> void:
	_try_advance_for_event("building_selected", building_id)


func _on_building_upgrade_started(building_id: String, _target_level: int) -> void:
	_try_advance_for_event("building_upgrade_started", building_id)


func _on_building_upgraded(building_id: String, _level: int) -> void:
	_try_advance_for_event("building_upgraded", building_id)


func _on_research_started(research_id: String) -> void:
	_try_advance_for_event("research_started", research_id)


func _on_research_completed(research_id: String) -> void:
	_try_advance_for_event("research_completed", research_id)


func _on_troop_training_started(troop_type: String, _tier: int, _amount: int) -> void:
	_try_advance_for_event("troop_training_started", troop_type)


func _on_troop_training_completed(troop_type: String, _tier: int, _amount: int) -> void:
	_try_advance_for_event("troop_training_completed", troop_type)


func _on_world_opened() -> void:
	_try_advance_for_event("world_opened")


func _on_wildling_selected(wildling_id: String) -> void:
	_try_advance_for_event("wildling_selected", wildling_id)


func _on_march_dispatched(march_data: Dictionary) -> void:
	var mtype: String = str(march_data.get("march_type", ""))
	_try_advance_for_event("march_dispatched", mtype, march_data)


func _on_wildling_defeated(wildling_id: String) -> void:
	_try_advance_for_event("wildling_defeated", wildling_id)


func _on_resource_tile_selected(resource_type: String) -> void:
	_try_advance_for_event("resource_tile_selected", resource_type)


func _on_gathering_started(resource_type: String) -> void:
	_try_advance_for_event("gathering_started", resource_type)


func _on_gathering_completed(resource_type: String, _amount: int) -> void:
	_try_advance_for_event("gathering_completed", resource_type)


func _on_alliance_opened() -> void:
	_try_advance_for_event("alliance_opened")


func _on_resource_collected(resource_type: String, _amount: int) -> void:
	_try_advance_for_event("resource_collected", resource_type)


# --- Progression engine -------------------------------------------------------

func _try_advance_for_event(event_name: String, target_id: String = "", payload: Dictionary = {}) -> bool:
	if not is_ftue_active():
		return false
	if _busy_advancing:
		return false
	var step: Dictionary = get_current_step()
	if step.is_empty():
		return false
	var sid: String = str(step.get("step_id", ""))
	if sid.is_empty() or sid == "ftue_complete":
		return false
	if completed_steps.has(sid):
		# Already done — snap forward once, never multi-skip on one event.
		_busy_advancing = true
		current_step_id = _resolve_next_after(sid)
		save_tutorial_state()
		_busy_advancing = false
		step_changed.emit(current_step_id)
		return false

	var expected: String = str(step.get("expected_event", "")).strip_edges()
	if expected.is_empty() or expected != event_name:
		return false
	if not _target_matches(step, target_id, payload):
		return false

	_complete_current_step()
	return true


func _target_matches(step: Dictionary, target_id: String, payload: Dictionary) -> bool:
	var expected_march: String = str(step.get("expected_march_type", "")).strip_edges()
	if not expected_march.is_empty():
		var mtype: String = str(payload.get("march_type", target_id)).strip_edges()
		if mtype != expected_march:
			return false

	var expected_target: String = str(step.get("expected_target_id", "")).strip_edges()
	if expected_target.is_empty():
		return true
	var tid: String = target_id.strip_edges().to_lower()
	if tid.is_empty() and typeof(payload.get("building_id", null)) != TYPE_NIL:
		tid = str(payload.get("building_id", "")).strip_edges().to_lower()
	for part: String in expected_target.split("|", false):
		if tid == part.strip_edges().to_lower():
			return true
	return false


func _complete_current_step() -> void:
	_busy_advancing = true
	var sid: String = current_step_id
	if sid.is_empty() or completed_steps.has(sid):
		_busy_advancing = false
		return

	completed_steps.append(sid)
	_log("Completed: %s" % sid)
	step_completed.emit(sid)

	var nxt: String = _resolve_next_after(sid)
	if nxt.is_empty() or nxt == "ftue_complete":
		current_step_id = "ftue_complete"
		if not completed_steps.has("ftue_complete"):
			completed_steps.append("ftue_complete")
		ftue_completed = true
		save_tutorial_state()
		_log("Next: ftue_complete")
		_log("FTUE complete")
		step_changed.emit(current_step_id)
		tutorial_completed.emit()
		_busy_advancing = false
		return

	current_step_id = nxt
	save_tutorial_state()
	_log("Next: %s" % current_step_id)
	if _maybe_skip_obsolete_citadel_upgrade_steps():
		_log("Next (after Citadel skip): %s" % current_step_id)
	_maybe_grant_citadel_kit_for_step(current_step_id)
	_maybe_grant_research_kit_for_step(current_step_id)
	_maybe_seed_ftue_farm_collect_for_step(current_step_id)
	step_changed.emit(current_step_id)
	_busy_advancing = false


func _log(message: String) -> void:
	print("[TUTORIAL] %s" % message)
