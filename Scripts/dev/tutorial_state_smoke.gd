extends SceneTree

## Isolated TutorialState smoke (Citadel-first FTUE).
## MUST set CROWNSPIR_TUTORIAL_SMOKE=1 so TutorialState never touches user://tutorial.cfg.
## Run:
##   $env:CROWNSPIR_TUTORIAL_SMOKE=1
##   Godot --headless --path <project> -s res://Scripts/dev/tutorial_state_smoke.gd

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
	_test_i_citadel_skip_when_l2()
	_test_c_correct_event()
	_test_d_save_reload()
	_test_e_duplicate_event()
	_test_f_skip()
	_test_g_debug_reset()
	_test_h_completed_persists()
	_test_j_farm_cannot_satisfy_citadel()

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


func _citadel_level() -> int:
	var cs: Node = root.get_node_or_null("/root/ConstructionState")
	if cs == null or not cs.has_method("get_canonical_building_level"):
		return 1
	return int(cs.call("get_canonical_building_level", "castle"))


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
	_assert(str(_ts.call("get_current_step_id")) == before, "B: farm upgrade must not advance intro")


func _ensure_citadel_l1() -> void:
	var cs: Node = root.get_node_or_null("/root/ConstructionState")
	if cs == null:
		return
	if not cs.has_method("get_canonical_building_level") or not cs.has_method("debug_reset_citadel_for_ftue_retest"):
		return
	if int(cs.call("get_canonical_building_level", "castle")) >= 2:
		cs.call("debug_reset_citadel_for_ftue_retest")


func _restart_smoke_ftue() -> void:
	_ts.call("begin_smoke_isolation")
	_ts.call("load_tutorial_state")
	_ts.call("begin_ftue")


func _test_c_correct_event() -> void:
	print("[TUTORIAL SMOKE] C correct event (Citadel-first)")
	_ensure_citadel_l1()
	_restart_smoke_ftue()
	_assert(bool(_ts.call("acknowledge_intro")), "C: acknowledge_intro failed")
	_assert(str(_ts.call("get_current_step_id")) == "select_building", "C: expected select_building")
	_assert(bool(_ts.call("is_step_completed", "intro_welcome")), "C: intro not marked completed")

	var step: Dictionary = _ts.call("get_current_step")
	_assert(str(step.get("target_id", "")) == "castle", "C: select_building must target castle")

	var before_farm: String = str(_ts.call("get_current_step_id"))
	_ge.call("emit_building_selected", "farm")
	_assert(str(_ts.call("get_current_step_id")) == before_farm, "C: farm select must not advance citadel step")

	_ge.call("emit_building_selected", "castle")
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
	print("[TUTORIAL SMOKE] E duplicate event (Citadel upgrade path)")
	# Advance once with correct Citadel event.
	_ge.call("emit_building_upgrade_started", "castle", 2)
	_assert(str(_ts.call("get_current_step_id")) == "complete_building_upgrade", "E: setup advance failed")
	# Farm must not satisfy Citadel completion.
	_ge.call("emit_building_upgraded", "farm", 2)
	_assert(str(_ts.call("get_current_step_id")) == "complete_building_upgrade", "E: farm upgrade satisfied citadel step")
	# Duplicate of previous event must not skip ahead.
	_ge.call("emit_building_upgrade_started", "castle", 2)
	_assert(str(_ts.call("get_current_step_id")) == "complete_building_upgrade", "E: duplicate upgrade_started advanced")
	# Completing Citadel once → Farm collect lesson; duplicate must not multi-skip.
	_ge.call("emit_building_upgraded", "castle", 2)
	_assert(str(_ts.call("get_current_step_id")) == "collect_resources", "E: citadel upgrade complete should reach collect_resources")
	_ge.call("emit_building_upgraded", "castle", 3)
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


func _test_i_citadel_skip_when_l2() -> void:
	print("[TUTORIAL SMOKE] I citadel skip when already L2+")
	if _citadel_level() < 2:
		print("[TUTORIAL SMOKE] I skipped — Citadel not L2+ in this environment")
		return
	_ts.call("begin_smoke_isolation")
	_ts.call("load_tutorial_state")
	_ts.call("begin_ftue")
	_ts.call("acknowledge_intro")
	_assert(
		str(_ts.call("get_current_step_id")) == "collect_resources",
		"I: intro should skip obsolete citadel steps → collect_resources when L2+"
	)
	for step_name: String in ["select_building", "start_building_upgrade", "complete_building_upgrade"]:
		_assert(bool(_ts.call("is_step_completed", step_name)), "I: %s should be marked complete after skip" % step_name)
	# reconcile remains idempotent when already past citadel steps.
	var changed: bool = bool(_ts.call("reconcile_citadel_ftue_progress"))
	_assert(not changed, "I: reconcile should be no-op once on collect_resources")
	_assert(str(_ts.call("get_current_step_id")) == "collect_resources", "I: step changed after no-op reconcile")


func _test_j_farm_cannot_satisfy_citadel() -> void:
	print("[TUTORIAL SMOKE] J farm cannot satisfy citadel objectives")
	_ensure_citadel_l1()
	_restart_smoke_ftue()
	_ts.call("acknowledge_intro")
	_ge.call("emit_building_selected", "castle")
	_ge.call("emit_building_upgrade_started", "castle", 2)
	_assert(str(_ts.call("get_current_step_id")) == "complete_building_upgrade", "J: setup on complete_building_upgrade failed")
	_ge.call("emit_building_upgraded", "farm", 2)
	_assert(str(_ts.call("get_current_step_id")) == "complete_building_upgrade", "J: farm L2 must not complete citadel upgrade step")
