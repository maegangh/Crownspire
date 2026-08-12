extends SceneTree

## F9 first-press interactivity + Farm collect-icon targeting.
##   $env:CROWNSPIR_TUTORIAL_SMOKE="1"
##   Godot --headless --path <project> -s res://Scripts/dev/tutorial_f9_collect_smoke.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if OS.get_environment("CROWNSPIR_TUTORIAL_SMOKE") != "1":
		push_error("[F9/COLLECT] ABORT — CROWNSPIR_TUTORIAL_SMOKE=1 required")
		quit(2)
		return

	root.content_scale_size = Vector2i(383, 682)
	DisplayServer.window_set_size(Vector2i(383, 682))

	var err: Error = change_scene_to_file("res://Scenes/City/City.tscn")
	if err != OK:
		push_error("[F9/COLLECT] City load failed")
		quit(1)
		return
	for _i in 14:
		await process_frame

	var hud: Node = root.find_child("GameHUD", true, false)
	var overlay: Control = hud.get_node_or_null("TutorialOverlay") as Control if hud else null
	var ts: Node = root.get_node_or_null("/root/TutorialState")
	if overlay == null or ts == null:
		push_error("[F9/COLLECT] overlay/TutorialState missing")
		quit(1)
		return

	var fail: Array[String] = []
	ts.call("begin_smoke_isolation")

	# --- A) Simulate ONE F9 press (debug restart lifecycle) ---
	overlay.call("_debug_restart_ftue")
	await process_frame
	await process_frame
	await process_frame

	var cont: Button = overlay.find_child("ContinueButton", true, false) as Button
	var skip: Button = overlay.find_child("SkipButton", true, false) as Button
	var panel: PanelContainer = overlay.find_child("InstructionPanel", true, false) as PanelContainer
	var full_dim: ColorRect = overlay.find_child("FullDim", true, false) as ColorRect

	print("[F9/COLLECT] after F9: step=", ts.get("current_step_id"), " overlay=", overlay.visible)
	print("[F9/COLLECT] cont vis=", cont.visible, " filter=", cont.mouse_filter, " disabled=", cont.disabled)
	print("[F9/COLLECT] skip vis=", skip.visible, " filter=", skip.mouse_filter)
	print("[F9/COLLECT] panel z=", panel.z_index, " dim z=", full_dim.z_index, " dim filter=", full_dim.mouse_filter)

	if str(ts.get("current_step_id")) != "intro_welcome":
		fail.append("F9 did not land on intro_welcome")
	if not overlay.visible:
		fail.append("overlay not visible after one F9")
	if not cont.visible or cont.disabled or cont.mouse_filter != Control.MOUSE_FILTER_STOP:
		fail.append("CONTINUE not interactive after one F9")
	if not skip.visible or skip.mouse_filter != Control.MOUSE_FILTER_STOP:
		fail.append("SKIP not interactive after one F9")
	if panel.z_index <= full_dim.z_index:
		fail.append("panel z_index not above FullDim")

	# Simulate CONTINUE press path (signal), then second F9 must still work once.
	ts.call("acknowledge_intro")
	await process_frame
	overlay.call("_debug_restart_ftue")
	await process_frame
	await process_frame
	if not cont.visible or cont.mouse_filter != Control.MOUSE_FILTER_STOP:
		fail.append("CONTINUE dead after second single F9")

	# --- B) Collect icon targeting (seed must expose real CollectIcon; no forced ready) ---
	var farm: Node2D = null
	var scene: Node = get_current_scene()
	if scene != null:
		farm = scene.get_node_or_null("Buildings/Farm") as Node2D
	if farm == null:
		fail.append("Farm missing")
	else:
		if farm.has_method("set_ready_to_collect"):
			farm.call("set_ready_to_collect", false)
		farm.set("_prod_stored", 10.0)
		if farm.has_method("_refresh_collect_icon_from_stored"):
			farm.call("_refresh_collect_icon_from_stored")
		if ts.has_method("_set_farm_collect_seed_granted"):
			ts.call("_set_farm_collect_seed_granted", true)
		if ts.has_method("try_seed_ftue_farm_collect"):
			ts.call("try_seed_ftue_farm_collect")
		await process_frame
		await process_frame

	var Resolver = load("res://Scripts/UI/TutorialTargetResolver.gd")
	var collect_step := {
		"target_type": "resource_collect_icon",
		"target_id": "farm",
	}
	# city_building resolve pans to UpgradeArea (can yank camera away) — resolve it
	# only for shape comparison, then re-resolve collect so framing stays on CollectIcon.
	var farm_building: Dictionary = Resolver.resolve(hud, {
		"target_type": "city_building",
		"target_id": "farm",
	})
	var collect: Dictionary = Resolver.resolve(hud, collect_step)
	collect = Resolver.resolve(hud, collect_step)
	await process_frame
	if not bool(collect.get("ok", false)):
		fail.append("resource_collect_icon/farm failed to resolve")
	else:
		var crect: Rect2 = Resolver.rect_for_result(collect, 14.0)
		var brect: Rect2 = Resolver.rect_for_result(farm_building, 14.0)
		var icon: Sprite2D = farm.get_node_or_null("CollectIcon") as Sprite2D
		var icon_c: Vector2 = icon.get_global_transform_with_canvas().origin
		print("[F9/COLLECT] collect rect=", crect, " building rect=", brect)
		print("[F9/COLLECT] icon path=", icon.get_path(), " canvas=", icon_c, " vis=", icon.visible)
		if not icon.visible:
			fail.append("CollectIcon not visible for collect step")
		if crect.get_center().distance_to(icon_c) > 50.0:
			fail.append("collect spotlight not centered on CollectIcon")
		# Must not be the same as the large Farm building spotlight.
		if crect.get_center().distance_to(brect.get_center()) < 30.0 and crect.get_area() > brect.get_area() * 0.6:
			fail.append("collect spotlight still looks like Farm building target")
		if crect.get_center().y < 90.0:
			fail.append("collect spotlight in top HUD band")
		var vp: Vector2 = Vector2(383, 682)
		if not Rect2(Vector2.ZERO, vp).grow(-8.0).has_point(crect.get_center()):
			fail.append("collect spotlight off portrait viewport")

	# Drive overlay to collect_resources presentation
	ts.set("current_step_id", "collect_resources")
	ts.emit_signal("step_changed", "collect_resources")
	await process_frame
	await process_frame
	await process_frame
	await process_frame

	# COLLECT button must appear inside the tutorial panel (Phase 1A fix).
	if not cont.visible:
		fail.append("COLLECT button not visible on collect_resources step")
	elif cont.text != "COLLECT":
		fail.append("collect button text expected COLLECT got '%s'" % cont.text)
	elif cont.disabled or cont.mouse_filter != Control.MOUSE_FILTER_STOP:
		fail.append("COLLECT button not interactive")
	else:
		print("[F9/COLLECT] COLLECT btn ok text=", cont.text, " panel_h=", panel.size.y)

	var hole: Panel = overlay.find_child("HighlightHole", true, false) as Panel
	if hole == null or not hole.visible:
		fail.append("collect step highlight missing")
	else:
		var hg: Rect2 = hole.get_global_rect()
		var icon2: Sprite2D = farm.get_node_or_null("CollectIcon") as Sprite2D
		var ic: Vector2 = icon2.get_global_transform_with_canvas().origin
		print("[F9/COLLECT] overlay hole=", hg, " icon=", ic)
		if not hg.has_point(ic) and hg.get_center().distance_to(ic) > 48.0:
			fail.append("overlay hole not over CollectIcon")
		if panel.get_global_rect().intersects(hg.grow(4.0)):
			fail.append("instruction panel covers CollectIcon hole")

	# Panel COLLECT path advances tutorial (same as world collect icon).
	var before_panel: String = str(ts.get("current_step_id"))
	overlay.call("_trigger_tutorial_resource_collect", "farm")
	await process_frame
	await process_frame
	var after_panel: String = str(ts.get("current_step_id"))
	print("[F9/COLLECT] panel COLLECT step ", before_panel, " → ", after_panel)
	if before_panel == "collect_resources" and after_panel == "collect_resources":
		fail.append("tutorial did not advance on panel COLLECT")

	# Real event path advances tutorial (world icon / GameEvents).
	ts.set("current_step_id", "collect_resources")
	ts.emit_signal("step_changed", "collect_resources")
	await process_frame
	var ge: Node = root.get_node_or_null("/root/GameEvents")
	var before: String = str(ts.get("current_step_id"))
	if ge != null:
		ge.emit_signal("resource_collected", "food", 100)
		await process_frame
		await process_frame
	var after: String = str(ts.get("current_step_id"))
	print("[F9/COLLECT] step ", before, " → ", after, " via resource_collected")
	if before == "collect_resources" and after == "collect_resources":
		fail.append("tutorial did not advance on resource_collected")

	if fail.is_empty():
		print("[F9/COLLECT] PASS")
		quit(0)
	else:
		for f: String in fail:
			push_error("[F9/COLLECT] FAIL: %s" % f)
		quit(1)
