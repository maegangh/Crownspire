extends SceneTree

## Verifies Farm collect spotlight after Citadel-first FTUE path.
## Resolver unit checks + overlay hole on collect_resources (not step 2 Farm select).
##   $env:CROWNSPIR_TUTORIAL_SMOKE="1"
##   Godot --headless --path <project> -s res://Scripts/dev/tutorial_farm_spotlight_smoke.gd


func _initialize() -> void:
	call_deferred("_run")


func _citadel_level() -> int:
	var cs: Node = root.get_node_or_null("/root/ConstructionState")
	if cs == null or not cs.has_method("get_canonical_building_level"):
		return 1
	return int(cs.call("get_canonical_building_level", "castle"))


func _advance_to_collect_resources(ts: Node, ge: Node, overlay: Control) -> String:
	ts.call("acknowledge_intro")
	await process_frame
	await process_frame
	var sid: String = str(ts.get("current_step_id"))
	if sid == "select_building" and _citadel_level() >= 2 and ts.has_method("reconcile_citadel_ftue_progress"):
		ts.call("reconcile_citadel_ftue_progress")
		sid = str(ts.get("current_step_id"))
		if overlay != null:
			ts.emit_signal("step_changed", sid)
			await process_frame
	if sid == "collect_resources":
		return sid
	if sid != "select_building":
		return sid
	ge.emit_signal("building_selected", "castle")
	await process_frame
	await process_frame
	ge.emit_signal("building_upgrade_started", "castle", 2)
	await process_frame
	ge.emit_signal("building_upgraded", "castle", 2)
	await process_frame
	await process_frame
	return str(ts.get("current_step_id"))


