extends SceneTree

## Alliance apply → pending UI / duplicate / restore coverage.
## Live Nakama optional: when authenticated, also verifies list_my_pending_applications RPC path.
##   Godot --headless --path <project> -s res://Scripts/dev/alliance_application_flow_smoke.gd


var _fail: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)


func _run() -> void:
	await process_frame
	await process_frame
	var ab: Node = root.get_node_or_null("/root/AllianceBackend")
	if ab == null:
		push_error("[ALLIANCE APPLY] ABORT — AllianceBackend missing")
		quit(2)
		return

	print("[ALLIANCE APPLY] A remember + query helpers")
	ab.call("remember_pending_application", "ally_test_1", "Test Alliance", "Application sent.")
	_assert(bool(ab.call("is_application_pending", "ally_test_1")), "A: pending not remembered")
	_assert(not bool(ab.call("is_application_pending", "ally_other")), "A: unrelated id marked pending")
	# Duplicate remember must not create a second entry.
	ab.call("remember_pending_application", "ally_test_1", "Test Alliance", "Application already sent.")
	var cached: Array = ab.call("get_cached_my_pending_applications")
	var count_a := 0
	for e: Variant in cached:
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("alliance_id", "")) == "ally_test_1":
			count_a += 1
	_assert(count_a == 1, "A: duplicate remember created %d entries" % count_a)

	print("[ALLIANCE APPLY] B join_alliance pending / already-sent normalization (mocked via remember)")
	# Simulate server already-sent payload handling by exercising public remember + message rules
	# through a lightweight local mirror of join pending branch (no fake membership).
	var already := {
		"ok": true,
		"pending": true,
		"alliance_id": "ally_test_2",
		"message": "Application already sent.",
	}
	ab.call(
		"remember_pending_application",
		str(already.get("alliance_id", "")),
		"",
		str(already.get("message", ""))
	)
	_assert(bool(ab.call("is_application_pending", "ally_test_2")), "B: already-sent not treated as pending")

	print("[ALLIANCE APPLY] C UI action labels")
	# Mirror AllianceScreen card rules without constructing full HUD.
	var pending_label := "APPLICATION PENDING" if bool(ab.call("is_application_pending", "ally_test_1")) else "Apply"
	_assert(pending_label == "APPLICATION PENDING", "C: pending label wrong: %s" % pending_label)

	print("[ALLIANCE APPLY] D live list_my_pending_applications (optional)")
	var nc: Node = root.get_node_or_null("/root/NakamaConnection")
	var live_ok := false
	if nc != null:
		# Wait briefly for auth/socket from autoload connection.
		var deadline: int = Time.get_ticks_msec() + 12000
		while Time.get_ticks_msec() < deadline:
			if bool(nc.call("is_authenticated")) and bool(nc.call("is_socket_connected")):
				live_ok = true
				break
			await process_frame
			await create_timer(0.2).timeout
	if live_ok:
		var listed: Dictionary = await ab.call("list_my_pending_applications")
		_assert(bool(listed.get("ok", false)), "D: list_my_pending failed: %s" % str(listed.get("error", "")))
		# After live refresh, synthetic ids may be replaced by server truth — that is correct.
		var apps: Array = listed.get("applications", [])
		print("[ALLIANCE APPLY] D live pending count=", apps.size())
		for app_v: Variant in apps:
			if typeof(app_v) != TYPE_DICTIONARY:
				continue
			var aid: String = str((app_v as Dictionary).get("alliance_id", ""))
			_assert(bool(ab.call("is_application_pending", aid)), "D: live pending id not queryable: %s" % aid)
	else:
		print("[ALLIANCE APPLY] D skipped — Nakama not connected (local-dev without override)")

	print("[ALLIANCE APPLY] E leader Applications view API surface")
	_assert(ab.has_method("list_join_requests"), "E: list_join_requests missing")
	_assert(ab.has_method("approve_application"), "E: approve_application missing")
	_assert(ab.has_method("reject_application"), "E: reject_application missing")
	_assert(ab.has_method("list_my_pending_applications"), "E: list_my_pending_applications missing")

	if _fail.is_empty():
		print("[ALLIANCE APPLY] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[ALLIANCE APPLY] FAIL: %s" % f)
		quit(1)
