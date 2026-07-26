extends Node

## Canonical Academy research progression + queue limits.
## UI must consult these APIs; do not enforce limits only in AcademyResearchWindow.

signal research_jobs_changed
signal research_completed(research_id: String, level: int)

const SAVE_PATH := "user://research_queue.cfg"

## Legacy fields kept for older callers / savegame.save
var research_hall_level: int = 1
var economy_research_level: int = 0
var military_research_level: int = 0
var troop_attack_bonus: int = 0

## Tech tree levels: research_id -> int level
var research_levels: Dictionary = {}

## All in-progress jobs (active timers). May temporarily exceed limit after migration.
## Job: { research_id, level, time_remaining, total_duration }
var active_jobs: Array = []

## Product: Permanent Secondary Research Queue ($9.99). No temporary research queue planned.
## Default false — do not grant paid queues without a real entitlement grant.
var permanent_secondary_research_queue: bool = false

var _save_accum: float = 0.0

const RESEARCH_QUEUE_MAX: int = 2


func _ready() -> void:
	load_research_state()


func _process(delta: float) -> void:
	_tick_jobs(delta)


# --- Entitlement / limits -----------------------------------------------------

func has_permanent_secondary_research_queue() -> bool:
	return permanent_secondary_research_queue


## True when the paid permanent secondary research queue is owned.
func has_secondary_research_queue() -> bool:
	return has_permanent_secondary_research_queue()


## Default 1; permanent secondary → 2. Never above RESEARCH_QUEUE_MAX.
func get_research_queue_limit() -> int:
	if has_permanent_secondary_research_queue():
		return RESEARCH_QUEUE_MAX
	return 1


## Future store grant hook (no payment processing here).
func grant_permanent_secondary_research_queue() -> void:
	permanent_secondary_research_queue = true
	save_research_state()
	research_jobs_changed.emit()


func get_active_research_jobs() -> Array:
	return active_jobs.duplicate(true)


func get_used_research_queues() -> int:
	return active_jobs.size()


func has_free_research_queue() -> bool:
	return get_used_research_queues() < get_research_queue_limit()


func can_start_research(research_id: String) -> Dictionary:
	var rid: String = research_id.strip_edges()
	if rid.is_empty():
		return {"ok": false, "reason": "Invalid research."}
	if _find_job_index(rid) >= 0:
		return {"ok": false, "reason": "Already researching."}
	if not has_free_research_queue():
		return {"ok": false, "reason": "Research Queue Full"}
	return {"ok": true, "reason": ""}


# --- Job API ------------------------------------------------------------------

func get_primary_job() -> Dictionary:
	if active_jobs.is_empty():
		return {}
	return (active_jobs[0] as Dictionary).duplicate(true)


func get_job_for(research_id: String) -> Dictionary:
	var idx: int = _find_job_index(research_id)
	if idx < 0:
		return {}
	return (active_jobs[idx] as Dictionary).duplicate(true)


## Jobs after the primary slot (legacy "queue" view / overflow migration display).
func get_waiting_jobs() -> Array:
	if active_jobs.size() <= 1:
		return []
	var out: Array = []
	for i: int in range(1, active_jobs.size()):
		out.append((active_jobs[i] as Dictionary).duplicate(true))
	return out


func try_start_research(job: Dictionary) -> Dictionary:
	var rid: String = str(job.get("research_id", "")).strip_edges()
	var gate: Dictionary = can_start_research(rid)
	if not bool(gate.get("ok", false)):
		return gate
	var stored: Dictionary = {
		"research_id": rid,
		"level": int(job.get("level", 1)),
		"time_remaining": float(job.get("time_remaining", job.get("total_duration", 0.0))),
		"total_duration": float(job.get("total_duration", job.get("time_remaining", 0.0))),
	}
	active_jobs.append(stored)
	save_research_state()
	research_jobs_changed.emit()
	if has_node("/root/GameEvents"):
		GameEvents.emit_research_started(rid)
	return {"ok": true, "reason": ""}


func cancel_research(research_id: String) -> Dictionary:
	var idx: int = _find_job_index(research_id)
	if idx < 0:
		return {}
	var job: Dictionary = (active_jobs[idx] as Dictionary).duplicate(true)
	active_jobs.remove_at(idx)
	save_research_state()
	research_jobs_changed.emit()
	return job


func cancel_primary_research() -> Dictionary:
	if active_jobs.is_empty():
		return {}
	return cancel_research(str((active_jobs[0] as Dictionary).get("research_id", "")))


## Reduce real research time_remaining. Completes via canonical path if due.
func speedup_research(research_id: String, seconds: float) -> Dictionary:
	var rid: String = research_id.strip_edges()
	var idx: int = _find_job_index(rid)
	if idx < 0 and rid.is_empty() and not active_jobs.is_empty():
		rid = str((active_jobs[0] as Dictionary).get("research_id", ""))
		idx = _find_job_index(rid)
	if idx < 0:
		return {"ok": false, "reason": "No active research for this project."}
	var sec: float = maxf(0.0, seconds)
	if sec <= 0.0:
		return {"ok": false, "reason": "Invalid speedup duration."}

	var job: Dictionary = active_jobs[idx] as Dictionary
	var rem: float = maxf(0.0, float(job.get("time_remaining", 0.0)) - sec)
	job["time_remaining"] = rem
	active_jobs[idx] = job
	save_research_state()
	research_jobs_changed.emit()

	if rem <= 0.0:
		_complete_job(rid)
		return {
			"ok": true,
			"reason": "",
			"completed": true,
			"remaining": 0.0,
			"research_id": rid,
		}
	return {
		"ok": true,
		"reason": "",
		"completed": false,
		"remaining": rem,
		"research_id": rid,
	}


