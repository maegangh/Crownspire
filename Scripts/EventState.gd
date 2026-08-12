extends Node

## Crownspire live-event framework (local / beta).
## Persist: user://events.cfg
## First event: Royal Ascension (data/events/royal_ascension.json).

signal event_changed
signal points_awarded(event_id: String, points: int, reason: String, total: int)
signal milestone_claimed(event_id: String, threshold: int)

const SAVE_PATH: String = "user://events.cfg"
const SMOKE_SAVE_PATH: String = "user://events_smoke_test.cfg"
const DEFS_DIR: String = "res://data/events/"
const STATUS_INACTIVE: String = "INACTIVE"
const STATUS_ACTIVE: String = "ACTIVE"
const STATUS_ENDED: String = "ENDED"

var _save_path_override: String = ""
## Runtime progress for the current local event instance.
var _progress: Dictionary = {}
## Cached event definitions by id.
var _defs: Dictionary = {}


func _ready() -> void:
	_load_all_defs()
	load_events()
	_connect_gameplay_signals()
	call_deferred("_tick_expiration")


func _process(_delta: float) -> void:
	_tick_expiration()


func get_save_path() -> String:
	if _save_path_override != "":
		return _save_path_override
	if has_node("/root/AccountSavePaths"):
		return AccountSavePaths.path_for("events.cfg")
	return SAVE_PATH


# --- Public API ---

func get_event_status() -> String:
	_tick_expiration()
	return str(_progress.get("status", STATUS_INACTIVE))


func get_current_event_id() -> String:
	return str(_progress.get("event_id", ""))


func is_event_active(event_id: String = "") -> bool:
	_tick_expiration()
	if str(_progress.get("status", STATUS_INACTIVE)) != STATUS_ACTIVE:
		return false
	if event_id != "" and str(_progress.get("event_id", "")) != event_id:
		return false
	return true


func get_active_event() -> Dictionary:
	_tick_expiration()
	if str(_progress.get("status", STATUS_INACTIVE)) == STATUS_INACTIVE:
		return {}
	var eid: String = str(_progress.get("event_id", ""))
	var def: Dictionary = get_event_definition(eid)
	return {
		"event_id": eid,
		"status": str(_progress.get("status", STATUS_INACTIVE)),
		"start_unix": int(_progress.get("start_unix", 0)),
		"end_unix": int(_progress.get("end_unix", 0)),
		"points": int(_progress.get("points", 0)),
		"claimed_milestones": (_progress.get("claimed_milestones", []) as Array).duplicate(),
		"definition": def.duplicate(true),
	}


func get_points(event_id: String = "") -> int:
	if event_id != "" and str(_progress.get("event_id", "")) != event_id:
		return 0
	return int(_progress.get("points", 0))


func get_time_remaining(event_id: String = "") -> int:
	_tick_expiration()
	if event_id != "" and str(_progress.get("event_id", "")) != event_id:
		return 0
	if str(_progress.get("status", "")) != STATUS_ACTIVE:
		return 0
	var end_unix: int = int(_progress.get("end_unix", 0))
	return maxi(0, end_unix - int(Time.get_unix_time_from_system()))


func get_event_definition(event_id: String) -> Dictionary:
	if _defs.has(event_id):
		return (_defs[event_id] as Dictionary).duplicate(true)
	return {}


func list_event_definitions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key: Variant in _defs.keys():
		out.append((_defs[key] as Dictionary).duplicate(true))
	return out


