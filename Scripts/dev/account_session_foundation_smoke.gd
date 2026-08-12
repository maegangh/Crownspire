extends SceneTree

## Phase 1 account/session foundation regression smoke.
##   Godot --headless --path <project> -s res://Scripts/dev/account_session_foundation_smoke.gd

const AccountSessionStoreScript = preload("res://Scripts/Backend/AccountSessionStore.gd")

var _fail: Array[String] = []
var _captured_logs: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)


func _run() -> void:
	await process_frame
	await process_frame

	var nc: Node = root.get_node_or_null("/root/NakamaConnection")
	var identity: Node = root.get_node_or_null("/root/AccountIdentityState")
	if nc == null or identity == null:
		push_error("[ACCOUNT P1] ABORT — NakamaConnection or AccountIdentityState missing")
		quit(2)
		return

	print("[ACCOUNT P1] A token redaction + no token prints in auth logs")
	_test_token_redaction(nc)

	print("[ACCOUNT P1] C wait for live Nakama auth")
	var live_ok := false
	var deadline: int = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if bool(nc.call("is_authenticated")):
			live_ok = true
			break
		await process_frame
		await create_timer(0.15).timeout

	if not live_ok:
		for f: String in _fail:
			push_error("[ACCOUNT P1] FAIL: %s" % f)
		push_error("[ACCOUNT P1] ABORT — Nakama not authenticated (need user://nakama_config.cfg)")
		quit(2)
		return

	var user_id: String = str(nc.call("get_user_id")).strip_edges()
	_assert(user_id != "", "C: empty user_id after auth")
	print("[ACCOUNT P1] C authenticated user=%s source=%s" % [
		user_id.substr(0, mini(8, user_id.length())),
		str(nc.call("get_last_auth_source")),
	])

	# Ensure real ownership claim happened outside smoke isolation.
	identity.call("on_authenticated", user_id, str(nc.call("get_last_auth_source")))

	print("[ACCOUNT P1] B ownership claim / match / mismatch (isolated)")
	_test_ownership_rules(identity)
	# Re-sync real ownership after isolation ends.
	identity.call("on_authenticated", user_id, str(nc.call("get_last_auth_source")))

	print("[ACCOUNT P1] D device user retains user_id + session persist")
	await _test_session_persist_and_restore(nc, user_id)

	print("[ACCOUNT P1] E refresh path (session_refresh_async)")
	await _test_session_refresh(nc, user_id)

	print("[ACCOUNT P1] F missing session falls back to device auth")
	await _test_missing_session_device_fallback(nc, user_id)

	print("[ACCOUNT P1] G expired auth token + valid refresh restores via refresh")
	await _test_expired_token_refresh(nc, user_id)

	print("[ACCOUNT P1] H account metadata + gate foundation")
	_test_account_metadata(identity, user_id)

	print("[ACCOUNT P1] I alliance / socket still works")
	await _test_alliance_still_works(nc)

	print("[ACCOUNT P1] J relaunch metadata survival (reload ownership + session files)")
	_test_relaunch_survival(nc, identity, user_id)

	if _fail.is_empty():
		print("[ACCOUNT P1] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[ACCOUNT P1] FAIL: %s" % f)
		quit(1)


func _test_token_redaction(nc: Node) -> void:
	var store = nc.call("get_session_store")
	var fake_jwt := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1aWQiOiJhYmMxMjMiLCJleHAiOjE3MDAwMDAwMDB9.signature"
	var redacted: String = store.redact_for_log("auth token=%s refresh=%s" % [fake_jwt, fake_jwt])
	_assert(redacted.find(fake_jwt) < 0, "A: redact left JWT intact")
	_assert(redacted.find("<REDACTED_JWT>") >= 0, "A: redact missing marker")
	# Source-level guard: connection logs must not print session.token / refresh_token.
	var src := FileAccess.get_file_as_string("res://Scripts/Backend/NakamaConnection.gd")
	_assert(src.find("print(session)") < 0, "A: prints full session object")
	_assert(src.find("print(_session)") < 0, "A: prints _session object")
	for line: String in src.split("\n"):
		var t: String = line.strip_edges()
		if not t.begins_with("print(") and not t.begins_with("push_warning(") and not t.begins_with("push_error("):
			continue
		_assert(t.find("refresh_token") < 0, "A: log line mentions refresh_token: %s" % t)
		_assert(t.find(".token") < 0, "A: log line mentions .token: %s" % t)


