extends SceneTree

## Account login, linking, password visibility, purchase gate, and same-user smokes.
## Isolated — no production Nakama link, no live purchase.
##   Godot --headless --path <project> -s res://Scripts/dev/account_login_recovery_smoke.gd

const AccountEmailAuthScript = preload("res://Scripts/Backend/AccountEmailAuth.gd")
const Commerce := preload("res://Scripts/CommerceAuthority.gd")
const PanelScript := preload("res://Scripts/UI/AccountSettingsPanel.gd")
const ShopScript := preload("res://Scripts/UI/ShopScreen.gd")

const SMOKE_PASSWORD := "P4SmokePass_NeverPersist_9x!"
const SMOKE_EMAIL_A := "login.recovery.a@crownspire.smoke.test"

var _fail: Array[String] = []


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
	var asp: Node = root.get_node_or_null("/root/AccountSavePaths")
	var cloud: Node = root.get_node_or_null("/root/AccountCloudSave")
	if nc == null or identity == null or asp == null or cloud == null:
		push_error("[ACCOUNT LOGIN] ABORT — required autoloads missing")
		quit(2)
		return

	identity.call("begin_smoke_isolation")
	asp.call("begin_smoke_isolation")
	asp.call("enable_smoke_bootstrap_hold", true)
	cloud.call("begin_smoke_isolation")
	nc.call("begin_email_auth_smoke_isolation")
	nc.call("begin_session_store_smoke_isolation")
	Commerce.begin_smoke_isolation()

	print("[ACCOUNT LOGIN] A Guest → Secure Mythic Crown Studios Account")
	identity.call("claim_local_saves_for_user", "user_a")
	asp.call("open_save_context", "user_a", {"legacy_owner": "other", "legacy_mismatch": true, "reload": false})
	asp.call("set_cloud_bootstrap_hold", false)
	nc.call("smoke_set_session_user", "user_a")
	Commerce.set_test_session_authority_payloads(
		{"diamonds": 0, "entitlements": [], "user_id": "user_a"},
		{"diamonds": 0, "entitlements": [], "user_id": "user_a"}
	)
	var before_uid: String = str(nc.call("get_user_id"))
	_assert(str(identity.call("get_account_kind")) == "GUEST", "A: start guest")
	var secure: Dictionary = await identity.call("secure_guest_with_email", SMOKE_EMAIL_A, SMOKE_PASSWORD, SMOKE_PASSWORD)
	_assert(bool(secure.get("ok", false)), "A: secure failed: %s" % str(secure))
	_assert(str(secure.get("user_id", "")) == before_uid, "A: user_id changed on secure")
	_assert(str(identity.call("get_current_player_id")) == before_uid, "A: Player ID changed after secure")
	_assert(str(identity.call("get_account_kind")) == "SECURED", "A: not secured")
	_assert(bool(identity.call("has_recoverable_identity")), "A: recoverable identity")
	_assert(bool(secure.get("wallet_refreshed", false)), "A: wallet refresh missing")
	var counts_a: Dictionary = Commerce.get_session_authority_sync_counts()
	_assert(int(counts_a.get("refresh", 0)) >= 1, "A: refresh_server_wallet not called")

	print("[ACCOUNT LOGIN] B password eye")
	var panel: Control = PanelScript.new()
	panel.name = "AccountSettingsPanelSmoke"
	root.add_child(panel)
	await process_frame
	if panel.has_method("show_secure_view"):
		panel.call("show_secure_view")
	await process_frame
	await process_frame
	var pw: LineEdit = panel.find_child("PasswordEdit", true, false)
	var confirm: LineEdit = panel.find_child("ConfirmPasswordEdit", true, false)
	var toggle: Button = panel.find_child("PasswordVisibilityToggle", true, false)
	var confirm_toggle: Button = panel.find_child("ConfirmPasswordVisibilityToggle", true, false)
	_assert(pw != null, "B: password field missing")
	_assert(confirm != null, "B: confirm field missing")
	_assert(toggle != null, "B: password eye missing")
	_assert(confirm_toggle != null, "B: confirm eye missing")
	if pw != null and toggle != null:
		_assert(bool(pw.secret), "B: password hidden by default")
		pw.text = "KeepThisSecret_123"
		toggle.emit_signal("pressed")
		await process_frame
		_assert(not bool(pw.secret), "B: tap eye should show")
		_assert(str(pw.text) == "KeepThisSecret_123", "B: text lost when shown")
		toggle.emit_signal("pressed")
		await process_frame
		_assert(bool(pw.secret), "B: tap again should hide")
		_assert(str(pw.text) == "KeepThisSecret_123", "B: text lost when hidden")
	if confirm != null and confirm_toggle != null:
		_assert(bool(confirm.secret), "B: confirm hidden by default")
		confirm.text = "KeepThisSecret_123"
		confirm_toggle.emit_signal("pressed")
		await process_frame
		_assert(not bool(confirm.secret), "B: confirm show")
		_assert(str(confirm.text) == "KeepThisSecret_123", "B: confirm text lost")
	if panel.has_method("show_login_view"):
		panel.call("show_login_view")
	await process_frame
	await process_frame
	var login_pw: LineEdit = panel.find_child("LoginPasswordEdit", true, false)
	var login_toggle: Button = panel.find_child("LoginPasswordVisibilityToggle", true, false)
	_assert(login_pw != null, "B: login password field missing")
	_assert(login_toggle != null, "B: login password eye missing")
	if login_pw != null and login_toggle != null:
		_assert(bool(login_pw.secret), "B: login password hidden by default")
		login_pw.text = "KeepThisSecret_123"
		login_toggle.emit_signal("pressed")
		await process_frame
		_assert(not bool(login_pw.secret), "B: login tap eye should show")
		_assert(str(login_pw.text) == "KeepThisSecret_123", "B: login text lost when shown")
		login_toggle.emit_signal("pressed")
		await process_frame
		_assert(bool(login_pw.secret), "B: login tap again should hide")
		_assert(str(login_pw.text) == "KeepThisSecret_123", "B: login text lost when hidden")
	_assert(panel.find_child("ContinueGoogleButton", true, false) == null, "B: Google login button must stay hidden")
	_assert(panel.find_child("LinkGoogleButton", true, false) == null, "B: Google link button must stay hidden")
	panel.queue_free()

	print("[ACCOUNT LOGIN] C guest purchase gate")
	identity.call("end_smoke_isolation")
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", "guest_buy")
	nc.call("smoke_set_session_user", "guest_buy")
	_assert(not bool(identity.call("can_start_real_money_purchase")), "C: guest must not purchase")
	var shop: Control = ShopScript.new()
	shop.name = "ShopProtectSmoke"
	root.add_child(shop)
	await process_frame
	shop.call("on_open")
	await process_frame
	await process_frame
	shop.call("_on_buy_live_product", "com.crownspire.diamonds_500")
	await process_frame
	await process_frame
	_assert(shop.find_child("ProtectAccountModal", true, false) != null, "C: protect modal missing")
	var gated: Dictionary = Commerce.purchase_android_product("com.crownspire.diamonds_500")
	_assert(str(gated.get("status", "")) == Commerce.STATUS_ACCOUNT_PROTECTION_REQUIRED, "C: status %s" % str(gated.get("status", "")))
	_assert(str(gated.get("status", "")) != "BILLING_FLOW_LAUNCHED", "C: billing launched")
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "C: currency granted")
	shop.queue_free()

	print("[ACCOUNT LOGIN] D secured purchase path remains")
	identity.call("smoke_mark_secured_email")
	_assert(bool(identity.call("can_start_real_money_purchase")), "D: secured can purchase")
	var ready: Dictionary = Commerce.purchase_android_product("com.crownspire.diamonds_500")
	_assert(str(ready.get("status", "")) != Commerce.STATUS_ACCOUNT_PROTECTION_REQUIRED, "D: still gated")
	_assert(
		str(ready.get("status", "")) == Commerce.STATUS_BILLING_UNAVAILABLE
		or str(ready.get("status", "")) == Commerce.STATUS_UNAUTHENTICATED
		or str(ready.get("status", "")) == "BILLING_FLOW_LAUNCHED",
		"D: unexpected %s" % str(ready.get("status", ""))
	)

	print("[ACCOUNT LOGIN] E email login rebinds partition + wallet refresh")
	nc.call("smoke_set_session_user", "user_a")
	identity.call("claim_local_saves_for_user", "user_a")
	asp.call("open_save_context", "user_a", {"legacy_owner": "other", "legacy_mismatch": true, "reload": false})
	asp.call("set_cloud_bootstrap_hold", false)
	var re_secure: Dictionary = await identity.call("secure_guest_with_email", SMOKE_EMAIL_A, SMOKE_PASSWORD, SMOKE_PASSWORD)
	_assert(bool(re_secure.get("ok", false)) or str(identity.call("get_account_kind")) == "SECURED", "E: fixture secure")
	nc.call("smoke_set_session_user", "device_b_guest")
	identity.call("claim_local_saves_for_user", "device_b_guest")
	asp.call("open_save_context", "device_b_guest", {"legacy_owner": "other", "legacy_mismatch": true, "reload": false})
	Commerce.set_test_session_authority_payloads(
		{"diamonds": 0, "entitlements": [], "user_id": "user_a"},
		{"diamonds": 0, "entitlements": [], "user_id": "user_a"}
	)
	var login_a: Dictionary = await identity.call("login_with_email", SMOKE_EMAIL_A, SMOKE_PASSWORD)
	_assert(bool(login_a.get("ok", false)), "E: login failed: %s" % str(login_a))
	_assert(str(login_a.get("user_id", "")) == "user_a", "E: wrong user")
	_assert(str(identity.call("get_current_player_id")) == "user_a", "E: Player ID did not follow returning login")
	_assert(str(asp.call("get_active_user_id")) == "user_a", "E: partition not rebound")
	_assert(bool(login_a.get("wallet_refreshed", false)), "E: wallet refresh missing")

	print("[ACCOUNT LOGIN] F stale wallet from previous user cannot apply")
	nc.call("smoke_set_session_user", "user_b")
	identity.call("on_authenticated", "user_b", "device")
	_assert(not bool(Commerce.apply_commerce_wallet_payload({"diamonds": 999, "user_id": "user_a"})), "F: stale A wallet applied")
	_assert(int(Commerce.get_authoritative_diamonds()) != 999, "F: merged stale diamonds")
	_assert(bool(Commerce.apply_commerce_wallet_payload({"diamonds": 0, "user_id": "user_b"})), "F: B wallet rejected")
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "F: B wallet not 0")

	print("[ACCOUNT LOGIN] G Google unavailable without plugin/config + architecture")
	var google_status: Dictionary = identity.call("get_google_sign_in_status")
	_assert(not bool(google_status.get("available", true)), "G: Google must be unavailable")
	var google_link: Dictionary = await identity.call("link_google_identity", "")
	_assert(not bool(google_link.get("ok", true)), "G: Google link must fail closed")
	_assert(str(google_link.get("error", "")) == AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE, "G: error code")
	var google_same: Dictionary = identity.call("smoke_link_provider_same_user", "GOOGLE", "user_b", "user_b")
	_assert(bool(google_same.get("ok", false)), "G: same-user Google smoke failed")
	_assert(str(google_same.get("user_id", "")) == "user_b", "G: Google user changed")
	_assert(str(identity.call("get_current_player_id")) == "user_b", "G: Player ID changed after same-user Google link")
	var google_changed: Dictionary = identity.call("smoke_link_provider_same_user", "GOOGLE", "user_b", "user_other")
	_assert(not bool(google_changed.get("ok", true)), "G: changed user_id must stop")
	_assert(str(google_changed.get("error", "")) == AccountEmailAuthScript.ERR_USER_CHANGED, "G: USER_ID_CHANGED")
	_assert(not bool(google_changed.get("rebound", true)), "G: must not rebind")
	_assert(not bool(google_changed.get("wallet_moved", true)), "G: must not move wallet")
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", "user_g")
	nc.call("smoke_set_session_user", "user_g")
	var google_arch: Dictionary = await identity.call("link_google_identity", "smoke-google-sub-g")
	_assert(bool(google_arch.get("ok", false)), "G: architecture link failed: %s" % str(google_arch))
	_assert(str(google_arch.get("user_id", "")) == "user_g", "G: architecture user changed")
	_assert(bool(identity.call("has_recoverable_identity")), "G: Google link must count as recoverable")
	_assert(bool(google_arch.get("wallet_refreshed", false)), "G: wallet refresh missing on Google link")

	print("[ACCOUNT LOGIN] H Apple link unavailable + same-user smoke guard")
	var apple_status: Dictionary = identity.call("get_apple_sign_in_status")
	_assert(not bool(apple_status.get("available", true)), "H: Apple must be unavailable")
	var apple_link: Dictionary = await identity.call("link_apple_identity", "")
	_assert(not bool(apple_link.get("ok", true)), "H: Apple link must fail closed")
	var apple_changed: Dictionary = identity.call("smoke_link_provider_same_user", "APPLE", "user_b", "user_other")
	_assert(not bool(apple_changed.get("ok", true)), "H: changed user_id must stop")
	_assert(str(apple_changed.get("error", "")) == AccountEmailAuthScript.ERR_USER_CHANGED, "H: USER_ID_CHANGED")

	print("[ACCOUNT LOGIN] I paid guest cannot silently switch")
	nc.call("smoke_set_session_user", "paid_guest")
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", "paid_guest")
	asp.call("open_save_context", "paid_guest", {"legacy_owner": "other", "legacy_mismatch": true, "reload": false})
	asp.call("set_cloud_bootstrap_hold", false)
	nc.call("smoke_set_session_user", "paid_guest")
	Commerce.apply_commerce_wallet_payload({"diamonds": 500, "user_id": "paid_guest", "entitlements": []})
	_assert(int(Commerce.get_authoritative_diamonds()) == 500, "I: fixture diamonds")
	_assert(str(identity.call("get_account_kind")) == "GUEST", "I: still guest")
	var safety: Dictionary = identity.call("evaluate_guest_switch_safety")
	_assert(bool(safety.get("block", false)), "I: paid guest must block switch")
	_assert(bool(safety.get("warn", false)), "I: paid guest must warn")
	var blocked_login: Dictionary = await identity.call("login_with_email", SMOKE_EMAIL_A, SMOKE_PASSWORD)
	_assert(not bool(blocked_login.get("ok", true)), "I: login should be blocked")
	_assert(str(blocked_login.get("error", "")) == AccountEmailAuthScript.ERR_GUEST_SWITCH_BLOCKED, "I: block code")
	_assert(str(nc.call("get_user_id")) == "paid_guest", "I: session switched anyway")
	_assert(int(Commerce.get_authoritative_diamonds()) == 500, "I: wallet merged/cleared")

	cloud.call("end_smoke_isolation")
	identity.call("end_smoke_isolation")
	asp.call("end_smoke_isolation")
	nc.call("end_email_auth_smoke_isolation")
	nc.call("end_session_store_smoke_isolation")
	Commerce.end_smoke_isolation()

	if _fail.is_empty():
		print("[ACCOUNT LOGIN] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[ACCOUNT LOGIN] FAIL: %s" % f)
		quit(1)
