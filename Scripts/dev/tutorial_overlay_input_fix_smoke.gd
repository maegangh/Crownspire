extends SceneTree

## Verifies intro panel fits short portrait + Continue/Skip are topmost hit targets.
##   $env:CROWNSPIR_TUTORIAL_SMOKE="1"
##   Godot --headless --path <project> -s res://Scripts/dev/tutorial_overlay_input_fix_smoke.gd

var _fail: Array[String] = []


func _initialize() -> void:
	print("[TUTORIAL INPUT FIX] start")
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if OS.get_environment("CROWNSPIR_TUTORIAL_SMOKE") != "1":
		push_error("[TUTORIAL INPUT FIX] ABORT — CROWNSPIR_TUTORIAL_SMOKE=1 required")
		quit(2)
		return

	# Match the manual debug portrait size.
	root.content_scale_size = Vector2i(383, 682)
	DisplayServer.window_set_size(Vector2i(383, 682))

	var err: Error = change_scene_to_file("res://Scenes/City/City.tscn")
	if err != OK:
		push_error("City load failed")
		quit(1)
		return
	for _i in 10:
		await process_frame

	var hud: Node = root.find_child("GameHUD", true, false)
	var overlay: Control = hud.get_node_or_null("TutorialOverlay") as Control if hud else null
	var ts: Node = root.get_node_or_null("/root/TutorialState")
	if overlay == null or ts == null:
		push_error("overlay/TutorialState missing")
		quit(1)
		return

	ts.call("begin_smoke_isolation")
	ts.call("load_tutorial_state")
	ts.call("begin_ftue")
	await process_frame
	await process_frame

	var vp: Vector2 = overlay.size
	if vp.y < 10.0:
		vp = overlay.get_viewport_rect().size
	print("[TUTORIAL INPUT FIX] overlay size=", vp)

	var panel: Control = overlay.find_child("InstructionPanel", true, false) as Control
	var cont: Button = overlay.find_child("ContinueButton", true, false) as Button
	var skip: Button = overlay.find_child("SkipButton", true, false) as Button
	var full_dim: Control = overlay.find_child("FullDim", true, false) as Control

	_assert(panel != null and cont != null and skip != null, "chrome missing")
	_assert(bool(overlay.visible), "overlay not visible")
	_assert(str(ts.call("get_current_step_id")) == "intro_welcome", "not intro")

	if panel != null:
		var pr: Rect2 = panel.get_global_rect()
		print("[TUTORIAL INPUT FIX] panel=", pr)
		_assert(pr.position.y < vp.y * 0.35, "panel still too low (y=%s)" % pr.position.y)
		_assert(pr.end.y <= vp.y - 8.0, "panel clipped below viewport (end=%s vp=%s)" % [pr.end.y, vp.y])
		_assert(panel.z_index >= 20, "panel z_index too low")

	if cont != null:
		var cr: Rect2 = cont.get_global_rect()
		print("[TUTORIAL INPUT FIX] continue=", cr)
		_assert(cr.end.y <= vp.y - 4.0, "CONTINUE below viewport")
		_assert(cr.size.y > 0.0 and cr.size.x > 0.0, "CONTINUE has zero size")

	if full_dim != null:
		_assert(full_dim.z_index < panel.z_index, "FullDim not under panel")
		_assert(int(full_dim.mouse_filter) == int(Control.MOUSE_FILTER_STOP), "FullDim should STOP gameplay")

	if skip != null:
		_assert(skip.z_index > full_dim.z_index, "Skip not above FullDim")
		_assert(int(skip.mouse_filter) == int(Control.MOUSE_FILTER_STOP), "Skip filter")

	# Simulate Continue press.
	if cont != null:
		cont.pressed.emit()
	await process_frame
	_assert(str(ts.call("get_current_step_id")) == "select_building", "CONTINUE did not advance")

	# Reset to intro, open skip confirm.
	ts.call("debug_reset_ftue")
	ts.call("begin_ftue")
	await process_frame
	if skip != null:
		skip.pressed.emit()
	await process_frame
	var skip_layer: Control = overlay.find_child("SkipConfirm", true, false) as Control
	_assert(skip_layer != null and skip_layer.visible, "Skip confirm not shown")
	if skip_layer != null:
		_assert(skip_layer.z_index >= 30, "SkipConfirm z too low")

	# Cancel
	var cancel: Button = null
	for c: Node in skip_layer.find_children("*", "Button", true, false):
		if c is Button and (c as Button).text == "CANCEL":
			cancel = c as Button
			break
	_assert(cancel != null, "CANCEL missing")
	if cancel != null:
		cancel.pressed.emit()
	await process_frame
	_assert(not skip_layer.visible, "CANCEL did not hide confirm")

	# Confirm skip
	if skip != null:
		skip.pressed.emit()
	await process_frame
	var confirm: Button = null
	for c2: Node in skip_layer.find_children("*", "Button", true, false):
		if c2 is Button and (c2 as Button).text == "SKIP" and c2 != skip:
			confirm = c2 as Button
			break
	if confirm != null:
		confirm.pressed.emit()
	await process_frame
	_assert(bool(ts.call("is_ftue_complete")), "skip confirm failed")
	_assert(not bool(overlay.visible), "overlay still open")

	if _fail.is_empty():
		print("[TUTORIAL INPUT FIX] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[TUTORIAL INPUT FIX] FAIL: %s" % f)
		quit(1)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)
