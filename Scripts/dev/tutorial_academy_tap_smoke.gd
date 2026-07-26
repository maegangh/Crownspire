extends SceneTree

## KNOWLEDGE step: after TroopTraining, Academy spotlight tap must reach normal
## activate_building_tap → building_selected("academy") → TutorialState advance.
##   $env:CROWNSPIR_TUTORIAL_SMOKE="1"
##   Godot --headless --path <project> -s res://scripts/dev/tutorial_academy_tap_smoke.gd

var _fail: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if OS.get_environment("CROWNSPIR_TUTORIAL_SMOKE") != "1":
		push_error("[ACADEMY TAP] ABORT — CROWNSPIR_TUTORIAL_SMOKE=1 required")
		quit(2)
		return

	root.content_scale_size = Vector2i(417, 742)
	DisplayServer.window_set_size(Vector2i(417, 742))

	var err: Error = change_scene_to_file("res://Scenes/City/City.tscn")
	if err != OK:
		push_error("[ACADEMY TAP] City load failed")
		quit(1)
		return
	for _i in 14:
		await process_frame

	var scene: Node = get_current_scene()
	var hud: Node = root.find_child("GameHUD", true, false)
	var cam: Node = scene.get_node_or_null("Camera2D")
	var hud_mgr: Node = hud.get_node_or_null("UIManager") if hud else null
	var overlay: Control = hud.get_node_or_null("TutorialOverlay") as Control if hud else null
	var ts: Node = root.get_node_or_null("/root/TutorialState")
	var academy: Node = scene.get_node_or_null("Buildings/Academy")
	var gs: Node = root.get_node_or_null("/root/GameState")
	if scene == null or hud == null or cam == null or overlay == null or ts == null or academy == null:
		push_error("[ACADEMY TAP] missing scene nodes")
		quit(1)
		return

	# Leave-behind that previously swallowed KNOWLEDGE taps.
	hud_mgr.call("open_screen", "TroopTrainingScreen")
	await process_frame
	_assert(bool(hud_mgr.call("is_screen_open")), "precondition: training screen open")

	ts.call("begin_smoke_isolation")
	ts.call("load_tutorial_state")
	ts.set("ftue_started", true)
	ts.set("ftue_completed", false)
	ts.set("skipped", false)
	ts.set("current_step_id", "open_research")
	ts.emit_signal("step_changed", "open_research")
	await process_frame
	await process_frame
	await process_frame

	_assert(not bool(hud_mgr.call("is_screen_open")), "HUD UIManager still open after open_research")
	_assert(not bool(cam.call("_is_blocked")), "camera still blocked after open_research")
	if gs != null:
		_assert(not bool(gs.get("popup_open")), "popup_open stuck true")

	# Camera focus updates canvas transforms next frames — wait for a real hole.
	var hole: Control = null
	for _w in 12:
		hole = overlay.find_child("HighlightHole", true, false) as Control
		if hole != null and hole.visible and hole.size.x >= 40.0 and hole.size.y >= 40.0:
			break
		await process_frame
	if hole == null or not hole.visible or hole.size.x < 40.0 or hole.size.y < 40.0:
		_fail.append("HighlightHole missing/unstable")
		for f: String in _fail:
			push_error("[ACADEMY TAP] FAIL: %s" % f)
		quit(1)
		return
	_assert(int(hole.mouse_filter) == int(Control.MOUSE_FILTER_IGNORE), "HighlightHole must IGNORE")
	var panel: Control = overlay.find_child("InstructionPanel", true, false) as Control
	if panel != null:
		_assert(
			int(panel.mouse_filter) == int(Control.MOUSE_FILTER_IGNORE),
			"Action InstructionPanel must IGNORE (was swallowing Academy taps)"
		)
		# Input-safe even if measure is wrong; still keep compact for portrait.
		if panel.size.y > 180.0:
			print("[ACADEMY TAP] WARN panel tall=", panel.size, " (IGNORE so taps still pass)")
	var center: Vector2 = hole.get_global_rect().get_center()
	print("[ACADEMY TAP] hole=", hole.get_global_rect(), " center=", center, " panel=", panel.size if panel else "?", " filter=", panel.mouse_filter if panel else -1)

	var upgrade: CollisionShape2D = academy.get_node_or_null("UpgradeArea/CollisionShape2D") as CollisionShape2D
	_assert(upgrade != null, "Academy UpgradeArea missing")

	# Inject city camera tap at hole center (normal gesture path).
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = center
	press.global_position = center
	cam._input(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = center
	release.global_position = center
	cam._input(release)
	await process_frame
	await process_frame
	await process_frame

	var step_now: String = str(ts.get("current_step_id"))
	print("[ACADEMY TAP] step_after_tap=", step_now)
	_assert(step_now == "start_research", "TutorialState did not advance (step=%s)" % step_now)

	# Normal Academy path opens action chooser (Research / Upgrade).
	var action_popup: Node = hud.get_node_or_null("BuildingActionPopup")
	_assert(action_popup != null, "BuildingActionPopup missing after Academy tap")
	if action_popup != null:
		# Choose Research — normal gameplay path, not a tutorial-only open.
		for c: Node in action_popup.find_children("*", "Button", true, false):
			if c is Button and (c as Button).text == "Research":
				(c as Button).pressed.emit()
				break
		await process_frame
		await process_frame

	var research: Node = hud.get_node_or_null("AcademyResearchWindow")
	var research_open: bool = research != null and research is CanvasItem and (research as CanvasItem).visible
	print("[ACADEMY TAP] research_open=", research_open)
	_assert(research_open, "Research UI did not open via normal Academy path")

	if _fail.is_empty():
		print("[ACADEMY TAP] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[ACADEMY TAP] FAIL: %s" % f)
		quit(1)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)
