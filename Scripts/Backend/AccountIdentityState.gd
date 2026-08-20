extends Node

## Crownspire account identity + local save ownership + email/Google secure/login.
## Does not store passwords or Google ID tokens. Google Sign-In is available only when
## the Android Credential Manager plugin is loaded and a web client ID is configured.

signal account_state_changed
signal local_save_ownership_changed
signal local_save_mismatch(auth_user_id: String, owner_user_id: String)
signal login_gate_requested(reason: String)
signal email_auth_completed(result: Dictionary)

const AccountEmailAuthScript = preload("res://Scripts/Backend/AccountEmailAuth.gd")
const CommerceAuthorityScript = preload("res://Scripts/CommerceAuthority.gd")

const OWNERSHIP_PATH := "user://account_local_ownership.cfg"
const SMOKE_OWNERSHIP_PATH := "user://account_local_ownership_smoke_test.cfg"
const OWNER_SECTION := "ownership"
const MISMATCH_CODE := "LOCAL_SAVE_ACCOUNT_MISMATCH"

enum AccountKind { GUEST, SECURED }
enum AuthPhase { IDLE, AUTHENTICATING }

## Future login-gate architecture — Phase 4 may request SHOW_GATE for secured accounts.
enum BootGateMode { AUTO_CONTINUE, SHOW_GATE }

const LEGACY_SAVE_MARKERS: PackedStringArray = [
	"user://buildings.cfg",
	"user://resources.cfg",
	"user://troops.cfg",
	"user://heroes.cfg",
	"user://quests.cfg",
	"user://bag.cfg",
	"user://research_queue.cfg",
	"user://construction_queue.cfg",
	"user://marches.cfg",
	"user://mail.cfg",
]

var _ownership_path_override: String = ""
var _auth_user_id: String = ""
var _account_kind: int = AccountKind.GUEST
var _auth_phase: int = AuthPhase.IDLE
var _linked_providers: Dictionary = {} ## EMAIL/GOOGLE/APPLE/FACEBOOK -> true
var _masked_email: String = ""
var _local_owner_user_id: String = ""
var _known_secured: bool = false ## persisted: device knows a secured Crownspire account
var _mismatch_active: bool = false
var _boot_gate_mode: int = BootGateMode.AUTO_CONTINUE
var _session_auth_source: String = "" ## restore | refresh | device | email | link_email | gate_required
var _last_email_error: Dictionary = {}
var _smoke_mode: bool = false
var _public_player_id: String = "" ## formatted display ID, never Nakama UUID
var _public_player_id_status: String = "" ## "" | LOADING | READY | UNAVAILABLE
var _public_player_id_owner: String = ""
var _public_player_id_generation: int = 0
var _smoke_public_ids: Dictionary = {} ## user_id -> formatted public ID
var _smoke_public_id_unavailable: bool = false

const PUBLIC_PLAYER_ID_ALPHABET := "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
const RPC_GET_PUBLIC_PLAYER_ID := "crownspire_account_get_public_player_id"


func _ready() -> void:
	_load_ownership_record()
	call_deferred("_bind_nakama")


func begin_smoke_isolation() -> void:
	_ownership_path_override = SMOKE_OWNERSHIP_PATH
	_auth_user_id = ""
	_account_kind = AccountKind.GUEST
	_auth_phase = AuthPhase.IDLE
	_linked_providers = {}
	_masked_email = ""
	_local_owner_user_id = ""
	_known_secured = false
	_mismatch_active = false
	_session_auth_source = ""
	_boot_gate_mode = BootGateMode.AUTO_CONTINUE
	_last_email_error = {}
	_smoke_mode = true
	_clear_public_player_id_state()
	_smoke_public_ids = {}
	_smoke_public_id_unavailable = false
	if FileAccess.file_exists(get_ownership_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(get_ownership_path()))


func end_smoke_isolation() -> void:
	_ownership_path_override = SMOKE_OWNERSHIP_PATH
	if FileAccess.file_exists(get_ownership_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(get_ownership_path()))
	_ownership_path_override = ""
	_smoke_mode = false
	_auth_user_id = ""
	_account_kind = AccountKind.GUEST
	_auth_phase = AuthPhase.IDLE
	_linked_providers = {}
	_masked_email = ""
	_local_owner_user_id = ""
	_known_secured = false
	_mismatch_active = false
	_session_auth_source = ""
	_boot_gate_mode = BootGateMode.AUTO_CONTINUE
	_last_email_error = {}
	_clear_public_player_id_state()
	_smoke_public_ids = {}
	_smoke_public_id_unavailable = false
	_load_ownership_record()


func get_ownership_path() -> String:
	if _ownership_path_override != "":
		return _ownership_path_override
	return OWNERSHIP_PATH


func get_auth_user_id() -> String:
	return _auth_user_id


func get_local_owner_user_id() -> String:
	return _local_owner_user_id


## Live Nakama user_id for the account currently on this device. Internal authority only.
func get_current_player_id() -> String:
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc != null and nc.has_method("get_user_id"):
		var uid: String = str(nc.call("get_user_id")).strip_edges()
		if uid != "":
			return uid
	return _auth_user_id.strip_edges()


## Log-only UUID prefix. Never use this as the player-facing Player ID.
func get_current_player_id_short() -> String:
	return format_player_id_short(get_current_player_id())


## Public Player ID for Copy. Empty until the server ID is ready. Never the Nakama UUID.
func get_player_id_copy_payload() -> String:
	if _public_player_id_status != "READY":
		return ""
	return _public_player_id


func format_player_id_short(user_id: String) -> String:
	return _short_id(user_id)


func get_public_player_id() -> String:
	return _public_player_id if _public_player_id_status == "READY" else ""