func has_unclaimed_milestones(event_id: String = "") -> bool:
	var snap: Dictionary = get_active_event()
	if snap.is_empty():
		# Ended events may still have claimable rewards.
		if str(_progress.get("status", "")) != STATUS_ENDED:
			return false
		if event_id != "" and str(_progress.get("event_id", "")) != event_id:
			return false
		snap = {
			"event_id": str(_progress.get("event_id", "")),
			"points": int(_progress.get("points", 0)),
			"claimed_milestones": (_progress.get("claimed_milestones", []) as Array).duplicate(),
			"definition": get_event_definition(str(_progress.get("event_id", ""))),
		}
	elif event_id != "" and str(snap.get("event_id", "")) != event_id:
		return false
	var def: Dictionary = snap.get("definition", {}) as Dictionary
	var points: int = int(snap.get("points", 0))
	var claimed: Array = snap.get("claimed_milestones", []) as Array
	for m: Variant in def.get("milestones", []):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var th: int = int((m as Dictionary).get("threshold", 0))
		if points >= th and int(th) not in claimed:
			return true
	return false


func get_milestone_states(event_id: String = "") -> Array[Dictionary]:
	var eid: String = event_id if event_id != "" else str(_progress.get("event_id", ""))
	var def: Dictionary = get_event_definition(eid)
	var points: int = get_points(eid) if eid == str(_progress.get("event_id", "")) else 0
	if eid == str(_progress.get("event_id", "")):
		points = int(_progress.get("points", 0))
	var claimed: Array = []
	if eid == str(_progress.get("event_id", "")):
		claimed = _progress.get("claimed_milestones", []) as Array
	var out: Array[Dictionary] = []
	for m: Variant in def.get("milestones", []):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = m as Dictionary
		var th: int = int(md.get("threshold", 0))
		var state: String = "LOCKED"
		if int(th) in claimed:
			state = "CLAIMED"
		elif points >= th:
			state = "AVAILABLE"
		out.append({
			"threshold": th,
			"state": state,
			"rewards": (md.get("rewards", []) as Array).duplicate(true),
		})
	return out


func claim_milestone(threshold: int, event_id: String = "") -> Dictionary:
	var eid: String = event_id if event_id != "" else str(_progress.get("event_id", ""))
	if eid == "" or eid != str(_progress.get("event_id", "")):
		return {"ok": false, "error": "No matching event progress."}
	var status: String = str(_progress.get("status", STATUS_INACTIVE))
	if status != STATUS_ACTIVE and status != STATUS_ENDED:
		return {"ok": false, "error": "Event is not claimable."}
	var points: int = int(_progress.get("points", 0))
	if points < threshold:
		return {"ok": false, "error": "Milestone not reached."}
	var claimed: Array = _progress.get("claimed_milestones", []) as Array
	if typeof(claimed) != TYPE_ARRAY:
		claimed = []
	if int(threshold) in claimed:
		return {"ok": false, "error": "Already claimed."}
	var def: Dictionary = get_event_definition(eid)
	var rewards: Array = []
	for m: Variant in def.get("milestones", []):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if int((m as Dictionary).get("threshold", 0)) == threshold:
			rewards = (m as Dictionary).get("rewards", []) as Array
			break
	if rewards.is_empty():
		return {"ok": false, "error": "Milestone rewards missing."}
	_grant_rewards(rewards)
	claimed.append(int(threshold))
	_progress["claimed_milestones"] = claimed
	save_events()
	milestone_claimed.emit(eid, threshold)
	event_changed.emit()
	return {"ok": true, "threshold": threshold, "rewards": rewards.duplicate(true)}


# --- Debug (debug builds only) ---

func debug_start_event(event_id: String = "royal_ascension") -> Dictionary:
	if not OS.is_debug_build():
		return {"ok": false, "error": "Debug only."}
	return _start_event(event_id, true)


func debug_reset_event() -> Dictionary:
	if not OS.is_debug_build():
		return {"ok": false, "error": "Debug only."}
	_progress = {
		"event_id": "",
		"status": STATUS_INACTIVE,
		"start_unix": 0,
		"end_unix": 0,
		"points": 0,
		"claimed_milestones": [],
	}
	save_events()
	event_changed.emit()
	return {"ok": true}


func debug_add_points(amount: int = 1000) -> Dictionary:
	if not OS.is_debug_build():
		return {"ok": false, "error": "Debug only."}
	if not is_event_active():
		return {"ok": false, "error": "No active event."}
	_award_points(maxi(0, amount), "debug")
	return {"ok": true, "points": get_points()}


