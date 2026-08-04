extends Node

## Canonical Hospital healing queue (Phase 4).
## One active job. Uses TroopState wounded pools + GameState wallet.
## Does NOT own a second troop inventory.

signal healing_jobs_changed
signal healing_completed(job_id: String, quantity: int)

const SAVE_PATH := "user://healing_queue.cfg"
const BUILDINGS_CFG := "user://buildings.cfg"
const QUEUE_LIMIT: int = 1

## Beta formulas (centralized). Derived from TroopDatabase training data.
## Cost = 50% of training cost for the selected type/tier stacks.
## Time = 25% of training time for those stacks (min 30s).
const HEAL_COST_RATIO: float = 0.50
const HEAL_TIME_RATIO: float = 0.25
const HEAL_TIME_MIN_SEC: int = 30

## Capacity from buildings.json Sacred Hospital: level × 1000.
const HOSPITAL_CAPACITY_PER_LEVEL: int = 1000

## Active job or empty.
## {
##   job_id, troop_tiers, total_quantity,
##   start_unix, end_unix, total_duration,
##   costs, restored
## }
var active_job: Dictionary = {}

var _save_path_override: String = ""
var _save_accum: float = 0.0


func _ready() -> void:
	load_healing_state()
	_resolve_due_job()
	if has_node("/root/ConstructionState"):
		var cs: Node = get_node("/root/ConstructionState")
		if not cs.construction_completed.is_connected(_on_construction_completed):
			cs.construction_completed.connect(_on_construction_completed)
	_sync_hospital_capacity()


func _process(delta: float) -> void:
	_resolve_due_job()
	if active_job.is_empty():
		return
	_save_accum += delta
	if _save_accum >= 2.0:
		_save_accum = 0.0
		save_healing_state()


func get_save_path() -> String:
	if _save_path_override != "":
		return _save_path_override
	return SAVE_PATH


func begin_smoke_isolation() -> void:
	_save_path_override = "user://healing_queue_smoke.cfg"
	active_job = {}
	if FileAccess.file_exists(get_save_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(get_save_path()))


func end_smoke_isolation() -> void:
	_save_path_override = ""
	load_healing_state()


# --- Capacity -----------------------------------------------------------------

func get_hospital_level() -> int:
	# Phase 0B2-B: completed hospital level from ConstructionState authority only.
	if has_node("/root/ConstructionState") and ConstructionState.has_method("get_canonical_building_level"):
		return maxi(1, int(ConstructionState.get_canonical_building_level("hospital")))
	return 1


## Canonical Hospital Capacity: Sacred Hospital level × 1000 (buildings.json text).
## Display / future Sanctuary gate only — Phase 4 does NOT delete overflow wounded.
func get_hospital_capacity() -> int:
	return maxi(HOSPITAL_CAPACITY_PER_LEVEL, get_hospital_level() * HOSPITAL_CAPACITY_PER_LEVEL)


func get_waiting_wounded_count() -> int:
	if not has_node("/root/TroopState"):
		return 0
	return TroopState.get_wounded_count()


func _sync_hospital_capacity() -> void:
	if has_node("/root/TroopState"):
		TroopState.hospital_capacity = get_hospital_capacity()


func _on_construction_completed(building_id: String, _new_level: int) -> void:
	if str(building_id) == "hospital":
		_sync_hospital_capacity()
		healing_jobs_changed.emit()


# --- Queue queries ------------------------------------------------------------

func get_queue_limit() -> int:
	return QUEUE_LIMIT


func get_used_queues() -> int:
	return 0 if active_job.is_empty() else 1


func has_free_queue() -> bool:
	return active_job.is_empty()


func has_active_job() -> bool:
	return not active_job.is_empty()


func get_active_job() -> Dictionary:
	if active_job.is_empty():
		return {}
	return _job_public_view(active_job)


func get_remaining_seconds() -> float:
	if active_job.is_empty():
		return 0.0
	var now: int = int(Time.get_unix_time_from_system())
	return maxf(0.0, float(int(active_job.get("end_unix", now)) - now))


## Troops reserved in the active heal job (still occupy Hospital capacity).
func get_healing_occupancy() -> int:
	if active_job.is_empty() or bool(active_job.get("restored", false)):
		return 0
	return maxi(0, int(active_job.get("total_quantity", 0)))