func get_public_player_id_status() -> String:
	return _public_player_id_status


func get_player_facing_id_label_text() -> String:
	if _public_player_id_status == "READY" and _public_player_id != "":
		return "%s: %s" % [tr("PLAYER_ID"), _public_player_id]
	if _public_player_id_status == "UNAVAILABLE":
		return "%s: %s" % [tr("PLAYER_ID"), tr("PLAYER_ID_UNAVAILABLE")]
	return "%s: %s" % [tr("PLAYER_ID"), tr("PLAYER_ID_LOADING")]


func can_copy_public_player_id() -> bool:
	return _public_player_id_status == "READY" and _public_player_id != ""


func smoke_set_public_player_id_for_user(user_id: String, public_id: String) -> void:
	var uid: String = user_id.strip_edges()
	var formatted: String = format_public_player_id(public_id)
	if uid == "" or formatted == "":
		return
	_smoke_public_ids[uid] = formatted


func smoke_mark_public_player_id_unavailable(unavailable: bool = true) -> void:
	_smoke_public_id_unavailable = unavailable


func retry_public_player_id() -> void:
	var uid: String = get_current_player_id()
	if uid == "":
		return
	_kickoff_public_player_id(uid, true)


## Player-facing Chief Name. Never email. Empty if no authoritative name is known.
func get_chief_display_name() -> String:
	var ab: Node = get_node_or_null("/root/AllianceBackend")
	if ab != null and ab.has_method("get_display_name"):
		var server_name: String = str(ab.call("get_display_name")).strip_edges()
		if server_name != "":
			if ab.has_method("get_profile"):
				var prof: Variant = ab.call("get_profile")
				if typeof(prof) == TYPE_DICTIONARY:
					var prof_uid: String = str((prof as Dictionary).get("user_id", "")).strip_edges()
					var live: String = get_current_player_id()
					if prof_uid != "" and live != "" and prof_uid != live:
						return ""
			return server_name
	return ""


## Copies the public Player ID. Never copies the Nakama UUID. Does not log the value.
func copy_current_player_id_to_clipboard() -> Dictionary:
	var payload: String = get_player_id_copy_payload()
	if payload.is_empty():
		return {"ok": false, "copied": false, "clipboard_available": false}
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return {"ok": false, "copied": false, "clipboard_available": false}
	DisplayServer.clipboard_set(payload)
	return {"ok": true, "copied": true, "clipboard_available": true}


func get_account_kind() -> String:
	return "SECURED" if _account_kind == AccountKind.SECURED else "GUEST"


## Combined UI/status string: AUTHENTICATING | ACCOUNT_MISMATCH | SAVE_CONFLICT | SECURED | GUEST | RECONNECTING | LOGIN_REQUIRED
func get_account_status() -> String:
	if _auth_phase == AuthPhase.AUTHENTICATING:
		return "AUTHENTICATING"
	if _mismatch_active:
		return "ACCOUNT_MISMATCH"
	var cloud: Node = get_node_or_null("/root/AccountCloudSave")
	if cloud != null and cloud.has_method("has_blocked_conflict") and bool(cloud.call("has_blocked_conflict")):
		return "SAVE_CONFLICT"
	if is_live_authenticated() and _account_kind == AccountKind.SECURED:
		return "SECURED"
	# Terminal restore failure only. Known secured ownership is not live auth.
	if should_force_login_gate():
		return "LOGIN_REQUIRED"
	if needs_live_session_restore():
		return "RECONNECTING"
	if _account_kind == AccountKind.SECURED:
		return "SECURED"
	return "GUEST"


func is_guest() -> bool:
	return _account_kind == AccountKind.GUEST


func is_secured() -> bool:
	return _account_kind == AccountKind.SECURED


func is_known_secured() -> bool:
	return _known_secured


func is_live_authenticated() -> bool:
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	return nc != null and nc.has_method("is_authenticated") and bool(nc.call("is_authenticated"))


func needs_live_session_restore() -> bool:
	if not _known_secured:
		return false
	return not is_live_authenticated()


func is_authenticating() -> bool:
	return _auth_phase == AuthPhase.AUTHENTICATING


func get_auth_phase() -> String:
	return "AUTHENTICATING" if _auth_phase == AuthPhase.AUTHENTICATING else "IDLE"

func get_linked_providers() -> Dictionary:
	return _linked_providers.duplicate(true)


func get_masked_email() -> String:
	return _masked_email


func has_recoverable_identity() -> bool:
	return (
		bool(_linked_providers.get("EMAIL", false))
		or bool(_linked_providers.get("GOOGLE", false))
		or bool(_linked_providers.get("APPLE", false))
	)


func can_start_real_money_purchase() -> bool:
	return has_recoverable_identity()


func is_google_sign_in_available() -> bool:
	var google: Node = get_node_or_null("/root/GoogleIdentityClient")
	if google == null or not google.has_method("is_ready"):
		return false
	return bool(google.call("is_ready"))


func is_apple_sign_in_available() -> bool:
	## No Sign in with Apple plugin, entitlement, or Service ID wiring is in this repo.
	return false


