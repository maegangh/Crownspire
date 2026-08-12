extends Node

## Passiveuary overflow passive recovery (Phase 5).
## Owns recovery wave timestamps only. Troop ownership lives in TroopState.
## No resource cost. No upgrade. No QueueStatusHUD card.

signal sanctuary_changed
signal sanctuary_wave_completed(wave_id: String, quantity: int)

const SAVE_PATH := "user://sanctuary.cfg"

## Sanctuary recovery = HEAL_TIME × this multiplier (uses HealingState formula).
const SANCTUARY_RECOVERY_MULTIPLIER: float = 2.0
const SANCTUARY_RECOVERY_MIN_SEC: int = 60

## Waves: [{ wave_id, troop_tiers, total_quantity, start_unix, end_unix, restored }]
var recovery_waves: Array = []

var _save_path_override: String = ""
var _save_accum: float = 0.0


func _ready() -> void:
	load_sanctuary_state()
	_resolve_due_waves()


func _process(delta: float) -> void:
	_resolve_due_waves()
	if recovery_waves.is_empty():
		return
	_save_accum += delta
	if _save_accum >= 2.0:
		_save_accum = 0.0
		save_sanctuary_state()


func get_save_path() -> String:
	if _save_path_override != "":
		return _save_path_override
	if has_node("/root/AccountSavePaths"):
		return AccountSavePaths.path_for("sanctuary.cfg")
	return SAVE_PATH


func begin_smoke_isolation() -> void:
	_save_path_override = "user://sanctuary_smoke.cfg"
	recovery_waves.clear()
	if FileAccess.file_exists(get_save_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(get_save_path()))


func end_smoke_isolation() -> void:
	_save_path_override = ""
	load_sanctuary_state()


# --- Queries ------------------------------------------------------------------

func has_recovering() -> bool:
	return not _live_waves().is_empty()


func get_recovery_waves() -> Array:
	var out: Array = []
	for wave: Dictionary in _live_waves():
		out.append(_wave_public_view(wave))
	return out


func get_total_recovering() -> int:
	if has_node("/root/TroopState"):
		return TroopState.get_sanctuary_count()
	var total: int = 0
	for wave: Dictionary in _live_waves():
		total += int(wave.get("total_quantity", 0))
	return total


func get_soonest_remaining_seconds() -> float:
	var best: float = -1.0
	for wave: Dictionary in _live_waves():
		var rem: float = float(_wave_public_view(wave).get("time_remaining", 0.0))
		if best < 0.0 or rem < best:
			best = rem
	return maxf(0.0, best)


## Aggregate sanctuary composition with earliest end_unix per type/tier.
func get_display_stacks() -> Array:
	var stacks: Dictionary = {} # "kind|tier" -> {kind, tier, quantity, end_unix}
	for wave: Dictionary in _live_waves():
		var end_unix: int = int(wave.get("end_unix", 0))
		var tiers: Dictionary = wave.get("troop_tiers", {}) as Dictionary
		for kind: String in ["infantry", "marksmen", "cavalry"]:
			var by_tier: Dictionary = tiers.get(kind, {}) as Dictionary
			if typeof(by_tier) != TYPE_DICTIONARY:
				continue
			for tk: Variant in by_tier.keys():
				var qty: int = int(by_tier[tk])
				if qty <= 0:
					continue
				var key: String = "%s|%d" % [kind, int(tk)]
				if stacks.has(key):
					var row: Dictionary = stacks[key]
					row["quantity"] = int(row.get("quantity", 0)) + qty
					row["end_unix"] = mini(int(row.get("end_unix", end_unix)), end_unix)
					stacks[key] = row
				else:
					stacks[key] = {
						"kind": kind,
						"tier": int(tk),
						"quantity": qty,
						"end_unix": end_unix,
					}
	var out: Array = []
	for kind_order: String in ["infantry", "marksmen", "cavalry"]:
		var kind_rows: Array = []
		for key2: Variant in stacks.keys():
			var row2: Dictionary = stacks[key2]
			if str(row2.get("kind", "")) == kind_order:
				kind_rows.append(row2)
		kind_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("tier", 0)) < int(b.get("tier", 0))
		)
		out.append_array(kind_rows)
	return out