# --- Cost / time formulas -----------------------------------------------------

func estimate_heal_cost(troop_tiers: Dictionary) -> Dictionary:
	var total := {"food": 0, "wood": 0, "stone": 0, "iron": 0}
	if not has_node("/root/TroopDatabase"):
		return total
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = troop_tiers.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			continue
		var display: String = _display_kind(kind)
		for tk: Variant in by_tier.keys():
			var qty: int = int(by_tier[tk])
			if qty <= 0:
				continue
			var train: Dictionary = TroopDatabase.get_training_cost(display, int(tk), qty)
			total["food"] = int(total["food"]) + int(ceil(float(train.get("food", 0)) * HEAL_COST_RATIO))
			total["wood"] = int(total["wood"]) + int(ceil(float(train.get("wood", 0)) * HEAL_COST_RATIO))
			total["stone"] = int(total["stone"]) + int(ceil(float(train.get("stone", 0)) * HEAL_COST_RATIO))
			total["iron"] = int(total["iron"]) + int(ceil(float(train.get("iron", 0)) * HEAL_COST_RATIO))
	return total


func estimate_heal_seconds(troop_tiers: Dictionary) -> int:
	if not has_node("/root/TroopDatabase"):
		return HEAL_TIME_MIN_SEC
	var train_total: int = 0
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = troop_tiers.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			continue
		var display: String = _display_kind(kind)
		for tk: Variant in by_tier.keys():
			var qty: int = int(by_tier[tk])
			if qty <= 0:
				continue
			train_total += TroopDatabase.get_training_time(display, int(tk), qty)
	var heal_sec: int = int(ceil(float(train_total) * HEAL_TIME_RATIO))
	return maxi(HEAL_TIME_MIN_SEC, heal_sec)


func count_composition(troop_tiers: Dictionary) -> int:
	var total: int = 0
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = troop_tiers.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			continue
		for tk: Variant in by_tier.keys():
			total += maxi(0, int(by_tier[tk]))
	return total


func normalize_composition(troop_tiers: Dictionary) -> Dictionary:
	var out: Dictionary = {"infantry": {}, "marksmen": {}, "cavalry": {}}
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = troop_tiers.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			continue
		var clean: Dictionary = {}
		for tk: Variant in by_tier.keys():
			var qty: int = int(by_tier[tk])
			if qty > 0:
				clean[str(int(tk))] = qty
		out[kind] = clean
	return out


# --- Lifecycle ----------------------------------------------------------------

func can_start_healing(troop_tiers: Dictionary) -> Dictionary:
	if not has_free_queue():
		return {"ok": false, "reason": "Healing Queue Full"}
	var composition: Dictionary = normalize_composition(troop_tiers)
	var qty: int = count_composition(composition)
	if qty <= 0:
		return {"ok": false, "reason": "Select wounded troops to heal."}
	if not has_node("/root/TroopState"):
		return {"ok": false, "reason": "TroopState missing."}
	if not TroopState.has_method("can_remove_wounded_by_tiers"):
		return {"ok": false, "reason": "Wounded API missing."}
	if not TroopState.can_remove_wounded_by_tiers(composition):
		return {"ok": false, "reason": "Not enough wounded troops."}
	var costs: Dictionary = estimate_heal_cost(composition)
	if has_node("/root/GameState"):
		if not GameState.can_afford_resources(
			int(costs.get("food", 0)),
			int(costs.get("wood", 0)),
			int(costs.get("stone", 0)),
			int(costs.get("iron", 0))
		):
			return {"ok": false, "reason": "Not enough resources."}
	return {
		"ok": true,
		"reason": "",
		"composition": composition,
		"quantity": qty,
		"costs": costs,
		"duration_sec": estimate_heal_seconds(composition),
	}


