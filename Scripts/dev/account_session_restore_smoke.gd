extends SceneTree

## Session restore across app updates / token expiry. Isolated — no live login, spend, or purchase.
##   Godot --headless --path <project> -s res://Scripts/dev/account_session_restore_smoke.gd

const AccountSessionStoreScript = preload("res://Scripts/Backend/AccountSessionStore.gd")
const PanelScript = preload("res://Scripts/UI/AccountSettingsPanel.gd")
const Commerce := preload("res://Scripts/CommerceAuthority.gd")

const USER_A := "restore_smoke_user_aaaaaaaa"
const PUBLIC_A := "A2B3-C4D5"

var _fail: Array[String] = []
var _gate_reasons: PackedStringArray = PackedStringArray()
var _auth_emits: int = 0
var _device_auth_calls: int = 0
var _refresh_calls: int = 0
var _refresh_result: NakamaSession = null


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
		push_error("[SESSION RESTORE] ABORT — required autoloads missing")
		quit(2)
		return

	if nc.has_signal("login_gate_needed") and not nc.login_gate_needed.is_connected(_on_gate):
		nc.login_gate_needed.connect(_on_gate)
	if identity.has_signal("login_gate_requested") and not identity.login_gate_requested.is_connected(_on_gate):
		identity.login_gate_requested.connect(_on_gate)

	var asp: Node = root.get_node_or_null("/root/AccountSavePaths")
	nc.call("begin_restore_smoke_isolation")
	identity.call("begin_smoke_isolation")
	if asp != null and asp.has_method("begin_smoke_isolation"):
		asp.call("begin_smoke_isolation")
	Commerce.begin_smoke_isolation()

	print("[SESSION RESTORE] A valid stored session restores same user silently")
	await _test_valid_restore(nc, identity)

	print("[SESSION RESTORE] B expired access + valid refresh")
	await _test_refresh_restore(nc, identity)

	print("[SESSION RESTORE] C transient network does not erase session or mint guest")
	await _test_transient_refresh(nc, identity)

	print("[SESSION RESTORE] D unrecoverable refresh shows login gate")
	await _test_unrecoverable(nc, identity)

	print("[SESSION RESTORE] E app-version/update does not clear session file")
	_test_version_survival(nc)

	print("[SESSION RESTORE] F local secured metadata without live session")
	await _test_false_secured_ui(nc, identity)

	print("[SESSION RESTORE] G successful restore can bind PPI + wallet")
	await _test_post_restore_hooks(nc, identity)

	print("[SESSION RESTORE] H create=false device restore success does not open gate")
	await _test_device_restore_success(nc, identity)

	print("[SESSION RESTORE] I restore user mismatch fails closed")
	await _test_device_restore_mismatch(nc, identity)

	print("[SESSION RESTORE] J queued gate is suppressed when live auth wins")
	await _test_gate_suppressed_by_live_auth(nc, identity)

	print("[SESSION RESTORE] K create=true is never used in secured restore")
	_test_create_false_policy()

	print("[SESSION RESTORE] L GameHUD boot does not treat ownership as gate")
	_test_hud_boot_gate_authority()

	identity.call("end_smoke_isolation")
	if asp != null and asp.has_method("end_smoke_isolation"):
		asp.call("end_smoke_isolation")
	nc.call("end_restore_smoke_isolation")
	Commerce.end_smoke_isolation()

	if _fail.is_empty():
		print("[SESSION RESTORE] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[SESSION RESTORE] FAIL: %s" % f)
		quit(1)


func _on_gate(reason: String = "") -> void:
	_gate_reasons.append(str(reason))