func get_google_sign_in_status() -> Dictionary:
	var google: Node = get_node_or_null("/root/GoogleIdentityClient")
	var status: Dictionary = {}
	if google != null and google.has_method("get_availability_status"):
		status = google.call("get_availability_status")
	var available: bool = bool(status.get("available", false))
	var blockers: PackedStringArray = PackedStringArray()
	var raw_blockers: Variant = status.get("blockers", [])
	if raw_blockers is PackedStringArray:
		blockers = raw_blockers
	elif typeof(raw_blockers) == TYPE_ARRAY:
		for item: Variant in raw_blockers:
			blockers.append(str(item))
	if blockers.is_empty() and not available:
		blockers.append("Google Sign-In is not available in this build")
	return {
		"available": available,
		"linked": bool(_linked_providers.get("GOOGLE", false)),
		"native_plugin": bool(status.get("native_plugin", false)),
		"oauth_configured": bool(status.get("oauth_configured", false)),
		"code": str(status.get("code", "")),
		"android_runtime": bool(status.get("android_runtime", false)),
		"singleton_present": bool(status.get("singleton_present", false)),
		"oauth_config_present": bool(status.get("oauth_config_present", false)),
		"player_diagnostic": str(status.get("player_diagnostic", "")),
		"error": "" if available else AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE,
		"message": (
			"" if available
			else AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE)
		),
		"blockers": blockers,
	}


func get_apple_sign_in_status() -> Dictionary:
	return {
		"available": false,
		"linked": bool(_linked_providers.get("APPLE", false)),
		"error": AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE,
		"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE),
		"blockers": PackedStringArray([
			"No Sign in with Apple native plugin in this repository",
			"Apple Developer Sign in with Apple capability / Service ID is required",
			"iOS entitlement and nonce/identity-token handshake are required",
		]),
	}


func get_linked_method_labels() -> PackedStringArray:
	var labels: PackedStringArray = PackedStringArray()
	if bool(_linked_providers.get("EMAIL", false)):
		labels.append("Mythic Crown Studios Account")
	if bool(_linked_providers.get("GOOGLE", false)):
		labels.append("Google")
	if bool(_linked_providers.get("APPLE", false)):
		labels.append("Apple")
	return labels


## Link Google to the CURRENT Nakama user. Does not authenticate_google (that can create/switch users).
func link_google_identity(id_token: String = "") -> Dictionary:
	var token: String = id_token.strip_edges()
	id_token = ""
	if token.is_empty():
		if not is_google_sign_in_available():
			return {
				"ok": false,
				"available": false,
				"error": AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE,
				"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE),
			}
		var acquired: Dictionary = await _acquire_google_id_token()
		if not bool(acquired.get("ok", false)):
			return acquired
		token = str(acquired.get("id_token", "")).strip_edges()
		acquired["id_token"] = ""
	elif not _smoke_mode and not is_google_sign_in_available():
		token = ""
		return {
			"ok": false,
			"available": false,
			"error": AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE,
			"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE),
		}
	if token.is_empty():
		return {
			"ok": false,
			"error": AccountEmailAuthScript.ERR_MISSING_TOKEN,
			"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_MISSING_TOKEN),
		}
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null or not bool(nc.call("is_authenticated")):
		token = ""
		var err := {
			"ok": false,
			"error": AccountEmailAuthScript.ERR_NOT_AUTH,
			"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_NOT_AUTH),
		}
		_last_email_error = err
		return err
	var before_uid: String = str(nc.call("get_user_id")).strip_edges()
	_set_auth_phase(AuthPhase.AUTHENTICATING)
	var link_res: Dictionary = await nc.call("link_google_token", token)
	token = ""
	if not bool(link_res.get("ok", false)):
		_set_auth_phase(AuthPhase.IDLE)
		_last_email_error = link_res
		email_auth_completed.emit(link_res)
		return link_res
	var after_uid: String = str(nc.call("get_user_id")).strip_edges()
	if after_uid != before_uid:
		_set_auth_phase(AuthPhase.IDLE)
		var changed := {
			"ok": false,
			"error": AccountEmailAuthScript.ERR_USER_CHANGED,
			"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_USER_CHANGED),
			"before_user_id": before_uid,
			"after_user_id": after_uid,
			"rebound": false,
			"wallet_moved": false,
		}
		_last_email_error = changed
		email_auth_completed.emit(changed)
		return changed
	_linked_providers["GOOGLE"] = true
	_account_kind = AccountKind.SECURED
	_known_secured = true
	_save_ownership_record(before_uid, has_legacy_local_progression())
	await _probe_account_now()
	_set_auth_phase(AuthPhase.IDLE)
	var ok_res := {
		"ok": true,
		"secured": true,
		"user_id": before_uid,
		"provider": "GOOGLE",
		"account_kind": get_account_kind(),
	}
	_last_email_error = {}
	await _refresh_wallet_after_account_op()
	ok_res["wallet_refreshed"] = true
	account_state_changed.emit()
	email_auth_completed.emit(ok_res)
	print("[AccountIdentity] Google linked to existing account user=%s" % _short_id(before_uid))
	return ok_res


## Returning Google login. create=false. May switch to the intended linked user; never merges wallets.
func login_with_google(id_token: String = "") -> Dictionary:
	var token: String = id_token.strip_edges()
	id_token = ""
	if token.is_empty():
		if not is_google_sign_in_available():
			return {
				"ok": false,
				"available": false,
				"logged_in": false,
				"error": AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE,
				"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE),
			}
		var acquired: Dictionary = await _acquire_google_id_token()
		if not bool(acquired.get("ok", false)):
			return acquired
		token = str(acquired.get("id_token", "")).strip_edges()
		acquired["id_token"] = ""
	elif not _smoke_mode and not is_google_sign_in_available():
		token = ""
		return {
			"ok": false,
			"available": false,
			"logged_in": false,
			"error": AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE,
			"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE),
		}
	if token.is_empty():
		return {
			"ok": false,
			"logged_in": false,
			"error": AccountEmailAuthScript.ERR_MISSING_TOKEN,
			"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_MISSING_TOKEN),
		}
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null:
		token = ""
		var err := {
			"ok": false,
			"logged_in": false,
			"error": AccountEmailAuthScript.ERR_NETWORK,
			"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_NETWORK),
		}
		_last_email_error = err
		return err
	var previous_uid: String = ""
	if bool(nc.call("is_authenticated")):
		previous_uid = str(nc.call("get_user_id")).strip_edges()
	var previous_was_guest: bool = is_guest() and previous_uid != ""
	var safety: Dictionary = evaluate_guest_switch_safety()
	if bool(safety.get("block", false)):
		token = ""
		var blocked := {
			"ok": false,
			"logged_in": false,
			"error": AccountEmailAuthScript.ERR_GUEST_SWITCH_BLOCKED,
			"message": str(safety.get("message", AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_GUEST_SWITCH_BLOCKED))),
			"factors": safety.get("factors", []),
		}
		_last_email_error = blocked
		return blocked
	_set_auth_phase(AuthPhase.AUTHENTICATING)
	var login_res: Dictionary = await nc.call("authenticate_google_login", token)
	token = ""
	if not bool(login_res.get("ok", false)):
		_set_auth_phase(AuthPhase.IDLE)
		_last_email_error = login_res
		email_auth_completed.emit(login_res)
		return login_res
	return await _finish_returning_login(str(login_res.get("user_id", "")), previous_uid, previous_was_guest, "google", {"GOOGLE": true})