## Start heal: spend → reserve wounded into job → timed queue.
func start_healing(troop_tiers: Dictionary) -> Dictionary:
	var gate: Dictionary = can_start_healing(troop_tiers)
	if not bool(gate.get("ok", false)):
		return gate

	var composition: Dictionary = gate.get("composition", {}) as Dictionary
	var costs: Dictionary = gate.get("costs", {}) as Dictionary
	var duration_sec: int = int(gate.get("duration_sec", HEAL_TIME_MIN_SEC))
	var qty: int = int(gate.get("quantity", 0))

	if not GameState.spend_resources(
		int(costs.get("food", 0)),
		int(costs.get("wood", 0)),
		int(costs.get("stone", 0)),
		int(costs.get("iron", 0))
	):
		return {"ok": false, "reason": "Not enough resources."}

	if not TroopState.remove_wounded_by_tiers(composition):
		# Refund spend — wounded remove failed after spend.
		if has_node("/root/TroopDatabase"):
			TroopDatabase.refund_training_cost(costs)
		else:
			GameState.add_food(int(costs.get("food", 0)))
			GameState.add_wood(int(costs.get("wood", 0)))
			GameState.add_stone(int(costs.get("stone", 0)))
			GameState.add_iron(int(costs.get("iron", 0)))
		return {"ok": false, "reason": "Failed to reserve wounded troops."}

	var now: int = int(Time.get_unix_time_from_system())
	var job_id: String = "heal_%d_%d" % [now, randi() % 100000]
	active_job = {
		"job_id": job_id,
		"troop_tiers": composition.duplicate(true),
		"total_quantity": qty,
		"start_unix": now,
		"end_unix": now + duration_sec,
		"total_duration": duration_sec,
		"costs": costs.duplicate(true),
		"restored": false,
	}
	save_healing_state()
	healing_jobs_changed.emit()
	return {"ok": true, "reason": "", "job_id": job_id, "end_unix": now + duration_sec}


## Reduce healing batch end_unix by seconds. Completes via canonical path if due.
## Used by Alliance Help — does not bypass queue rules.
func speedup_healing(job_id: String, seconds: int) -> Dictionary:
	if active_job.is_empty():
		return {"ok": false, "reason": "No active healing job."}
	var jid: String = job_id.strip_edges()
	if jid != "" and str(active_job.get("job_id", "")) != jid:
		return {"ok": false, "reason": "Healing job id mismatch."}
	var sec: int = maxi(0, seconds)
	if sec <= 0:
		return {"ok": false, "reason": "Invalid speedup."}
	var now: int = int(Time.get_unix_time_from_system())
	var end_unix: int = int(active_job.get("end_unix", now)) - sec
	active_job["end_unix"] = end_unix
	save_healing_state()
	healing_jobs_changed.emit()
	if end_unix <= now:
		return _complete_active_job()
	return {
		"ok": true,
		"reason": "",
		"job_id": str(active_job.get("job_id", "")),
		"remaining": maxf(0.0, float(end_unix - now)),
		"end_unix": end_unix,
	}


## Instant-complete through canonical restore path (debug / future Finish).
func finish_healing_now() -> Dictionary:
	if active_job.is_empty():
		return {"ok": false, "reason": "No active healing job."}
	active_job["end_unix"] = int(Time.get_unix_time_from_system()) - 1
	return _complete_active_job()


func _resolve_due_job() -> void:
	if active_job.is_empty():
		return
	if bool(active_job.get("restored", false)):
		active_job = {}
		save_healing_state()
		return
	var now: int = int(Time.get_unix_time_from_system())
	if now >= int(active_job.get("end_unix", 0)):
		_complete_active_job()


func _complete_active_job() -> Dictionary:
	if active_job.is_empty():
		return {"ok": false, "reason": "No active healing job."}
	if bool(active_job.get("restored", false)):
		active_job = {}
		save_healing_state()
		healing_jobs_changed.emit()
		return {"ok": true, "reason": "Already restored."}

	var job: Dictionary = active_job.duplicate(true)
	var job_id: String = str(job.get("job_id", ""))
	var tiers: Dictionary = job.get("troop_tiers", {}) as Dictionary
	var qty: int = int(job.get("total_quantity", count_composition(tiers)))

	# Mark restored before mutating troops — prevents duplicate offline restore.
	active_job["restored"] = true
	save_healing_state()

	if has_node("/root/TroopState"):
		TroopState.return_troops_by_tiers(tiers)

	active_job = {}
	save_healing_state()
	healing_completed.emit(job_id, qty)
	healing_jobs_changed.emit()
	return {"ok": true, "reason": "", "job_id": job_id, "quantity": qty}