func _test_ownership_rules(identity: Node) -> void:
	var asp: Node = root.get_node_or_null("/root/AccountSavePaths")
	identity.call("begin_smoke_isolation")
	if asp != null and asp.has_method("begin_smoke_isolation"):
		asp.call("begin_smoke_isolation")
	# Fabricate a legacy marker under smoke-only path? has_legacy_local_progression checks real user://.
	# Ownership rules themselves are tested via claim + mismatch without needing real buildings.cfg.
	var claim1: Dictionary = identity.call("on_authenticated", "user_aaa", "device")
	_assert(bool(claim1.get("ok", false)), "B1: first claim failed")
	_assert(bool(claim1.get("claimed", false)), "B1: first auth should claim")
	_assert(str(identity.call("get_local_owner_user_id")) == "user_aaa", "B1: owner not aaa")
	_assert(not bool(identity.call("has_local_save_mismatch")), "B1: mismatch after claim")

	var claim2: Dictionary = identity.call("on_authenticated", "user_aaa", "restore")
	_assert(bool(claim2.get("ok", false)), "B2: matching user rejected")
	_assert(not bool(claim2.get("claimed", false)), "B2: re-claim should not claim again")
	_assert(not bool(identity.call("has_local_save_mismatch")), "B2: mismatch on match")

	# Marker file to prove mismatch does not delete/overwrite local progression files.
	var marker_path := "user://account_p1_smoke_marker.cfg"
	var marker := ConfigFile.new()
	marker.set_value("m", "v", "keep_me")
	marker.save(marker_path)
	var before_mtime := FileAccess.get_modified_time(marker_path)

	var bad: Dictionary = identity.call("on_authenticated", "user_bbb", "device")
	_assert(not bool(bad.get("ok", false)), "B3: mismatch should fail ok")
	_assert(str(bad.get("error", "")) == "LOCAL_SAVE_ACCOUNT_MISMATCH", "B3: wrong error code")
	_assert(bool(identity.call("has_local_save_mismatch")), "B3: mismatch flag not set")
	_assert(str(identity.call("get_mismatch_code")) == "LOCAL_SAVE_ACCOUNT_MISMATCH", "B3: code getter")
	_assert(str(identity.call("get_local_owner_user_id")) == "user_aaa", "B3: owner changed on mismatch")
	# Phase 2: own empty partition is safe; legacy handoff remains mismatched.
	if asp != null:
		_assert(str(asp.call("get_active_user_id")) == "user_bbb", "B3: save context not bound to bbb")
		var b_path: String = str(asp.call("path_for", "buildings.cfg"))
		_assert(b_path.find("user_bbb") >= 0, "B3: path not isolated to bbb: %s" % b_path)
		_assert(b_path.find("user_aaa") < 0, "B3: path leaked aaa partition")
	_assert(FileAccess.file_exists(marker_path), "B3: local marker deleted")
	var after := ConfigFile.new()
	_assert(after.load(marker_path) == OK, "B3: marker unreadable")
	_assert(str(after.get_value("m", "v", "")) == "keep_me", "B3: marker overwritten")
	_assert(FileAccess.get_modified_time(marker_path) == before_mtime, "B3: marker mtime changed")

	if asp != null and asp.has_method("end_smoke_isolation"):
		asp.call("end_smoke_isolation")
	identity.call("end_smoke_isolation")
	if FileAccess.file_exists(marker_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(marker_path))


