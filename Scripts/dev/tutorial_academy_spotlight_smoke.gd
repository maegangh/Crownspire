extends SceneTree

## Academy FTUE spotlight must frame Buildings/Academy (building_id=academy), not left towers.
##   $env:CROWNSPIR_TUTORIAL_SMOKE="1"
##   Godot --headless --path <project> -s res://Scripts/dev/tutorial_academy_spotlight_smoke.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if OS.get_environment("CROWNSPIR_TUTORIAL_SMOKE") != "1":
		push_error("[ACADEMY SPOT] ABORT — CROWNSPIR_TUTORIAL_SMOKE=1 required")
		quit(2)
		return

	root.content_scale_size = Vector2i(417, 742)
	DisplayServer.window_set_size(Vector2i(417, 742))

	var err: Error = change_scene_to_file("res://Scenes/City/City.tscn")
	if err != OK:
		push_error("[ACADEMY SPOT] City load failed")
		quit(1)
		return
	for _i in 12:
		await process_frame

	var fail: Array[String] = []
	var hud: Node = root.find_child("GameHUD", true, false)
	var scene: Node = get_current_scene()
	var academy: Node2D = scene.get_node_or_null("Buildings/Academy") as Node2D if scene else null
	var dragon: Node2D = scene.get_node_or_null("Buildings/DragonRoost") as Node2D if scene else null
	var Resolver = load("res://Scripts/UI/TutorialTargetResolver.gd")
	if academy == null or hud == null:
		push_error("[ACADEMY SPOT] Academy/GameHUD missing")
		quit(1)
		return

	if str(academy.get("building_id")) != "academy":
		fail.append("canonical building_id is not academy")

	var result: Dictionary = Resolver.resolve(hud, {
		"target_type": "city_building",
		"target_id": "academy",
	})
	await process_frame
	# Re-resolve after camera focus for stable screen rect.
	result = Resolver.resolve(hud, {
		"target_type": "city_building",
		"target_id": "academy",
	})
	var node: Node2D = result.get("node2d") as Node2D
	var rect: Rect2 = Resolver.rect_for_result(result, 14.0)
	var sprite: Sprite2D = academy.get_node_or_null("Sprite2D") as Sprite2D
	var sprite_c: Vector2 = sprite.get_global_transform_with_canvas().origin
	var upgrade: CollisionShape2D = academy.get_node_or_null("UpgradeArea/CollisionShape2D") as CollisionShape2D
	var upgrade_c: Vector2 = upgrade.get_global_transform_with_canvas().origin if upgrade else sprite_c

	print("[ACADEMY SPOT] path=", node.get_path() if node else "null")
	print("[ACADEMY SPOT] rect=", rect, " center=", rect.get_center())
	print("[ACADEMY SPOT] sprite_c=", sprite_c, " upgrade_c=", upgrade_c)

	if node == null or str(node.get_path()).find("Buildings/Academy") < 0:
		fail.append("resolved wrong node")
	if rect.get_center().distance_to(upgrade_c) > 80.0 and rect.get_center().distance_to(sprite_c) > 80.0:
		fail.append("spotlight far from Academy interactive center")

	# Must not sit on DragonRoost (left tower) canvas position.
	if dragon != null:
		var dsprite: Sprite2D = dragon.get_node_or_null("Sprite2D") as Sprite2D
		var dc: Vector2 = dsprite.get_global_transform_with_canvas().origin if dsprite else Vector2.ZERO
		print("[ACADEMY SPOT] dragon_c=", dc)
		if rect.has_point(dc) and rect.get_center().distance_to(upgrade_c) > 120.0:
			fail.append("spotlight still covering DragonRoost instead of Academy")

	# On portrait viewport, hole should be on-screen after camera focus.
	var vp: Vector2 = Vector2(417, 742)
	var clipped: Rect2 = rect.intersection(Rect2(Vector2.ZERO, vp))
	print("[ACADEMY SPOT] clipped=", clipped)
	if clipped.size.x < 40.0 or clipped.size.y < 40.0:
		fail.append("Academy spotlight not on-screen after focus (clipped=%s)" % str(clipped))

	# Overlay step path
	var ts: Node = root.get_node_or_null("/root/TutorialState")
	var overlay: Control = hud.get_node_or_null("TutorialOverlay") as Control
	if ts != null and overlay != null:
		ts.call("begin_smoke_isolation")
		ts.call("load_tutorial_state")
		ts.set("current_step_id", "open_research")
		ts.set("ftue_started", true)
		ts.emit_signal("step_changed", "open_research")
		await process_frame
		await process_frame
		var hl: Panel = overlay.find_child("HighlightHole", true, false) as Panel
		if hl == null or not hl.visible:
			fail.append("highlight missing on open_research")
		else:
			var hg: Rect2 = hl.get_global_rect()
			print("[ACADEMY SPOT] overlay_hole=", hg)
			if hg.get_center().distance_to(upgrade_c) > 140.0:
				fail.append("overlay hole not near Academy")

	if fail.is_empty():
		print("[ACADEMY SPOT] PASS")
		quit(0)
	else:
		for f: String in fail:
			push_error("[ACADEMY SPOT] FAIL: %s" % f)
		quit(1)