func _job_public_view(job: Dictionary) -> Dictionary:
	var out: Dictionary = job.duplicate(true)
	var now: int = int(Time.get_unix_time_from_system())
	out["time_remaining"] = maxf(0.0, float(int(out.get("end_unix", now)) - now))
	return out


func _display_kind(kind: String) -> String:
	match kind.strip_edges().to_lower():
		"infantry":
			return "Infantry"
		"marksmen":
			return "Marksmen"
		"cavalry":
			return "Cavalry"
		_:
			return kind.capitalize()


# --- Save / load --------------------------------------------------------------

func save_healing_state() -> void:
	var save := ConfigFile.new()
	if active_job.is_empty():
		save.set_value("queue", "has_job", false)
	else:
		save.set_value("queue", "has_job", true)
		save.set_value("queue", "job_id", str(active_job.get("job_id", "")))
		save.set_value("queue", "troop_tiers", active_job.get("troop_tiers", {}))
		save.set_value("queue", "total_quantity", int(active_job.get("total_quantity", 0)))
		save.set_value("queue", "start_unix", int(active_job.get("start_unix", 0)))
		save.set_value("queue", "end_unix", int(active_job.get("end_unix", 0)))
		save.set_value("queue", "total_duration", int(active_job.get("total_duration", 0)))
		save.set_value("queue", "costs", active_job.get("costs", {}))
		save.set_value("queue", "restored", bool(active_job.get("restored", false)))
	save.save(get_save_path())


func load_healing_state() -> void:
	active_job = {}
	var save := ConfigFile.new()
	if save.load(get_save_path()) != OK:
		return
	if not bool(save.get_value("queue", "has_job", false)):
		return
	active_job = {
		"job_id": str(save.get_value("queue", "job_id", "")),
		"troop_tiers": save.get_value("queue", "troop_tiers", {}),
		"total_quantity": int(save.get_value("queue", "total_quantity", 0)),
		"start_unix": int(save.get_value("queue", "start_unix", 0)),
		"end_unix": int(save.get_value("queue", "end_unix", 0)),
		"total_duration": int(save.get_value("queue", "total_duration", 0)),
		"costs": save.get_value("queue", "costs", {}),
		"restored": bool(save.get_value("queue", "restored", false)),
	}
	if typeof(active_job.get("troop_tiers", null)) != TYPE_DICTIONARY:
		active_job["troop_tiers"] = {"infantry": {}, "marksmen": {}, "cavalry": {}}


