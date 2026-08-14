extends Node

## Authoritative city protection for Peace Shield / Anti-Scout / Beginner Protection.
## Local player state is persisted. Remote player state is cached from public profiles
## / hostile-action validation responses — never invent remote garrison data.

signal protection_changed

const SAVE_PATH: String = "user://city_protection.cfg"
const SMOKE_SAVE_PATH: String = "user://city_protection_smoke_test.cfg"
const SAVE_VERSION: int = 1

## Design-backed from data/Items.json ("Peace Shield (3 Days)").
const PEACE_SHIELD_ITEM_ID: String = "boost_shield_peace_3d"
const PEACE_SHIELD_DURATION_SEC: int = 3 * 24 * 60 * 60

## Design-backed from data/Items.json ("Anti-Scout (24 Hours)").
const ANTI_SCOUT_ITEM_ID: String = "boost_anti_scout_24h"
const ANTI_SCOUT_DURATION_SEC: int = 24 * 60 * 60

## Beginner protection duration/exit is NOT product-locked yet.
## Support exists; auto-grant stays off until design supplies values.
##
## CONFIGURE PRODUCT RULE HERE (do not invent a silent duration):
##   Client local: CityProtectionState.set_beginner_protection_expires_at (LOCAL ONLY)
##   Public RPC: crownspire_clear_own_beginner_protection (clear own only)
##   Trusted server helper: trustedSetBeginnerProtection (NOT a public RPC)
##   Profile fields: beginner_protection_expires_at, beginner_protection_cleared
## BEGINNER_PROTECTION_DURATION_SEC stays 0 until product locks a value.
##
## Peace Shield / Anti-Scout:
##   Items boost_shield_peace_3d / boost_anti_scout_24h live in client BagState only.
##   Server inventory authority does NOT exist for these yet — no public activate RPC.
const BEGINNER_PROTECTION_DURATION_SEC: int = 0
const BEGINNER_PROTECTION_PRODUCT_LOCKED: bool = false

var peace_shield_expires_at: int = 0
var anti_scout_expires_at: int = 0
var beginner_protection_expires_at: int = 0
## Optional product exit flag — when true, beginner protection is cleared.
var beginner_protection_cleared: bool = false

## Remote snapshots keyed by user_id (from public profile / validate RPC).
var _remote_cache: Dictionary = {}
var _save_path_override: String = ""


func _ready() -> void:
	load_protection()


func get_save_path() -> String:
	if _save_path_override != "":
		return _save_path_override
	if has_node("/root/AccountSavePaths"):
		return AccountSavePaths.path_for("city_protection.cfg")
	return SAVE_PATH


func begin_smoke_isolation() -> void:
	_save_path_override = SMOKE_SAVE_PATH
	peace_shield_expires_at = 0
	anti_scout_expires_at = 0
	beginner_protection_expires_at = 0
	beginner_protection_cleared = false
	_remote_cache.clear()
	if FileAccess.file_exists(SMOKE_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SMOKE_SAVE_PATH))


func end_smoke_isolation() -> void:
	_save_path_override = ""
	load_protection()


func now_unix() -> int:
	return int(Time.get_unix_time_from_system())


func is_peace_shield_active(at_unix: int = -1) -> bool:
	var t: int = at_unix if at_unix >= 0 else now_unix()
	return peace_shield_expires_at > t


func is_anti_scout_active(at_unix: int = -1) -> bool:
	var t: int = at_unix if at_unix >= 0 else now_unix()
	return anti_scout_expires_at > t


func is_beginner_protection_active(at_unix: int = -1) -> bool:
	if beginner_protection_cleared:
		return false
	var t: int = at_unix if at_unix >= 0 else now_unix()
	return beginner_protection_expires_at > t


func local_snapshot(at_unix: int = -1) -> Dictionary:
	var t: int = at_unix if at_unix >= 0 else now_unix()
	return {
		"peace_shield_expires_at": peace_shield_expires_at,
		"anti_scout_expires_at": anti_scout_expires_at,
		"beginner_protection_expires_at": beginner_protection_expires_at,
		"beginner_protection_cleared": beginner_protection_cleared,
		"peace_shield_active": is_peace_shield_active(t),
		"anti_scout_active": is_anti_scout_active(t),
		"beginner_protection_active": is_beginner_protection_active(t),
	}


## Activate Peace Shield from bag use. Duration from Items.json design (3 days).
func activate_peace_shield_from_item() -> Dictionary:
	var now: int = now_unix()
	var base: int = maxi(now, peace_shield_expires_at)
	peace_shield_expires_at = base + PEACE_SHIELD_DURATION_SEC
	save_protection()
	protection_changed.emit()
	return {"ok": true, "expires_at": peace_shield_expires_at, "duration_sec": PEACE_SHIELD_DURATION_SEC}


