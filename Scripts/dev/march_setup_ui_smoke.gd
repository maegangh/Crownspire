extends SceneTree

## Verifies runtime MarchSetup troop rows have no steppers and header exits exist.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var err: Error = change_scene_to_file("res://Scenes/World/KingdomMap.tscn")
	if err != OK:
		push_error("[MARCH UI SMOKE] KingdomMap load failed")
		quit(1)
		return
	for _i in 10:
		await process_frame

	var setup: Control = root.find_child("MarchSetupScreen", true, false) as Control
	if setup == null:
		push_error("[MARCH UI SMOKE] MarchSetupScreen missing")
		quit(1)
		return

	var script_path: String = setup.get_script().resource_path if setup.get_script() else ""
	print("[MARCH UI SMOKE] runtime script=", script_path)

	# Gather setup: heroes must stay empty (no auto Maegan).
	setup.call("open_for_target", {
		"target_type": "resource",
		"resource_tile_id": "smoke_tile",
		"resource_type": "food",
		"resource_level": 1,
		"resource_amount": 1000,
		"display_name": "Fertile Wheat Farm",
		"position": {"x": 100.0, "y": 100.0},
	})
	await process_frame
	await process_frame

	var fail: Array[String] = []
	var sel_var: Variant = setup.get("_selected_heroes")
	if typeof(sel_var) == TYPE_ARRAY and not (sel_var as Array).is_empty():
		fail.append("Gather setup auto-selected heroes (expected none)")
	var heroes_section: Label = setup.find_child("HeroesSectionLabel", true, false) as Label
	if heroes_section == null or not str(heroes_section.text).contains("OPTIONAL"):
		fail.append("Gather heroes section should be labeled OPTIONAL")

	if setup.find_child("CloseButton", true, false) != null:
		(setup.find_child("CloseButton", true, false) as Button).pressed.emit()
	await process_frame

	setup.call("open_for_target", {
		"instance_id": 1,
		"species": "wolf",
		"level": 1,
		"power": 100,
		"position": {"x": 0, "y": 0},
	})
	await process_frame
	await process_frame

	sel_var = setup.get("_selected_heroes")
	if typeof(sel_var) == TYPE_ARRAY and not (sel_var as Array).is_empty():
		fail.append("Wildling setup auto-selected heroes (expected none)")

	var back: Button = setup.find_child("BackButton", true, false) as Button
	var close_btn: Button = setup.find_child("CloseButton", true, false) as Button
	var select_troops: Button = setup.find_child("SelectAllTroopsButton", true, false) as Button
	var clear_troops: Button = setup.find_child("ClearTroopsButton", true, false) as Button
	var march_btn: Button = setup.find_child("MarchButton", true, false) as Button

	if back == null:
		fail.append("BackButton missing")
	if close_btn == null:
		fail.append("CloseButton missing")
	if select_troops == null or select_troops.text != "SELECT ALL TROOPS":
		fail.append("SELECT ALL TROOPS missing")
	if clear_troops == null:
		fail.append("CLEAR troops missing")
	if march_btn == null:
		fail.append("MARCH missing")

	# Troop list scroll (tier rows) — not a whole-screen scroll.
	var troop_scroll: Node = setup.find_child("TroopListScroll", true, false)
	if troop_scroll == null or not (troop_scroll is ScrollContainer):
		fail.append("TroopListScroll missing")
	if setup.find_child("ContentScroll", true, false) is ScrollContainer:
		fail.append("ContentScroll ScrollContainer must not wrap the whole screen")

	# Tier rows should expose +/- controls (not legacy 3-row summary).
	var tier_row: Node = setup.find_child("TroopTierRow_infantry_1", true, false)
	if tier_row == null:
		# Player may not own T1 infantry in smoke session — any tier row is fine.
		for child: Node in setup.find_child("TroopTierList", true, false).get_children() if setup.find_child("TroopTierList", true, false) else []:
			if str(child.name).begins_with("TroopTierRow_"):
				tier_row = child
				break
	if tier_row == null:
		fail.append("no TroopTierRow_* rows built (need owned troops in TroopState)")
	else:
		var has_plus: bool = false
		for c: Node in tier_row.get_children():
			if c is Button and str((c as Button).text) == "+":
				has_plus = true
		if not has_plus:
			fail.append("tier row missing + button")

	var vp_h: float = setup.get_viewport_rect().size.y
	if march_btn != null:
		var mrect: Rect2 = march_btn.get_global_rect()
		if mrect.end.y > vp_h - 180.0:
			fail.append("MARCH may overlap bottom HUD (end=%.1f vp=%.1f)" % [mrect.end.y, vp_h])

	# X closes without trap
	if close_btn != null:
		close_btn.pressed.emit()
	await process_frame
	if setup.visible or setup.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		fail.append("X did not hide/ignore MarchSetup")

	if fail.is_empty():
		print("[MARCH UI SMOKE] PASS")
		quit(0)
	else:
		for f: String in fail:
			push_error("[MARCH UI SMOKE] FAIL: %s" % f)
		quit(1)