## Link Apple to the CURRENT Nakama user. Does not authenticate_apple (that can create/switch users).
func link_apple_identity(_id_token: String = "") -> Dictionary:
	return {
		"ok": false,
		"available": false,
		"error": AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE,
		"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE),
	}


## Smoke-only: prove SAME user_id linking without calling production Google/Apple APIs.
func smoke_link_provider_same_user(provider: String, before_user_id: String, after_user_id: String) -> Dictionary:
	if not _smoke_mode:
		return {
			"ok": false,
			"error": AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE,
			"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE),
		}
	var key: String = provider.strip_edges().to_upper()
	if key != "GOOGLE" and key != "APPLE":
		return {"ok": false, "error": AccountEmailAuthScript.ERR_AUTH_FAILED}
	var before: String = before_user_id.strip_edges()
	var after: String = after_user_id.strip_edges()
	if before.is_empty() or after != before:
		return {
			"ok": false,
			"error": AccountEmailAuthScript.ERR_USER_CHANGED,
			"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_USER_CHANGED),
			"before_user_id": before,
			"after_user_id": after,
			"rebound": false,
			"wallet_moved": false,
		}
	_linked_providers[key] = true
	_account_kind = AccountKind.SECURED
	_known_secured = true
	account_state_changed.emit()
	return {
		"ok": true,
		"secured": true,
		"user_id": before,
		"provider": key,
		"account_kind": get_account_kind(),
	}


func smoke_mark_secured_email(masked_email: String = "s***@crownspire.smoke.test") -> void:
	if not _smoke_mode:
		return
	_linked_providers["EMAIL"] = true
	_account_kind = AccountKind.SECURED
	_known_secured = true
	_masked_email = masked_email.strip_edges()
	account_state_changed.emit()


func smoke_mark_google_linked() -> void:
	if not _smoke_mode:
		return
	_linked_providers["GOOGLE"] = true
	_account_kind = AccountKind.SECURED
	_known_secured = true
	account_state_changed.emit()


func evaluate_guest_switch_safety() -> Dictionary:
	## Returning-player login gate is recovering a known secured account — never block that.
	if _known_secured or _boot_gate_mode == BootGateMode.SHOW_GATE or should_block_guest_device_fallback():
		return {"warn": false, "block": false, "factors": []}
	if not is_guest():
		return {"warn": false, "block": false, "factors": []}
	var factors: Array = []
	if int(CommerceAuthorityScript.get_authoritative_diamonds()) > 0:
		factors.append("diamonds")
	if int(CommerceAuthorityScript.get_beta_voucher_balance()) > 0:
		factors.append("vouchers")
	if CommerceAuthorityScript.has_any_active_entitlement():
		factors.append("entitlements")
	if CommerceAuthorityScript.has_pending_purchase_ledger():
		factors.append("purchase_ledger")
	var has_progress: bool = false
	var asp: Node = get_node_or_null("/root/AccountSavePaths")
	if asp != null and bool(asp.call("is_bound")):
		has_progress = bool(asp.call("has_account_gameplay_progress", str(asp.call("get_active_user_id"))))
	if not has_progress:
		has_progress = has_legacy_local_progression()
	if has_progress:
		factors.append("progress")
	var block: bool = false
	for f: Variant in factors:
		if str(f) != "progress":
			block = true
			break
	var warn: bool = has_progress or block
	var message: String = ""
	if block:
		message = AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_GUEST_SWITCH_BLOCKED)
	elif warn:
		message = "This Guest Account is not secured. Logging into another account will leave guest progress on this device only — it may be unrecoverable if this device is lost. Secure Account first to protect it."
	return {
		"warn": warn,
		"block": block,
		"factors": factors,
		"message": message,
	}


func has_local_save_mismatch() -> bool:
	return _mismatch_active


func get_mismatch_code() -> String:
	return MISMATCH_CODE if _mismatch_active else ""


func get_session_auth_source() -> String:
	return _session_auth_source


func get_boot_gate_mode() -> String:
	return "SHOW_GATE" if _boot_gate_mode == BootGateMode.SHOW_GATE else "AUTO_CONTINUE"


func get_last_email_error() -> Dictionary:
	return _last_email_error.duplicate(true)


func set_boot_gate_mode_for_future(mode: String) -> void:
	if mode.strip_edges().to_upper() == "SHOW_GATE":
		_boot_gate_mode = BootGateMode.SHOW_GATE
	else:
		_boot_gate_mode = BootGateMode.AUTO_CONTINUE