# --- Duration -----------------------------------------------------------------

func estimate_recovery_seconds(troop_tiers: Dictionary) -> int:
	var base_heal: int = SANCTUARY_RECOVERY_MIN_SEC
	if has_node("/root/HealingState") and HealingState.has_method("estimate_heal_seconds"):
		base_heal = HealingState.estimate_heal_seconds(troop_tiers)
	var sec: int = int(ceil(float(base_heal) * SANCTUARY_RECOVERY_MULTIPLIER))
	return maxi(SANCTUARY_RECOVERY_MIN_SEC, sec)


# --- Lifecycle ----------------------------------------------------------------

## Start passive recovery for a new overflow composition (no resources).
func enqueue_recovery(troop_tiers: Dictionary) -> Dictionary:
	if typeof(troop_tiers) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "Invalid composition."}
	var composition: Dictionary = _normalize(troop_tiers)
	var qty: int = _count(composition)
	if qty <= 0:
		return {"ok": false, "reason": "Empty overflow."}

	var now: int = int(Time.get_unix_time_from_system())
	var duration: int = estimate_recovery_seconds(composition)
	var wave_id: String = "sanct_%d_%d" % [now, randi() % 100000]
	recovery_waves.append({
		"wave_id": wave_id,
		"troop_tiers": composition.duplicate(true),
		"total_quantity": qty,
		"start_unix": now,
		"end_unix": now + duration,
		"restored": false,
	})
	save_sanctuary_state()
	sanctuary_changed.emit()
	return {"ok": true, "wave_id": wave_id, "end_unix": now + duration, "duration_sec": duration}


func _resolve_due_waves() -> void:
	if recovery_waves.is_empty():
		return
	var now: int = int(Time.get_unix_time_from_system())
	var due_ids: PackedStringArray = PackedStringArray()
	for wave: Variant in recovery_waves:
		if typeof(wave) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = wave as Dictionary
		if bool(d.get("restored", false)):
			continue
		if now >= int(d.get("end_unix", 0)):
			due_ids.append(str(d.get("wave_id", "")))
	for wid: String in due_ids:
		_complete_wave(wid)


func _complete_wave(wave_id: String) -> Dictionary:
	var idx: int = _find_wave_index(wave_id)
	if idx < 0:
		return {"ok": false, "reason": "Wave not found."}
	var wave: Dictionary = recovery_waves[idx] as Dictionary
	if bool(wave.get("restored", false)):
		recovery_waves.remove_at(idx)
		save_sanctuary_state()
		sanctuary_changed.emit()
		return {"ok": true, "reason": "Already restored."}

	var tiers: Dictionary = wave.get("troop_tiers", {}) as Dictionary
	var qty: int = int(wave.get("total_quantity", 0))

	# Mark first to prevent duplicate offline restore.
	wave["restored"] = true
	recovery_waves[idx] = wave
	save_sanctuary_state()

	if has_node("/root/TroopState"):
		# Remove from Sanctuary storage then restore to available.
		if TroopState.has_method("remove_sanctuary_by_tiers"):
			TroopState.remove_sanctuary_by_tiers(tiers)
		TroopState.return_troops_by_tiers(tiers)

	recovery_waves.remove_at(idx)
	save_sanctuary_state()
	sanctuary_wave_completed.emit(wave_id, qty)
	sanctuary_changed.emit()
	return {"ok": true, "wave_id": wave_id, "quantity": qty}


## Debug/instant complete earliest wave.
func finish_soonest_wave_now() -> Dictionary:
	var live: Array = _live_waves()
	if live.is_empty():
		return {"ok": false, "reason": "No recovering waves."}
	var wave: Dictionary = live[0]
	wave["end_unix"] = int(Time.get_unix_time_from_system()) - 1
	var idx: int = _find_wave_index(str(wave.get("wave_id", "")))
	if idx >= 0:
		recovery_waves[idx] = wave
	return _complete_wave(str(wave.get("wave_id", "")))


