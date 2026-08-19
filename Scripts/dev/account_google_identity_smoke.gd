extends SceneTree

## Google identity architecture smokes. Isolated — no live Google login, no purchase.
##   Godot --headless --path <project> -s res://Scripts/dev/account_google_identity_smoke.gd

const AccountEmailAuthScript = preload("res://Scripts/Backend/AccountEmailAuth.gd")
const Commerce := preload("res://Scripts/CommerceAuthority.gd")
const PanelScript := preload("res://Scripts/UI/AccountSettingsPanel.gd")

const SMOKE_GOOGLE_A := "smoke-google-sub-a"
const SMOKE_GOOGLE_OTHER := "smoke-google-sub-other"
const TOKEN_MARKER := "smoke-google-id-token-MUST-NOT-PERSIST"

var _fail: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)


func _file_contains(path: String, needle: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	return text.find(needle) >= 0


func _run() -> void:
	await process_frame
	await process_frame

	var nc: Node = root.get_node_or_null("/root/NakamaConnection")
	var identity: Node = root.get_node_or_null("/root/AccountIdentityState")
	var asp: Node = root.get_node_or_null("/root/AccountSavePaths")
	var cloud: Node = root.get_node_or_null("/root/AccountCloudSave")
	var google: Node = root.get_node_or_null("/root/GoogleIdentityClient")
	if nc == null or identity == null or asp == null or cloud == null or google == null:
		push_error("[GOOGLE IDENTITY] ABORT — required autoloads missing")
		quit(2)
		return

	identity.call("begin_smoke_isolation")
	asp.call("begin_smoke_isolation")
	asp.call("enable_smoke_bootstrap_hold", true)
	cloud.call("begin_smoke_isolation")
	nc.call("begin_email_auth_smoke_isolation")
	nc.call("begin_session_store_smoke_isolation")
	Commerce.begin_smoke_isolation()

	print("[GOOGLE IDENTITY] A oauth config + unavailable native + no fake auth")
	_assert(bool(google.call("has_oauth_config")), "A: web client ID not loaded from local cfg")
	_assert(bool(google.call("web_client_id_is_well_formed")), "A: web client ID malformed")
	_assert(not _file_contains("res://config/google_oauth.cfg", "GOCSPX-"), "A: tracked cfg has secret-like value")
	_assert(not _file_contains("res://config/google_oauth.cfg", "client_secret="), "A: tracked cfg has client_secret")
	_assert(not bool(google.call("is_native_plugin_present")), "A: native plugin must not exist in headless")
	_assert(not bool(google.call("is_ready")), "A: client must not be ready without Android plugin")
	_assert(not bool(identity.call("is_google_sign_in_available")), "A: identity available")
	var status: Dictionary = identity.call("get_google_sign_in_status")
	_assert(not bool(status.get("available", true)), "A: status available")
	_assert(bool(status.get("oauth_configured", false)), "A: status oauth_configured")
	_assert(not bool(status.get("native_plugin", true)), "A: status native_plugin")
	var empty_link: Dictionary = await identity.call("link_google_identity")
	_assert(not bool(empty_link.get("ok", true)), "A: empty link succeeded")
	_assert(str(empty_link.get("error", "")) == AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE, "A: empty link code")
	var empty_login: Dictionary = await identity.call("login_with_google")
	_assert(not bool(empty_login.get("ok", true)), "A: empty login succeeded")
	_assert(str(empty_login.get("error", "")) == AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE, "A: empty login code")
	var panel: Control = PanelScript.new()
	panel.name = "GoogleUiSmoke"
	root.add_child(panel)
	await process_frame
	await process_frame
	_assert(panel.find_child("ProviderUnavailableNote", true, false) != null, "A: unavailable note missing")
	var gdiag: Label = panel.find_child("GoogleDiagnosticNote", true, false)
	_assert(gdiag != null, "A: Google diagnostic missing")
	_assert(gdiag != null and str(gdiag.text).find("G1") >= 0, "A: expected G1 diagnostic")
	_assert(gdiag == null or str(gdiag.text).find("apps.googleusercontent") < 0, "A: diagnostic leaked client id")
	_assert(panel.find_child("PlayerIdLabel", true, false) != null, "A: Player ID must remain")
	_assert(panel.find_child("LinkGoogleButton", true, false) == null, "A: link button shown")
	_assert(panel.find_child("SignInGoogleButton", true, false) == null, "A: sign-in button shown")
	if panel.has_method("show_login_view"):
		panel.call("show_login_view")
	await process_frame
	await process_frame
	_assert(panel.find_child("ContinueGoogleButton", true, false) == null, "A: continue button shown")
	panel.queue_free()

	print("[GOOGLE IDENTITY] availability codes + safe diagnostics")
	_assert(str(google.call("get_availability_code")) == "NOT_ANDROID", "diag: default NOT_ANDROID")
	google.call("smoke_reset_availability_log")
	google.call("log_availability_once")
	var avail_log: String = str(google.call("get_last_availability_log"))
	_assert(avail_log.find("[CrownspireGoogle] availability=NOT_ANDROID") >= 0, "diag: log format NOT_ANDROID")
	_assert(avail_log.find("android_runtime=false") >= 0, "diag: android_runtime boolean")
	_assert(avail_log.find("apps.googleusercontent") < 0, "diag: log leaked web client id")
	_assert(avail_log.to_lower().find("gocspx") < 0, "diag: log leaked secret")
	_assert(avail_log.find("eyJ") < 0, "diag: log leaked token")
	google.call("smoke_set_availability_flags", true, false, true)
	_assert(str(google.call("get_availability_code")) == "SINGLETON_MISSING", "diag: SINGLETON_MISSING")
	_assert(str(google.call("get_player_diagnostic_code")) == "G1", "diag: singleton maps to G1")
	google.call("smoke_set_availability_flags", true, true, false)
	_assert(str(google.call("get_availability_code")) == "OAUTH_CONFIG_MISSING", "diag: OAUTH_CONFIG_MISSING")
	_assert(str(google.call("get_player_diagnostic_code")) == "G2", "diag: oauth maps to G2")
	var g2_panel: Control = PanelScript.new()
	g2_panel.name = "GoogleDiagG2"
	root.add_child(g2_panel)
	await process_frame
	await process_frame
	var g2_note: Label = g2_panel.find_child("GoogleDiagnosticNote", true, false)
	_assert(g2_note != null and str(g2_note.text).find("G2") >= 0, "diag: Account Settings G2")
	_assert(g2_panel.find_child("LinkGoogleButton", true, false) == null, "diag: G2 must not show Google link")
	g2_panel.queue_free()
	google.call("smoke_set_availability_flags", true, true, true)
	_assert(str(google.call("get_availability_code")) == "READY", "diag: READY")
	_assert(str(google.call("get_player_diagnostic_code")) == "", "diag: READY has no player code")
	var ready_panel: Control = PanelScript.new()
	ready_panel.name = "GoogleDiagReady"
	root.add_child(ready_panel)
	await process_frame
	await process_frame
	_assert(ready_panel.find_child("GoogleDiagnosticNote", true, false) == null, "diag: READY must not show G1/G2")
	_assert(ready_panel.find_child("AppleUnavailableNote", true, false) != null, "diag: Apple remains unavailable")
	_assert(ready_panel.find_child("SignInGoogleButton", true, false) != null, "diag: READY guest can Secure with Google")
	_assert(ready_panel.find_child("PlayerIdLabel", true, false) != null, "diag: Player ID remains when Google ready")
	ready_panel.queue_free()
	google.call("smoke_clear_availability_flags")
	_assert(str(google.call("get_availability_code")) == "NOT_ANDROID", "diag: flags cleared")
	_assert(not bool(identity.call("is_google_sign_in_available")), "diag: identity unavailable after clear")

	print("[GOOGLE IDENTITY] B guest Google link preserves user_id")
	identity.call("claim_local_saves_for_user", "user_a")
	asp.call("open_save_context", "user_a", {"legacy_owner": "other", "legacy_mismatch": true, "reload": false})
	asp.call("set_cloud_bootstrap_hold", false)
	nc.call("smoke_set_session_user", "user_a")
	identity.call("on_authenticated", "user_a", "device")
	Commerce.set_test_session_authority_payloads(
		{"diamonds": 40, "entitlements": [], "user_id": "user_a"},
		{"diamonds": 40, "entitlements": [], "user_id": "user_a"}
	)
	Commerce.apply_commerce_wallet_payload({"diamonds": 40, "user_id": "user_a", "entitlements": []})
	_assert(str(identity.call("get_account_kind")) == "GUEST", "B: start guest")
	var before: String = str(nc.call("get_user_id"))
	var linked: Dictionary = await identity.call("link_google_identity", SMOKE_GOOGLE_A)
	_assert(bool(linked.get("ok", false)), "B: link failed: %s" % str(linked))
	_assert(str(linked.get("user_id", "")) == before, "B: user_id changed")
	_assert(str(nc.call("get_user_id")) == "user_a", "B: session changed")
	_assert(str(identity.call("get_current_player_id")) == before, "B: Player ID changed after Google link")
	_assert(str(identity.call("get_account_kind")) == "SECURED", "B: not secured")
	_assert(bool(identity.call("get_linked_providers").get("GOOGLE", false)), "B: GOOGLE not linked")
	_assert(bool(identity.call("has_recoverable_identity")), "B: not recoverable")
	_assert(bool(linked.get("wallet_refreshed", false)), "B: wallet refresh missing")
	_assert(int(Commerce.get_authoritative_diamonds()) == 40, "B: wallet not preserved")

	print("[GOOGLE IDENTITY] C changed user_id fails closed")
	nc.call("smoke_set_session_user", "user_a")
	var changed: Dictionary = await identity.call("link_google_identity", "FORCE_USER_CHANGE")
	_assert(not bool(changed.get("ok", true)), "C: changed user succeeded")
	_assert(str(changed.get("error", "")) == AccountEmailAuthScript.ERR_USER_CHANGED, "C: code")
	_assert(not bool(changed.get("rebound", true)), "C: rebound")
	_assert(not bool(changed.get("wallet_moved", true)), "C: wallet moved")
	_assert(int(Commerce.get_authoritative_diamonds()) == 40, "C: wallet mutated")

	print("[GOOGLE IDENTITY] D Google already linked to a different Nakama user")
	nc.call("smoke_set_session_user", "user_b")
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", "user_b")
	asp.call("open_save_context", "user_b", {"legacy_owner": "other", "legacy_mismatch": true, "reload": false})
	nc.call("smoke_set_session_user", "user_b")
	var conflict: Dictionary = await identity.call("link_google_identity", SMOKE_GOOGLE_A)
	_assert(not bool(conflict.get("ok", true)), "D: conflict succeeded")
	_assert(str(conflict.get("error", "")) == AccountEmailAuthScript.ERR_IDENTITY_IN_USE, "D: code %s" % str(conflict))
	_assert(str(nc.call("get_user_id")) == "user_b", "D: current user changed")
	_assert(str(identity.call("get_account_kind")) == "GUEST", "D: merged into other account")

	print("[GOOGLE IDENTITY] E returning Google login rebinds partition")
	nc.call("smoke_set_session_user", "device_guest")
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", "device_guest")
	asp.call("open_save_context", "device_guest", {"legacy_owner": "other", "legacy_mismatch": true, "reload": false})
	asp.call("set_cloud_bootstrap_hold", false)
	nc.call("smoke_set_session_user", "device_guest")
	identity.call("on_authenticated", "device_guest", "device")
	Commerce.set_test_session_authority_payloads(
		{"diamonds": 0, "entitlements": [], "user_id": "user_a"},
		{"diamonds": 0, "entitlements": [], "user_id": "user_a"}
	)
	Commerce.apply_commerce_wallet_payload({"diamonds": 0, "user_id": "device_guest", "entitlements": []})
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "E: guest fixture")
	_assert(str(identity.call("get_account_kind")) == "GUEST", "E: start guest")
	var login: Dictionary = await identity.call("login_with_google", SMOKE_GOOGLE_A)
	_assert(bool(login.get("ok", false)), "E: login failed: %s" % str(login))
	_assert(str(login.get("user_id", "")) == "user_a", "E: wrong user")
	_assert(str(asp.call("get_active_user_id")) == "user_a", "E: partition not rebound")
	_assert(bool(login.get("wallet_refreshed", false)), "E: wallet refresh missing")
	_assert(bool(login.get("switched_from_guest", false)), "E: should switch from guest")
	_assert(int(Commerce.get_authoritative_diamonds()) == 0, "E: expected user_a wallet 0, got %d" % int(Commerce.get_authoritative_diamonds()))

	print("[GOOGLE IDENTITY] F unknown Google login does not create")
	var unknown: Dictionary = await identity.call("login_with_google", SMOKE_GOOGLE_OTHER)
	_assert(not bool(unknown.get("ok", true)), "F: unknown Google created an account")
	_assert(str(unknown.get("error", "")) == AccountEmailAuthScript.ERR_INVALID_CREDENTIALS, "F: code")

	print("[GOOGLE IDENTITY] E2 paid guest cannot Google-login to another account")
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", "paid_guest")
	asp.call("open_save_context", "paid_guest", {"legacy_owner": "other", "legacy_mismatch": true, "reload": false})
	nc.call("smoke_set_session_user", "paid_guest")
	identity.call("on_authenticated", "paid_guest", "device")
	Commerce.apply_commerce_wallet_payload({"diamonds": 7, "user_id": "paid_guest", "entitlements": []})
	_assert(int(Commerce.get_authoritative_diamonds()) == 7, "E2: paid fixture")
	var blocked_g: Dictionary = await identity.call("login_with_google", SMOKE_GOOGLE_A)
	_assert(not bool(blocked_g.get("ok", true)), "E2: paid guest Google login succeeded")
	_assert(str(blocked_g.get("error", "")) == AccountEmailAuthScript.ERR_GUEST_SWITCH_BLOCKED, "E2: code")
	_assert(str(nc.call("get_user_id")) == "paid_guest", "E2: session switched")
	_assert(int(Commerce.get_authoritative_diamonds()) == 7, "E2: wallet merged")

	print("[GOOGLE IDENTITY] G token is not persisted")
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", "user_tok")
	nc.call("smoke_set_session_user", "user_tok")
	var tok_link: Dictionary = await identity.call("link_google_identity", TOKEN_MARKER)
	_assert(bool(tok_link.get("ok", false)), "G: token link failed: %s" % str(tok_link))
	var ownership_path: String = str(identity.call("get_ownership_path"))
	_assert(not _file_contains(ownership_path, TOKEN_MARKER), "G: token written to ownership")
	var store: Object = nc.call("get_session_store")
	var session_path: String = str(store.call("get_store_path")) if store != null else ""
	_assert(session_path == "" or not _file_contains(session_path, TOKEN_MARKER), "G: token written to session store")
	_assert(not _file_contains("res://config/google_oauth.cfg", TOKEN_MARKER), "G: token written to oauth cfg")

	print("[GOOGLE IDENTITY] H purchase gate requires actual Google linked state")
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", "guest_buy")
	nc.call("smoke_set_session_user", "guest_buy")
	_assert(not bool(identity.call("can_start_real_money_purchase")), "H: guest must not purchase")
	_assert(not bool(identity.call("is_google_sign_in_available")), "H: availability is not identity")
	identity.call("smoke_mark_google_linked")
	_assert(bool(identity.call("can_start_real_money_purchase")), "H: Google-linked must qualify")
	var gated: Dictionary = Commerce.purchase_android_product("com.crownspire.diamonds_500")
	_assert(str(gated.get("status", "")) != Commerce.STATUS_ACCOUNT_PROTECTION_REQUIRED, "H: still gated after Google link")

	print("[GOOGLE IDENTITY] I MCS email still works alongside Google architecture")
	identity.call("begin_smoke_isolation")
	identity.call("claim_local_saves_for_user", "user_mcs")
	asp.call("open_save_context", "user_mcs", {"legacy_owner": "other", "legacy_mismatch": true, "reload": false})
	asp.call("set_cloud_bootstrap_hold", false)
	nc.call("smoke_set_session_user", "user_mcs")
	var secure: Dictionary = await identity.call(
		"secure_guest_with_email",
		"google.arch.mcs@crownspire.smoke.test",
		"P4SmokePass_NeverPersist_9x!",
		"P4SmokePass_NeverPersist_9x!"
	)
	_assert(bool(secure.get("ok", false)), "I: MCS secure failed: %s" % str(secure))
	var extra: Dictionary = await identity.call("link_google_identity", "smoke-google-sub-mcs")
	_assert(bool(extra.get("ok", false)), "I: additional Google link failed: %s" % str(extra))
	_assert(str(extra.get("user_id", "")) == "user_mcs", "I: MCS user changed on Google link")
	_assert(bool(identity.call("get_linked_providers").get("EMAIL", false)), "I: EMAIL dropped")
	_assert(bool(identity.call("get_linked_providers").get("GOOGLE", false)), "I: GOOGLE missing")

	print("[GOOGLE IDENTITY] J stale wallet protection remains")
	nc.call("smoke_set_session_user", "user_j")
	identity.call("on_authenticated", "user_j", "device")
	_assert(not bool(Commerce.apply_commerce_wallet_payload({"diamonds": 999, "user_id": "user_a"})), "J: stale wallet applied")
	_assert(int(Commerce.get_authoritative_diamonds()) != 999, "J: merged stale diamonds")

	cloud.call("end_smoke_isolation")
	identity.call("end_smoke_isolation")
	asp.call("end_smoke_isolation")
	nc.call("end_email_auth_smoke_isolation")
	nc.call("end_session_store_smoke_isolation")
	Commerce.end_smoke_isolation()

	if _fail.is_empty():
		print("[GOOGLE IDENTITY] PASS")
		quit(0)
	else:
		for f: String in _fail:
			push_error("[GOOGLE IDENTITY] FAIL: %s" % f)
		quit(1)
