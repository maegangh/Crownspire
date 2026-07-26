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

	setup.call("open_for_target", {
		"instance_id": 1,
		"species": "wolf",
		"level": 1,
		"power": 100,
		"position": {"x": 0, "y": 0},
	})
	await process_frame
	await process_frame

	var back: Button = setup.find_child("BackButton", true, false) as Button
	var close_btn: Button = setup.find_child("CloseButton", true, false) as Button
	var select_troops: Button = setup.find_child("SelectAllTroopsButton", true, false) as Button
	var clear_troops: Button = setup.find_child("ClearTroopsButton", true, false) as Button
	var march_btn: Button = setup.find_child("MarchButton", true, false) as Button

	var fail: Array[String] = []
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

	# No per-row steppers / old Select All labels inside troop rows.
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var row: Node = setup.find_child("TroopRow_%s" % kind, true, false)
		if row == null:
			fail.append("TroopRow_%s missing" % kind)
			continue
		for child: Node in row.get_children():
			if child is Button:
				fail.append("TroopRow_%s still has Button: %s" % [kind, child.name])

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
