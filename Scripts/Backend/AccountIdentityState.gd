extends Node

## Crownspire account identity + local save ownership + Phase 4 email secure/login.
## Does not store passwords. Does not implement Google/Apple/Facebook yet.

signal account_state_changed
signal local_save_ownership_changed
signal local_save_mismatch(auth_user_id: String, owner_user_id: String)
signal login_gate_requested(reason: String)
signal email_auth_completed(result: Dictionary)

const AccountEmailAuthScript = preload("res://Scripts/Backend/AccountEmailAuth.gd")

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
	_load_ownership_record()


func get_ownership_path() -> String:
	if _ownership_path_override != "":
		return _ownership_path_override
	return OWNERSHIP_PATH


func get_auth_user_id() -> String:
	return _auth_user_id


func get_local_owner_user_id() -> String:
	return _local_owner_user_id


func get_account_kind() -> String:
	return "SECURED" if _account_kind == AccountKind.SECURED else "GUEST"


## Combined UI/status string: AUTHENTICATING | ACCOUNT_MISMATCH | SAVE_CONFLICT | SECURED | GUEST
func get_account_status() -> String:
	if _auth_phase == AuthPhase.AUTHENTICATING:
		return "AUTHENTICATING"
	if _mismatch_active:
		return "ACCOUNT_MISMATCH"
	var cloud: Node = get_node_or_null("/root/AccountCloudSave")
	if cloud != null and cloud.has_method("has_blocked_conflict") and bool(cloud.call("has_blocked_conflict")):
		return "SAVE_CONFLICT"
	if _account_kind == AccountKind.SECURED:
		return "SECURED"
	return "GUEST"


func is_guest() -> bool:
	return _account_kind == AccountKind.GUEST


func is_secured() -> bool:
	return _account_kind == AccountKind.SECURED


func is_known_secured() -> bool:
	return _known_secured


func is_authenticating() -> bool:
	return _auth_phase == AuthPhase.AUTHENTICATING


func get_auth_phase() -> String:
	return "AUTHENTICATING" if _auth_phase == AuthPhase.AUTHENTICATING else "IDLE"

func get_linked_providers() -> Dictionary:
	return _linked_providers.duplicate(true)


func get_masked_email() -> String:
	return _masked_email


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
	## Valid restored/refresh sessions never force the gate (handled before this is consulted).
	## Known secured account whose session cannot be restored → prefer login over new guest.
	if _boot_gate_mode == BootGateMode.SHOW_GATE:
		return true
	return should_block_guest_device_fallback()


func should_block_guest_device_fallback() -> bool:
	## True when this device remembers a secured account and must not silently mint a new guest.
	if not _known_secured:
		return false
	var owner: String = _local_owner_user_id.strip_edges()
	return owner != ""