func get_remaining_seconds(research_id: String = "") -> float:
	var job: Dictionary = get_job_for(research_id) if not research_id.is_empty() else get_primary_job()
	if job.is_empty():
		return 0.0
	return float(job.get("time_remaining", 0.0))


func get_research_level(research_id: String) -> int:
	return int(research_levels.get(research_id, 0))


func set_research_level(research_id: String, level: int) -> void:
	research_levels[research_id] = level
	save_research_state()


## Import jobs from legacy AcademyResearchWindow / UIManager without dropping progress.
## Keeps ALL jobs even if count > current queue limit; new starts stay blocked until under limit.
func import_legacy_jobs(active: Dictionary, queue: Array, levels: Dictionary = {}) -> void:
	if not levels.is_empty():
		for k: Variant in levels.keys():
			var id_key: String = str(k)
			var lvl: int = int(levels[k])
			research_levels[id_key] = maxi(int(research_levels.get(id_key, 0)), lvl)

	var incoming: Array = []
	if not active.is_empty() and str(active.get("research_id", "")) != "":
		incoming.append(active)
	for item: Variant in queue:
		if typeof(item) == TYPE_DICTIONARY and str((item as Dictionary).get("research_id", "")) != "":
			incoming.append(item)

	for item: Variant in incoming:
		var d: Dictionary = item as Dictionary
		var rid: String = str(d.get("research_id", ""))
		if _find_job_index(rid) >= 0:
			continue
		active_jobs.append({
			"research_id": rid,
			"level": int(d.get("level", 1)),
			"time_remaining": float(d.get("time_remaining", d.get("total_duration", 0.0))),
			"total_duration": float(d.get("total_duration", d.get("time_remaining", 0.0))),
		})

	save_research_state()
	research_jobs_changed.emit()


# --- Tick / complete ----------------------------------------------------------

func _tick_jobs(delta: float) -> void:
	if active_jobs.is_empty():
		return
	var completed: Array[Dictionary] = []
	for i: int in range(active_jobs.size()):
		var job: Dictionary = active_jobs[i]
		job["time_remaining"] = maxf(0.0, float(job.get("time_remaining", 0.0)) - delta)
		active_jobs[i] = job
		if float(job.get("time_remaining", 0.0)) <= 0.0:
			completed.append(job.duplicate(true))

	if completed.is_empty():
		_save_accum += delta
		if _save_accum >= 2.0:
			_save_accum = 0.0
			save_research_state()
		return

	for done: Dictionary in completed:
		_complete_job(str(done.get("research_id", "")))


func _complete_job(research_id: String) -> void:
	var idx: int = _find_job_index(research_id)
	if idx < 0:
		return
	var job: Dictionary = active_jobs[idx] as Dictionary
	var lvl: int = int(job.get("level", 1))
	active_jobs.remove_at(idx)
	research_levels[research_id] = maxi(int(research_levels.get(research_id, 0)), lvl)
	save_research_state()
	research_completed.emit(research_id, lvl)
	research_jobs_changed.emit()
	if has_node("/root/GameEvents"):
		GameEvents.emit_research_completed(research_id)


func _find_job_index(research_id: String) -> int:
	for i: int in range(active_jobs.size()):
		if str((active_jobs[i] as Dictionary).get("research_id", "")) == research_id:
			return i
	return -1


# --- Save / load --------------------------------------------------------------

func save_research_state() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("meta", "permanent_secondary_research_queue", permanent_secondary_research_queue)
	# Keep legacy key in sync for older readers.
	cfg.set_value("meta", "secondary_research_queue_owned", permanent_secondary_research_queue)
	cfg.set_value("meta", "research_hall_level", research_hall_level)
	cfg.set_value("meta", "economy_research_level", economy_research_level)
	cfg.set_value("meta", "military_research_level", military_research_level)
	cfg.set_value("levels", "json", JSON.stringify(research_levels))
	cfg.set_value("jobs", "json", JSON.stringify(active_jobs))
	cfg.save(SAVE_PATH)


func load_research_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	permanent_secondary_research_queue = bool(cfg.get_value(
		"meta",
		"permanent_secondary_research_queue",
		bool(cfg.get_value("meta", "secondary_research_queue_owned", false))
	))
	research_hall_level = int(cfg.get_value("meta", "research_hall_level", research_hall_level))
	economy_research_level = int(cfg.get_value("meta", "economy_research_level", economy_research_level))
	military_research_level = int(cfg.get_value("meta", "military_research_level", military_research_level))

	var levels_raw: Variant = JSON.parse_string(str(cfg.get_value("levels", "json", "{}")))
	if typeof(levels_raw) == TYPE_DICTIONARY:
		research_levels = levels_raw as Dictionary

	var jobs_raw: Variant = JSON.parse_string(str(cfg.get_value("jobs", "json", "[]")))
	if typeof(jobs_raw) == TYPE_ARRAY:
		active_jobs = jobs_raw as Array
	# Migration: never strip excess jobs; can_start stays false until under limit.