func _test_valid_restore(nc: Node, identity: Node) -> void:
	_reset_handlers(nc, identity)
	identity.call("claim_local_saves_for_user", USER_A)
	identity.call("smoke_mark_secured_email")
	_assert(bool(identity.call("is_known_secured")), "A: known secured lost")
	_assert(not bool(identity.call("should_force_login_gate")), "A: ownership alone forced gate")
	var session: NakamaSession = _make_session(USER_A, int(Time.get_unix_time_from_system()) + 3600, int(Time.get_unix_time_from_system()) + 7200)
	var store = nc.call("get_session_store")
	_assert(store.save_session(session), "A: save failed")
	var restored: NakamaSession = await nc.call("restore_stored_session_for_test", "device-a")
	_assert(restored != null and restored.is_valid(), "A: restore returned null")
	_assert(str(restored.user_id) == USER_A, "A: user_id changed")
	_assert(str(nc.call("get_last_auth_source")) == "restore", "A: source %s" % str(nc.call("get_last_auth_source")))
	_assert(_refresh_calls == 0, "A: refresh should not run")
	_assert(_device_auth_calls == 0, "A: device auth should not run")
	_assert(_gate_reasons.is_empty(), "A: login gate emitted")
	_assert(not bool(identity.call("should_force_login_gate")), "A: gate forced after successful restore")
	_assert(bool(nc.call("is_authenticated")), "A: live session not applied")
	_assert(bool(Commerce.is_nakama_authenticated()), "A: Shop auth API still unauthenticated")
	_assert(store.has_stored_session(), "A: stored session erased")


func _test_refresh_restore(nc: Node, identity: Node) -> void:
	_reset_handlers(nc, identity)
	identity.call("claim_local_saves_for_user", USER_A)
	identity.call("smoke_mark_secured_email")
	var expired: NakamaSession = _make_session(USER_A, 1, int(Time.get_unix_time_from_system()) + 7200)
	var store = nc.call("get_session_store")
	_assert(store.save_session(expired), "B: save expired failed")
	var fresh: NakamaSession = _make_session(USER_A, int(Time.get_unix_time_from_system()) + 3600, int(Time.get_unix_time_from_system()) + 7200)
	_refresh_result = fresh
	nc.call("smoke_set_refresh_handler", Callable(self, "_refresh_ok"))
	var restored: NakamaSession = await nc.call("restore_stored_session_for_test", "device-a")
	_assert(restored != null and str(restored.user_id) == USER_A, "B: refresh restore failed")
	_assert(str(nc.call("get_last_auth_source")) == "refresh", "B: source %s" % str(nc.call("get_last_auth_source")))
	_assert(_refresh_calls == 1, "B: refresh not called")
	_assert(_device_auth_calls == 0, "B: device auth ran")
	_assert(store.save_session(restored), "B: save refreshed failed")
	var again: NakamaSession = store.restore_session_object()
	_assert(again != null and not again.is_expired(), "B: refreshed session not saved")
	_assert(str(again.user_id) == USER_A, "B: saved user changed")
	_assert(_gate_reasons.is_empty(), "B: login gate emitted")
	_assert(not bool(identity.call("should_force_login_gate")), "B: gate forced after refresh")
	_assert(bool(Commerce.is_nakama_authenticated()), "B: Shop auth API still unauthenticated")


func _test_transient_refresh(nc: Node, identity: Node) -> void:
	_reset_handlers(nc, identity)
	identity.call("claim_local_saves_for_user", USER_A)
	identity.call("smoke_mark_secured_email")
	var expired: NakamaSession = _make_session(USER_A, 1, int(Time.get_unix_time_from_system()) + 7200)
	var store = nc.call("get_session_store")
	_assert(store.save_session(expired), "C: save failed")
	var before: Dictionary = store.load_session_data()
	nc.call("smoke_set_refresh_handler", Callable(self, "_refresh_transient"))
	var restored: NakamaSession = await nc.call("restore_stored_session_for_test", "device-a")
	_assert(restored == null, "C: should not return a session")
	_assert(str(nc.call("get_last_auth_source")) == "retry", "C: source %s" % str(nc.call("get_last_auth_source")))
	_assert(_device_auth_calls == 0, "C: device auth should wait for retry")
	_assert(_gate_reasons.is_empty(), "C: transient failure forced login")
	_assert(store.has_stored_session(), "C: stored session erased")
	var after: Dictionary = store.load_session_data()
	_assert(str(after.get("user_id", "")) == USER_A, "C: stored user_id lost")
	_assert(str(after.get("auth_token", "")).length() == str(before.get("auth_token", "")).length(), "C: auth token cleared")
	_assert(str(after.get("refresh_token", "")).length() == str(before.get("refresh_token", "")).length(), "C: refresh token cleared")
	_assert(not bool(identity.call("should_force_login_gate")), "C: transient failure forced permanent gate")
	_assert(str(identity.call("get_account_status")) != "LOGIN_REQUIRED", "C: status LOGIN_REQUIRED during retry")


