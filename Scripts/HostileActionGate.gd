extends Node

## Authoritative hostile-action eligibility for player castles (attack / scout).
## UI may mirror these reasons, but MarchState dispatch must refuse independently.
## Realm Standing / outlaw / KvK sanctions are intentionally NOT evaluated here.

const ACTION_ATTACK: String = "attack"
const ACTION_SCOUT: String = "scout"

const REASON_SELF := "Cannot target your own city."
const REASON_ALLIANCE_ATTACK := "Cannot attack an alliance member."
const REASON_ALLIANCE_SCOUT := "Cannot scout an alliance member."
const REASON_SHIELD := "This city is protected by a Peace Shield."
const REASON_BEGINNER := "This city is under Beginner Protection."
const REASON_INVALID := "Target castle could not be resolved."
const REASON_STALE := "Target castle is no longer available."


## Evaluate whether the local player may perform a hostile action on target.
## target must identify user_id; alliance_id / protection fields when known.
func evaluate(action: String, target: Dictionary, attacker_override: Dictionary = {}) -> Dictionary:
	var act: String = action.strip_edges().to_lower()
	if act != ACTION_ATTACK and act != ACTION_SCOUT:
		return _deny("invalid_action", "Unsupported hostile action.")

	var target_uid: String = str(target.get("user_id", target.get("target_user_id", ""))).strip_edges()
	if target_uid == "":
		return _deny("invalid_target", REASON_INVALID)

	var attacker_uid: String = str(attacker_override.get("user_id", "")).strip_edges()
	if attacker_uid == "":
		attacker_uid = _local_user_id()
	if attacker_uid != "" and attacker_uid == target_uid:
		return _deny("self", REASON_SELF)

	if bool(target.get("unresolvable", false)) or bool(target.get("stale", false)):
		return _deny("stale_target", REASON_STALE)

	# Coordinates required for a live castle target (world map / registry).
	var has_coord: bool = target.has("world_x") or target.has("x") \
			or (typeof(target.get("position", null)) == TYPE_DICTIONARY)
	if not has_coord and not bool(target.get("skip_coord_check", false)):
		# Allow if explicit resolvable flag from server validation.
		if not bool(target.get("resolved", false)):
			return _deny("invalid_target", REASON_INVALID)

	var attacker_alliance: String = str(attacker_override.get("alliance_id", "")).strip_edges()
	if attacker_alliance == "":
		attacker_alliance = _local_alliance_id()
	var target_alliance: String = str(target.get("alliance_id", "")).strip_edges()
	if attacker_alliance != "" and target_alliance != "" and attacker_alliance == target_alliance:
		if act == ACTION_SCOUT:
			return _deny("same_alliance", REASON_ALLIANCE_SCOUT)
		return _deny("same_alliance", REASON_ALLIANCE_ATTACK)

	var flags: Dictionary = {}
	if has_node("/root/CityProtectionState"):
		flags = CityProtectionState.protection_flags_for_target(target)
	else:
		flags = {
			"peace_shield_active": bool(target.get("peace_shield_active", false)),
			"anti_scout_active": bool(target.get("anti_scout_active", false)),
			"beginner_protection_active": bool(target.get("beginner_protection_active", false)),
		}

	if bool(flags.get("peace_shield_active", false)):
		return _deny("peace_shield", REASON_SHIELD)
	if bool(flags.get("beginner_protection_active", false)):
		return _deny("beginner_protection", REASON_BEGINNER)

	# Anti-Scout blocks scout intelligence gathering (not attacks).
	if act == ACTION_SCOUT and bool(flags.get("anti_scout_active", false)):
		return _deny("anti_scout", "This city is protected by Anti-Scout.")

	return {
		"ok": true,
		"action": act,
		"target_user_id": target_uid,
		"code": "allowed",
		"reason": "",
	}


func can_attack(target: Dictionary, attacker_override: Dictionary = {}) -> Dictionary:
	return evaluate(ACTION_ATTACK, target, attacker_override)


func can_scout(target: Dictionary, attacker_override: Dictionary = {}) -> Dictionary:
	return evaluate(ACTION_SCOUT, target, attacker_override)


func _deny(code: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "reason": reason, "error": reason}


func _local_user_id() -> String:
	if has_node("/root/NakamaConnection"):
		return str(NakamaConnection.get_user_id()).strip_edges()
	return ""


func _local_alliance_id() -> String:
	if has_node("/root/AllianceBackend") and AllianceBackend.has_method("get_alliance_id"):
		var backend_id: String = str(AllianceBackend.get_alliance_id()).strip_edges()
		if backend_id != "":
			return backend_id
	if has_node("/root/AllianceState"):
		var aid: Variant = AllianceState.get("alliance_id")
		return str(aid).strip_edges() if aid != null else ""
	return ""