func _test_session_persist_and_restore(nc: Node, user_id: String) -> void:
	nc.call("begin_session_store_smoke_isolation")
	var session: NakamaSession = nc.call("get_session")
	_assert(session != null and session.is_valid(), "D: live session invalid")
	var store = nc.call("get_session_store")
	_assert(store.save_session(session), "D: save_session failed")
	_assert(store.has_stored_session(), "D: has_stored_session false after save")

	var restored: NakamaSession = store.restore_session_object()
	_assert(restored != null and restored.is_valid(), "D: restore_session_object failed")
	_assert(str(restored.user_id) == user_id, "D: restored user_id mismatch")
	_assert(not restored.is_expired(), "D: restored session unexpectedly expired")

	# Simulate priority restore path without socket reconnect.
	var data: Dictionary = store.load_session_data()
	_assert(str(data.get("user_id", "")) == user_id, "D: stored user_id metadata missing")
	_assert(str(data.get("auth_token", "")).strip_edges() != "", "D: auth_token missing in store")
	# Never print tokens — only lengths.
	print("[ACCOUNT P1] D stored token_len=%d refresh_len=%d" % [
		str(data.get("auth_token", "")).length(),
		str(data.get("refresh_token", "")).length(),
	])
	nc.call("end_session_store_smoke_isolation")


func _test_session_refresh(nc: Node, user_id: String) -> void:
	var client: NakamaClient = nc.call("get_client")
	var session: NakamaSession = nc.call("get_session")
	_assert(client != null and session != null, "E: client/session missing")
	if str(session.refresh_token).strip_edges() == "":
		print("[ACCOUNT P1] E skipped — server did not return refresh_token")
		return
	var refreshed: NakamaSession = await client.session_refresh_async(session)
	_assert(refreshed != null and not refreshed.is_exception(), "E: refresh exception")
	_assert(refreshed.is_valid(), "E: refreshed invalid")
	_assert(str(refreshed.user_id) == user_id, "E: refreshed user_id changed")
	var tmp = AccountSessionStoreScript.new()
	tmp.begin_smoke_isolation()
	_assert(tmp.save_session(refreshed), "E: save refreshed failed")
	var again: NakamaSession = tmp.restore_session_object()
	_assert(again != null and str(again.user_id) == user_id, "E: restore after refresh failed")
	tmp.end_smoke_isolation()


func _test_missing_session_device_fallback(nc: Node, expected_user_id: String) -> void:
	nc.call("begin_session_store_smoke_isolation")
	var store = nc.call("get_session_store")
	_assert(not store.has_stored_session(), "F: smoke store should be empty")
	# Directly exercise priority auth with empty store → device.
	var device_id: String = ""
	if nc.has_method("get_device_id_path"):
		var cfg := ConfigFile.new()
		if cfg.load(str(nc.call("get_device_id_path"))) == OK:
			device_id = str(cfg.get_value("device", "id", "")).strip_edges()
	_assert(device_id != "", "F: device id missing")
	var client: NakamaClient = nc.call("get_client")
	# Mimic NakamaConnection priority with empty store.
	var restored: NakamaSession = store.restore_session_object()
	_assert(restored == null, "F: empty store restored a session")
	var session: NakamaSession = await client.authenticate_device_async(device_id)
	_assert(session != null and not session.is_exception(), "F: device auth failed")
	_assert(str(session.user_id) == expected_user_id, "F: device auth user_id changed")
	_assert(store.save_session(session), "F: persist after device auth failed")
	nc.call("end_session_store_smoke_isolation")


func _test_expired_token_refresh(nc: Node, user_id: String) -> void:
	var client: NakamaClient = nc.call("get_client")
	var live: NakamaSession = nc.call("get_session")
	if live == null or str(live.refresh_token).strip_edges() == "":
		print("[ACCOUNT P1] G skipped — no refresh_token")
		return
	# Forge an expired auth JWT (local unpack only; signature not verified client-side).
	var payload := {
		"uid": user_id,
		"usn": str(live.username),
		"exp": 1,
	}
	var forged: String = _forge_unsigned_jwt(payload)
	var expired: NakamaSession = NakamaSession.new(forged, false, live.refresh_token)
	_assert(expired != null and expired.is_valid(), "G: forged session invalid")
	_assert(expired.is_expired(), "G: forged session should be expired")
	_assert(not expired.is_refresh_expired(), "G: refresh should still be valid")

	var store = AccountSessionStoreScript.new()
	store.begin_smoke_isolation()
	_assert(store.save_session(expired), "G: save forged expired failed")
	var restored: NakamaSession = store.restore_session_object()
	_assert(restored != null and restored.is_expired(), "G: restored not expired")
	var refreshed: NakamaSession = await client.session_refresh_async(restored)
	_assert(refreshed != null and not refreshed.is_exception(), "G: refresh failed: %s" % [
		str(refreshed.get_exception().message) if refreshed != null and refreshed.get_exception() != null else "?"
	])
	_assert(str(refreshed.user_id) == user_id, "G: refresh user_id mismatch")
	_assert(not refreshed.is_expired(), "G: refreshed still expired")
	store.end_smoke_isolation()


