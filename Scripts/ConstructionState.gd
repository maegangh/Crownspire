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

signal construction_jobs_changed
signal construction_completed(building_id: String, new_level: int)

const SAVE_PATH := "user://construction_queue.cfg"
const BUILDINGS_CFG := "user://buildings.cfg"
const CONSTRUCTION_QUEUE_MAX: int = 2
const TEMP_SECONDARY_CONSTRUCTION_DAYS: int = 30

## Job shape:
## {
##   building_id, from_level, target_level,
##   start_unix, end_unix, total_duration
## }
var active_jobs: Array = []

var permanent_secondary_construction_queue: bool = false
var temporary_secondary_construction_queue_expires_unix: int = 0
var _save_accum: float = 0.0


func _ready() -> void:
	load_construction_state()
	_normalize_loaded_jobs()
	_migrate_from_building_cfg()
	_resolve_due_jobs()


func _process(delta: float) -> void:
	_tick_jobs(delta)


# --- Entitlement / limits -----------------------------------------------------

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


# --- Queue queries ------------------------------------------------------------

func get_active_construction_jobs() -> Array:
	return active_jobs.duplicate(true)


func get_used_construction_queues() -> int:
	return active_jobs.size()


func has_free_construction_queue() -> bool:
	return get_used_construction_queues() < get_construction_queue_limit()


func can_start_construction(building_id: String) -> Dictionary:
	var bid: String = building_id.strip_edges()
	if bid.is_empty():
		return {"ok": false, "reason": "Invalid building."}
	if _find_job_index(bid) >= 0:
		return {"ok": false, "reason": "Already upgrading."}
	if not has_free_construction_queue():
		return {"ok": false, "reason": "Construction Queue Full"}
	return {"ok": true, "reason": ""}


func get_job_for(building_id: String) -> Dictionary:
	var idx: int = _find_job_index(building_id)
	if idx < 0:
		return {}
	return _job_public_view(active_jobs[idx] as Dictionary)


func is_building_upgrading(building_id: String) -> bool:
	return _find_job_index(building_id) >= 0


func get_remaining_seconds(building_id: String) -> float:
	var job: Dictionary = get_job_for(building_id)
	if job.is_empty():
		return 0.0
	return float(job.get("time_remaining", 0.0))


# --- Lifecycle ----------------------------------------------------------------

## Start timed construction. Does NOT apply target level.
func start_construction(building_id: String, from_level: int, target_level: int, duration_sec: float) -> Dictionary:
	return try_start_construction(building_id, from_level, target_level, duration_sec)


## Back-compat wrapper (older callers passed target_level + duration only).
func try_start_construction(building_id: String, a = null, b = null, c = null) -> Dictionary:
	var bid: String = building_id.strip_edges()
	var from_level: int = 1
	var target_level: int = 2
	var duration_sec: float = 30.0

	# New signature: (id, from_level, target_level, duration)
	# Old signature: (id, target_level, duration)
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
		# Kept for older UI; derived from end_unix each tick.
		"time_remaining": float(end_unix - now),
	})
	save_construction_state()
	_sync_resource_manager_flags(bid, true, float(end_unix - now))
	construction_jobs_changed.emit()
	return {"ok": true, "reason": "", "end_unix": end_unix}


## Instant-complete active job through the canonical completion path (beta Finish).
func finish_construction_now(building_id: String) -> Dictionary:
	var idx: int = _find_job_index(building_id)
	if idx < 0:
		return {"ok": false, "reason": "No active construction for this building."}
	return complete_construction(building_id)


func complete_construction(building_id: String) -> Dictionary:
	var idx: int = _find_job_index(building_id)
	if idx < 0:
		return {"ok": false, "reason": "No active construction for this building."}
	return _complete_job_at(idx)


func cancel_construction(building_id: String) -> Dictionary:
	var idx: int = _find_job_index(building_id)
	if idx < 0:
		return {}
	var job: Dictionary = (active_jobs[idx] as Dictionary).duplicate(true)
	active_jobs.remove_at(idx)
	save_construction_state()
	_sync_resource_manager_flags(str(job.get("building_id", "")), false, 0.0)
	construction_jobs_changed.emit()
	return job