func _test_unrecoverable(nc: Node, identity: Node) -> void:
	_reset_handlers(nc, identity)
	identity.call("claim_local_saves_for_user", USER_A)
	identity.call("smoke_mark_secured_email")
	_assert(bool(identity.call("should_block_guest_device_fallback")), "D: should block guest")
	_assert(not bool(identity.call("should_force_login_gate")), "D: ownership forced gate before terminal failure")
	var expired: NakamaSession = _make_session(USER_A, 1, int(Time.get_unix_time_from_system()) + 7200)
	var store = nc.call("get_session_store")
	_assert(store.save_session(expired), "D: save failed")
	nc.call("smoke_set_refresh_handler", Callable(self, "_refresh_invalid"))
	nc.call("smoke_set_device_auth_handler", Callable(self, "_device_invalid"))
	var restored: NakamaSession = await nc.call("restore_stored_session_for_test", "device-a")
	_assert(restored == null, "D: unrecoverable returned a session")
	_assert(str(nc.call("get_last_auth_source")) == "gate_required", "D: source %s" % str(nc.call("get_last_auth_source")))
	_assert(_gate_reasons.size() > 0, "D: login gate not shown")
	_assert(bool(identity.call("should_force_login_gate")), "D: terminal failure did not force gate")
	_assert(str(identity.call("get_account_status")) == "LOGIN_REQUIRED", "D: status %s" % str(identity.call("get_account_status")))
	_assert(store.has_stored_session(), "D: unrecoverable erased credentials")
	_assert(str(store.load_session_data().get("user_id", "")) == USER_A, "D: user_id lost")
	_assert(nc.call("get_last_device_restore_create") == false, "D: create flag was not false")


func _test_version_survival(nc: Node) -> void:
	var store = nc.call("get_session_store")
	var session: NakamaSession = _make_session(USER_A, int(Time.get_unix_time_from_system()) + 3600, int(Time.get_unix_time_from_system()) + 7200)
	_assert(store.save_session(session), "E: save failed")
	var conn_src := FileAccess.get_file_as_string("res://Scripts/Backend/NakamaConnection.gd")
	var store_src := FileAccess.get_file_as_string("res://Scripts/Backend/AccountSessionStore.gd")
	_assert(conn_src.find("versionCode") < 0, "E: NakamaConnection ties logout to versionCode")
	_assert(store_src.find("this file must survive updates") >= 0, "E: missing update-persistence comment")
	_assert(store_src.find("version/code") < 0 and store_src.find("export_version") < 0, "E: session store keyed to export version")
	_assert(store.has_stored_session(), "E: session missing after version-change simulation")
	var restored: NakamaSession = store.restore_session_object()
	_assert(restored != null and str(restored.user_id) == USER_A, "E: session did not survive update simulation")