func request_login_gate(reason: String = "session_unrecoverable") -> void:
	_boot_gate_mode = BootGateMode.SHOW_GATE
	_session_auth_source = "gate_required"
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
	_auth_user_id = uid
	if _boot_gate_mode == BootGateMode.SHOW_GATE and auth_source != "gate_required":
		_boot_gate_mode = BootGateMode.AUTO_CONTINUE
	_refresh_account_kind_from_nakama()
	var ownership: Dictionary = _apply_local_ownership_rules(uid)
	var asp: Node = get_node_or_null("/root/AccountSavePaths")
	if asp != null and asp.has_method("open_for_authenticated_user"):
		var save_ctx: Dictionary = asp.call("open_for_authenticated_user", uid, ownership)
		ownership["save_context"] = save_ctx
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
	_set_auth_phase(AuthPhase.AUTHENTICATING)
	var login_res: Dictionary = await nc.call("authenticate_email_login", str(form.get("email", "")), password)
	password = ""
	if not bool(login_res.get("ok", false)):
		_set_auth_phase(AuthPhase.IDLE)
		_last_email_error = login_res
		email_auth_completed.emit(login_res)
		return login_res
	var new_uid: String = str(login_res.get("user_id", "")).strip_edges()
	if new_uid.is_empty():
		_set_auth_phase(AuthPhase.IDLE)
		var bad := {
			"ok": false,
			"error": AccountEmailAuthScript.ERR_AUTH_FAILED,
			"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_AUTH_FAILED),
		}
		_last_email_error = bad
		email_auth_completed.emit(bad)
		return bad
	# Bind identity + partition for B. Guest A partition files remain on disk untouched.
	var ownership: Dictionary = on_authenticated(new_uid, "email")
	_linked_providers["EMAIL"] = true
	_account_kind = AccountKind.SECURED
	_masked_email = AccountEmailAuthScript.mask_email(str(form.get("email", "")))
	_known_secured = true
	# Active ownership follows logged-in account; previous guest partition is preserved separately.
	_local_owner_user_id = new_uid
	_mismatch_active = false
	_save_ownership_record(new_uid, false)
	await _probe_account_now()
	# Cloud sync / restore for the logged-in account (empty Device B → restore).
	var cloud_res: Dictionary = {}
	var cloud: Node = get_node_or_null("/root/AccountCloudSave")
	if cloud != null and cloud.has_method("sync_after_auth"):
		cloud_res = await cloud.call("sync_after_auth")
	_set_auth_phase(AuthPhase.IDLE)
	# Auth succeeded — keep gate dismissible. Conflict is a post-auth resolution step, not login failure.
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
	}
	if cloud != null and cloud.has_method("has_blocked_conflict") and bool(cloud.call("has_blocked_conflict")):
		ok_res["conflict"] = true
		ok_res["needs_resolution"] = true
		ok_res["error"] = AccountEmailAuthScript.ERR_CLOUD_CONFLICT
		ok_res["message"] = AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_CLOUD_CONFLICT)
		# Keep SHOW_GATE semantics for UI until conflict is resolved (no silent guest).
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
	account_state_changed.emit()
	email_auth_completed.emit(ok_res)
	print(
		"[AccountIdentity] Email login user=%s switched_from=%s conflict=%s"
		% [_short_id(new_uid), _short_id(previous_uid), str(ok_res.get("conflict", false))]
	)
	return ok_res


func warn_before_login_switch() -> Dictionary:
	## UI helper: guest with progress may become unrecoverable if device data is lost.
	## Never show guest-warning copy on a forced secured-account reauth gate.
	if _known_secured or _boot_gate_mode == BootGateMode.SHOW_GATE or should_block_guest_device_fallback():
		return {"warn": false}
	if not is_guest():
		return {"warn": false}
	var asp: Node = get_node_or_null("/root/AccountSavePaths")
	var has_progress: bool = false
	if asp != null and bool(asp.call("is_bound")):
		has_progress = bool(asp.call("has_account_gameplay_progress", str(asp.call("get_active_user_id"))))
	if not has_progress:
		has_progress = has_legacy_local_progression()
	if not has_progress:
		return {"warn": false}
	return {
		"warn": true,
		"message": "This Guest Account is not secured. Logging into another account will leave guest progress on this device only — it may be unrecoverable if this device is lost. Secure Account first to protect it.",
	}


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
		if _linked_providers.has("EMAIL"):
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
	# Never load passwords — none should exist.
	if cfg.has_section_key(OWNER_SECTION, "password") or cfg.has_section_key(OWNER_SECTION, "email_password"):
		push_warning("[AccountIdentity] Removing unexpected password key from ownership file")
		cfg.erase_section_key(OWNER_SECTION, "password")
		cfg.erase_section_key(OWNER_SECTION, "email_password")
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
	# Explicitly ensure password keys are never written.
	if cfg.has_section_key(OWNER_SECTION, "password"):
		cfg.erase_section_key(OWNER_SECTION, "password")
	if cfg.has_section_key(OWNER_SECTION, "email_password"):
		cfg.erase_section_key(OWNER_SECTION, "email_password")
	cfg.save(get_ownership_path())


func _short_id(user_id: String) -> String:
	var uid: String = user_id.strip_edges()
	if uid.length() <= 8:
		return uid
	return uid.substr(0, 8)