func should_force_login_gate() -> bool:
	## Overlay authority: terminal restore failure AND no usable live Nakama session.
	## Known secured ownership alone must never force the login gate.
	if is_live_authenticated():
		return false
	return _boot_gate_mode == BootGateMode.SHOW_GATE


func should_block_guest_device_fallback() -> bool:
	## True when this device remembers a secured account and must not silently mint a new guest.
	if not _known_secured:
		return false
	var owner: String = _local_owner_user_id.strip_edges()
	return owner != ""


func request_login_gate(reason: String = "session_unrecoverable") -> void:
	if is_live_authenticated():
		print("[CrownspireSession] gate_suppressed_live_session")
		return
	_boot_gate_mode = BootGateMode.SHOW_GATE
	_session_auth_source = "gate_required"
	print("[CrownspireSession] gate_requested reason=%s" % reason.strip_edges())
	account_state_changed.emit()
	login_gate_requested.emit(reason)


func is_local_progression_safe_to_use() -> bool:
	var asp: Node = get_node_or_null("/root/AccountSavePaths")
	if asp != null and asp.has_method("can_load_active_partition"):
		if bool(asp.call("is_bound")) and str(asp.call("get_active_user_id")) == _auth_user_id:
			return true
	return not _mismatch_active


func has_legacy_local_progression() -> bool:
	for path: String in LEGACY_SAVE_MARKERS:
		if FileAccess.file_exists(path):
			return true
	return false


func on_authenticated(user_id: String, auth_source: String = "device") -> Dictionary:
	var uid: String = user_id.strip_edges()
	_session_auth_source = auth_source.strip_edges()
	if uid.is_empty():
		return {"ok": false, "error": "empty_user_id"}
	var previous_uid: String = _auth_user_id.strip_edges()
	_auth_user_id = uid
	if previous_uid != "" and previous_uid != uid:
		_clear_public_player_id_state()
	# Live auth wins any previously queued terminal gate.
	if auth_source != "gate_required":
		_boot_gate_mode = BootGateMode.AUTO_CONTINUE
	_refresh_account_kind_from_nakama()
	var ownership: Dictionary = _apply_local_ownership_rules(uid)
	var asp: Node = get_node_or_null("/root/AccountSavePaths")
	if asp != null and asp.has_method("open_for_authenticated_user"):
		var save_ctx: Dictionary = asp.call("open_for_authenticated_user", uid, ownership)
		ownership["save_context"] = save_ctx
	_kickoff_public_player_id(uid, false)
	account_state_changed.emit()
	return ownership


func claim_local_saves_for_user(user_id: String) -> Dictionary:
	var uid: String = user_id.strip_edges()
	if uid.is_empty():
		return {"ok": false, "error": "empty_user_id"}
	_local_owner_user_id = uid
	_mismatch_active = false
	_save_ownership_record(uid, true)
	local_save_ownership_changed.emit()
	return {"ok": true, "claimed": true, "owner_user_id": uid}


## Link email+password to the CURRENT authenticated guest. user_id must not change.
func secure_guest_with_email(email: String, password: String, confirm_password: String) -> Dictionary:
	var form: Dictionary = AccountEmailAuthScript.validate_secure_form(email, password, confirm_password)
	if not bool(form.get("ok", false)):
		_last_email_error = form
		return form
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null or not bool(nc.call("is_authenticated")):
		var err := {
			"ok": false,
			"error": AccountEmailAuthScript.ERR_NOT_AUTH,
			"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_NOT_AUTH),
		}
		_last_email_error = err
		return err
	var before_uid: String = str(nc.call("get_user_id")).strip_edges()
	_set_auth_phase(AuthPhase.AUTHENTICATING)
	var link_res: Dictionary = await nc.call("link_email_credentials", str(form.get("email", "")), password)
	# Clear password from local scope ASAP (GDScript keeps args; avoid logging).
	password = ""
	confirm_password = ""
	if not bool(link_res.get("ok", false)):
		_set_auth_phase(AuthPhase.IDLE)
		_last_email_error = link_res
		email_auth_completed.emit(link_res)
		return link_res
	var after_uid: String = str(nc.call("get_user_id")).strip_edges()
	if after_uid != before_uid:
		_set_auth_phase(AuthPhase.IDLE)
		var changed := {
			"ok": false,
			"error": AccountEmailAuthScript.ERR_USER_CHANGED,
			"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_USER_CHANGED),
			"before_user_id": before_uid,
			"after_user_id": after_uid,
		}
		_last_email_error = changed
		email_auth_completed.emit(changed)
		return changed
	_linked_providers["EMAIL"] = true
	_account_kind = AccountKind.SECURED
	_masked_email = AccountEmailAuthScript.mask_email(str(form.get("email", "")))
	_known_secured = true
	_save_ownership_record(before_uid, has_legacy_local_progression())
	await _probe_account_now()
	_set_auth_phase(AuthPhase.IDLE)
	var ok_res := {
		"ok": true,
		"secured": true,
		"user_id": before_uid,
		"masked_email": _masked_email,
		"account_kind": get_account_kind(),
	}
	_last_email_error = {}
	await _refresh_wallet_after_account_op()
	ok_res["wallet_refreshed"] = true
	account_state_changed.emit()
	email_auth_completed.emit(ok_res)
	print("[AccountIdentity] Account secured with email user=%s" % _short_id(before_uid))
	return ok_res