# --- Scoring ---

func _connect_gameplay_signals() -> void:
	if not has_node("/root/GameEvents"):
		return
	if not GameEvents.building_upgraded.is_connected(_on_building_upgraded):
		GameEvents.building_upgraded.connect(_on_building_upgraded)
	if not GameEvents.research_completed.is_connected(_on_research_completed):
		GameEvents.research_completed.connect(_on_research_completed)
	if not GameEvents.troop_training_completed.is_connected(_on_troop_training_completed):
		GameEvents.troop_training_completed.connect(_on_troop_training_completed)
	if not GameEvents.wildling_defeated.is_connected(_on_wildling_defeated):
		GameEvents.wildling_defeated.connect(_on_wildling_defeated)
	if not GameEvents.gathering_completed.is_connected(_on_gathering_completed):
		GameEvents.gathering_completed.connect(_on_gathering_completed)
	if GameEvents.has_signal("speedup_used") and not GameEvents.speedup_used.is_connected(_on_speedup_used):
		GameEvents.speedup_used.connect(_on_speedup_used)


func _on_building_upgraded(_building_id: String, _level: int) -> void:
	_score_flat("building_upgraded")


func _on_research_completed(_research_id: String = "") -> void:
	_score_flat("research_completed")


func _on_troop_training_completed(_troop_type: String, _tier: int, amount: int) -> void:
	if not is_event_active():
		return
	var rule: Dictionary = _scoring_rule("troop_training_completed")
	var per_100: int = int(rule.get("points_per_100_troops", 150))
	var pts: int = int((maxi(0, amount) * per_100) / 100)
	if pts > 0:
		_award_points(pts, "troop_training_completed")


func _on_wildling_defeated(_wildling_id: String = "") -> void:
	_score_flat("wildling_defeated")


func _on_gathering_completed(_resource_type: String, amount: int) -> void:
	if not is_event_active():
		return
	var rule: Dictionary = _scoring_rule("gathering_completed")
	var per_1000: int = int(rule.get("points_per_1000_resources", 10))
	var pts: int = int(maxi(0, amount) / 1000) * per_1000
	if pts > 0:
		_award_points(pts, "gathering_completed")


func _on_speedup_used(_category: String, seconds_actual: int) -> void:
	if not is_event_active():
		return
	var rule: Dictionary = _scoring_rule("speedup_used")
	var per_min: int = int(rule.get("points_per_minute", 1))
	var minutes: int = int(maxi(0, seconds_actual) / 60)
	var pts: int = minutes * per_min
	if pts > 0:
		_award_points(pts, "speedup_used")


func _score_flat(rule_key: String) -> void:
	if not is_event_active():
		return
	var rule: Dictionary = _scoring_rule(rule_key)
	var pts: int = int(rule.get("points", 0))
	if pts > 0:
		_award_points(pts, rule_key)


func _scoring_rule(rule_key: String) -> Dictionary:
	var def: Dictionary = get_event_definition(str(_progress.get("event_id", "")))
	var scoring: Dictionary = def.get("scoring", {}) as Dictionary
	var rule: Variant = scoring.get(rule_key, {})
	if typeof(rule) == TYPE_DICTIONARY:
		return rule as Dictionary
	return {}


func _award_points(points: int, reason: String) -> void:
	if points <= 0:
		return
	if str(_progress.get("status", "")) != STATUS_ACTIVE:
		return
	_progress["points"] = int(_progress.get("points", 0)) + points
	save_events()
	var eid: String = str(_progress.get("event_id", ""))
	var total: int = int(_progress.get("points", 0))
	points_awarded.emit(eid, points, reason, total)
	event_changed.emit()


# --- Lifecycle ---