func run_phase4_smoke_test() -> bool:
	begin_smoke_isolation()
	var failed: int = 0
	if not has_node("/root/TroopState") or not has_node("/root/GameState"):
		push_error("[HealingState] smoke missing TroopState/GameState")
		end_smoke_isolation()
		return false

	var bak_w: Dictionary = TroopState.get_wounded_by_tiers()
	var bak_inf: Dictionary = TroopState.infantry_by_tier.duplicate(true)
	var bak_food: int = GameState.food
	var bak_wood: int = GameState.wood
	var bak_stone: int = GameState.stone
	var bak_iron: int = GameState.iron

	# Seed wounded.
	TroopState.wounded_infantry_by_tier = {1: 100, 2: 50}
	TroopState.wounded_marksmen_by_tier = {}
	TroopState.wounded_cavalry_by_tier = {}
	TroopState._resync_wounded_totals()
	TroopState.save_troops()

	GameState.food = 100000
	GameState.wood = 100000
	GameState.stone = 100000
	GameState.iron = 100000
	GameState.save_resources()

	var select: Dictionary = {"infantry": {"1": 40, "2": 20}, "marksmen": {}, "cavalry": {}}
	var started: Dictionary = start_healing(select)
	if not bool(started.get("ok", false)):
		push_error("[HealingState] smoke start failed: %s" % str(started.get("reason", "")))
		failed += 1
	else:
		var waiting: Dictionary = TroopState.get_wounded_by_tiers()
		var w1: int = int((waiting.get("infantry", {}) as Dictionary).get("1", 0))
		var w2: int = int((waiting.get("infantry", {}) as Dictionary).get("2", 0))
		if w1 != 60 or w2 != 30:
			push_error("[HealingState] smoke waiting wounded expected T1=60 T2=30 got %d/%d" % [w1, w2])
			failed += 1
		var job: Dictionary = get_active_job()
		var jt: Dictionary = job.get("troop_tiers", {}) as Dictionary
		var j1: int = int((jt.get("infantry", {}) as Dictionary).get("1", 0))
		var j2: int = int((jt.get("infantry", {}) as Dictionary).get("2", 0))
		if j1 != 40 or j2 != 20:
			push_error("[HealingState] smoke job tiers wrong")
			failed += 1

	# Queue full
	var second: Dictionary = start_healing({"infantry": {"1": 1}, "marksmen": {}, "cavalry": {}})
	if bool(second.get("ok", false)) or str(second.get("reason", "")) != "Healing Queue Full":
		push_error("[HealingState] smoke queue-full expected")
		failed += 1
	else:
		print("[HealingState] smoke queue-full OK")

	# Capacity getter
	var cap: int = get_hospital_capacity()
	if cap < HOSPITAL_CAPACITY_PER_LEVEL:
		push_error("[HealingState] smoke capacity too low %d" % cap)
		failed += 1

	# Complete → available gains
	var avail_before: int = TroopState.get_tier_count("Infantry", 1)
	var done: Dictionary = finish_healing_now()
	if not bool(done.get("ok", false)):
		push_error("[HealingState] smoke finish failed")
		failed += 1
	else:
		var avail_after: int = TroopState.get_tier_count("Infantry", 1)
		if avail_after - avail_before != 40:
			push_error("[HealingState] smoke restore T1 expected +40 got +%d" % (avail_after - avail_before))
			failed += 1
		if has_active_job():
			push_error("[HealingState] smoke job should clear")
			failed += 1
		var wait2: Dictionary = TroopState.get_wounded_by_tiers()
		if int((wait2.get("infantry", {}) as Dictionary).get("1", 0)) != 60:
			push_error("[HealingState] smoke leftover wounded wrong")
			failed += 1

	# Offline: start short job, backdate end, reload
	TroopState.wounded_infantry_by_tier = {1: 10}
	TroopState._resync_wounded_totals()
	GameState.food = 100000
	GameState.wood = 100000
	var offline_start: Dictionary = start_healing({"infantry": {"1": 5}, "marksmen": {}, "cavalry": {}})
	if bool(offline_start.get("ok", false)):
		active_job["end_unix"] = int(Time.get_unix_time_from_system()) - 5
		save_healing_state()
		var avail_o0: int = TroopState.get_tier_count("Infantry", 1)
		load_healing_state()
		_resolve_due_job()
		var avail_o1: int = TroopState.get_tier_count("Infantry", 1)
		if avail_o1 - avail_o0 != 5:
			push_error("[HealingState] smoke offline restore expected +5")
			failed += 1
		else:
			print("[HealingState] smoke offline restore OK")
		# Second resolve must not duplicate
		_resolve_due_job()
		if TroopState.get_tier_count("Infantry", 1) != avail_o1:
			push_error("[HealingState] smoke offline duplicate restore")
			failed += 1

	# Restore player state
	TroopState.wounded_infantry_by_tier = TroopState._deserialize_tier_map(bak_w.get("infantry", {}), 0)
	TroopState.wounded_marksmen_by_tier = TroopState._deserialize_tier_map(bak_w.get("marksmen", {}), 0)
	TroopState.wounded_cavalry_by_tier = TroopState._deserialize_tier_map(bak_w.get("cavalry", {}), 0)
	TroopState.infantry_by_tier = bak_inf
	TroopState._resync_wounded_totals()
	TroopState._resync_totals()
	TroopState.save_troops()
	GameState.food = bak_food
	GameState.wood = bak_wood
	GameState.stone = bak_stone
	GameState.iron = bak_iron
	GameState.save_resources()

	end_smoke_isolation()
	if failed == 0:
		print("[HealingState] Phase-4 smoke PASSED")
		return true
	print("[HealingState] Phase-4 smoke FAILED count=%d" % failed)
	return false