func _test_false_secured_ui(nc: Node, identity: Node) -> void:
	_reset_handlers(nc, identity)
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", USER_A)
	identity.call("smoke_mark_secured_email")
	nc.call("smoke_set_unauthenticated", true)
	_assert(bool(identity.call("is_known_secured")), "F: known secured lost")
	_assert(not bool(identity.call("is_live_authenticated")), "F: live session should be false")
	_assert(bool(identity.call("needs_live_session_restore")), "F: restore needed flag")
	_assert(not bool(identity.call("should_force_login_gate")), "F: ownership alone forced login gate")
	var status: String = str(identity.call("get_account_status"))
	_assert(status == "RECONNECTING", "F: status %s" % status)
	_assert(status != "SECURED", "F: still reporting live SECURED")
	_assert(status != "LOGIN_REQUIRED", "F: ownership treated as terminal login gate")
	var panel: Control = PanelScript.new()
	panel.name = "AccountSettingsRestoreSmoke"
	root.add_child(panel)
	await process_frame
	await process_frame
	var title: Label = panel.find_child("AccountStatusTitle", true, false)
	_assert(title != null, "F: status title missing")
	if title != null:
		_assert(str(title.text) == "Sign in required", "F: false authenticated title: %s" % str(title.text))
		_assert(str(title.text).find("Secured") < 0, "F: still showing Secured")
	var body: Label = panel.find_child("AccountStatusBody", true, false)
	_assert(body != null, "F: status body missing")
	if body != null:
		_assert(str(body.text).find("not signed in") >= 0, "F: body does not explain reconnect")
	_assert(panel.find_child("SecureAccountButton", true, false) == null, "F: Secure Account offered during restore")
	panel.queue_free()
	nc.call("smoke_set_unauthenticated", false)


func _test_post_restore_hooks(nc: Node, identity: Node) -> void:
	_reset_handlers(nc, identity)
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", USER_A)
	identity.call("smoke_set_public_player_id_for_user", USER_A, PUBLIC_A)
	Commerce.set_test_session_authority_payloads(
		{"diamonds": 0, "entitlements": [], "user_id": USER_A, "vouchers": 5},
		{"diamonds": 0, "entitlements": [], "user_id": USER_A, "vouchers": 5}
	)
	var session: NakamaSession = _make_session(USER_A, int(Time.get_unix_time_from_system()) + 3600, int(Time.get_unix_time_from_system()) + 7200)
	var store = nc.call("get_session_store")
	_assert(store.save_session(session), "G: save failed")
	var restored: NakamaSession = await nc.call("restore_stored_session_for_test", "device-a")
	_assert(restored != null and str(restored.user_id) == USER_A, "G: restore failed")
	var ownership: Dictionary = identity.call("on_authenticated", str(restored.user_id), str(nc.call("get_last_auth_source")))
	_assert(bool(ownership.get("ok", false)), "G: on_authenticated failed")
	_assert(str(identity.call("get_auth_user_id")) == USER_A, "G: auth user mismatch")
	await process_frame
	_assert(str(identity.call("get_public_player_id")) == PUBLIC_A, "G: Public Player ID not fetchable after restore")
	await Commerce.on_session_authenticated()
	_assert(int(Commerce.get_session_authority_sync_counts().get("refresh", 0)) >= 1, "G: wallet refresh did not run")
	_assert(str(identity.call("get_local_owner_user_id")) == USER_A, "G: partition owner changed")
	_assert(not bool(identity.call("should_force_login_gate")), "G: gate forced after restore hooks")
	_assert(bool(Commerce.is_nakama_authenticated()), "G: Shop auth API still unauthenticated")


func _test_device_restore_success(nc: Node, identity: Node) -> void:
	_reset_handlers(nc, identity)
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", USER_A)
	identity.call("smoke_mark_secured_email")
	var expired: NakamaSession = _make_session(USER_A, 1, 1)
	var store = nc.call("get_session_store")
	_assert(store.save_session(expired), "H: save failed")
	nc.call("smoke_set_device_auth_handler", Callable(self, "_device_ok"))
	var restored: NakamaSession = await nc.call("restore_stored_session_for_test", "device-a")
	_assert(restored != null and str(restored.user_id) == USER_A, "H: device restore failed")
	_assert(str(nc.call("get_last_auth_source")) == "device_restore", "H: source %s" % str(nc.call("get_last_auth_source")))
	_assert(_device_auth_calls == 1, "H: device restore not attempted")
	_assert(_gate_reasons.is_empty(), "H: login gate emitted")
	_assert(not bool(identity.call("should_force_login_gate")), "H: gate forced after device restore")
	_assert(nc.call("get_last_device_restore_create") == false, "H: create was not false")
	_assert(bool(Commerce.is_nakama_authenticated()), "H: Shop auth API still unauthenticated")