func activate_anti_scout_from_item() -> Dictionary:
	var now: int = now_unix()
	var base: int = maxi(now, anti_scout_expires_at)
	anti_scout_expires_at = base + ANTI_SCOUT_DURATION_SEC
	save_protection()
	protection_changed.emit()
	return {"ok": true, "expires_at": anti_scout_expires_at, "duration_sec": ANTI_SCOUT_DURATION_SEC}


## Test / future product hook — do not call from live UX until duration is locked.
func set_beginner_protection_expires_at(expires_at: int) -> void:
	beginner_protection_expires_at = maxi(0, expires_at)
	if expires_at <= now_unix():
		beginner_protection_cleared = true
	else:
		beginner_protection_cleared = false
	save_protection()
	protection_changed.emit()


func clear_beginner_protection() -> void:
	beginner_protection_expires_at = 0
	beginner_protection_cleared = true
	save_protection()
	protection_changed.emit()


func cache_remote_protection(user_id: String, payload: Dictionary) -> void:
	var uid: String = user_id.strip_edges()
	if uid == "":
		return
	_remote_cache[uid] = {
		"peace_shield_expires_at": int(payload.get("peace_shield_expires_at", 0)),
		"anti_scout_expires_at": int(payload.get("anti_scout_expires_at", 0)),
		"beginner_protection_expires_at": int(payload.get("beginner_protection_expires_at", 0)),
		"alliance_id": str(payload.get("alliance_id", "")),
		"updated_at": now_unix(),
	}


func get_remote_snapshot(user_id: String) -> Dictionary:
	var uid: String = user_id.strip_edges()
	if uid == "":
		return {}
	var raw: Variant = _remote_cache.get(uid, {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return (raw as Dictionary).duplicate(true)


func protection_flags_for_target(target: Dictionary, at_unix: int = -1) -> Dictionary:
	var t: int = at_unix if at_unix >= 0 else now_unix()
	var uid: String = str(target.get("user_id", target.get("target_user_id", ""))).strip_edges()
	var local_id: String = _local_user_id()
	var peace_exp: int = int(target.get("peace_shield_expires_at", 0))
	var anti_exp: int = int(target.get("anti_scout_expires_at", 0))
	var beg_exp: int = int(target.get("beginner_protection_expires_at", 0))
	var beg_cleared: bool = bool(target.get("beginner_protection_cleared", false))

	if uid != "" and uid == local_id:
		var local: Dictionary = local_snapshot(t)
		return {
			"peace_shield_active": bool(local.get("peace_shield_active", false)),
			"anti_scout_active": bool(local.get("anti_scout_active", false)),
			"beginner_protection_active": bool(local.get("beginner_protection_active", false)),
		}

	if peace_exp <= 0 and anti_exp <= 0 and beg_exp <= 0 and uid != "":
		var cached: Dictionary = get_remote_snapshot(uid)
		peace_exp = int(cached.get("peace_shield_expires_at", 0))
		anti_exp = int(cached.get("anti_scout_expires_at", 0))
		beg_exp = int(cached.get("beginner_protection_expires_at", 0))

	# Explicit boolean overrides from validate RPC / tests.
	if target.has("peace_shield_active"):
		return {
			"peace_shield_active": bool(target.get("peace_shield_active", false)),
			"anti_scout_active": bool(target.get("anti_scout_active", false)),
			"beginner_protection_active": bool(target.get("beginner_protection_active", false)),
		}

	return {
		"peace_shield_active": peace_exp > t,
		"anti_scout_active": anti_exp > t,
		"beginner_protection_active": (not beg_cleared) and beg_exp > t,
	}


func _local_user_id() -> String:
	if has_node("/root/NakamaConnection"):
		return str(NakamaConnection.get_user_id()).strip_edges()
	return ""


func save_protection() -> void:
	var save := ConfigFile.new()
	save.set_value("meta", "save_version", SAVE_VERSION)
	save.set_value("protection", "peace_shield_expires_at", peace_shield_expires_at)
	save.set_value("protection", "anti_scout_expires_at", anti_scout_expires_at)
	save.set_value("protection", "beginner_protection_expires_at", beginner_protection_expires_at)
	save.set_value("protection", "beginner_protection_cleared", beginner_protection_cleared)
	save.save(get_save_path())
	if has_node("/root/AccountCloudSave"):
		AccountCloudSave.mark_dirty("city_protection")


func load_protection() -> void:
	var save := ConfigFile.new()
	if save.load(get_save_path()) != OK:
		peace_shield_expires_at = 0
		anti_scout_expires_at = 0
		beginner_protection_expires_at = 0
		beginner_protection_cleared = false
		return
	peace_shield_expires_at = int(save.get_value("protection", "peace_shield_expires_at", 0))
	anti_scout_expires_at = int(save.get_value("protection", "anti_scout_expires_at", 0))
	beginner_protection_expires_at = int(save.get_value("protection", "beginner_protection_expires_at", 0))
	beginner_protection_cleared = bool(save.get_value("protection", "beginner_protection_cleared", false))
