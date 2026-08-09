extends SceneTree

## Verifies action-step instruction cards stay compact (not full-height).
##   $env:CROWNSPIR_TUTORIAL_SMOKE="1"
##   Godot --headless --path <project> -s res://Scripts/dev/tutorial_action_panel_smoke.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if OS.get_environment("CROWNSPIR_TUTORIAL_SMOKE") != "1":
		push_error("[ACTION PANEL] ABORT — CROWNSPIR_TUTORIAL_SMOKE=1 required")
		quit(2)
		return

	root.content_scale_size = Vector2i(383, 682)
	DisplayServer.window_set_size(Vector2i(383, 682))

	var err: Error = change_scene_to_file("res://Scenes/City/City.tscn")
	if err != OK:
		push_error("[ACTION PANEL] City load failed")
		quit(1)
		return
	for _i in 12:
		await process_frame

	var hud: Node = root.find_child("GameHUD", true, false)
	var overlay: Control = hud.get_node_or_null("TutorialOverlay") as Control if hud else null
	var ts: Node = root.get_node_or_null("/root/TutorialState")
	if overlay == null or ts == null:
		push_error("[ACTION PANEL] TutorialOverlay/TutorialState missing")
		quit(1)
		return

	ts.call("begin_smoke_isolation")
	ts.call("load_tutorial_state")
	ts.call("begin_ftue")
	await process_frame
	await process_frame

	var panel: PanelContainer = overlay.find_child("InstructionPanel", true, false) as PanelContainer
	var cont: Button = overlay.find_child("ContinueButton", true, false) as Button
	var fail: Array[String] = []

	# Acknowledge: CONTINUE visible, panel allowed to be taller.
	if not cont.visible:
		fail.append("intro CONTINUE hidden")
	print("[ACTION PANEL] ack size=", panel.size, " cont=", cont.visible)

	ts.call("acknowledge_intro")
	await process_frame
	await process_frame
	await process_frame

	# Action: YOUR CITY / select_building
	var step_id: String = str(ts.get("current_step_id"))
	if step_id != "select_building":
		fail.append("expected select_building, got %s" % step_id)

	var action_h: float = panel.size.y
	var action_w: float = panel.size.x
	var vp: Vector2 = overlay.get_viewport_rect().size
	print("[ACTION PANEL] action size=", panel.size, " pos=", panel.position, " cont=", cont.visible)

	if cont.visible:
		fail.append("action CONTINUE should be hidden")
	if action_h > 160.0:
		fail.append("action card too tall: %.1f (cap ~150)" % action_h)
	if action_h > vp.y * 0.35:
		fail.append("action card fills too much of screen: %.1f / %.1f" % [action_h, vp.y])
	if action_w < vp.x * 0.5:
		fail.append("action card unexpectedly narrow: %.1f" % action_w)

	# Must sit above bottom HUD reserve and not cover Farm spotlight center.
	var hole: Panel = overlay.find_child("HighlightHole", true, false) as Panel
	if hole != null and hole.visible:
		var hg: Rect2 = hole.get_global_rect()
		var pg: Rect2 = panel.get_global_rect()
		print("[ACTION PANEL] hole=", hg, " panel=", pg)
		if pg.intersects(hg.grow(4.0)):
			fail.append("action card overlaps Farm spotlight")
		if pg.end.y > vp.y - 180.0:
			fail.append("action card overlaps bottom HUD band (end.y=%.1f)" % pg.end.y)

	# Spot-check several action steps keep compact height + hidden CONTINUE.
	var action_steps: Array[String] = [
		"start_building_upgrade",
		"open_world",
		"select_wildling",
		"open_alliance",
	]
	for sid: String in action_steps:
		_force_step(ts, sid)
		await process_frame
		await process_frame
		if cont.visible:
			fail.append("%s shows CONTINUE" % sid)
		if panel.size.y > 160.0:
			fail.append("%s card too tall: %.1f" % [sid, panel.size.y])
		print("[ACTION PANEL] ", sid, " h=", panel.size.y, " cont=", cont.visible)

	if fail.is_empty():
		print("[ACTION PANEL] PASS")
		quit(0)
	else:
		for f: String in fail:
			push_error("[ACTION PANEL] FAIL: %s" % f)
		quit(1)


func _force_step(ts: Node, step_id: String) -> void:
	## Presentation-only jump for layout checks — does not alter progression logic.
	ts.set("current_step_id", step_id)
	ts.emit_signal("step_changed", step_id)
