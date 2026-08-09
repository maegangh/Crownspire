extends SceneTree

## Live portrait Research detail must show SPEED UP while a job is running.
##   Godot --headless --path <project> -s res://Scripts/dev/research_mobile_speedup_smoke.gd

var _fail: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	root.content_scale_size = Vector2i(417, 742)
	DisplayServer.window_set_size(Vector2i(417, 742))

	var err: Error = change_scene_to_file("res://Scenes/City/City.tscn")
	if err != OK:
		push_error("[RES SU] City load failed")
		quit(1)
		return
	for _i in 14:
		await process_frame

	var hud: Node = root.find_child("GameHUD", true, false)
	var rs: Node = root.get_node_or_null("/root/ResearchState")
	var svc: Node = root.get_node_or_null("/root/SpeedupService")
	var bag: Node = root.get_node_or_null("/root/BagState")
	if hud == null or rs == null or svc == null:
		push_error("[RES SU] missing nodes")
		quit(1)
		return

	# Clear any leftover jobs.
	while not bool((rs.call("get_primary_job") as Dictionary).is_empty()):
		rs.call("cancel_primary_research")
		await process_frame

	# Open Academy research window (runtime path).
	var academy: Node = get_current_scene().get_node_or_null("Buildings/Academy")
	if academy != null and academy.has_method("activate_building_tap"):
		# Avoid BuildingActionPopup — open research directly if possible.
		pass
	var win: Control = hud.get_node_or_null("AcademyResearchWindow") as Control
	if win == null:
		var packed: PackedScene = load("res://Scenes/AcademyResearchWindow.tscn") as PackedScene
		win = packed.instantiate() as Control
		win.name = "AcademyResearchWindow"
		hud.add_child(win)
	win.call("open_research")
	await process_frame
	await process_frame

	_assert(bool(win.get("_mobile_built")), "mobile shell not built (portrait path)")

	# Start a short research job via ResearchState.
	var rid: String = "citadel_irrigation" # may differ — pick first research id from DB
	var db: Array = win.get("database") as Array if "database" in win else []
	if db.is_empty() and win.has_method("_load_database"):
		win.call("_load_database")
		db = win.get("database") as Array
	if not db.is_empty():
		rid = str((db[0] as Dictionary).get("id", rid))

	var start: Dictionary = rs.call("try_start_research", {
		"research_id": rid,
		"level": 1,
		"time_remaining": 51.0,
		"total_duration": 51.0,
	})
	_assert(bool(start.get("ok", false)), "could not start research: %s" % str(start))
	await process_frame

	# Open the live mobile detail for this tech (the CANCEL-only screen).
	win.call("_mobile_show_detail", rid)
	await process_frame
	await process_frame

	var su: Button = win.find_child("MobileSpeedUpButton", true, false) as Button
	var cancel: Button = win.find_child("MobileCancelResearchButton", true, false) as Button
	var progress: Label = win.find_child("MobileActiveProgress", true, false) as Label
	_assert(su != null, "MobileSpeedUpButton missing on live detail")
	_assert(cancel != null, "MobileCancelResearchButton missing")
	_assert(progress != null and progress.text.find("In progress") >= 0, "progress label missing")
	_assert(su.visible and not su.disabled, "SPEED UP should be enabled with rem>0")
	_assert(su.text == "SPEED UP", "SPEED UP label")

	# Desktop SpeedupContainer is not the live portrait control — optional presence.
	var desktop_su: Node = win.find_child("SpeedUpButton", true, false)
	print("[RES SU] mobile_su=", su != null, " desktop_su=", desktop_su != null, " rid=", rid)

	# Popup opens even with zero bag items.
	if bag != null:
		# Don't require clearing entire bag; just ensure popup path works.
		pass
	su.pressed.emit()
	await process_frame
	await process_frame
	var popup: Control = hud.find_child("SpeedUpPopup", true, false) as Control
	if popup == null:
		popup = root.find_child("SpeedUpPopup", true, false) as Control
	_assert(popup != null and popup.visible, "SpeedUpPopup did not open")

	# Eligible filter: research + universal only (API check).
	var subs: PackedStringArray = svc.call("get_timer_subcategories", "research")
	_assert(subs.has("research") and subs.has("universal"), "research eligibility categories")
	_assert(not subs.has("construction") and not subs.has("training"), "no construction/training in research filter")

	# Partial speedup via service (grant 1m if missing — or use 1h and check remaining drop).
	var before: float = float(svc.call("get_remaining_seconds", "research", rid))
	# Prefer applying via ResearchState directly to validate completion path without needing items.
	var partial: Dictionary = rs.call("speedup_research", rid, 10.0)
	_assert(bool(partial.get("ok", false)), "partial speedup ok")
	var after: float = float(rs.call("get_job_for", rid).get("time_remaining", -1))
	_assert(after <= before - 9.0, "timer reduced (before=%.1f after=%.1f)" % [before, after])
	await process_frame
	if progress != null and is_instance_valid(progress):
		# Tick sync should rewrite remaining text.
		win.call("_sync_active_research_ui")
		await process_frame
		_assert(progress.text.find("In progress") >= 0, "progress still shows in-progress after partial")

	# Complete via overflow speedup
	rs.call("speedup_research", rid, 9999.0)
	await process_frame
	await process_frame
	var job_after: Dictionary = rs.call("get_job_for", rid)
	_assert(job_after.is_empty(), "job should complete after overflow speedup")

	# Item catalog report (not a fail): baseline 1m/5m/30m/1h
	var ids: PackedStringArray = PackedStringArray()
	var idb: Node = root.get_node_or_null("/root/ItemDatabase")
	if idb != null and idb.has_method("get_items_by_category"):
		for it: Variant in idb.call("get_items_by_category", "speedup"):
			if typeof(it) == TYPE_DICTIONARY:
				ids.append(str((it as Dictionary).get("id", "")))
	var need: Array[String] = [
		"speedup_universal_1m", "speedup_universal_5m", "speedup_universal_30m", "speedup_universal_1h",
		"speedup_research_1m", "speedup_research_5m", "speedup_research_30m", "speedup_research_1h",
	]
	var missing: PackedStringArray = PackedStringArray()
	for n: String in need:
		if not ids.has(n):
			missing.append(n)
	print("[RES SU] speedup catalog missing baseline IDs: ", missing)

	if _fail.is_empty():
		print("[RES SU] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[RES SU] FAIL: %s" % f)
		quit(1)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)