func _test_device_restore_mismatch(nc: Node, identity: Node) -> void:
	_reset_handlers(nc, identity)
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", USER_A)
	identity.call("smoke_mark_secured_email")
	var expired: NakamaSession = _make_session(USER_A, 1, 1)
	var store = nc.call("get_session_store")
	_assert(store.save_session(expired), "I: save failed")
	nc.call("smoke_set_device_auth_handler", Callable(self, "_device_mismatch"))
	var restored: NakamaSession = await nc.call("restore_stored_session_for_test", "device-a")
	_assert(restored == null, "I: mismatch returned a session")
	_assert(str(nc.call("get_last_auth_source")) == "gate_required", "I: source %s" % str(nc.call("get_last_auth_source")))
	_assert(_gate_reasons.size() > 0, "I: mismatch did not request gate")
	_assert(bool(identity.call("should_force_login_gate")), "I: mismatch did not force gate")
	_assert(store.has_stored_session(), "I: mismatch erased credentials")
	_assert(str(store.load_session_data().get("user_id", "")) == USER_A, "I: stored user changed")
	_assert(nc.call("get_last_device_restore_create") == false, "I: create was not false")


func _test_gate_suppressed_by_live_auth(nc: Node, identity: Node) -> void:
	_reset_handlers(nc, identity)
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", USER_A)
	identity.call("smoke_mark_secured_email")
	identity.call("request_login_gate", "session_unrecoverable")
	_assert(bool(identity.call("should_force_login_gate")), "J: queued gate not armed")
	var session: NakamaSession = _make_session(USER_A, int(Time.get_unix_time_from_system()) + 3600, int(Time.get_unix_time_from_system()) + 7200)
	var store = nc.call("get_session_store")
	_assert(store.save_session(session), "J: save failed")
	var restored: NakamaSession = await nc.call("restore_stored_session_for_test", "device-a")
	_assert(restored != null, "J: restore failed")
	identity.call("on_authenticated", USER_A, "restore")
	_assert(not bool(identity.call("should_force_login_gate")), "J: live auth did not clear gate")
	_gate_reasons = PackedStringArray()
	identity.call("request_login_gate", "session_unrecoverable")
	_assert(not bool(identity.call("should_force_login_gate")), "J: request while live still armed gate")
	_assert(_gate_reasons.is_empty(), "J: request while live still emitted overlay")


func _test_create_false_policy() -> void:
	var src: String = FileAccess.get_file_as_string("res://Scripts/Backend/NakamaConnection.gd")
	var start: int = src.find("func _restore_existing_device_session")
	var nxt: int = src.find("func _invoke_smoke_device_auth", start)
	_assert(start >= 0 and nxt > start, "K: restore device function missing")
	if start >= 0 and nxt > start:
		var block: String = src.substr(start, nxt - start)
		_assert(block.find("authenticate_device_async(device_id, null, false)") >= 0, "K: create=false missing")
		_assert(block.find("authenticate_device_async(device_id, null, true)") < 0, "K: create=true used in restore")
	var pri_start: int = src.find("func _authenticate_session_priority")
	var pri_end: int = src.find("func _expected_restore_user_id", pri_start)
	if pri_start >= 0 and pri_end > pri_start:
		var pri: String = src.substr(pri_start, pri_end - pri_start)
		var guest_idx: int = pri.find("return await _client.authenticate_device_async(device_id)")
		var gate_idx: int = pri.find("gate_required")
		_assert(guest_idx < 0 or gate_idx < guest_idx, "K: guest create path runs before gate block")


