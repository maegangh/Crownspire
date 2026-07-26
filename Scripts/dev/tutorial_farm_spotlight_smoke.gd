extends SceneTree

## Verifies Farm tutorial spotlight uses Sprite2D bounds, not building-root / HUD top-left.
##   $env:CROWNSPIR_TUTORIAL_SMOKE="1"
##   Godot --headless --path <project> -s res://scripts/dev/tutorial_farm_spotlight_smoke.gd


func _initialize() -> void:
	call_deferred("_run")


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
	var scene: Node = root.get_child(root.get_child_count() - 1)
	# current_scene after change
	scene = get_current_scene()
	if scene != null:
		farm = scene.get_node_or_null("Buildings/Farm") as Node2D
	if farm == null:
		push_error("[FARM SPOTLIGHT] Buildings/Farm missing")
		quit(1)
		return

	var Resolver = load("res://scripts/UI/TutorialTargetResolver.gd")
	var step := {
		"target_type": "city_building",
		"target_id": "farm",
	}
	var result: Dictionary = Resolver.resolve(hud, step)
	if not bool(result.get("ok", false)):
		push_error("[FARM SPOTLIGHT] resolve failed")
		quit(1)
		return

	var node: Node2D = result.get("node2d") as Node2D
	var rect: Rect2 = Resolver.rect_for_result(result, 14.0)
	var root_canvas: Vector2 = farm.get_global_transform_with_canvas().origin
	var sprite: Sprite2D = farm.get_node_or_null("Sprite2D") as Sprite2D
	var sprite_canvas: Vector2 = sprite.get_global_transform_with_canvas().origin if sprite else Vector2.ZERO

	print("[FARM SPOTLIGHT] node=", node.get_path())
	print("[FARM SPOTLIGHT] root_canvas=", root_canvas)
	print("[FARM SPOTLIGHT] sprite_canvas=", sprite_canvas)
	print("[FARM SPOTLIGHT] spotlight=", rect)

	var fail: Array[String] = []
	if str(node.get_path()).find("Buildings/Farm") < 0:
		fail.append("resolved wrong node: %s" % node.get_path())
	# Must not sit on profile/avatar band (top-left ~25,27 → 138,90).
	var profile := Rect2(0, 0, 160, 120)
	if profile.intersects(rect) and rect.get_center().y < 140.0:
		fail.append("spotlight still in top-left profile band: %s" % str(rect))
	# Sprite-based center should be well below building-root canvas Y.
	if sprite != null and rect.get_center().y <= root_canvas.y + 20.0:
		fail.append("spotlight center not below Farm root (root_y=%.1f center_y=%.1f)" % [
			root_canvas.y, rect.get_center().y
		])
	if rect.get_center().distance_to(sprite_canvas) > 120.0:
		fail.append("spotlight far from Farm Sprite2D (dist=%.1f)" % rect.get_center().distance_to(sprite_canvas))

	# Full FTUE step path through overlay.
	var ts: Node = root.get_node_or_null("/root/TutorialState")
	var overlay: Control = hud.get_node_or_null("TutorialOverlay") as Control if hud else null
	if ts != null and overlay != null:
		ts.call("begin_smoke_isolation")
		ts.call("load_tutorial_state")
		ts.call("begin_ftue")
		await process_frame
		ts.call("acknowledge_intro")
		await process_frame
		await process_frame
		var hl: Panel = overlay.find_child("HighlightHole", true, false) as Panel
		if hl == null or not hl.visible:
			fail.append("highlight not visible on select_building")
		else:
			var hg: Rect2 = hl.get_global_rect()
			if hg.get_center().y < 120.0 and hg.get_center().x < 160.0:
				fail.append("overlay highlight still near top-left profile: %s" % str(hg))
			print("[FARM SPOTLIGHT] overlay_hole=", hg)

		# Advancement must come from the real GameEvents path (not overlay).
		var step_before: String = str(ts.get("current_step_id"))
		var ge: Node = root.get_node_or_null("/root/GameEvents")
		if ge != null and ge.has_signal("building_selected"):
			ge.emit_signal("building_selected", "farm")
			await process_frame
			await process_frame
			var step_after: String = str(ts.get("current_step_id"))
			print("[FARM SPOTLIGHT] step %s → %s via building_selected" % [step_before, step_after])
			if step_before != "select_building":
				fail.append("expected select_building before farm select, got %s" % step_before)
			elif step_after == "select_building":
				fail.append("tutorial did not advance on building_selected(farm)")

	if fail.is_empty():
		print("[FARM SPOTLIGHT] PASS")
		quit(0)
	else:
		for f: String in fail:
			push_error("[FARM SPOTLIGHT] FAIL: %s" % f)
		quit(1)
