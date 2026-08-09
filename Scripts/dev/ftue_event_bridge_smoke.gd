extends SceneTree

## Headless smoke for Sprint 1A GameEvents bridge.
## Run: Godot --headless --path <project> -s res://Scripts/dev/ftue_event_bridge_smoke.gd

var _seen: Dictionary = {}
var _fail: Array[String] = []
var _ge: Node = null
var _cs: Node = null
var _rs: Node = null
var _ts: Node = null


func _initialize() -> void:
	print("[FTUE SMOKE] start")
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_ge = root.get_node_or_null("/root/GameEvents")
	_cs = root.get_node_or_null("/root/ConstructionState")
	_rs = root.get_node_or_null("/root/ResearchState")
	_ts = root.get_node_or_null("/root/TroopState")
	if _ge == null:
		push_error("[FTUE SMOKE] GameEvents autoload missing")
		quit(1)
		return

	_connect_all()

	_ge.call("emit_city_opened")
	_ge.call("emit_world_opened")
	_ge.call("emit_building_selected", "academy")
	_ge.call("emit_mail_opened")
	_ge.call("emit_alliance_opened")
	_ge.call("emit_wildling_selected", "wolf_L1")
	_ge.call("emit_resource_tile_selected", "wood")
	_ge.call("emit_march_dispatched", {"march_id": "smoke_m1", "march_type": "gather"})
	_ge.call("emit_gathering_started", "wood")
	_ge.call("emit_gathering_completed", "wood", 50)

	await _test_construction()
	await _test_research()
	await _test_training()

	_assert_seen("city_opened")
	_assert_seen("world_opened")
	_assert_seen("building_selected")
	_assert_seen("building_upgrade_started")
	_assert_seen("building_upgraded")
	_assert_seen("research_started")
	_assert_seen("research_completed")
	_assert_seen("troop_training_started")
	_assert_seen("troop_training_completed")
	_assert_seen("mail_opened")
	_assert_seen("alliance_opened")
	_assert_seen("wildling_selected")
	_assert_seen("resource_tile_selected")
	_assert_seen("march_dispatched")
	_assert_seen("gathering_started")
	_assert_seen("gathering_completed")

	if _fail.is_empty():
		print("[FTUE SMOKE] PASS — all expected events observed")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[FTUE SMOKE] FAIL: %s" % f)
		quit(1)


func _connect_all() -> void:
	_ge.connect("city_opened", func() -> void: _mark("city_opened"))
	_ge.connect("world_opened", func() -> void: _mark("world_opened"))
	_ge.connect("building_selected", func(_id: String) -> void: _mark("building_selected"))
	_ge.connect("building_upgrade_started", func(_id: String, _lvl: int) -> void: _mark("building_upgrade_started"))
	_ge.connect("building_upgraded", func(_id: String, _lvl: int) -> void: _mark("building_upgraded"))
	_ge.connect("research_started", func(_id: String) -> void: _mark("research_started"))
	_ge.connect("research_completed", func(_id: String) -> void: _mark("research_completed"))
	_ge.connect("troop_training_started", func(_t: String, _tier: int, _n: int) -> void: _mark("troop_training_started"))
	_ge.connect("troop_training_completed", func(_t: String, _tier: int, _n: int) -> void: _mark("troop_training_completed"))
	_ge.connect("mail_opened", func() -> void: _mark("mail_opened"))
	_ge.connect("alliance_opened", func() -> void: _mark("alliance_opened"))
	_ge.connect("wildling_selected", func(_id: String) -> void: _mark("wildling_selected"))
	_ge.connect("resource_tile_selected", func(_t: String) -> void: _mark("resource_tile_selected"))
	_ge.connect("march_dispatched", func(_m: Dictionary) -> void: _mark("march_dispatched"))
	_ge.connect("gathering_started", func(_t: String) -> void: _mark("gathering_started"))
	_ge.connect("gathering_completed", func(_t: String, _n: int) -> void: _mark("gathering_completed"))
	_ge.connect("wildling_defeated", func(_id: String) -> void: _mark("wildling_defeated"))


func _mark(key: String) -> void:
	_seen[key] = true


func _assert_seen(key: String) -> void:
	if not bool(_seen.get(key, false)):
		_fail.append("missing event: %s" % key)


func _test_construction() -> void:
	if _cs == null:
		_fail.append("ConstructionState missing")
		return
	var bid := "farm"
	if bool(_cs.call("is_building_upgrading", bid)):
		_cs.call("cancel_construction", bid)
	var from_lvl: int = 1
	if FileAccess.file_exists("user://buildings.cfg"):
		var cfg := ConfigFile.new()
		if cfg.load("user://buildings.cfg") == OK:
			from_lvl = int(cfg.get_value(bid, "level", 1))
	var target: int = from_lvl + 1
	var started: Dictionary = _cs.call("try_start_construction", bid, from_lvl, target, 0.05)
	if not bool(started.get("ok", false)):
		_fail.append("construction start failed: %s" % str(started.get("reason", "")))
		return
	var done: Dictionary = _cs.call("finish_construction_now", bid)
	if not bool(done.get("ok", false)):
		_fail.append("construction finish failed")
	await process_frame


func _test_research() -> void:
	if _rs == null:
		_fail.append("ResearchState missing")
		return
	var rid := "construction_speed_1"
	var existing: Dictionary = _rs.call("get_job_for", rid)
	if not existing.is_empty():
		_rs.call("cancel_research", rid)
	var next_lvl: int = maxi(1, int(_rs.call("get_research_level", rid)) + 1)
	var started: Dictionary = _rs.call("try_start_research", {
		"research_id": rid,
		"level": next_lvl,
		"time_remaining": 0.01,
		"total_duration": 0.01,
	})
	if not bool(started.get("ok", false)):
		_fail.append("research start failed: %s" % str(started.get("reason", "")))
	var guard := 0
	var jobs: Array = _rs.get("active_jobs") as Array
	while not jobs.is_empty() and guard < 200:
		_rs.call("_tick_jobs", 1.0)
		jobs = _rs.get("active_jobs") as Array
		guard += 1
		await process_frame
	await process_frame


func _test_training() -> void:
	if _ts == null:
		_fail.append("TroopState missing")
		return
	var ttype := "Infantry"
	if bool(_ts.call("has_active_job", ttype)):
		if bool(_ts.call("is_training_ready", ttype)):
			_ts.call("collect_training", ttype)
		else:
			_fail.append("infantry job already active — skip training bridge test")
			return
	if not bool(_ts.call("start_training", ttype, 2, 1, 1)):
		_fail.append("start_training failed")
		return
	_ts.set("infantry_finish_time", int(Time.get_unix_time_from_system()) - 1)
	_ts.call("check_finished_training")
	if not bool(_ts.call("collect_training", ttype)):
		_fail.append("collect_training failed")
	await process_frame