func finish_all_waves_now() -> void:
	while has_recovering():
		var r: Dictionary = finish_soonest_wave_now()
		if not bool(r.get("ok", false)):
			break


# --- Helpers ------------------------------------------------------------------

func _live_waves() -> Array:
	var out: Array = []
	for wave: Variant in recovery_waves:
		if typeof(wave) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = wave as Dictionary
		if bool(d.get("restored", false)):
			continue
		out.append(d)
	return out


func _find_wave_index(wave_id: String) -> int:
	for i: int in range(recovery_waves.size()):
		if str((recovery_waves[i] as Dictionary).get("wave_id", "")) == wave_id:
			return i
	return -1


func _wave_public_view(wave: Dictionary) -> Dictionary:
	var out: Dictionary = wave.duplicate(true)
	var now: int = int(Time.get_unix_time_from_system())
	out["time_remaining"] = maxf(0.0, float(int(out.get("end_unix", now)) - now))
	return out


func _normalize(troop_tiers: Dictionary) -> Dictionary:
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


func _count(composition: Dictionary) -> int:
	var total: int = 0
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = composition.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			continue
		for tk: Variant in by_tier.keys():
			total += maxi(0, int(by_tier[tk]))
	return total


# --- Save ---------------------------------------------------------------------

func save_sanctuary_state() -> void:
	var save := ConfigFile.new()
	save.set_value("recovery", "wave_count", recovery_waves.size())
	for i: int in range(recovery_waves.size()):
		var wave: Dictionary = recovery_waves[i] as Dictionary
		var section: String = "wave_%d" % i
		save.set_value(section, "wave_id", str(wave.get("wave_id", "")))
		save.set_value(section, "troop_tiers", wave.get("troop_tiers", {}))
		save.set_value(section, "total_quantity", int(wave.get("total_quantity", 0)))
		save.set_value(section, "start_unix", int(wave.get("start_unix", 0)))
		save.set_value(section, "end_unix", int(wave.get("end_unix", 0)))
		save.set_value(section, "restored", bool(wave.get("restored", false)))
	save.save(get_save_path())


func load_sanctuary_state() -> void:
	recovery_waves.clear()
	var save := ConfigFile.new()
	if save.load(get_save_path()) != OK:
		return
	var count: int = int(save.get_value("recovery", "wave_count", 0))
	for i: int in range(count):
		var section: String = "wave_%d" % i
		if not save.has_section(section):
			continue
		recovery_waves.append({
			"wave_id": str(save.get_value(section, "wave_id", "")),
			"troop_tiers": save.get_value(section, "troop_tiers", {}),
			"total_quantity": int(save.get_value(section, "total_quantity", 0)),
			"start_unix": int(save.get_value(section, "start_unix", 0)),
			"end_unix": int(save.get_value(section, "end_unix", 0)),
			"restored": bool(save.get_value(section, "restored", false)),
		})


