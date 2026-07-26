extends SceneTree

## Isolated TutorialState smoke.
## MUST set CROWNSPIR_TUTORIAL_SMOKE=1 so TutorialState never touches user://tutorial.cfg.
## Run:
##   $env:CROWNSPIR_TUTORIAL_SMOKE=1
##   Godot --headless --path <project> -s res://scripts/dev/tutorial_state_smoke.gd

var _fail: Array[String] = []
var _ts: Node = null
var _ge: Node = null


func _initialize() -> void:
	print("[TUTORIAL SMOKE] start")
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if OS.get_environment("CROWNSPIR_TUTORIAL_SMOKE") != "1":
		push_error("[TUTORIAL SMOKE] ABORT — CROWNSPIR_TUTORIAL_SMOKE=1 required (protects real tutorial.cfg)")
		quit(2)
		return

	_ts = root.get_node_or_null("/root/TutorialState")
	_ge = root.get_node_or_null("/root/GameEvents")
	if _ts == null or _ge == null:
		push_error("[TUTORIAL SMOKE] TutorialState or GameEvents missing")
		quit(1)
		return

	if str(_ts.call("get_save_path")) != "user://tutorial_smoke_test.cfg":
		_fail.append("save path not isolated: %s" % str(_ts.call("get_save_path")))

	_test_a_new_state()
	_test_b_wrong_event()
	_test_c_correct_event()
	_test_d_save_reload()
	_test_e_duplicate_event()
	_test_f_skip()
	_test_g_debug_reset()
	_test_h_completed_persists()

	if _fail.is_empty():
		print("[TUTORIAL SMOKE] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[TUTORIAL SMOKE] FAIL: %s" % f)
		quit(1)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)


func _test_a_new_state() -> void:
	print("[TUTORIAL SMOKE] A new state")
	_ts.call("begin_smoke_isolation")
	_ts.call("load_tutorial_state")
	_assert(not bool(_ts.call("is_ftue_active")), "A: should start inactive")
	_assert(not bool(_ts.call("is_ftue_complete")), "A: should not be complete")
	_assert(bool(_ts.call("begin_ftue")), "A: begin_ftue failed")
	_assert(bool(_ts.call("is_ftue_active")), "A: should be active after begin")
	_assert(str(_ts.call("get_current_step_id")) == "intro_welcome", "A: first step should be intro_welcome")


func _test_b_wrong_event() -> void:
	print("[TUTORIAL SMOKE] B wrong event")
	var before: String = str(_ts.call("get_current_step_id"))
	_ge.call("emit_building_upgraded", "farm", 2)
	_assert(str(_ts.call("get_current_step_id")) == before, "B: wrong event advanced step")


func _test_c_correct_event() -> void:
	print("[TUTORIAL SMOKE] C correct event")
	_assert(bool(_ts.call("acknowledge_intro")), "C: acknowledge_intro failed")
	_assert(str(_ts.call("get_current_step_id")) == "select_building", "C: expected select_building")
	_assert(bool(_ts.call("is_step_completed", "intro_welcome")), "C: intro not marked completed")
	_ge.call("emit_building_selected", "farm")
	_assert(str(_ts.call("get_current_step_id")) == "start_building_upgrade", "C: expected start_building_upgrade")


func _test_d_save_reload() -> void:
	print("[TUTORIAL SMOKE] D save/reload")
	var step_before: String = str(_ts.call("get_current_step_id"))
	_ts.call("save_tutorial_state")
	# Simulate reload of tutorial progress only.
	_ts.set("current_step_id", "")
	_ts.set("ftue_started", false)
	_ts.set("completed_steps", PackedStringArray())
	_ts.call("load_tutorial_state")
	_assert(bool(_ts.call("is_ftue_active")), "D: active lost after reload")
	_assert(str(_ts.call("get_current_step_id")) == step_before, "D: step not persisted (%s vs %s)" % [str(_ts.call("get_current_step_id")), step_before])
	_assert(bool(_ts.call("is_step_completed", "intro_welcome")), "D: completed_steps lost")


func _test_e_duplicate_event() -> void:
	print("[TUTORIAL SMOKE] E duplicate event")
	# Advance once with correct event.
	_ge.call("emit_building_upgrade_started", "farm", 2)
	_assert(str(_ts.call("get_current_step_id")) == "complete_building_upgrade", "E: setup advance failed")
	# Duplicate of previous event must not skip ahead.
	_ge.call("emit_building_upgrade_started", "farm", 2)
	_assert(str(_ts.call("get_current_step_id")) == "complete_building_upgrade", "E: duplicate advanced")
	# Completing event once → next; second identical completion must not multi-skip.
	_ge.call("emit_building_upgraded", "farm", 2)
	_assert(str(_ts.call("get_current_step_id")) == "collect_resources", "E: upgrade complete advance failed")
	_ge.call("emit_building_upgraded", "farm", 3)
	_assert(str(_ts.call("get_current_step_id")) == "collect_resources", "E: duplicate upgraded multi-skipped")


func _test_f_skip() -> void:
	print("[TUTORIAL SMOKE] F skip")
	var food_before: int = -1
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		food_before = int(gs.get("food"))
	_ts.call("skip_ftue")
	_assert(bool(_ts.call("is_ftue_complete")), "F: not complete after skip")
	_assert(bool(_ts.get("skipped")), "F: skipped flag false")
	_assert(not bool(_ts.call("is_ftue_active")), "F: still active after skip")
	if gs != null and food_before >= 0:
		_assert(int(gs.get("food")) == food_before, "F: skip mutated GameState.food")


func _test_g_debug_reset() -> void:
	print("[TUTORIAL SMOKE] G debug reset")
	var ok: bool = bool(_ts.call("debug_reset_ftue"))
	_assert(ok, "G: debug_reset_ftue failed (need debug build)")
	_assert(not bool(_ts.call("is_ftue_complete")), "G: still complete after reset")
	_assert(not bool(_ts.call("is_ftue_active")), "G: active after reset without begin")
	_assert(str(_ts.call("get_current_step_id")) == "", "G: step not cleared")


func _test_h_completed_persists() -> void:
	print("[TUTORIAL SMOKE] H completed persists")
	_ts.call("begin_ftue")
	_ts.call("skip_ftue")
	_ts.call("save_tutorial_state")
	_ts.set("ftue_completed", false)
	_ts.set("skipped", false)
	_ts.set("current_step_id", "intro_welcome")
	_ts.call("load_tutorial_state")
	_assert(bool(_ts.call("is_ftue_complete")), "H: completed lost after reload")
	_assert(bool(_ts.get("skipped")), "H: skipped lost after reload")
	# Wrong events must not reopen a completed FTUE.
	_ge.call("emit_research_completed", "econ_food_prod_1")
	_assert(bool(_ts.call("is_ftue_complete")), "H: event reopened completed FTUE")
	_assert(not bool(_ts.call("is_ftue_active")), "H: completed became active")