func _test_hud_boot_gate_authority() -> void:
	var hud: String = FileAccess.get_file_as_string("res://Scenes/UI/GameHUD.gd")
	_assert(hud.find("should_force_login_gate") >= 0, "L: HUD lost gate authority check")
	_assert(hud.find("gate_suppressed_live_session") >= 0, "L: HUD missing live-session suppress")
	_assert(hud.find("gate_shown reason=") >= 0, "L: HUD missing gate_shown diagnostic")
	_assert(hud.find("_on_login_gate_requested(\"boot\")") >= 0, "L: HUD boot path lost")
	var gate_src: String = FileAccess.get_file_as_string("res://Scripts/UI/AccountLoginGate.gd")
	_assert(gate_src.find("func should_present_overlay") >= 0, "L: overlay helper missing")
	_assert(gate_src.find("gate_suppressed_live_session") >= 0, "L: ensure_on_tree missing suppress")


func _reset_handlers(nc: Node, identity: Node = null) -> void:
	_gate_reasons = PackedStringArray()
	_device_auth_calls = 0
	_refresh_calls = 0
	_refresh_result = null
	nc.call("smoke_set_refresh_handler", Callable(self, "_no_refresh"))
	nc.call("smoke_set_device_auth_handler", Callable(self, "_no_device"))
	nc.call("smoke_set_unauthenticated", false)
	if nc.has_method("smoke_clear_restore_session"):
		nc.call("smoke_clear_restore_session")
	if identity != null and identity.has_method("set_boot_gate_mode_for_future"):
		identity.call("set_boot_gate_mode_for_future", "AUTO_CONTINUE")


func _refresh_ok(_restored: NakamaSession) -> NakamaSession:
	_refresh_calls += 1
	return _refresh_result


func _refresh_transient(_restored: NakamaSession) -> Dictionary:
	_refresh_calls += 1
	return {"ok": false, "transient": true, "error": "network timeout"}


func _refresh_invalid(_restored: NakamaSession) -> Dictionary:
	_refresh_calls += 1
	return {"ok": false, "transient": false, "error": "Invalid refresh token"}


func _device_invalid(_device_id: String, _expected: String) -> Dictionary:
	_device_auth_calls += 1
	return {"ok": false, "transient": false, "error": "device id not found"}


func _device_ok(_device_id: String, expected_user_id: String) -> NakamaSession:
	_device_auth_calls += 1
	return _make_session(expected_user_id, int(Time.get_unix_time_from_system()) + 3600, int(Time.get_unix_time_from_system()) + 7200)


func _device_mismatch(_device_id: String, _expected: String) -> NakamaSession:
	_device_auth_calls += 1
	return _make_session("restore_smoke_user_mismatch", int(Time.get_unix_time_from_system()) + 3600, int(Time.get_unix_time_from_system()) + 7200)


func _no_refresh(_restored: NakamaSession) -> Dictionary:
	_refresh_calls += 1
	return {"ok": false, "transient": false, "error": "unexpected refresh"}


func _no_device(_device_id: String, _expected: String) -> Dictionary:
	_device_auth_calls += 1
	return {"ok": false, "transient": false, "error": "unexpected device auth"}


func _make_session(user_id: String, access_exp: int, refresh_exp: int) -> NakamaSession:
	var access := _forge_unsigned_jwt({"uid": user_id, "usn": "restore_smoke", "exp": access_exp})
	var refresh := _forge_unsigned_jwt({"uid": user_id, "exp": refresh_exp})
	return NakamaSession.new(access, false, refresh)


func _forge_unsigned_jwt(payload: Dictionary) -> String:
	var header := {"alg": "HS256", "typ": "JWT"}
	var h: String = Marshalls.utf8_to_base64(JSON.stringify(header)).replace("+", "-").replace("/", "_").rstrip("=")
	var p: String = Marshalls.utf8_to_base64(JSON.stringify(payload)).replace("+", "-").replace("/", "_").rstrip("=")
	return "%s.%s.fakesig" % [h, p]