func _start_event(event_id: String, force_debug: bool = false) -> Dictionary:
	var def: Dictionary = get_event_definition(event_id)
	if def.is_empty():
		return {"ok": false, "error": "Unknown event definition."}
	var hours: float = float(def.get("duration_hours", 24))
	var now: int = int(Time.get_unix_time_from_system())
	_progress = {
		"event_id": event_id,
		"status": STATUS_ACTIVE,
		"start_unix": now,
		"end_unix": now + int(ceil(hours * 3600.0)),
		"points": 0,
		"claimed_milestones": [],
	}
	save_events()
	event_changed.emit()
	if force_debug:
		print("[EventState] DEBUG started %s for %.1fh" % [event_id, hours])
	return {"ok": true, "event": get_active_event()}


func _tick_expiration() -> void:
	if str(_progress.get("status", "")) != STATUS_ACTIVE:
		return
	var end_unix: int = int(_progress.get("end_unix", 0))
	if end_unix <= 0:
		return
	if int(Time.get_unix_time_from_system()) >= end_unix:
		_progress["status"] = STATUS_ENDED
		save_events()
		event_changed.emit()


# --- Rewards ---

func _grant_rewards(rewards: Array) -> void:
	for reward: Variant in rewards:
		if typeof(reward) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = reward as Dictionary
		var rtype: String = str(r.get("type", "")).strip_edges().to_lower()
		var rid: String = str(r.get("id", "")).strip_edges()
		var amount: int = maxi(0, int(r.get("amount", 0)))
		if amount <= 0:
			continue
		match rtype:
			"resource":
				_grant_resource(rid, amount)
			"diamond":
				if has_node("/root/GameState"):
					GameState.diamonds += amount
			"item", "speedup", "boost", "chest":
				if has_node("/root/BagState"):
					BagState.add_item(rid, amount)
			_:
				push_warning("[EventState] Unknown reward type: %s" % rtype)
	if has_node("/root/GameState") and GameState.has_method("save_resources"):
		GameState.save_resources()


func _grant_resource(id: String, amount: int) -> void:
	if not has_node("/root/GameState"):
		return
	match id:
		"food":
			GameState.add_food(amount)
		"wood":
			GameState.add_wood(amount)
		"stone":
			GameState.add_stone(amount)
		"iron":
			GameState.add_iron(amount)
		"diamonds":
			GameState.diamonds += amount
		_:
			# Bag resource packs (resource_food_100k etc.)
			if has_node("/root/BagState"):
				BagState.add_item(id, amount)


# --- Definitions / save ---

func _load_all_defs() -> void:
	_defs.clear()
	var dir := DirAccess.open(DEFS_DIR)
	if dir == null:
		# Fallback single known event.
		_try_load_def_file(DEFS_DIR.path_join("royal_ascension.json"))
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			_try_load_def_file(DEFS_DIR.path_join(fname))
		fname = dir.get_next()
	dir.list_dir_end()


func _try_load_def_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var def: Dictionary = parsed as Dictionary
	var eid: String = str(def.get("id", "")).strip_edges()
	if eid.is_empty():
		return
	_defs[eid] = def


func save_events() -> void:
	var save := ConfigFile.new()
	save.set_value("progress", "json", JSON.stringify(_progress))
	save.save(get_save_path())