func _run() -> void:
	await process_frame
	if OS.get_environment("CROWNSPIR_TUTORIAL_SMOKE") != "1":
		push_error("[FARM SPOTLIGHT] ABORT — CROWNSPIR_TUTORIAL_SMOKE=1 required")
		quit(2)
		return

	root.content_scale_size = Vector2i(383, 682)
	DisplayServer.window_set_size(Vector2i(383, 682))

	var err: Error = change_scene_to_file("res://Scenes/City/City.tscn")
	if err != OK:
		push_error("[FARM SPOTLIGHT] City load failed")
		quit(1)
		return
	for _i in 12:
		await process_frame

	var hud: Node = root.find_child("GameHUD", true, false)
	var farm: Node2D = null
	var scene: Node = get_current_scene()
	if scene != null:
		farm = scene.get_node_or_null("Buildings/Farm") as Node2D
	if farm == null:
		push_error("[FARM SPOTLIGHT] Buildings/Farm missing")
		quit(1)
		return

	var Resolver = load("res://Scripts/UI/TutorialTargetResolver.gd")
	var fail: Array[String] = []

	# --- Resolver: Farm building still resolves with sprite-based bounds ---
	var farm_building_step := {
		"target_type": "city_building",
		"target_id": "farm",
	}
	var building_result: Dictionary = Resolver.resolve(hud, farm_building_step)
	if not bool(building_result.get("ok", false)):
		fail.append("farm city_building resolve failed")
	else:
		var node: Node2D = building_result.get("node2d") as Node2D
		var rect: Rect2 = Resolver.rect_for_result(building_result, 14.0)
		var root_canvas: Vector2 = farm.get_global_transform_with_canvas().origin
		var sprite: Sprite2D = farm.get_node_or_null("Sprite2D") as Sprite2D
		var sprite_canvas: Vector2 = sprite.get_global_transform_with_canvas().origin if sprite else Vector2.ZERO
		print("[FARM SPOTLIGHT] node=", node.get_path())
		print("[FARM SPOTLIGHT] root_canvas=", root_canvas)
		print("[FARM SPOTLIGHT] sprite_canvas=", sprite_canvas)
		print("[FARM SPOTLIGHT] building_spotlight=", rect)
		if str(node.get_path()).find("Buildings/Farm") < 0:
			fail.append("resolved wrong node: %s" % node.get_path())
		var profile := Rect2(0, 0, 160, 120)
		if profile.intersects(rect) and rect.get_center().y < 140.0:
			fail.append("farm building spotlight in top-left profile band: %s" % str(rect))
		if sprite != null and rect.get_center().y <= root_canvas.y + 20.0:
			fail.append("farm building spotlight center not below Farm root")
		if rect.get_center().distance_to(sprite_canvas) > 120.0:
			fail.append("farm building spotlight far from Sprite2D")

	# --- Citadel resolver: step 2 targets castle, not farm ---
	var citadel_result: Dictionary = Resolver.resolve(hud, {
		"target_type": "city_building",
		"target_id": "castle",
	})
	if not bool(citadel_result.get("ok", false)):
		fail.append("castle city_building resolve failed")
	else:
		var castle_node: Node2D = citadel_result.get("node2d") as Node2D
		if castle_node == null or str(castle_node.get_path()).find("Castle") < 0:
			fail.append("castle resolve did not land on Castle node: %s" % str(castle_node.get_path() if castle_node else "(null)"))

	# --- Full FTUE path → collect_resources Farm collect spotlight ---
	var ts: Node = root.get_node_or_null("/root/TutorialState")
	var overlay: Control = hud.get_node_or_null("TutorialOverlay") as Control if hud else null
	var ge: Node = root.get_node_or_null("/root/GameEvents")
	if ts != null and overlay != null and ge != null:
		ts.call("begin_smoke_isolation")
		ts.call("load_tutorial_state")
		ts.call("begin_ftue")
		await process_frame

		# Citadel-first: intro → citadel steps (or L2 skip) → collect_resources.
		var final_step: String = await _advance_to_collect_resources(ts, ge, overlay)
		print("[FARM SPOTLIGHT] reached step=", final_step, " citadel_level=", _citadel_level())
		if final_step != "collect_resources":
			fail.append("expected collect_resources after citadel path, got %s" % final_step)
		else:
			# Do NOT force set_ready_to_collect — seed must make the real CollectIcon visible
			# even when grant flag was already set and stored was below threshold.
			if farm.has_method("set_ready_to_collect"):
				farm.call("set_ready_to_collect", false)
			# Simulate below-threshold stored so seed has work to do.
			if "prod_stored" in farm or farm.get("_prod_stored") != null:
				farm.set("_prod_stored", 10.0)
			if farm.has_method("_refresh_collect_icon_from_stored"):
				farm.call("_refresh_collect_icon_from_stored")
			await process_frame
			var icon_before: Sprite2D = farm.get_node_or_null("CollectIcon") as Sprite2D
			if icon_before != null and icon_before.visible:
				fail.append("precondition: CollectIcon should start hidden before seed")

			# Mark grant flag as already set (regression: must still ensure icon).
			if ts.has_method("_set_farm_collect_seed_granted"):
				ts.call("_set_farm_collect_seed_granted", true)
			if ts.has_method("try_seed_ftue_farm_collect"):
				var seed_res: Dictionary = ts.call("try_seed_ftue_farm_collect")
				print("[FARM SPOTLIGHT] seed_res=", seed_res)
			await process_frame
			await process_frame

			var icon: Sprite2D = farm.get_node_or_null("CollectIcon") as Sprite2D
			if icon == null or not icon.visible:
				fail.append("CollectIcon not visible after FTUE seed (already_granted path)")
			elif not bool(farm.get("ready_to_collect")):
				fail.append("Farm ready_to_collect false after FTUE seed")

			var collect_result: Dictionary = Resolver.resolve(hud, {
				"target_type": "resource_collect_icon",
				"target_id": "farm",
			})
			if not bool(collect_result.get("ok", false)):
				fail.append("resource_collect_icon/farm failed on collect_resources path")
			else:
				var crect: Rect2 = Resolver.rect_for_result(collect_result, 14.0)
				var icon_c: Vector2 = icon.get_global_transform_with_canvas().origin
				print("[FARM SPOTLIGHT] collect_spotlight=", crect, " icon=", icon_c)
				if crect.get_center().distance_to(icon_c) > 50.0:
					fail.append("collect spotlight not centered on CollectIcon")
				# Must not land on top resource HUD band.
				if crect.get_center().y < 90.0:
					fail.append("collect spotlight in top HUD band: %s" % str(crect))
				var vp: Vector2 = Vector2(383, 682)
				if not Rect2(Vector2.ZERO, vp).grow(-8.0).has_point(crect.get_center()):
					fail.append("collect spotlight center off portrait viewport: %s" % str(crect.get_center()))

			# Overlay on collect_resources after citadel-first path: COLLECT action + hole.
			ts.emit_signal("step_changed", "collect_resources")
			for _w in 6:
				await process_frame
			var cont: Button = overlay.find_child("ContinueButton", true, false) as Button
			if cont == null or not cont.visible:
				fail.append("COLLECT button not visible on collect_resources after citadel path")
			elif cont.text != "COLLECT":
				fail.append("collect_resources button expected COLLECT got '%s'" % cont.text)
			else:
				print("[FARM SPOTLIGHT] COLLECT btn ok after citadel path text=", cont.text)
			var hole: Panel = overlay.find_child("HighlightHole", true, false) as Panel
			var panel: PanelContainer = overlay.find_child("InstructionPanel", true, false) as PanelContainer
			if hole == null or not hole.visible:
				fail.append("collect_resources highlight hole not visible")
			else:
				var hg: Rect2 = hole.get_global_rect()
				var ic2: Vector2 = icon.get_global_transform_with_canvas().origin
				print("[FARM SPOTLIGHT] overlay hole=", hg, " icon=", ic2, " panel=", panel.position if panel else null)
				if not hg.has_point(ic2) and hg.get_center().distance_to(ic2) > 48.0:
					fail.append("overlay hole not over CollectIcon after citadel path")
				if hg.get_center().y < 90.0:
					fail.append("overlay hole in top HUD band")
				if panel != null:
					var pr: Rect2 = panel.get_global_rect()
					if pr.intersects(hg.grow(4.0)):
						fail.append("instruction panel covers CollectIcon hole")

			# Farm select must not advance citadel select_building (when L1 path available).
			if _citadel_level() < 2:
				ts.call("begin_smoke_isolation")
				ts.call("load_tutorial_state")
				ts.call("begin_ftue")
				await process_frame
				ts.call("acknowledge_intro")
				await process_frame
				var before: String = str(ts.get("current_step_id"))
				if before == "select_building":
					ge.emit_signal("building_selected", "farm")
					await process_frame
					if str(ts.get("current_step_id")) != "select_building":
						fail.append("farm select advanced citadel select_building")

	if fail.is_empty():
		print("[FARM SPOTLIGHT] PASS")
		quit(0)
	else:
		for f: String in fail:
			push_error("[FARM SPOTLIGHT] FAIL: %s" % f)
		quit(1)