## Authenticate an existing email account (create=false). Switches active partition; never merges.
func login_with_email(email: String, password: String) -> Dictionary:
	var form: Dictionary = AccountEmailAuthScript.validate_login_form(email, password)
	if not bool(form.get("ok", false)):
		_last_email_error = form
		return form
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null:
		var err := {
			"ok": false,
			"error": AccountEmailAuthScript.ERR_NETWORK,
			"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_NETWORK),
		}
		_last_email_error = err
		return err
	var previous_uid: String = ""
	if bool(nc.call("is_authenticated")):
		previous_uid = str(nc.call("get_user_id")).strip_edges()
	var previous_was_guest: bool = is_guest() and previous_uid != ""
	var safety: Dictionary = evaluate_guest_switch_safety()
	if bool(safety.get("block", false)):
		var blocked := {
			"ok": false,
			"logged_in": false,
			"error": AccountEmailAuthScript.ERR_GUEST_SWITCH_BLOCKED,
			"message": str(safety.get("message", AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_GUEST_SWITCH_BLOCKED))),
			"factors": safety.get("factors", []),
		}
		_last_email_error = blocked
		return blocked
	_set_auth_phase(AuthPhase.AUTHENTICATING)
	var login_res: Dictionary = await nc.call("authenticate_email_login", str(form.get("email", "")), password)
	password = ""
	if not bool(login_res.get("ok", false)):
		_set_auth_phase(AuthPhase.IDLE)
		_last_email_error = login_res
		email_auth_completed.emit(login_res)
		return login_res
	return await _finish_returning_login(str(login_res.get("user_id", "")), previous_uid, previous_was_guest, "email", {"EMAIL": true, "masked_email": AccountEmailAuthScript.mask_email(str(form.get("email", "")))})


func warn_before_login_switch() -> Dictionary:
	## UI helper: guest with progress may become unrecoverable if device data is lost.
	## Paid Diamonds/vouchers/entitlements block a silent switch. Gameplay-only guests still warn
	## but may log in because partitions are preserved on disk (no merge).
	return evaluate_guest_switch_safety()


func _finish_returning_login(
	new_uid_raw: String,
	previous_uid: String,
	previous_was_guest: bool,
	auth_source: String,
	extras: Dictionary
) -> Dictionary:
	var new_uid: String = new_uid_raw.strip_edges()
	if new_uid.is_empty():
		_set_auth_phase(AuthPhase.IDLE)
		var bad := {
			"ok": false,
			"logged_in": false,
			"error": AccountEmailAuthScript.ERR_AUTH_FAILED,
			"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_AUTH_FAILED),
		}
		_last_email_error = bad
		email_auth_completed.emit(bad)
		return bad
	var ownership: Dictionary = on_authenticated(new_uid, auth_source)
	if bool(extras.get("EMAIL", false)):
		_linked_providers["EMAIL"] = true
	if bool(extras.get("GOOGLE", false)):
		_linked_providers["GOOGLE"] = true
	_account_kind = AccountKind.SECURED
	if extras.has("masked_email"):
		_masked_email = str(extras.get("masked_email", "")).strip_edges()
	_known_secured = true
	_local_owner_user_id = new_uid
	_mismatch_active = false
	_save_ownership_record(new_uid, false)
	await _probe_account_now()
	var cloud_res: Dictionary = {}
	var cloud: Node = get_node_or_null("/root/AccountCloudSave")
	if cloud != null and cloud.has_method("sync_after_auth"):
		cloud_res = await cloud.call("sync_after_auth")
	_set_auth_phase(AuthPhase.IDLE)
	_boot_gate_mode = BootGateMode.AUTO_CONTINUE
	var ok_res := {
		"ok": true,
		"logged_in": true,
		"user_id": new_uid,
		"previous_user_id": previous_uid,
		"switched_from_guest": previous_was_guest and previous_uid != "" and previous_uid != new_uid,
		"previous_guest_preserved": previous_was_guest and previous_uid != "" and previous_uid != new_uid,
		"masked_email": _masked_email,
		"ownership": ownership,
		"cloud_sync": cloud_res,
		"gameplay_live": cloud != null and cloud.has_method("is_gameplay_live") and bool(cloud.call("is_gameplay_live")),
		"auth_source": auth_source,
	}
	if cloud != null and cloud.has_method("has_blocked_conflict") and bool(cloud.call("has_blocked_conflict")):
		ok_res["conflict"] = true
		ok_res["needs_resolution"] = true
		ok_res["error"] = AccountEmailAuthScript.ERR_CLOUD_CONFLICT
		ok_res["message"] = AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_CLOUD_CONFLICT)
		_boot_gate_mode = BootGateMode.SHOW_GATE
		_last_email_error = {
			"ok": true,
			"logged_in": true,
			"conflict": true,
			"error": AccountEmailAuthScript.ERR_CLOUD_CONFLICT,
			"message": ok_res["message"],
		}
	else:
		ok_res["conflict"] = false
		_last_email_error = {}
	await _refresh_wallet_after_account_op()
	ok_res["wallet_refreshed"] = true
	account_state_changed.emit()
	email_auth_completed.emit(ok_res)
	print(
		"[AccountIdentity] %s login user=%s switched_from=%s conflict=%s"
		% [auth_source, _short_id(new_uid), _short_id(previous_uid), str(ok_res.get("conflict", false))]
	)
	return ok_res


func _acquire_google_id_token() -> Dictionary:
	var google: Node = get_node_or_null("/root/GoogleIdentityClient")
	if google == null or not google.has_method("request_id_token"):
		return {
			"ok": false,
			"available": false,
			"error": AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE,
			"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE),
		}
	return await google.call("request_id_token")


func _refresh_wallet_after_account_op() -> void:
	if _smoke_mode and not bool(CommerceAuthorityScript.is_smoke_isolation()):
		return
	await CommerceAuthorityScript.on_session_authenticated()


