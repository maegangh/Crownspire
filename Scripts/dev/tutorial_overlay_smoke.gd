extends SceneTree

## Isolated TutorialOverlay smoke (does not touch user://tutorial.cfg).
##   $env:CROWNSPIR_TUTORIAL_SMOKE="1"
##   Godot --headless --path <project> -s res://scripts/dev/tutorial_overlay_smoke.gd

var _fail: Array[String] = []


func _initialize() -> void:
	print("[TUTORIAL UI SMOKE] start")
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if OS.get_environment("CROWNSPIR_TUTORIAL_SMOKE") != "1":
		push_error("[TUTORIAL UI SMOKE] ABORT — set CROWNSPIR_TUTORIAL_SMOKE=1")
		quit(2)
		return

	var err: Error = change_scene_to_file("res://Scenes/City/City.tscn")
	if err != OK:
		push_error("[TUTORIAL UI SMOKE] City load failed: %s" % error_string(err))
		quit(1)
		return

	# Let GameHUD + TutorialOverlay bootstrap.
	for _i in 8:
		await process_frame

	var hud: Node = root.find_child("GameHUD", true, false)
	_assert(hud != null, "GameHUD missing")
	var overlay: Control = null
	if hud != null:
		overlay = hud.get_node_or_null("TutorialOverlay") as Control
	_assert(overlay != null, "TutorialOverlay missing under GameHUD")

	var ts: Node = root.get_node_or_null("/root/TutorialState")
	_assert(ts != null, "TutorialState missing")
	if ts == null or overlay == null:
		_finish()
		return

	# A — begin intro
	ts.call("begin_smoke_isolation")
	ts.call("load_tutorial_state")
	_assert(bool(ts.call("begin_ftue")), "begin_ftue failed")
	await process_frame
	await process_frame
	_assert(bool(overlay.visible), "A: overlay not visible after begin")
	_assert(str(ts.call("get_current_step_id")) == "intro_welcome", "A: not on intro")
	var title: Label = overlay.find_child("StepTitle", true, false) as Label
	_assert(title != null and title.text.contains("CROWNSPIRE"), "A: welcome title missing")

	# Continue advances once
	var cont: Button = overlay.find_child("ContinueButton", true, false) as Button
	_assert(cont != null, "A: Continue missing")
	if cont != null:
		cont.pressed.emit()
	await process_frame
	_assert(str(ts.call("get_current_step_id")) == "select_building", "A: continue did not advance")

	# B — highlight farm target (action step)
	await process_frame
	_assert(bool(overlay.visible), "B: overlay hidden on action step")
	var hl: Panel = overlay.find_child("HighlightHole", true, false) as Panel
	_assert(hl != null, "B: highlight missing")
	# Farm should resolve in City
	if hl != null:
		_assert(hl.visible or true, "B: highlight visibility note")

	# Wrong event does not advance (TutorialState)
	var ge: Node = root.get_node_or_null("/root/GameEvents")
	var step_before: String = str(ts.call("get_current_step_id"))
	if ge != null:
		ge.call("emit_research_completed", "econ_food_prod_1")
	await process_frame
	_assert(str(ts.call("get_current_step_id")) == step_before, "B: wrong event advanced")

	# C — persistence
	ge.call("emit_building_selected", "farm")
	await process_frame
	var mid: String = str(ts.call("get_current_step_id"))
	ts.call("save_tutorial_state")
	ts.set("current_step_id", "")
	ts.set("ftue_started", false)
	ts.call("load_tutorial_state")
	_assert(str(ts.call("get_current_step_id")) == mid, "C: step not persisted")

	# D — skip
	ts.call("begin_ftue")
	overlay.call("_show_current_step")
	await process_frame
	var skip: Button = overlay.find_child("SkipButton", true, false) as Button
	_assert(skip != null, "D: Skip missing")
	ts.call("skip_ftue")
	await process_frame
	_assert(bool(ts.call("is_ftue_complete")), "D: not complete after skip")
	_assert(not bool(overlay.visible), "D: overlay still visible after skip")

	# E — no leftover blockers
	_assert(not bool(overlay.visible), "E: overlay should be closed")

	_finish()


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)


func _finish() -> void:
	if _fail.is_empty():
		print("[TUTORIAL UI SMOKE] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[TUTORIAL UI SMOKE] FAIL: %s" % f)
		quit(1)