func load_events() -> void:
	_progress = {
		"event_id": "",
		"status": STATUS_INACTIVE,
		"start_unix": 0,
		"end_unix": 0,
		"points": 0,
		"claimed_milestones": [],
	}
	var save := ConfigFile.new()
	if save.load(get_save_path()) != OK:
		return
	var raw: String = str(save.get_value("progress", "json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) == TYPE_DICTIONARY:
		_progress = _normalize_progress(parsed as Dictionary)
	_tick_expiration()


func _normalize_progress(raw: Dictionary) -> Dictionary:
	var claimed_raw: Array = raw.get("claimed_milestones", []) as Array
	var claimed: Array = []
	for v: Variant in claimed_raw:
		claimed.append(int(v))
	return {
		"event_id": str(raw.get("event_id", "")),
		"status": str(raw.get("status", STATUS_INACTIVE)),
		"start_unix": int(raw.get("start_unix", 0)),
		"end_unix": int(raw.get("end_unix", 0)),
		"points": int(raw.get("points", 0)),
		"claimed_milestones": claimed,
	}


func begin_smoke_isolation() -> void:
	_save_path_override = SMOKE_SAVE_PATH
	if FileAccess.file_exists(SMOKE_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SMOKE_SAVE_PATH))
	_progress = {
		"event_id": "",
		"status": STATUS_INACTIVE,
		"start_unix": 0,
		"end_unix": 0,
		"points": 0,
		"claimed_milestones": [],
	}
	save_events()


func end_smoke_isolation() -> void:
	_save_path_override = ""
	load_events()


func run_royal_ascension_smoke_test() -> bool:
	begin_smoke_isolation()
	var failed: int = 0
	# Force start even if somehow not debug (smoke uses isolation).
	var started: Dictionary = _start_event("royal_ascension", true)
	if not bool(started.get("ok", false)):
		push_error("[EventState] smoke: start failed")
		failed += 1
	if not is_event_active("royal_ascension"):
		push_error("[EventState] smoke: not active after start")
		failed += 1
	var before: int = get_points()
	_on_building_upgraded("castle", 2)
	if get_points() != before + 500:
		push_error("[EventState] smoke: building points wrong")
		failed += 1
	before = get_points()
	_on_research_completed("econ_1")
	if get_points() != before + 300:
		push_error("[EventState] smoke: research points wrong")
		failed += 1
	before = get_points()
	_on_troop_training_completed("Infantry", 1, 100)
	if get_points() != before + 150:
		push_error("[EventState] smoke: train 100 troops should be +150")
		failed += 1
	before = get_points()
	_on_wildling_defeated("w1")
	if get_points() != before + 100:
		push_error("[EventState] smoke: wildling points wrong")
		failed += 1
	before = get_points()
	_on_gathering_completed("food", 2500)
	if get_points() != before + 20:
		push_error("[EventState] smoke: gather 2500 should be +20")
		failed += 1
	before = get_points()
	_on_speedup_used("construction", 300)
	if get_points() != before + 5:
		push_error("[EventState] smoke: 300s speedup should be +5")
		failed += 1
	# Milestone claim once.
	_progress["points"] = 1000
	var claim1: Dictionary = claim_milestone(1000)
	if not bool(claim1.get("ok", false)):
		push_error("[EventState] smoke: claim 1000 failed")
		failed += 1
	var claim2: Dictionary = claim_milestone(1000)
	if bool(claim2.get("ok", false)):
		push_error("[EventState] smoke: duplicate claim must fail")
		failed += 1
	# Persist
	save_events()
	var pts_saved: int = get_points()
	var claimed_saved: Array = (_progress.get("claimed_milestones", []) as Array).duplicate()
	load_events()
	if get_points() != pts_saved or 1000 not in (_progress.get("claimed_milestones", []) as Array):
		push_error("[EventState] smoke: persist failed")
		failed += 1
	# Expiration stops scoring.
	_progress["end_unix"] = int(Time.get_unix_time_from_system()) - 1
	_tick_expiration()
	if str(_progress.get("status", "")) != STATUS_ENDED:
		push_error("[EventState] smoke: should be ENDED")
		failed += 1
	before = get_points()
	_on_building_upgraded("farm", 3)
	if get_points() != before:
		push_error("[EventState] smoke: ended event still scoring")
		failed += 1
	# Ended but claimable remains.
	_progress["points"] = 3000
	_progress["claimed_milestones"] = [1000]
	var claim_ended: Dictionary = claim_milestone(3000)
	if not bool(claim_ended.get("ok", false)):
		push_error("[EventState] smoke: ended claimable milestone failed")
		failed += 1

	end_smoke_isolation()
	if failed == 0:
		print("[EventState] Royal Ascension smoke test PASSED")
		return true
	push_error("[EventState] Royal Ascension smoke test FAILED (%d)" % failed)
	return false