func _bind_nakama() -> void:
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null:
		return
	if nc.has_signal("authenticated") and not nc.authenticated.is_connected(_on_nakama_authenticated):
		nc.authenticated.connect(_on_nakama_authenticated)
	if nc.has_signal("login_gate_needed") and not nc.login_gate_needed.is_connected(_on_login_gate_needed):
		nc.login_gate_needed.connect(_on_login_gate_needed)
	if nc.has_method("is_authenticated") and bool(nc.call("is_authenticated")):
		_on_nakama_authenticated()


func _on_login_gate_needed(reason: String) -> void:
	if is_live_authenticated():
		print("[CrownspireSession] gate_suppressed_live_session")
		return
	request_login_gate(reason)


func _on_nakama_authenticated() -> void:
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null or not nc.has_method("get_user_id"):
		return
	var uid: String = str(nc.call("get_user_id")).strip_edges()
	var source: String = "device"
	if nc.has_method("get_last_auth_source"):
		source = str(nc.call("get_last_auth_source"))
	on_authenticated(uid, source)


func _apply_local_ownership_rules(auth_uid: String) -> Dictionary:
	_load_ownership_record()
	var owner: String = _local_owner_user_id.strip_edges()
	if owner.is_empty():
		_local_owner_user_id = auth_uid
		_mismatch_active = false
		var had_legacy: bool = has_legacy_local_progression()
		_save_ownership_record(auth_uid, had_legacy)
		local_save_ownership_changed.emit()
		print("[AccountIdentity] Local save ownership claimed for current user (legacy=%s)" % str(had_legacy))
		return {
			"ok": true,
			"claimed": true,
			"legacy": had_legacy,
			"owner_user_id": auth_uid,
			"mismatch": false,
		}

	if owner == auth_uid:
		_mismatch_active = false
		return {
			"ok": true,
			"claimed": false,
			"owner_user_id": owner,
			"mismatch": false,
		}

	# Different account authenticated — partitions stay isolated; flag legacy flat mismatch only.
	_mismatch_active = true
	local_save_mismatch.emit(auth_uid, owner)
	push_warning(
		"[AccountIdentity] %s auth_user=%s local_owner=%s — local progression blocked for handoff"
		% [MISMATCH_CODE, _short_id(auth_uid), _short_id(owner)]
	)
	print(
		"[AccountIdentity] %s — refusing to load/overwrite local progression for a different account"
		% MISMATCH_CODE
	)
	return {
		"ok": false,
		"error": MISMATCH_CODE,
		"auth_user_id": auth_uid,
		"owner_user_id": owner,
		"mismatch": true,
	}


func _refresh_account_kind_from_nakama() -> void:
	_linked_providers = {}
	# Keep known secured from disk until probe confirms; don't mark SECURED from session alone.
	if not _known_secured:
		_account_kind = AccountKind.GUEST
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null or not nc.has_method("get_client") or not nc.has_method("get_session"):
		return
	if not bool(nc.call("is_authenticated")):
		return
	var client: NakamaClient = nc.call("get_client")
	var session: NakamaSession = nc.call("get_session")
	if client == null or session == null:
		return
	_probe_account_async(client, session)


func _probe_account_now() -> void:
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null or not bool(nc.call("is_authenticated")):
		return
	if nc.has_method("is_email_auth_smoke") and bool(nc.call("is_email_auth_smoke")):
		# Smoke fills providers via link/login result.
		if _linked_providers.has("EMAIL") or _linked_providers.has("GOOGLE"):
			_account_kind = AccountKind.SECURED
		return
	var client: NakamaClient = nc.call("get_client")
	var session: NakamaSession = nc.call("get_session")
	if client == null or session == null:
		return
	await _probe_account_async(client, session)


func _probe_account_async(client: NakamaClient, session: NakamaSession) -> void:
	var account = await client.get_account_async(session)
	if account == null or account.is_exception():
		return
	var linked: Dictionary = {}
	var email: String = str(account.email).strip_edges()
	if email != "":
		linked["EMAIL"] = true
		_masked_email = AccountEmailAuthScript.mask_email(email)
	var user = account.user
	if user != null:
		if str(user.google_id).strip_edges() != "":
			linked["GOOGLE"] = true
		if str(user.apple_id).strip_edges() != "":
			linked["APPLE"] = true
		if str(user.facebook_id).strip_edges() != "":
			linked["FACEBOOK"] = true
	_linked_providers = linked
	# Do not treat device-only session as SECURED.
	if not linked.is_empty():
		_account_kind = AccountKind.SECURED
		_known_secured = true
		if _auth_user_id != "":
			_save_ownership_record(_auth_user_id, has_legacy_local_progression())
	else:
		_account_kind = AccountKind.GUEST
	account_state_changed.emit()


func _set_auth_phase(phase: int) -> void:
	_auth_phase = phase
	account_state_changed.emit()


func _load_ownership_record() -> void:
	_local_owner_user_id = ""
	_known_secured = false
	_masked_email = ""
	var cfg := ConfigFile.new()
	if cfg.load(get_ownership_path()) != OK:
		return
	_local_owner_user_id = str(cfg.get_value(OWNER_SECTION, "user_id", "")).strip_edges()
	_known_secured = bool(cfg.get_value(OWNER_SECTION, "secured", false))
	_masked_email = str(cfg.get_value(OWNER_SECTION, "masked_email", "")).strip_edges()
	# Never load passwords or identity tokens — none should exist.
	if cfg.has_section_key(OWNER_SECTION, "password") or cfg.has_section_key(OWNER_SECTION, "email_password"):
		push_warning("[AccountIdentity] Removing unexpected password key from ownership file")
		cfg.erase_section_key(OWNER_SECTION, "password")
		cfg.erase_section_key(OWNER_SECTION, "email_password")
		cfg.save(get_ownership_path())
	if (
		cfg.has_section_key(OWNER_SECTION, "google_id_token")
		or cfg.has_section_key(OWNER_SECTION, "id_token")
		or cfg.has_section_key(OWNER_SECTION, "oauth_refresh_token")
	):
		push_warning("[AccountIdentity] Removing unexpected identity-token key from ownership file")
		cfg.erase_section_key(OWNER_SECTION, "google_id_token")
		cfg.erase_section_key(OWNER_SECTION, "id_token")
		cfg.erase_section_key(OWNER_SECTION, "oauth_refresh_token")
		cfg.save(get_ownership_path())


