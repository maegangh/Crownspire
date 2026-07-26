extends SceneTree

## Shared speedup smoke: eligibility, timer reduction, overflow completion, bag consume.
##   $env:CROWNSPIR_SPEEDUP_SMOKE="1"
##   Godot --headless --path <project> -s res://scripts/dev/speedup_shared_smoke.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if OS.get_environment("CROWNSPIR_SPEEDUP_SMOKE") != "1":
		push_error("[SPEEDUP SMOKE] ABORT — CROWNSPIR_SPEEDUP_SMOKE=1 required")
		quit(2)
		return

	var fail: Array[String] = []
	var svc: Node = root.get_node_or_null("/root/SpeedupService")
	var bag: Node = root.get_node_or_null("/root/BagState")
	var cs: Node = root.get_node_or_null("/root/ConstructionState")
	var rs: Node = root.get_node_or_null("/root/ResearchState")
	var ts: Node = root.get_node_or_null("/root/TroopState")
	if svc == null or bag == null or cs == null or rs == null or ts == null:
		push_error("[SPEEDUP SMOKE] Missing autoload(s)")
		quit(1)
		return

	# Isolate bag for this smoke.
	bag.set("items", {})
	bag.call("save_bag")

	# Duration parse + eligibility
	if int(svc.call("get_speedup_seconds", "speedup_universal_1h")) != 3600:
		fail.append("universal_1h duration")
	if int(svc.call("get_speedup_seconds", "speedup_training_3h")) != 10800:
		fail.append("training_3h duration")
	if int(svc.call("get_speedup_seconds", "speedup_construction_24h")) != 86400:
		fail.append("construction_24h duration")
	if not bool(svc.call("is_eligible_speedup", "speedup_universal_1h", "training")):
		fail.append("universal should be eligible for training")
	if bool(svc.call("is_eligible_speedup", "speedup_research_8h", "training")):
		fail.append("research speedup must NOT show for training")
	if bool(svc.call("is_eligible_speedup", "speedup_construction_24h", "research")):
		fail.append("construction speedup must NOT show for research")
	if bool(svc.call("is_eligible_speedup", "speedup_healing_1h", "construction")):
		fail.append("healing speedup must NOT show for construction")
	if bool(svc.call("is_eligible_speedup", "speedup_march_50", "construction")):
		fail.append("march speedup must NOT be timer-eligible")

	# --- Construction ---
	# Clear jobs
	for job: Variant in cs.get("active_jobs").duplicate():
		if typeof(job) == TYPE_DICTIONARY:
			cs.call("cancel_construction", str((job as Dictionary).get("building_id", "")))
	bag.call("add_item", "speedup_universal_1h", 2)
	bag.call("add_item", "speedup_construction_24h", 1)
	var start_c: Dictionary = cs.call("try_start_construction", "farm", 1, 2, 7200.0) # 2h
	if not bool(start_c.get("ok", false)):
		fail.append("start construction failed: %s" % str(start_c.get("reason", "")))
	else:
		var rem0: float = float(cs.call("get_remaining_seconds", "farm"))
		var owned0: int = int(bag.call("get_item_count", "speedup_universal_1h"))
		var r1: Dictionary = svc.call("apply_speedup_item", "construction", "farm", "speedup_universal_1h", 1)
		if not bool(r1.get("ok", false)):
			fail.append("construction speedup failed: %s" % str(r1.get("reason", "")))
		var rem1: float = float(cs.call("get_remaining_seconds", "farm"))
		var owned1: int = int(bag.call("get_item_count", "speedup_universal_1h"))
		print("[SPEEDUP SMOKE] construction rem %.0f→%.0f owned %d→%d" % [rem0, rem1, owned0, owned1])
		if owned1 != owned0 - 1:
			fail.append("construction did not consume bag item")
		if rem1 > rem0 - 3500.0: # allow small tick drift
			fail.append("construction timer not reduced by ~1h")
		# Finish with construction 24h
		var r2: Dictionary = svc.call("apply_speedup_item", "construction", "farm", "speedup_construction_24h", 1)
		if not bool(r2.get("ok", false)):
			fail.append("construction finish speedup failed")
		elif not bool(r2.get("completed", false)):
			fail.append("construction should complete on overflow")
		if cs.call("is_building_upgrading", "farm"):
			fail.append("construction queue not freed after complete")

	# --- Research ---
	for job2: Variant in rs.get("active_jobs").duplicate():
		if typeof(job2) == TYPE_DICTIONARY:
			rs.call("cancel_research", str((job2 as Dictionary).get("research_id", "")))
	bag.call("add_item", "speedup_research_8h", 1)
	bag.call("add_item", "speedup_training_3h", 1)
	var start_r: Dictionary = rs.call("try_start_research", {
		"research_id": "smoke_tech",
		"level": 1,
		"time_remaining": 9000.0,
		"total_duration": 9000.0,
	})
	if not bool(start_r.get("ok", false)):
		fail.append("start research failed: %s" % str(start_r.get("reason", "")))
	else:
		var elig: Array = svc.call("list_owned_eligible", "research")
		for e: Variant in elig:
			if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("item_id", "")) == "speedup_training_3h":
				fail.append("training item listed for research")
		var rem_r0: float = float(rs.call("get_remaining_seconds", "smoke_tech"))
		var rr: Dictionary = svc.call("apply_speedup_item", "research", "smoke_tech", "speedup_research_8h", 1)
		print("[SPEEDUP SMOKE] research rem %.0f result=%s" % [rem_r0, str(rr)])
		if not bool(rr.get("ok", false)):
			fail.append("research speedup failed")
		elif not bool(rr.get("completed", false)):
			fail.append("research 8h should complete 9000s job")
		if rs.call("_find_job_index", "smoke_tech") >= 0:
			fail.append("research job still active after complete")

	# --- Training ---
	# Clear infantry job if any
	if bool(ts.call("is_training_active", "Infantry")) or bool(ts.call("is_training_ready", "Infantry")):
		ts.call("_clear_job", "Infantry")
		ts.call("save_troops")
	bag.call("add_item", "speedup_training_3h", 2)
	# Start a short-ish train via public API if available
	var started_train: bool = false
	# start_training(type, amount, duration_sec, target_tier)
	if ts.has_method("start_training"):
		started_train = bool(ts.call("start_training", "Infantry", 5, 4000, 1))
	if not started_train:
		ts.set("infantry_training_active", true)
		ts.set("infantry_training_ready", false)
		ts.set("infantry_training_amount", 5)
		ts.set("infantry_target_tier", 1)
		ts.set("infantry_job_type", "train")
		ts.set("infantry_finish_time", int(Time.get_unix_time_from_system()) + 4000)
		ts.call("save_troops")
		started_train = true
	if not started_train:
		fail.append("could not start training job for smoke")
	else:
		var rem_t0: float = float(ts.call("get_training_time_left", "Infantry"))
		var rt: Dictionary = svc.call("apply_speedup_item", "training", "Infantry", "speedup_training_3h", 1)
		print("[SPEEDUP SMOKE] training rem %.0f result=%s ready=%s" % [
			rem_t0, str(rt.get("ok", false)), str(ts.call("is_training_ready", "Infantry"))
		])
		if not bool(rt.get("ok", false)):
			fail.append("training speedup failed")
		if not bool(ts.call("is_training_ready", "Infantry")):
			fail.append("training should be READY after 3h speedup on 4000s job")
		if bool(ts.call("is_training_ready", "Infantry")):
			var before: int = int(ts.call("get_tier_count", "Infantry", 1)) if ts.has_method("get_tier_count") else -1
			var collected: bool = bool(ts.call("collect_training", "Infantry"))
			if not collected:
				fail.append("collect_training failed after speedup-to-ready")
			var after: int = int(ts.call("get_tier_count", "Infantry", 1)) if ts.has_method("get_tier_count") else -1
			if before >= 0 and after != before + 5:
				fail.append("troops not awarded exactly once on collect (before=%d after=%d)" % [before, after])
			# Second collect must fail (no double award).
			if bool(ts.call("collect_training", "Infantry")):
				fail.append("second collect unexpectedly succeeded")

	# Persistence spot-check: construction end_unix survives save/load
	cs.call("try_start_construction", "quarry", 1, 2, 10000.0)
	bag.call("add_item", "speedup_universal_1h", 1)
	svc.call("apply_speedup_item", "construction", "quarry", "speedup_universal_1h", 1)
	var end_before: int = 0
	for j: Variant in cs.get("active_jobs"):
		if typeof(j) == TYPE_DICTIONARY and str((j as Dictionary).get("building_id", "")) == "quarry":
			end_before = int((j as Dictionary).get("end_unix", 0))
	cs.call("save_construction_state")
	cs.set("active_jobs", [])
	cs.call("load_construction_state")
	var end_after: int = 0
	for j2: Variant in cs.get("active_jobs"):
		if typeof(j2) == TYPE_DICTIONARY and str((j2 as Dictionary).get("building_id", "")) == "quarry":
			end_after = int((j2 as Dictionary).get("end_unix", 0))
	print("[SPEEDUP SMOKE] persist end_unix %d→%d" % [end_before, end_after])
	if end_before <= 0 or end_before != end_after:
		fail.append("construction end_unix did not persist")
	cs.call("cancel_construction", "quarry")

	if fail.is_empty():
		print("[SPEEDUP SMOKE] PASS")
		quit(0)
	else:
		for f: String in fail:
			push_error("[SPEEDUP SMOKE] FAIL: %s" % f)
		quit(1)
