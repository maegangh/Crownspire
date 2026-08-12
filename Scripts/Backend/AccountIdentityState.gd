extends Node

## Crownspire Phase 1 account identity + local save ownership.
## Does not migrate city progression. Does not implement provider linking UI.

signal account_state_changed
signal local_save_ownership_changed
signal local_save_mismatch(auth_user_id: String, owner_user_id: String)

const OWNERSHIP_PATH := "user://account_local_ownership.cfg"
const SMOKE_OWNERSHIP_PATH := "user://account_local_ownership_smoke_test.cfg"
const OWNER_SECTION := "ownership"
const MISMATCH_CODE := "LOCAL_SAVE_ACCOUNT_MISMATCH"

enum AccountKind { GUEST, SECURED }

## Future login-gate architecture only — Phase 1 never forces this for existing installs.
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
var _linked_providers: Dictionary = {} ## EMAIL/GOOGLE/APPLE/FACEBOOK -> true (Phase 1 optional fill)
var _local_owner_user_id: String = ""
var _mismatch_active: bool = false
var _boot_gate_mode: int = BootGateMode.AUTO_CONTINUE
var _session_auth_source: String = "" ## restore | refresh | device


func _ready() -> void:
	_load_ownership_record()
	call_deferred("_bind_nakama")


func begin_smoke_isolation() -> void:
	_ownership_path_override = SMOKE_OWNERSHIP_PATH
	_auth_user_id = ""
	_account_kind = AccountKind.GUEST
	_linked_providers = {}
	_local_owner_user_id = ""
	_mismatch_active = false
	_session_auth_source = ""
	_boot_gate_mode = BootGateMode.AUTO_CONTINUE
	if FileAccess.file_exists(get_ownership_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(get_ownership_path()))


func end_smoke_isolation() -> void:
	begin_smoke_isolation()
	_ownership_path_override = ""
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


func is_guest() -> bool:
	return _account_kind == AccountKind.GUEST


func is_secured() -> bool:
	return _account_kind == AccountKind.SECURED


func get_linked_providers() -> Dictionary:
	return _linked_providers.duplicate(true)


func has_local_save_mismatch() -> bool:
	return _mismatch_active


func get_mismatch_code() -> String:
	return MISMATCH_CODE if _mismatch_active else ""


func get_session_auth_source() -> String:
	return _session_auth_source


func get_boot_gate_mode() -> String:
	## Phase 1: always AUTO_CONTINUE for existing installs.
	return "SHOW_GATE" if _boot_gate_mode == BootGateMode.SHOW_GATE else "AUTO_CONTINUE"


## Future first-launch gate API — unused by Phase 1 boot.
func set_boot_gate_mode_for_future(mode: String) -> void:
	if mode.strip_edges().to_upper() == "SHOW_GATE":
		_boot_gate_mode = BootGateMode.SHOW_GATE
	else:
		_boot_gate_mode = BootGateMode.AUTO_CONTINUE


func should_force_login_gate() -> bool:
	## Existing installs must continue automatically in Phase 1.
	return false


func is_local_progression_safe_to_use() -> bool:
	## Phase 2: own partition is safe. Legacy flat handoff remains flagged via has_local_save_mismatch().
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
	## Called by NakamaConnection after a successful session is established.
	var uid: String = user_id.strip_edges()
	_session_auth_source = auth_source.strip_edges()
	if uid.is_empty():
		return {"ok": false, "error": "empty_user_id"}
	_auth_user_id = uid
	_refresh_account_kind_from_nakama()
	var ownership: Dictionary = _apply_local_ownership_rules(uid)
	var asp: Node = get_node_or_null("/root/AccountSavePaths")
	if asp != null and asp.has_method("open_for_authenticated_user"):
		var save_ctx: Dictionary = asp.call("open_for_authenticated_user", uid, ownership)
		ownership["save_context"] = save_ctx
	account_state_changed.emit()
	return ownership


func claim_local_saves_for_user(user_id: String) -> Dictionary:
	## Explicit claim helper (also used by smokes). Does not move files.
	var uid: String = user_id.strip_edges()
	if uid.is_empty():
		return {"ok": false, "error": "empty_user_id"}
	_local_owner_user_id = uid
	_mismatch_active = false
	_save_ownership_record(uid, true)
	local_save_ownership_changed.emit()
	return {"ok": true, "claimed": true, "owner_user_id": uid}


func _bind_nakama() -> void:
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null:
		return
	if nc.has_signal("authenticated") and not nc.authenticated.is_connected(_on_nakama_authenticated):
		nc.authenticated.connect(_on_nakama_authenticated)
	# If already authenticated before this autoload finished binding.
	if nc.has_method("is_authenticated") and bool(nc.call("is_authenticated")):
		_on_nakama_authenticated()


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
		# One-time legacy claim: existing local progression (or empty install) belongs to this user.
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

	# Authenticated identity does not own this device's local progression.
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
	## Authoritative linked-provider probe when possible. Otherwise remains GUEST.
	_linked_providers = {}
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
	# Fire-and-forget async refresh so auth path stays non-blocking for gameplay.
	_probe_account_async(client, session)


func _probe_account_async(client: NakamaClient, session: NakamaSession) -> void:
	var account = await client.get_account_async(session)
	if account == null or account.is_exception():
		return
	var linked: Dictionary = {}
	var email: String = str(account.email).strip_edges()
	if email != "":
		linked["EMAIL"] = true
	var user = account.user
	if user != null:
		if str(user.google_id).strip_edges() != "":
			linked["GOOGLE"] = true
		if str(user.apple_id).strip_edges() != "":
			linked["APPLE"] = true
		if str(user.facebook_id).strip_edges() != "":
			linked["FACEBOOK"] = true
	_linked_providers = linked
	# Do not treat device-only (or local session token) as SECURED.
	_account_kind = AccountKind.SECURED if not linked.is_empty() else AccountKind.GUEST
	account_state_changed.emit()


func _load_ownership_record() -> void:
	_local_owner_user_id = ""
	var cfg := ConfigFile.new()
	if cfg.load(get_ownership_path()) != OK:
		return
	_local_owner_user_id = str(cfg.get_value(OWNER_SECTION, "user_id", "")).strip_edges()


func _save_ownership_record(user_id: String, legacy_claimed: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(get_ownership_path())
	cfg.set_value(OWNER_SECTION, "user_id", user_id)
	cfg.set_value(OWNER_SECTION, "claimed_at", int(Time.get_unix_time_from_system()))
	cfg.set_value(OWNER_SECTION, "legacy_claimed", legacy_claimed)
	cfg.set_value(OWNER_SECTION, "version", 1)
	cfg.save(get_ownership_path())


func _short_id(user_id: String) -> String:
	var uid: String = user_id.strip_edges()
	if uid.length() <= 8:
		return uid
	return uid.substr(0, 8)