func _save_ownership_record(user_id: String, legacy_claimed: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(get_ownership_path())
	cfg.set_value(OWNER_SECTION, "user_id", user_id)
	cfg.set_value(OWNER_SECTION, "claimed_at", int(Time.get_unix_time_from_system()))
	cfg.set_value(OWNER_SECTION, "legacy_claimed", legacy_claimed)
	cfg.set_value(OWNER_SECTION, "version", 2)
	cfg.set_value(OWNER_SECTION, "secured", _known_secured or _account_kind == AccountKind.SECURED)
	cfg.set_value(OWNER_SECTION, "masked_email", _masked_email)
	# Explicitly ensure password / identity-token keys are never written.
	if cfg.has_section_key(OWNER_SECTION, "password"):
		cfg.erase_section_key(OWNER_SECTION, "password")
	if cfg.has_section_key(OWNER_SECTION, "email_password"):
		cfg.erase_section_key(OWNER_SECTION, "email_password")
	if cfg.has_section_key(OWNER_SECTION, "google_id_token"):
		cfg.erase_section_key(OWNER_SECTION, "google_id_token")
	if cfg.has_section_key(OWNER_SECTION, "id_token"):
		cfg.erase_section_key(OWNER_SECTION, "id_token")
	if cfg.has_section_key(OWNER_SECTION, "oauth_refresh_token"):
		cfg.erase_section_key(OWNER_SECTION, "oauth_refresh_token")
	cfg.save(get_ownership_path())


func _short_id(user_id: String) -> String:
	var uid: String = user_id.strip_edges()
	if uid.length() <= 8:
		return uid
	return uid.substr(0, 8)


func _clear_public_player_id_state() -> void:
	_public_player_id = ""
	_public_player_id_status = "LOADING"
	_public_player_id_owner = ""


func normalize_public_player_id(raw: String) -> String:
	var compact: String = raw.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if compact.length() != 8:
		return ""
	for i: int in range(compact.length()):
		if PUBLIC_PLAYER_ID_ALPHABET.find(compact[i]) < 0:
			return ""
	return compact


func format_public_player_id(raw: String) -> String:
	var normalized: String = normalize_public_player_id(raw)
	if normalized == "":
		return ""
	return "%s-%s" % [normalized.substr(0, 4), normalized.substr(4, 4)]


func _kickoff_public_player_id(user_id: String, force: bool) -> void:
	var uid: String = user_id.strip_edges()
	if uid == "":
		_clear_public_player_id_state()
		return
	if _public_player_id_owner != uid:
		_public_player_id = ""
		_public_player_id_status = "LOADING"
		_public_player_id_owner = uid
	elif force or _public_player_id_status != "READY":
		if _public_player_id_status != "READY":
			_public_player_id_status = "LOADING"
	_public_player_id_generation += 1
	var gen: int = _public_player_id_generation
	if _smoke_mode:
		_apply_smoke_public_player_id(uid, gen)
		account_state_changed.emit()
		return
	_ensure_public_player_id_async(uid, gen)


func _apply_smoke_public_player_id(user_id: String, gen: int) -> void:
	if gen != _public_player_id_generation or _public_player_id_owner != user_id:
		return
	if _smoke_public_id_unavailable:
		_public_player_id = ""
		_public_player_id_status = "UNAVAILABLE"
		return
	if _smoke_public_ids.has(user_id):
		var formatted: String = format_public_player_id(str(_smoke_public_ids[user_id]))
		if formatted != "":
			_public_player_id = formatted
			_public_player_id_status = "READY"
			return
	_public_player_id = ""
	_public_player_id_status = "LOADING"


func _ensure_public_player_id_async(user_id: String, gen: int) -> void:
	var res: Dictionary = await _rpc_get_public_player_id()
	if gen != _public_player_id_generation:
		return
	if get_current_player_id() != user_id:
		return
	var formatted: String = format_public_player_id(str(res.get("public_player_id", "")))
	if bool(res.get("ok", false)) and formatted != "":
		_public_player_id = formatted
		_public_player_id_status = "READY"
		account_state_changed.emit()
		return
	_public_player_id = ""
	_public_player_id_status = "UNAVAILABLE"
	account_state_changed.emit()


func _rpc_get_public_player_id() -> Dictionary:
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null or not nc.has_method("is_authenticated") or not bool(nc.call("is_authenticated")):
		return {"ok": false, "error": "not_authenticated"}
	if not nc.has_method("get_client") or not nc.has_method("get_session"):
		return {"ok": false, "error": "missing_client"}
	var client: Variant = nc.call("get_client")
	var session: Variant = nc.call("get_session")
	if client == null or session == null:
		return {"ok": false, "error": "missing_session"}
	var raw: Variant = await client.rpc_async(session, RPC_GET_PUBLIC_PLAYER_ID, "{}")
	if raw == null or (raw.has_method("is_exception") and bool(raw.call("is_exception"))):
		return {"ok": false, "error": "rpc_failed"}
	var payload_str: String = str(raw.payload) if ("payload" in raw) else ""
	if payload_str.strip_edges() == "":
		return {"ok": false, "error": "empty_payload"}
	var parsed: Variant = JSON.parse_string(payload_str)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "invalid_payload"}
	return parsed as Dictionary