# --- Tick / offline resolve ---------------------------------------------------

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
			# Legacy time_remaining-only job.
			if float(d.get("time_remaining", 1.0)) <= 0.0:
				due.append(str(d.get("building_id", "")))
		elif now >= end_unix:
			due.append(str(d.get("building_id", "")))
	for bid: String in due:
		var idx: int = _find_job_index(bid)
		if idx >= 0:
			_complete_job_at(idx)


## ONLY place that mutates building level on disk / city nodes.
func _complete_job_at(idx: int) -> Dictionary:
	if idx < 0 or idx >= active_jobs.size():
		return {"ok": false, "reason": "Invalid job"}
	var job: Dictionary = active_jobs[idx] as Dictionary
	var bid: String = str(job.get("building_id", ""))
	var new_level: int = int(job.get("target_level", 1))
	var from_level: int = int(job.get("from_level", maxi(1, new_level - 1)))

	# Remove first so a re-entrant tick cannot complete twice.
	active_jobs.remove_at(idx)
	save_construction_state()

	_write_building_level(bid, new_level)
	_sync_resource_manager_flags(bid, false, 0.0)
	_notify_city_level(bid, new_level)
	construction_completed.emit(bid, new_level)
	construction_jobs_changed.emit()
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
	for i: int in range(active_jobs.size()):
		if str((active_jobs[i] as Dictionary).get("building_id", "")) == building_id:
			return i
	return -1


func _write_building_level(building_id: String, new_level: int) -> void:
	var save := ConfigFile.new()
	save.load(BUILDINGS_CFG)
	save.set_value(building_id, "level", new_level)
	save.set_value(building_id, "upgrading", false)
	save.set_value(building_id, "upgrade_finish_time", 0)
	save.save(BUILDINGS_CFG)


func _sync_resource_manager_flags(building_id: String, upgrading: bool, duration_sec: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var scene: Node = tree.current_scene
	if scene == null:
		return
	for node: Node in scene.find_children("*", "Node", true, false):
		if node.get("building_id") == null:
			continue
		if str(node.get("building_id")) != building_id:
			continue
		if "upgrading" in node:
			node.set("upgrading", upgrading)
		if "upgrade_finish_time" in node:
			if upgrading:
				node.set("upgrade_finish_time", int(Time.get_unix_time_from_system()) + int(ceil(duration_sec)))
			else:
				node.set("upgrade_finish_time", 0)
		# While upgrading: persist flags only — NEVER bump building_level here.
		if node.has_method("save_building_level"):
			node.call("save_building_level")
		if (not upgrading) and node.has_method("load_building_level"):
			node.call_deferred("load_building_level")
		if (not upgrading) and node.has_method("update_level_label"):
			node.call_deferred("update_level_label")
		break


func _notify_city_level(building_id: String, new_level: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.call_group("city_buildings", "refresh_level_display")
	var scene: Node = tree.current_scene
	if scene == null:
		return
	for node: Node in scene.find_children("*", "Node", true, false):
		if node.get("building_id") != null and str(node.get("building_id")) == building_id:
			if "building_level" in node:
				node.set("building_level", new_level)
			if "upgrading" in node:
				node.set("upgrading", false)
			if "upgrade_finish_time" in node:
				node.set("upgrade_finish_time", 0)
			if node.has_method("update_level_label"):
				node.call("update_level_label")
			if node.has_method("save_building_level"):
				node.call("save_building_level")
			break


func _normalize_loaded_jobs() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	for i: int in range(active_jobs.size()):
		var job: Dictionary = active_jobs[i] as Dictionary
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
	if save.load(BUILDINGS_CFG) != OK:
		return
	var now: int = int(Time.get_unix_time_from_system())
	for section: String in save.get_sections():
		var upgrading: bool = bool(save.get_value(section, "upgrading", false))
		if not upgrading:
			continue
		var finish: int = int(save.get_value(section, "upgrade_finish_time", 0))
		var lvl: int = int(save.get_value(section, "level", 1))
		if finish <= now:
			finish = now + 60
		active_jobs.append({
			"building_id": section,
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
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("meta", "permanent_secondary_construction_queue", permanent_secondary_construction_queue)
	cfg.set_value("meta", "temporary_secondary_construction_queue_expires_unix", temporary_secondary_construction_queue_expires_unix)
	cfg.set_value("meta", "secondary_construction_queue_owned", has_secondary_construction_queue())
	cfg.set_value("jobs", "json", JSON.stringify(active_jobs))
	cfg.save(SAVE_PATH)


func load_construction_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
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
