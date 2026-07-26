extends SceneTree

## Smoke: FTUE closes BuildingUpgradeWindow for COLLECT; formatter absolute units; SPEED UP enabled.
##   $env:CROWNSPIR_TUTORIAL_SMOKE="1"
##   Godot --headless --path <project> -s res://scripts/dev/ftue_modal_speedup_format_smoke.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if OS.get_environment("CROWNSPIR_TUTORIAL_SMOKE") != "1":
		push_error("[LIVE3] ABORT — CROWNSPIR_TUTORIAL_SMOKE=1 required")
		quit(2)
		return

	root.content_scale_size = Vector2i(383, 682)
	var err: Error = change_scene_to_file("res://Scenes/City/City.tscn")
	if err != OK:
		push_error("[LIVE3] City load failed")
		quit(1)
		return
	for _i in 14:
		await process_frame

	var fail: Array[String] = []
	var hud: Node = root.find_child("GameHUD", true, false)
	var overlay: Control = hud.get_node_or_null("TutorialOverlay") as Control if hud else null
	var ts: Node = root.get_node_or_null("/root/TutorialState")
	var cs: Node = root.get_node_or_null("/root/ConstructionState")
	if hud == null or overlay == null or ts == null or cs == null:
		push_error("[LIVE3] missing nodes")
		quit(1)
		return

	# --- Formatter absolute units (farm L5 costs are 68 wood / 25 stone, not thousands) ---
	if hud.has_method("format_number"):
		var f46: String = str(hud.call("format_number", 46))
		var f46k: String = str(hud.call("format_number", 46000))
		var f25: String = str(hud.call("format_number", 25))
		var f25k: String = str(hud.call("format_number", 25000))
		print("[LIVE3] format 46=", f46, " 46000=", f46k, " 25=", f25, " 25000=", f25k)
		if f46 != "46":
			fail.append("46 should format as '46' not '%s' (costs are absolute)" % f46)
		if f46k != "46.0K":
			fail.append("46000 should format as 46.0K got %s" % f46k)
		if f25k != "25.0K":
			fail.append("25000 should format as 25.0K got %s" % f25k)
		if str(hud.call("format_number", 1000000000)) != "1.0B":
			fail.append("1B format missing")

	# --- SPEED UP enabled while construction active ---
	for job: Variant in cs.get("active_jobs").duplicate():
		if typeof(job) == TYPE_DICTIONARY:
			cs.call("cancel_construction", str((job as Dictionary).get("building_id", "")))
	var start: Dictionary = cs.call("try_start_construction", "farm", 4, 5, 30.0)
	if not bool(start.get("ok", false)):
		fail.append("could not start construction: %s" % str(start.get("reason", "")))
	else:
		var win: Node = hud.find_child("BuildingUpgradeWindow", true, false)
		if win == null:
			# Instance may live under GameHUD with different path
			win = root.find_child("BuildingUpgradeWindow", true, false)
		if win != null and win.has_method("open_for_building"):
			win.call("open_for_building", "farm")
			await process_frame
			await process_frame
			var btn: Button = win.find_child("SpeedUpButton", true, false) as Button
			if btn == null:
				fail.append("SpeedUpButton missing after open")
			else:
				print("[LIVE3] SPEED UP disabled=", btn.disabled, " visible=", btn.visible)
				if btn.disabled:
					fail.append("SPEED UP should be enabled during active construction")
				if not btn.visible:
					fail.append("SPEED UP should be visible during active construction")

	# --- FTUE modal dismissal for collect_resources ---
	ts.call("begin_smoke_isolation")
	ts.call("load_tutorial_state")
	ts.call("begin_ftue")
	await process_frame
	# Open upgrade window then jump presentation to collect
	var buw: Node = root.find_child("BuildingUpgradeWindow", true, false)
	if buw != null and buw.has_method("open_for_building"):
		buw.call("open_for_building", "farm")
		await process_frame
		if not (buw as CanvasItem).visible:
			fail.append("BuildingUpgradeWindow failed to open for modal test")
		ts.set("current_step_id", "collect_resources")
		ts.emit_signal("step_changed", "collect_resources")
		await process_frame
		await process_frame
		print("[LIVE3] after collect step, upgrade visible=", (buw as CanvasItem).visible)
		if (buw as CanvasItem).visible:
			fail.append("BuildingUpgradeWindow still open on COLLECT step")

	cs.call("cancel_construction", "farm")

	if fail.is_empty():
		print("[LIVE3] PASS")
		quit(0)
	else:
		for f: String in fail:
			push_error("[LIVE3] FAIL: %s" % f)
		quit(1)