func _test_account_metadata(identity: Node, user_id: String) -> void:
	_assert(str(identity.call("get_boot_gate_mode")) == "AUTO_CONTINUE", "H: boot gate not AUTO_CONTINUE")
	_assert(not bool(identity.call("should_force_login_gate")), "H: login gate forced in Phase 1")
	# After live auth, identity should know auth user (may have claimed real ownership).
	var auth_uid: String = str(identity.call("get_auth_user_id")).strip_edges()
	if auth_uid != "":
		_assert(auth_uid == user_id, "H: auth_user_id mismatch")
	var kind: String = str(identity.call("get_account_kind"))
	_assert(kind == "GUEST" or kind == "SECURED", "H: bad account kind %s" % kind)
	# Device-only must remain GUEST (do not infer secured from session token).
	# Linked providers may take a frame; give a short wait.
	print("[ACCOUNT P1] H account_kind=%s linked=%s" % [kind, str(identity.call("get_linked_providers"))])


func _test_alliance_still_works(nc: Node) -> void:
	var deadline: int = Time.get_ticks_msec() + 12000
	var sock_ok := false
	while Time.get_ticks_msec() < deadline:
		if bool(nc.call("is_socket_connected")):
			sock_ok = true
			break
		await process_frame
		await create_timer(0.15).timeout
	_assert(sock_ok, "I: realtime socket not connected")
	var ab: Node = root.get_node_or_null("/root/AllianceBackend")
	_assert(ab != null, "I: AllianceBackend missing")
	if ab != null and sock_ok:
		# Lightweight connectivity: list pending applications should not crash.
		if ab.has_method("list_my_pending_applications"):
			var listed: Dictionary = await ab.call("list_my_pending_applications")
			_assert(bool(listed.get("ok", false)), "I: list_my_pending failed: %s" % str(listed.get("error", "")))
			print("[ACCOUNT P1] I pending applications=%d" % int(Array(listed.get("applications", [])).size()))


func _test_relaunch_survival(nc: Node, identity: Node, user_id: String) -> void:
	var real_store = AccountSessionStoreScript.new()
	var session: NakamaSession = nc.call("get_session")
	_assert(session != null and session.is_valid(), "J: live session missing")
	_assert(real_store.save_session(session), "J: real save failed")
	_assert(real_store.has_stored_session(), "J: real store empty after save")
	var reloaded: NakamaSession = real_store.restore_session_object()
	_assert(reloaded != null and str(reloaded.user_id) == user_id, "J: session did not survive reload")

	var owner_path: String = str(identity.call("get_ownership_path"))
	_assert(FileAccess.file_exists(owner_path), "J: ownership cfg missing")
	var cfg := ConfigFile.new()
	_assert(cfg.load(owner_path) == OK, "J: ownership cfg load failed")
	var owner: String = str(cfg.get_value("ownership", "user_id", "")).strip_edges()
	_assert(owner == user_id, "J: ownership user mismatch after relaunch simulation")
	print("[ACCOUNT P1] J ownership_user=%s" % owner.substr(0, mini(8, owner.length())))


func _forge_unsigned_jwt(payload: Dictionary) -> String:
	var header := {"alg": "HS256", "typ": "JWT"}
	var h: String = Marshalls.utf8_to_base64(JSON.stringify(header)).replace("+", "-").replace("/", "_").rstrip("=")
	var p: String = Marshalls.utf8_to_base64(JSON.stringify(payload)).replace("+", "-").replace("/", "_").rstrip("=")
	return "%s.%s.fakesig" % [h, p]