func run_phase5_smoke_test() -> bool:
	begin_smoke_isolation()
	var failed: int = 0
	if not has_node("/root/TroopState") or not has_node("/root/HealingState"):
		push_error("[SanctuaryState] smoke missing TroopState/HealingState")
		end_smoke_isolation()
		return false

	var bak_w: Dictionary = TroopState.get_wounded_by_tiers()
	var bak_s: Dictionary = TroopState.get_sanctuary_by_tiers()
	var bak_inf: Dictionary = TroopState.infantry_by_tier.duplicate(true)
	var bak_heal: Dictionary = HealingState.active_job.duplicate(true)

	# Reset pools for deterministic occupancy.
	TroopState.wounded_infantry_by_tier = {1: 800}
	TroopState.wounded_marksmen_by_tier = {}
	TroopState.wounded_cavalry_by_tier = {}
	TroopState.sanctuary_infantry_by_tier = {}
	TroopState.sanctuary_marksmen_by_tier = {}
	TroopState.sanctuary_cavalry_by_tier = {}
	TroopState._resync_wounded_totals()
	TroopState._resync_sanctuary_totals()
	HealingState.active_job = {
		"job_id": "smoke_heal",
		"troop_tiers": {"infantry": {"1": 100}, "marksmen": {}, "cavalry": {}},
		"total_quantity": 100,
		"start_unix": 0,
		"end_unix": 999999999,
		"total_duration": 999,
		"costs": {},
		"restored": false,
	}

	# Force capacity 1000 for math (hospital level may vary — stub via occupancy).
	# Occupancy = 800 + 100 = 900; available = capacity - 900.
	var cap: int = TroopState.get_hospital_capacity()
	var occ: int = TroopState.get_hospital_occupancy()
	var avail: int = TroopState.get_hospital_available_capacity()
	if occ != 900:
		push_error("[SanctuaryState] smoke occupancy expected 900 got %d (cap=%d avail=%d)" % [occ, cap, avail])
		failed += 1

	# Scale test to capacity: want available=100. If cap != 1000, compute expected.
	var expected_h: int = avail
	var casualties: Dictionary = {"infantry": {"1": 150, "2": 75}, "marksmen": {}, "cavalry": {}}
	var total_c: int = 225
	var expected_s: int = total_c - expected_h
	if expected_h > total_c:
		expected_h = total_c
		expected_s = 0

	var routed: Dictionary = TroopState.route_wounded_by_tiers(casualties)
	if int(routed.get("hospital_count", -1)) != expected_h:
		push_error("[SanctuaryState] smoke hospital_count expected %d got %d" % [
			expected_h, int(routed.get("hospital_count", -1)),
		])
		failed += 1
	if int(routed.get("sanctuary_count", -1)) != expected_s:
		push_error("[SanctuaryState] smoke sanctuary_count expected %d got %d" % [
			expected_s, int(routed.get("sanctuary_count", -1)),
		])
		failed += 1
	else:
		print("[SanctuaryState] smoke overflow OK hospital=%d sanctuary=%d avail=%d" % [
			expected_h, expected_s, avail,
		])

	# Deterministic order: Infantry T1 fills hospital before T2.
	var h_part: Dictionary = routed.get("hospital", {}) as Dictionary
	var s_part: Dictionary = routed.get("sanctuary", {}) as Dictionary
	var h_inf: Dictionary = h_part.get("infantry", {}) as Dictionary
	var s_inf: Dictionary = s_part.get("infantry", {}) as Dictionary
	var h1: int = int(h_inf.get("1", h_inf.get(1, 0)))
	var h2: int = int(h_inf.get("2", h_inf.get(2, 0)))
	if expected_h >= 150:
		if h1 != 150:
			push_error("[SanctuaryState] smoke T1 should fill hospital first")
			failed += 1
	elif expected_h > 0:
		if h1 != expected_h or h2 != 0:
			push_error("[SanctuaryState] smoke low-tier-first failed h1=%d h2=%d expect_h=%d" % [h1, h2, expected_h])
			failed += 1
		var s1: int = int(s_inf.get("1", s_inf.get(1, 0)))
		var s2: int = int(s_inf.get("2", s_inf.get(2, 0)))
		if s1 + s2 != expected_s or s1 != 150 - expected_h or s2 != 75:
			push_error("[SanctuaryState] smoke sanctuary tier split wrong s1=%d s2=%d" % [s1, s2])
			failed += 1

	if expected_s > 0 and not has_recovering():
		push_error("[SanctuaryState] smoke expected recovery wave")
		failed += 1

	# Under-capacity: all to hospital when space.
	HealingState.active_job = {}
	TroopState.wounded_infantry_by_tier = {}
	TroopState.wounded_marksmen_by_tier = {}
	TroopState.wounded_cavalry_by_tier = {}
	TroopState._resync_wounded_totals()
	var under: Dictionary = TroopState.route_wounded_by_tiers({
		"infantry": {"1": 10}, "marksmen": {}, "cavalry": {},
	})
	if int(under.get("hospital_count", 0)) != 10 or int(under.get("sanctuary_count", 0)) != 0:
		push_error("[SanctuaryState] smoke under-capacity failed")
		failed += 1
	else:
		print("[SanctuaryState] smoke under-capacity OK")

	# Recovery completion → available, not hospital wounded.
	TroopState.sanctuary_infantry_by_tier = {3: 5}
	TroopState.sanctuary_marksmen_by_tier = {}
	TroopState.sanctuary_cavalry_by_tier = {}
	TroopState._resync_sanctuary_totals()
	recovery_waves.clear()
	enqueue_recovery({"infantry": {"3": 5}, "marksmen": {}, "cavalry": {}})
	var avail_before: int = TroopState.get_tier_count("Infantry", 3)
	var w_before: int = TroopState.get_wounded_tier_count("Infantry", 3)
	finish_soonest_wave_now()
	if TroopState.get_tier_count("Infantry", 3) - avail_before != 5:
		push_error("[SanctuaryState] smoke restore available failed")
		failed += 1
	if TroopState.get_wounded_tier_count("Infantry", 3) != w_before:
		push_error("[SanctuaryState] smoke must not enter hospital wounded")
		failed += 1
	if TroopState.get_sanctuary_tier_count("Infantry", 3) != 0:
		push_error("[SanctuaryState] smoke sanctuary stack not cleared")
		failed += 1
	else:
		print("[SanctuaryState] smoke recovery restore OK")

	# Offline: enqueue, backdate, reload.
	TroopState.sanctuary_infantry_by_tier = {1: 4}
	TroopState._resync_sanctuary_totals()
	recovery_waves.clear()
	enqueue_recovery({"infantry": {"1": 4}, "marksmen": {}, "cavalry": {}})
	if not recovery_waves.is_empty():
		recovery_waves[0]["end_unix"] = int(Time.get_unix_time_from_system()) - 3
		save_sanctuary_state()
		var a0: int = TroopState.get_tier_count("Infantry", 1)
		load_sanctuary_state()
		_resolve_due_waves()
		if TroopState.get_tier_count("Infantry", 1) - a0 != 4:
			push_error("[SanctuaryState] smoke offline restore failed")
			failed += 1
		else:
			print("[SanctuaryState] smoke offline OK")
		_resolve_due_waves()
		if TroopState.get_tier_count("Infantry", 1) - a0 != 4:
			push_error("[SanctuaryState] smoke offline duplicate")
			failed += 1

	# Restore player state
	TroopState.wounded_infantry_by_tier = TroopState._deserialize_tier_map(bak_w.get("infantry", {}), 0)
	TroopState.wounded_marksmen_by_tier = TroopState._deserialize_tier_map(bak_w.get("marksmen", {}), 0)
	TroopState.wounded_cavalry_by_tier = TroopState._deserialize_tier_map(bak_w.get("cavalry", {}), 0)
	TroopState.sanctuary_infantry_by_tier = TroopState._deserialize_tier_map(bak_s.get("infantry", {}), 0)
	TroopState.sanctuary_marksmen_by_tier = TroopState._deserialize_tier_map(bak_s.get("marksmen", {}), 0)
	TroopState.sanctuary_cavalry_by_tier = TroopState._deserialize_tier_map(bak_s.get("cavalry", {}), 0)
	TroopState.infantry_by_tier = bak_inf
	TroopState._resync_wounded_totals()
	TroopState._resync_sanctuary_totals()
	TroopState._resync_totals()
	TroopState.save_troops()
	HealingState.active_job = bak_heal
	HealingState.save_healing_state()

	end_smoke_isolation()
	if failed == 0:
		print("[SanctuaryState] Phase-5 smoke PASSED")
		return true
	print("[SanctuaryState] Phase-5 smoke FAILED count=%d" % failed)
	return false
