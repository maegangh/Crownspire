extends Node

## Alliance runtime state (Sprint 1A + 1B).
## Membership, roster, applications, and role permissions.
## Static role defs come from DataManager.get_alliance_data().

signal alliance_changed

const SAVE_PATH: String = "user://alliance.cfg"
const SMOKE_SAVE_PATH: String = "user://alliance_smoke_test.cfg"
const LOCAL_PLAYER_ID: String = "local_player"
const LOCAL_PLAYER_NAME: String = "Player"

const ROLE_MEMBER: String = "R1"
const ROLE_LEADER: String = "R5"
const MAX_TAG_LENGTH: int = 4
const MIN_TAG_LENGTH: int = 3
const MIN_NAME_LENGTH: int = 3
const MAX_NAME_LENGTH: int = 24

const STATUS_PENDING: String = "pending"
const STATUS_ACCEPTED: String = "accepted"
const STATUS_REJECTED: String = "rejected"

## Display names when alliance.json has no per-role name field.
const ROLE_DISPLAY_NAMES: Dictionary = {
	"R1": "Recruit",
	"R2": "Member",
	"R3": "Veteran",
	"R4": "Officer",
	"R5": "Leader",
}

## Sprint 1C — configurable donation presets and contribution rate.
const DONATION_AMOUNTS: Array[int] = [1000, 10000, 50000]
const DONATION_RESOURCES: Array[String] = ["food", "wood", "stone", "iron"]
const CONTRIBUTION_POINTS_PER_1000: int = 1

## Alliance Research attempts (regenerating contribution charges).
const MAX_RESEARCH_ATTEMPTS: int = 25
const ATTEMPT_REGEN_SECONDS: int = 1800
const RESEARCH_DIAMOND_BYPASS_COST: int = 100
const DEFAULT_CONTRIBUTION_RESOURCE: String = "food"
const DEFAULT_CONTRIBUTION_AMOUNT: int = 10000
const DEFAULT_RESEARCH_POINTS: int = 100
const DEFAULT_CONTRIBUTION_REWARDS: Dictionary = {
	"personal_contribution": 120,
	"alliance_coins": 120,
}
const RESEARCH_CONTRIBUTION_RESOURCES: Array[String] = ["food", "wood", "stone", "iron"]

const HELP_TYPE_CONSTRUCTION: String = "construction"
const HELP_TYPE_RESEARCH: String = "research"
const HELP_TYPE_TRAINING: String = "training"
const HELP_TYPE_HEALING: String = "healing"

## Current player membership (empty alliance_id means not in an alliance).
var alliance_id: String = ""
var alliance_name: String = ""
var alliance_tag: String = ""
var role: String = ""
var joined_unix: int = 0

## Offline-local registry of alliances created/joinable on this device.
var local_alliances: Array[Dictionary] = []

## When set, save/load use an isolated path so smoke tests never touch player data.
var _save_path_override: String = ""
var _alliance_log_enabled: bool = true

## Local player Alliance Research attempts (persisted in alliance.cfg).
var current_attempts: int = MAX_RESEARCH_ATTEMPTS
var max_attempts: int = MAX_RESEARCH_ATTEMPTS
var last_attempt_timestamp: int = 0


func get_save_path() -> String:
	if _save_path_override != "":
		return _save_path_override
	if has_node("/root/AccountSavePaths"):
		return AccountSavePaths.path_for("alliance.cfg")
	return SAVE_PATH


func _log_alliance(message: String) -> void:
	if _alliance_log_enabled:
		print("[AllianceState] %s" % message)


func _ready() -> void:
	var save_path: String = get_save_path()
	var had_save_file: bool = FileAccess.file_exists(save_path)
	_log_alliance("Boot load from %s (exists=%s)" % [save_path, str(had_save_file)])

	load_alliance()

	# Never seed demos over a real save, and never wipe loaded membership.
	if not had_save_file and local_alliances.is_empty() and not is_in_alliance():
		_seed_demo_alliances()
		var seed_err: Error = save_alliance()
		_log_alliance("First-launch demo seed save result=%s" % error_string(seed_err))
	else:
		_normalize_all_alliances()
		_repair_membership_consistency()
		var migrate_err: Error = save_alliance()
		_log_alliance(
			"Post-load normalize/repair save result=%s | id=%s role=%s alliances=%d"
			% [error_string(migrate_err), alliance_id, role, local_alliances.size()]
		)


func is_in_alliance() -> bool:
	return alliance_id != ""


func get_role_display_name(role_id: String) -> String:
	var data: Dictionary = DataManager.get_alliance_data()
	var roles: Dictionary = data.get("allianceRoles", {})
	var role_data: Variant = roles.get(role_id, {})
	if typeof(role_data) == TYPE_DICTIONARY:
		var named: String = str(role_data.get("name", role_data.get("displayName", "")))
		if named != "":
			return named
	return str(ROLE_DISPLAY_NAMES.get(role_id, role_id))


func get_role_rank(role_id: String) -> int:
	match role_id:
		"R1":
			return 1
		"R2":
			return 2
		"R3":
			return 3
		"R4":
			return 4
		"R5":
			return 5
		_:
			return 0


func get_role_permissions() -> Array:
	return _get_role_permission_list(role)


## Centralized permission check for the current player's role.
## Maps Sprint 1B permission names onto alliance.json rights when present.
func has_permission(permission_name: String) -> bool:
	if not is_in_alliance() or role == "":
		return false

	var role_data: Dictionary = _get_role_data(role)
	var perms: Array = role_data.get("permissions", [])

	if permission_name in perms:
		return true

	match permission_name:
		"view_members":
			return true
		"invite_members":
			return bool(role_data.get("inviteRights", false)) or ("dispatch_invitations" in perms)
		"review_applications":
			return get_role_rank(role) >= 4 or bool(role_data.get("kickRights", false))
		"promote_members", "demote_members":
			return get_role_rank(role) >= 4 or ("configure_roles_permissions" in perms)
		"remove_members":
			return bool(role_data.get("kickRights", false)) or ("kick_lower_ranks" in perms)
		"edit_announcement":
			return get_role_rank(role) >= 4 or ("schedule_events" in perms)
		"transfer_leadership":
			return role == ROLE_LEADER or ("delegate_lord_paramount" in perms)
		"select_research":
			return get_role_rank(role) >= 4 or bool(role_data.get("researchRights", false))
		_:
			return false


func can_create_alliance(name_text: String, tag_text: String) -> Dictionary:
	if is_in_alliance():
		return {"ok": false, "error": "Already in an alliance."}

	var clean_name: String = name_text.strip_edges()
	var clean_tag: String = tag_text.strip_edges().to_upper()

	if clean_name.length() < MIN_NAME_LENGTH or clean_name.length() > MAX_NAME_LENGTH:
		return {"ok": false, "error": "Name must be %d–%d characters." % [MIN_NAME_LENGTH, MAX_NAME_LENGTH]}

	if clean_tag.length() < MIN_TAG_LENGTH or clean_tag.length() > MAX_TAG_LENGTH:
		return {"ok": false, "error": "Tag must be %d–%d characters." % [MIN_TAG_LENGTH, MAX_TAG_LENGTH]}

	if not _is_alnum_tag(clean_tag):
		return {"ok": false, "error": "Tag must be letters/numbers only."}

	if _find_alliance_by_tag(clean_tag) != -1:
		return {"ok": false, "error": "That tag is already taken."}

	return {"ok": true, "name": clean_name, "tag": clean_tag}


func create_alliance(name_text: String, tag_text: String) -> Dictionary:
	var check: Dictionary = can_create_alliance(name_text, tag_text)
	if not check.get("ok", false):
		return check

	var now: int = int(Time.get_unix_time_from_system())
	var new_id: String = "all_%d_%d" % [now, randi() % 100000]
	var player_member: Dictionary = _make_member(
		LOCAL_PLAYER_ID,
		LOCAL_PLAYER_NAME,
		ROLE_LEADER,
		int(GameState.power) if has_node("/root/GameState") else 1614990,
		"online",
		now
	)

	var members: Array = [
		player_member,
		_make_member("seed_knight_1", "Sir Rowan", "R3", 420000, "online", now - 86400),
		_make_member("seed_ranger_1", "Archer Nyx", "R2", 280000, "offline", now - 172800),
		_make_member("seed_squire_1", "Squire Tobin", ROLE_MEMBER, 95000, "online", now - 3600),
	]

	var entry: Dictionary = {
		"id": new_id,
		"name": str(check["name"]),
		"tag": str(check["tag"]),
		"leader_id": LOCAL_PLAYER_ID,
		"member_count": members.size(),
		"members": members,
		"applications": _make_seed_applications(now),
		"announcement": "Welcome, lords. Raise the banner and grow our ranks.",
		"treasury": _empty_treasury(),
		"alliance_coins": 0,
		"help_requests": _make_seed_help_requests(now),
		"research": _empty_research_state(),
		"created_unix": now,
	}

	local_alliances.append(entry)
	_set_membership(new_id, str(check["name"]), str(check["tag"]), ROLE_LEADER)
	var save_err: Error = save_alliance()
	if save_err != OK:
		_log_alliance("create_alliance save FAILED: %s" % error_string(save_err))
		return {"ok": false, "error": "Alliance created in memory but failed to save."}
	_log_alliance("Created alliance id=%s tag=%s role=%s saved_ok" % [alliance_id, alliance_tag, role])
	alliance_changed.emit()
	return {"ok": true}


func get_joinable_alliances() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in local_alliances:
		var entry_id: String = str(entry.get("id", ""))
		if entry_id == "" or entry_id == alliance_id:
			continue
		result.append(entry)
	return result


func join_alliance(target_id: String) -> Dictionary:
	if is_in_alliance():
		return {"ok": false, "error": "Already in an alliance. Leave first."}

	var index: int = _find_alliance_by_id(target_id)
	if index == -1:
		return {"ok": false, "error": "Alliance not found."}

	var entry: Dictionary = local_alliances[index]
	_normalize_alliance_entry(entry)

	var members: Array = entry.get("members", [])
	for member: Variant in members:
		if typeof(member) == TYPE_DICTIONARY and _member_id(member) == LOCAL_PLAYER_ID:
			return {"ok": false, "error": "Already listed in that alliance."}

	var now: int = int(Time.get_unix_time_from_system())
	members.append(_make_member(
		LOCAL_PLAYER_ID,
		LOCAL_PLAYER_NAME,
		ROLE_MEMBER,
		int(GameState.power) if has_node("/root/GameState") else 1614990,
		"online",
		now
	))
	entry["members"] = members
	entry["member_count"] = members.size()
	local_alliances[index] = entry

	_set_membership(
		str(entry.get("id", "")),
		str(entry.get("name", "")),
		str(entry.get("tag", "")),
		ROLE_MEMBER
	)
	var save_err: Error = save_alliance()
	if save_err != OK:
		_log_alliance("join_alliance save FAILED: %s" % error_string(save_err))
		return {"ok": false, "error": "Joined in memory but failed to save."}
	_log_alliance("Joined alliance id=%s role=%s saved_ok" % [alliance_id, role])
	alliance_changed.emit()
	return {"ok": true}


func leave_alliance() -> Dictionary:
	if not is_in_alliance():
		return {"ok": false, "error": "Not in an alliance."}

	var index: int = _find_alliance_by_id(alliance_id)
	if index != -1:
		var entry: Dictionary = local_alliances[index]
		_normalize_alliance_entry(entry)
		var members: Array = entry.get("members", [])
		var remaining: Array = []
		for member: Variant in members:
			if typeof(member) != TYPE_DICTIONARY:
				continue
			if _member_id(member) == LOCAL_PLAYER_ID:
				continue
			remaining.append(member)

		if remaining.is_empty():
			local_alliances.remove_at(index)
		else:
			entry["members"] = remaining
			entry["member_count"] = remaining.size()
			if str(entry.get("leader_id", "")) == LOCAL_PLAYER_ID:
				var promote: Dictionary = remaining[0]
				promote["role"] = ROLE_LEADER
				_sync_member_aliases(promote)
				remaining[0] = promote
				entry["leader_id"] = _member_id(promote)
				entry["members"] = remaining
			local_alliances[index] = entry

	_clear_membership("player left alliance")
	var save_err: Error = save_alliance()
	if save_err != OK:
		_log_alliance("leave_alliance save FAILED: %s" % error_string(save_err))
		return {"ok": false, "error": "Left in memory but failed to save."}
	_log_alliance("Left alliance; membership cleared and saved.")
	alliance_changed.emit()
	return {"ok": true}


func get_current_alliance() -> Dictionary:
	if not is_in_alliance():
		return {}
	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		return {
			"id": alliance_id,
			"name": alliance_name,
			"tag": alliance_tag,
			"role": role,
			"member_count": 1,
			"members": [],
			"applications": [],
			"announcement": "",
		}
	_normalize_alliance_entry(local_alliances[index])
	return local_alliances[index].duplicate(true)


func get_members() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current: Dictionary = get_current_alliance()
	for member: Variant in current.get("members", []):
		if typeof(member) == TYPE_DICTIONARY:
			result.append(member)
	return result


func get_member(member_id: String) -> Dictionary:
	for member: Dictionary in get_members():
		if _member_id(member) == member_id:
			return member
	return {}


func get_pending_applications() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not has_permission("review_applications"):
		return result
	var current: Dictionary = get_current_alliance()
	for app: Variant in current.get("applications", []):
		if typeof(app) != TYPE_DICTIONARY:
			continue
		if str(app.get("status", STATUS_PENDING)) == STATUS_PENDING:
			result.append(app)
	return result


func get_announcement() -> String:
	return str(get_current_alliance().get("announcement", ""))


func set_announcement(text: String) -> Dictionary:
	if not has_permission("edit_announcement"):
		return {"ok": false, "error": "No permission to edit announcement."}
	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		return {"ok": false, "error": "Alliance not found."}
	local_alliances[index]["announcement"] = text.strip_edges()
	save_alliance()
	alliance_changed.emit()
	return {"ok": true}


func promote_member(member_id: String) -> Dictionary:
	if not has_permission("promote_members"):
		return {"ok": false, "error": "No permission to promote."}
	if member_id == LOCAL_PLAYER_ID:
		return {"ok": false, "error": "Cannot promote yourself here."}

	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		return {"ok": false, "error": "Alliance not found."}

	var entry: Dictionary = local_alliances[index]
	var member_index: int = _find_member_index(entry, member_id)
	if member_index == -1:
		return {"ok": false, "error": "Member not found."}

	var target: Dictionary = entry["members"][member_index]
	var target_role: String = str(target.get("role", ROLE_MEMBER))
	var actor_rank: int = get_role_rank(role)
	var target_rank: int = get_role_rank(target_role)

	if target_rank >= actor_rank:
		return {"ok": false, "error": "Cannot promote equal or higher ranks."}
	if target_rank + 1 >= actor_rank:
		return {"ok": false, "error": "Cannot promote above your own rank."}
	if target_rank >= 5:
		return {"ok": false, "error": "Already maximum rank."}

	var new_role: String = "R%d" % (target_rank + 1)
	target["role"] = new_role
	_sync_member_aliases(target)
	entry["members"][member_index] = target
	local_alliances[index] = entry
	save_alliance()
	alliance_changed.emit()
	return {"ok": true, "role": new_role}


func demote_member(member_id: String) -> Dictionary:
	if not has_permission("demote_members"):
		return {"ok": false, "error": "No permission to demote."}
	if member_id == LOCAL_PLAYER_ID:
		return {"ok": false, "error": "Cannot demote yourself here."}

	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		return {"ok": false, "error": "Alliance not found."}

	var entry: Dictionary = local_alliances[index]
	var member_index: int = _find_member_index(entry, member_id)
	if member_index == -1:
		return {"ok": false, "error": "Member not found."}

	var target: Dictionary = entry["members"][member_index]
	var target_role: String = str(target.get("role", ROLE_MEMBER))
	var actor_rank: int = get_role_rank(role)
	var target_rank: int = get_role_rank(target_role)

	if target_rank >= actor_rank:
		return {"ok": false, "error": "Cannot demote equal or higher ranks."}
	if target_rank <= 1:
		return {"ok": false, "error": "Already minimum rank."}

	var new_role: String = "R%d" % (target_rank - 1)
	target["role"] = new_role
	_sync_member_aliases(target)
	entry["members"][member_index] = target
	local_alliances[index] = entry
	save_alliance()
	alliance_changed.emit()
	return {"ok": true, "role": new_role}


func remove_member(member_id: String) -> Dictionary:
	if not has_permission("remove_members"):
		return {"ok": false, "error": "No permission to remove members."}
	if member_id == LOCAL_PLAYER_ID:
		return {"ok": false, "error": "Use Leave Alliance to leave."}

	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		return {"ok": false, "error": "Alliance not found."}

	var entry: Dictionary = local_alliances[index]
	var member_index: int = _find_member_index(entry, member_id)
	if member_index == -1:
		return {"ok": false, "error": "Member not found."}

	var target: Dictionary = entry["members"][member_index]
	var target_role: String = str(target.get("role", ROLE_MEMBER))
	var actor_rank: int = get_role_rank(role)
	var target_rank: int = get_role_rank(target_role)

	if target_role == ROLE_LEADER or target_rank >= 5:
		return {"ok": false, "error": "Cannot remove the R5 leader."}
	if target_rank >= actor_rank:
		return {"ok": false, "error": "Cannot remove equal or higher ranks."}

	var members: Array = entry.get("members", [])
	members.remove_at(member_index)
	entry["members"] = members
	entry["member_count"] = members.size()
	local_alliances[index] = entry
	save_alliance()
	alliance_changed.emit()
	return {"ok": true}


func transfer_leadership(member_id: String) -> Dictionary:
	if not has_permission("transfer_leadership"):
		return {"ok": false, "error": "Only the leader can transfer leadership."}
	if member_id == LOCAL_PLAYER_ID:
		return {"ok": false, "error": "Already the leader."}

	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		return {"ok": false, "error": "Alliance not found."}

	var entry: Dictionary = local_alliances[index]
	var target_index: int = _find_member_index(entry, member_id)
	var self_index: int = _find_member_index(entry, LOCAL_PLAYER_ID)
	if target_index == -1 or self_index == -1:
		return {"ok": false, "error": "Member not found."}

	var target: Dictionary = entry["members"][target_index]
	var self_member: Dictionary = entry["members"][self_index]

	target["role"] = ROLE_LEADER
	_sync_member_aliases(target)
	self_member["role"] = "R4"
	_sync_member_aliases(self_member)

	entry["members"][target_index] = target
	entry["members"][self_index] = self_member
	entry["leader_id"] = member_id
	local_alliances[index] = entry

	role = "R4"
	save_alliance()
	alliance_changed.emit()
	return {"ok": true}


func accept_application(application_id: String) -> Dictionary:
	if not has_permission("review_applications"):
		return {"ok": false, "error": "No permission to review applications."}

	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		return {"ok": false, "error": "Alliance not found."}

	var entry: Dictionary = local_alliances[index]
	_normalize_alliance_entry(entry)
	var apps: Array = entry.get("applications", [])
	var app_index: int = _find_application_index(apps, application_id)
	if app_index == -1:
		return {"ok": false, "error": "Application not found."}

	var app: Dictionary = apps[app_index]
	if str(app.get("status", "")) != STATUS_PENDING:
		return {"ok": false, "error": "Application is not pending."}

	var now: int = int(Time.get_unix_time_from_system())
	var new_member_id: String = "app_%s" % application_id
	var members: Array = entry.get("members", [])
	members.append(_make_member(
		new_member_id,
		str(app.get("player_name", "Applicant")),
		ROLE_MEMBER,
		int(app.get("player_power", 0)),
		"offline",
		now
	))
	entry["members"] = members
	entry["member_count"] = members.size()

	app["status"] = STATUS_ACCEPTED
	apps[app_index] = app
	entry["applications"] = apps
	local_alliances[index] = entry
	save_alliance()
	alliance_changed.emit()
	return {"ok": true}


func reject_application(application_id: String) -> Dictionary:
	if not has_permission("review_applications"):
		return {"ok": false, "error": "No permission to review applications."}

	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		return {"ok": false, "error": "Alliance not found."}

	var entry: Dictionary = local_alliances[index]
	_normalize_alliance_entry(entry)
	var apps: Array = entry.get("applications", [])
	var app_index: int = _find_application_index(apps, application_id)
	if app_index == -1:
		return {"ok": false, "error": "Application not found."}

	var app: Dictionary = apps[app_index]
	if str(app.get("status", "")) != STATUS_PENDING:
		return {"ok": false, "error": "Application is not pending."}

	app["status"] = STATUS_REJECTED
	apps[app_index] = app
	entry["applications"] = apps
	local_alliances[index] = entry
	save_alliance()
	alliance_changed.emit()
	return {"ok": true}


# --- Sprint 1C: Donations, Help, Embassy ---

func get_donation_amounts() -> Array[int]:
	return DONATION_AMOUNTS.duplicate()


func get_player_contribution_points() -> int:
	var member: Dictionary = get_member(LOCAL_PLAYER_ID)
	return int(member.get("contribution_points", 0))


func get_treasury() -> Dictionary:
	var current: Dictionary = get_current_alliance()
	var treasury: Variant = current.get("treasury", _empty_treasury())
	if typeof(treasury) != TYPE_DICTIONARY:
		return _empty_treasury()
	return {
		"food": int(treasury.get("food", 0)),
		"wood": int(treasury.get("wood", 0)),
		"stone": int(treasury.get("stone", 0)),
		"iron": int(treasury.get("iron", 0)),
	}


func get_total_alliance_contribution_points() -> int:
	var total: int = 0
	for member: Dictionary in get_members():
		total += int(member.get("contribution_points", 0))
	return total


func donate_resources(resource_id: String, amount: int) -> Dictionary:
	if not is_in_alliance():
		return {"ok": false, "error": "Not in an alliance."}
	if resource_id not in DONATION_RESOURCES:
		return {"ok": false, "error": "Invalid resource."}
	if amount <= 0:
		return {"ok": false, "error": "Invalid amount."}
	if amount not in DONATION_AMOUNTS:
		return {"ok": false, "error": "Choose a configured donation amount."}

	if not has_node("/root/GameState"):
		return {"ok": false, "error": "GameState unavailable."}

	var available: int = int(GameState.get(resource_id))
	if available < amount:
		return {"ok": false, "error": "Not enough %s." % resource_id}

	var food_cost: int = amount if resource_id == "food" else 0
	var wood_cost: int = amount if resource_id == "wood" else 0
	var stone_cost: int = amount if resource_id == "stone" else 0
	var iron_cost: int = amount if resource_id == "iron" else 0
	GameState.spend_resources(food_cost, wood_cost, stone_cost, iron_cost)

	var points: int = max(1, int((amount * CONTRIBUTION_POINTS_PER_1000) / 1000))
	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		return {"ok": false, "error": "Alliance not found."}

	var entry: Dictionary = local_alliances[index]
	_normalize_alliance_entry(entry)

	var treasury: Dictionary = entry.get("treasury", _empty_treasury())
	treasury[resource_id] = int(treasury.get(resource_id, 0)) + amount
	entry["treasury"] = treasury

	var member_index: int = _find_member_index(entry, LOCAL_PLAYER_ID)
	if member_index != -1:
		var member: Dictionary = entry["members"][member_index]
		member["contribution_points"] = int(member.get("contribution_points", 0)) + points
		_sync_member_aliases(member)
		entry["members"][member_index] = member

	local_alliances[index] = entry
	save_alliance()
	alliance_changed.emit()
	return {"ok": true, "points": points, "treasury": get_treasury()}


# --- Alliance Research ---

## UI buckets map onto alliance_research.json categories.
const RESEARCH_UI_CATEGORIES: Array[Dictionary] = [
	{"ui": "Growth", "sources": ["Support", "Territory"]},
	{"ui": "Economy", "sources": ["Economy"]},
	{"ui": "Battle", "sources": ["Military"]},
]


func _empty_research_state() -> Dictionary:
	return {
		"active_research_id": "",
		"nodes": {},
	}


func get_research_ui_categories() -> Array[Dictionary]:
	return RESEARCH_UI_CATEGORIES.duplicate(true)


func get_research_contribution_resource(research_id: String) -> String:
	var def: Dictionary = DataManager.get_alliance_research_def(research_id)
	var resource_id: String = str(def.get("contribution_resource", "")).to_lower()
	if resource_id in RESEARCH_CONTRIBUTION_RESOURCES:
		return resource_id

	# Legacy multi-resource contribution_cost → pick the highest-cost resource.
	var legacy: Variant = def.get("contribution_cost", {})
	if typeof(legacy) == TYPE_DICTIONARY and not legacy.is_empty():
		var best_id: String = DEFAULT_CONTRIBUTION_RESOURCE
		var best_amount: int = -1
		for candidate: String in RESEARCH_CONTRIBUTION_RESOURCES:
			var amount: int = int(legacy.get(candidate, 0))
			if amount > best_amount:
				best_amount = amount
				best_id = candidate
		return best_id

	return DEFAULT_CONTRIBUTION_RESOURCE


func get_research_contribution_amount(research_id: String) -> int:
	var def: Dictionary = DataManager.get_alliance_research_def(research_id)
	if def.has("contribution_amount"):
		return max(1, int(def.get("contribution_amount", DEFAULT_CONTRIBUTION_AMOUNT)))

	# Legacy multi-resource contribution_cost → use the chosen resource's amount.
	var resource_id: String = get_research_contribution_resource(research_id)
	var legacy: Variant = def.get("contribution_cost", {})
	if typeof(legacy) == TYPE_DICTIONARY and legacy.has(resource_id):
		return max(1, int(legacy.get(resource_id, DEFAULT_CONTRIBUTION_AMOUNT)))

	return DEFAULT_CONTRIBUTION_AMOUNT


## Compatibility helper: {resource, amount} for UI/tests.
func get_research_contribution_cost(research_id: String) -> Dictionary:
	return {
		"resource": get_research_contribution_resource(research_id),
		"amount": get_research_contribution_amount(research_id),
	}


func get_research_points_per_contribution(research_id: String) -> int:
	var def: Dictionary = DataManager.get_alliance_research_def(research_id)
	return max(1, int(def.get("research_points", DEFAULT_RESEARCH_POINTS)))


func get_research_contribution_rewards(research_id: String) -> Dictionary:
	var def: Dictionary = DataManager.get_alliance_research_def(research_id)
	var raw: Variant = def.get("contribution_rewards", {})
	if typeof(raw) != TYPE_DICTIONARY or raw.is_empty():
		return DEFAULT_CONTRIBUTION_REWARDS.duplicate()
	return {
		"personal_contribution": max(0, int(raw.get("personal_contribution", DEFAULT_CONTRIBUTION_REWARDS["personal_contribution"]))),
		"alliance_coins": max(0, int(raw.get("alliance_coins", DEFAULT_CONTRIBUTION_REWARDS["alliance_coins"]))),
	}


func get_alliance_coins() -> int:
	var current: Dictionary = get_current_alliance()
	return int(current.get("alliance_coins", 0))


func get_research_diamond_bypass_cost() -> int:
	return RESEARCH_DIAMOND_BYPASS_COST


func get_research_attempt_state() -> Dictionary:
	refresh_research_attempts(false)
	var next_sec: int = get_research_attempt_recovery_seconds()
	return {
		"current_attempts": current_attempts,
		"max_attempts": max_attempts,
		"last_attempt_timestamp": last_attempt_timestamp,
		"next_recovery_seconds": next_sec,
		"is_full": current_attempts >= max_attempts,
		"diamond_bypass_cost": RESEARCH_DIAMOND_BYPASS_COST,
	}


func get_research_attempt_recovery_seconds() -> int:
	if current_attempts >= max_attempts:
		return 0
	var now: int = int(Time.get_unix_time_from_system())
	if last_attempt_timestamp <= 0:
		return ATTEMPT_REGEN_SECONDS
	var elapsed: int = max(0, now - last_attempt_timestamp)
	var remaining: int = ATTEMPT_REGEN_SECONDS - (elapsed % ATTEMPT_REGEN_SECONDS)
	if remaining == ATTEMPT_REGEN_SECONDS and elapsed > 0 and elapsed % ATTEMPT_REGEN_SECONDS == 0:
		return 0
	return remaining


## Apply offline regeneration from last_attempt_timestamp. Returns true if values changed.
func refresh_research_attempts(save_if_changed: bool = true) -> bool:
	if max_attempts <= 0:
		max_attempts = MAX_RESEARCH_ATTEMPTS
	var now: int = int(Time.get_unix_time_from_system())
	var changed: bool = false

	if last_attempt_timestamp <= 0:
		last_attempt_timestamp = now
		current_attempts = clampi(current_attempts if current_attempts >= 0 else max_attempts, 0, max_attempts)
		changed = true
	elif current_attempts >= max_attempts:
		if current_attempts != max_attempts:
			current_attempts = max_attempts
			changed = true
	else:
		var elapsed: int = max(0, now - last_attempt_timestamp)
		var gained: int = int(elapsed / float(ATTEMPT_REGEN_SECONDS))
		if gained > 0:
			current_attempts = mini(max_attempts, current_attempts + gained)
			last_attempt_timestamp += gained * ATTEMPT_REGEN_SECONDS
			if current_attempts >= max_attempts:
				current_attempts = max_attempts
				last_attempt_timestamp = now
			changed = true

	if changed and save_if_changed:
		save_alliance()
	return changed


func _consume_research_attempt() -> bool:
	refresh_research_attempts(false)
	if current_attempts <= 0:
		return false
	if current_attempts >= max_attempts:
		last_attempt_timestamp = int(Time.get_unix_time_from_system())
	current_attempts -= 1
	return true


func get_research_state() -> Dictionary:
	var current: Dictionary = get_current_alliance()
	var research: Variant = current.get("research", _empty_research_state())
	if typeof(research) != TYPE_DICTIONARY:
		return _empty_research_state()
	var nodes: Variant = research.get("nodes", {})
	if typeof(nodes) != TYPE_DICTIONARY:
		nodes = {}
	return {
		"active_research_id": str(research.get("active_research_id", "")),
		"nodes": nodes,
	}


func get_active_research_id() -> String:
	return str(get_research_state().get("active_research_id", ""))


## ACTIVE | COMPLETED | LOCKED | AVAILABLE — single source for Research UI.
func get_research_status(research_id: String) -> String:
	return get_research_node_status(research_id)


func get_research_node_status(research_id: String) -> String:
	if research_id == "" or DataManager.get_alliance_research_def(research_id).is_empty():
		return "LOCKED"
	if research_id == get_active_research_id():
		return "ACTIVE"

	var def: Dictionary = DataManager.get_alliance_research_def(research_id)
	var runtime: Dictionary = get_research_node_runtime(research_id)
	var level: int = int(runtime.get("level", 0))
	var max_level: int = int(def.get("maxLevel", 1))
	if level >= max_level:
		return "COMPLETED"

	if not are_research_prerequisites_met(research_id):
		return "LOCKED"
	if get_alliance_level() < get_research_required_alliance_level(research_id):
		return "LOCKED"

	return "AVAILABLE"


## Derived Alliance level from progressed research (static unlock gate companion).
## Fresh alliances start at 1; each distinct tech with level >= 1 raises level by 1.
func get_alliance_level() -> int:
	var progressed: int = 0
	for category_block: Variant in DataManager.get_alliance_research_data():
		if typeof(category_block) != TYPE_DICTIONARY:
			continue
		for research_def: Variant in category_block.get("researches", []):
			if typeof(research_def) != TYPE_DICTIONARY:
				continue
			var rid: String = str(research_def.get("id", ""))
			if rid != "" and int(get_research_node_runtime(rid).get("level", 0)) >= 1:
				progressed += 1
	return max(1, 1 + progressed)


func get_research_required_alliance_level(research_id: String) -> int:
	var def: Dictionary = DataManager.get_alliance_research_def(research_id)
	if def.is_empty():
		return 1
	if def.has("required_alliance_level"):
		return max(1, int(def.get("required_alliance_level", 1)))
	var costs: Dictionary = def.get("costs", {})
	return max(1, int(costs.get("requiredAllianceLevel", 1)))


func are_research_prerequisites_met(research_id: String) -> bool:
	var def: Dictionary = DataManager.get_alliance_research_def(research_id)
	if def.is_empty():
		return false
	for prereq: Variant in def.get("prerequisites", []):
		if typeof(prereq) != TYPE_DICTIONARY:
			continue
		var prereq_id: String = str(prereq.get("research_id", ""))
		var need: int = max(1, int(prereq.get("required_level", 1)))
		if prereq_id == "":
			continue
		if int(get_research_node_runtime(prereq_id).get("level", 0)) < need:
			return false
	return true


## Human-readable unmet requirements (empty when unlocked aside from active/completed).
func get_research_unmet_requirements(research_id: String) -> Array[String]:
	var reasons: Array[String] = []
	var def: Dictionary = DataManager.get_alliance_research_def(research_id)
	if def.is_empty():
		reasons.append("Unknown research.")
		return reasons

	var prereqs: Array = def.get("prerequisites", [])
	for prereq: Variant in prereqs:
		if typeof(prereq) != TYPE_DICTIONARY:
			continue
		var prereq_id: String = str(prereq.get("research_id", ""))
		var need: int = max(1, int(prereq.get("required_level", 1)))
		if prereq_id == "":
			continue
		var prereq_def: Dictionary = DataManager.get_alliance_research_def(prereq_id)
		var have: int = int(get_research_node_runtime(prereq_id).get("level", 0))
		if have < need:
			var prereq_name: String = str(prereq_def.get("name", prereq_id))
			reasons.append("Requires %s Lv. %d" % [prereq_name, need])

	var need_alliance: int = get_research_required_alliance_level(research_id)
	var have_alliance: int = get_alliance_level()
	if have_alliance < need_alliance:
		reasons.append("Requires Alliance Level %d" % need_alliance)

	return reasons


func can_select_research(research_id: String) -> bool:
	if not is_in_alliance():
		return false
	var status: String = get_research_status(research_id)
	# Already-active may remain selected; only AVAILABLE may become newly active.
	return status == "AVAILABLE" or status == "ACTIVE"


func get_research_select_block_reason(research_id: String) -> String:
	var def: Dictionary = DataManager.get_alliance_research_def(research_id)
	if def.is_empty():
		return "Unknown research."
	var runtime: Dictionary = get_research_node_runtime(research_id)
	if int(runtime.get("level", 0)) >= int(def.get("maxLevel", 1)):
		return "Already completed"
	var unmet: Array[String] = get_research_unmet_requirements(research_id)
	if not unmet.is_empty():
		return unmet[0]
	var status: String = get_research_status(research_id)
	if status == "LOCKED":
		return "Complete the previous tier first"
	if status == "COMPLETED":
		return "Already completed"
	return "Cannot select this research."


func get_research_node_runtime(research_id: String) -> Dictionary:
	var nodes: Dictionary = get_research_state().get("nodes", {})
	var node: Variant = nodes.get(research_id, {})
	if typeof(node) != TYPE_DICTIONARY:
		return {"level": 0, "progress": 0}
	return {
		"level": int(node.get("level", 0)),
		"progress": int(node.get("progress", 0)),
	}


func get_research_defs_for_ui_category(ui_category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var sources: Array = []
	for entry: Dictionary in RESEARCH_UI_CATEGORIES:
		if str(entry.get("ui", "")) == ui_category:
			sources = entry.get("sources", [])
			break

	var tree: Array = DataManager.get_alliance_research_data()
	for category_block: Variant in tree:
		if typeof(category_block) != TYPE_DICTIONARY:
			continue
		var cat_name: String = str(category_block.get("category", ""))
		if cat_name not in sources:
			continue
		for research_def: Variant in category_block.get("researches", []):
			if typeof(research_def) != TYPE_DICTIONARY:
				continue
			var rid: String = str(research_def.get("id", ""))
			var def: Dictionary = DataManager.get_alliance_research_def(rid)
			if def.is_empty():
				continue
			def["ui_category"] = ui_category
			result.append(def)

	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: int = int(a.get("tier", 1))
		var tb: int = int(b.get("tier", 1))
		if ta != tb:
			return ta < tb
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return result


## Returns {tier_int: Array[Dictionary]} for tree UI layout.
func get_research_tiers_for_ui_category(ui_category: String) -> Dictionary:
	var tiers: Dictionary = {}
	for def: Dictionary in get_research_defs_for_ui_category(ui_category):
		var tier: int = int(def.get("tier", 1))
		if not tiers.has(tier):
			tiers[tier] = []
		var bucket: Array = tiers[tier]
		bucket.append(def)
		tiers[tier] = bucket
	return tiers


func get_research_requirement(research_id: String, level: int = -1) -> int:
	var def: Dictionary = DataManager.get_alliance_research_def(research_id)
	if def.is_empty():
		return 0
	var runtime: Dictionary = get_research_node_runtime(research_id)
	var use_level: int = level if level >= 0 else int(runtime.get("level", 0))
	var costs: Dictionary = def.get("costs", {})
	var base: float = float(costs.get("alliancePointsBase", 1000))
	var growth: float = float(costs.get("alliancePointsGrowthFactor", 1.4))
	return max(100, int(round(base * pow(growth, float(use_level)))))


func get_research_effect_text(research_id: String, level: int) -> String:
	var def: Dictionary = DataManager.get_alliance_research_def(research_id)
	if def.is_empty():
		return "No effect data."
	var effects: Dictionary = def.get("effects", {})
	var per_level: float = float(effects.get("valuePerLevel", 0))
	var explanation: String = str(effects.get("explanation", ""))
	if level <= 0:
		return "Not researched yet. " + explanation
	var total: float = per_level * float(level)
	var stat: String = str(effects.get("statAffected", "bonus"))
	return "Level %d: %+0.1f on %s. %s" % [level, total, stat, explanation]


func set_active_research(research_id: String) -> Dictionary:
	if not is_in_alliance():
		return {"ok": false, "error": "Not in an alliance."}
	if not has_permission("select_research"):
		return {"ok": false, "error": "No permission to set active research."}

	var def: Dictionary = DataManager.get_alliance_research_def(research_id)
	if def.is_empty():
		return {"ok": false, "error": "Unknown research."}

	if not can_select_research(research_id):
		return {"ok": false, "error": get_research_select_block_reason(research_id)}

	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		return {"ok": false, "error": "Alliance not found."}

	var entry: Dictionary = local_alliances[index]
	_normalize_alliance_entry(entry)
	var research: Dictionary = entry.get("research", _empty_research_state())
	research["active_research_id"] = research_id
	entry["research"] = research
	local_alliances[index] = entry
	var save_err: Error = save_alliance()
	if save_err != OK:
		return {"ok": false, "error": "Failed to save active research."}
	alliance_changed.emit()
	return {"ok": true}


## Contribute only to the Alliance's single active research project.
## use_diamond_bypass: spend diamonds instead of a research attempt (resources still required).
func contribute_to_active_research(use_diamond_bypass: bool = false) -> Dictionary:
	var active_id: String = get_active_research_id()
	if active_id == "":
		return {"ok": false, "error": "No active Alliance Research. Leadership must select one."}
	return contribute_to_research(active_id, use_diamond_bypass)


func contribute_to_research(research_id: String, use_diamond_bypass: bool = false) -> Dictionary:
	if not is_in_alliance():
		return {"ok": false, "error": "Not in an alliance."}

	var active_id: String = get_active_research_id()
	if active_id == "":
		return {"ok": false, "error": "No active Alliance Research. Leadership must select one."}
	if research_id != active_id:
		return {"ok": false, "error": "Only the current Alliance Research may receive contributions."}

	var def: Dictionary = DataManager.get_alliance_research_def(research_id)
	if def.is_empty():
		return {"ok": false, "error": "Unknown research."}

	var max_level: int = int(def.get("maxLevel", 1))
	var runtime: Dictionary = get_research_node_runtime(research_id)
	var level: int = int(runtime.get("level", 0))
	var progress: int = int(runtime.get("progress", 0))
	if level >= max_level:
		return {"ok": false, "error": "Research already maxed."}

	if not has_node("/root/GameState"):
		return {"ok": false, "error": "GameState unavailable."}

	var cost: Dictionary = get_research_contribution_cost(research_id)
	var resource_id: String = str(cost.get("resource", DEFAULT_CONTRIBUTION_RESOURCE))
	var amount: int = int(cost.get("amount", DEFAULT_CONTRIBUTION_AMOUNT))
	if resource_id not in RESEARCH_CONTRIBUTION_RESOURCES:
		return {"ok": false, "error": "Invalid contribution resource."}
	if amount <= 0:
		return {"ok": false, "error": "Invalid contribution amount."}

	var available: int = int(GameState.get(resource_id))
	if available < amount:
		return {"ok": false, "error": "Not enough %s." % resource_id}

	refresh_research_attempts(false)
	var used_diamond: bool = false
	if use_diamond_bypass:
		if int(GameState.diamonds) < RESEARCH_DIAMOND_BYPASS_COST:
			return {"ok": false, "error": "Not enough diamonds."}
		used_diamond = true
	else:
		if current_attempts <= 0:
			return {"ok": false, "error": "No research attempts remaining."}

	# Deduct attempt or diamonds, then the single configured resource.
	if used_diamond:
		GameState.diamonds -= RESEARCH_DIAMOND_BYPASS_COST
	else:
		if not _consume_research_attempt():
			return {"ok": false, "error": "No research attempts remaining."}

	var food_cost: int = amount if resource_id == "food" else 0
	var wood_cost: int = amount if resource_id == "wood" else 0
	var stone_cost: int = amount if resource_id == "stone" else 0
	var iron_cost: int = amount if resource_id == "iron" else 0
	GameState.spend_resources(food_cost, wood_cost, stone_cost, iron_cost)

	var research_points: int = get_research_points_per_contribution(research_id)
	var rewards: Dictionary = get_research_contribution_rewards(research_id)
	var personal_gain: int = int(rewards.get("personal_contribution", 0))
	var coins_gain: int = int(rewards.get("alliance_coins", 0))
	progress += research_points

	var levels_gained: int = 0
	while level < max_level:
		var required: int = get_research_requirement(research_id, level)
		if progress < required:
			break
		progress -= required
		level += 1
		levels_gained += 1

	if level >= max_level:
		progress = 0

	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		return {"ok": false, "error": "Alliance not found."}

	var entry: Dictionary = local_alliances[index]
	_normalize_alliance_entry(entry)
	var research: Dictionary = entry.get("research", _empty_research_state())
	var nodes: Dictionary = research.get("nodes", {})
	nodes[research_id] = {"level": level, "progress": progress}
	research["nodes"] = nodes

	# One active project at a time: clear when a level completes so leadership picks next.
	if levels_gained > 0:
		research["active_research_id"] = ""
	else:
		research["active_research_id"] = research_id

	entry["research"] = research
	entry["alliance_coins"] = int(entry.get("alliance_coins", 0)) + coins_gain

	var member_index: int = _find_member_index(entry, LOCAL_PLAYER_ID)
	if member_index != -1:
		var member: Dictionary = entry["members"][member_index]
		member["contribution_points"] = int(member.get("contribution_points", 0)) + personal_gain
		_sync_member_aliases(member)
		entry["members"][member_index] = member

	local_alliances[index] = entry
	var save_err: Error = save_alliance()
	if save_err != OK:
		return {"ok": false, "error": "Contribution applied but save failed."}
	alliance_changed.emit()
	return {
		"ok": true,
		"resource": resource_id,
		"amount": amount,
		"research_points": research_points,
		"personal_contribution": personal_gain,
		"alliance_coins": coins_gain,
		"alliance_coins_total": int(entry.get("alliance_coins", 0)),
		"points": personal_gain,
		"level": level,
		"progress": progress,
		"required": get_research_requirement(research_id, level) if level < max_level else 0,
		"levels_gained": levels_gained,
		"maxed": level >= max_level,
		"needs_next_selection": levels_gained > 0,
		"used_diamond_bypass": used_diamond,
		"attempts_remaining": current_attempts,
	}


func get_embassy_help_capacity() -> int:
	# Phase 0B2-C: player-owned Embassy completed level from ConstructionState authority.
	var level: int = 1
	if has_node("/root/ConstructionState") and ConstructionState.has_method("get_canonical_building_level"):
		level = max(1, int(ConstructionState.get_canonical_building_level("embassy")))

	var level_data: Dictionary = DataManager.get_building_level_data("embassy", level)
	var effect: String = str(level_data.get("buildingEffect", ""))
	var parsed: int = _parse_embassy_help_capacity(effect)
	if parsed > 0:
		return parsed

	# Fallback matching buildings.json pattern: level 1 => 11, +1 per level.
	return 10 + level


func get_help_requests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current: Dictionary = get_current_alliance()
	for req: Variant in current.get("help_requests", []):
		if typeof(req) == TYPE_DICTIONARY:
			result.append(req)
	return result


func create_help_request(help_type: String, remaining_time: int = 3600) -> Dictionary:
	if not is_in_alliance():
		return {"ok": false, "error": "Not in an alliance."}

	var normalized_type: String = help_type.to_lower()
	if normalized_type not in [HELP_TYPE_CONSTRUCTION, HELP_TYPE_RESEARCH, HELP_TYPE_TRAINING, HELP_TYPE_HEALING]:
		return {"ok": false, "error": "Invalid help type."}

	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		return {"ok": false, "error": "Alliance not found."}

	var entry: Dictionary = local_alliances[index]
	_normalize_alliance_entry(entry)
	var requests: Array = entry.get("help_requests", [])
	var capacity: int = get_embassy_help_capacity()
	if requests.size() >= capacity:
		return {"ok": false, "error": "Embassy help capacity full (%d)." % capacity}

	var now: int = int(Time.get_unix_time_from_system())
	requests.append({
		"request_id": "help_%d_%d" % [now, randi() % 100000],
		"player_name": LOCAL_PLAYER_NAME,
		"help_type": normalized_type,
		"remaining_time": max(60, remaining_time),
		"timestamp": now,
	})
	entry["help_requests"] = requests
	local_alliances[index] = entry
	save_alliance()
	alliance_changed.emit()
	return {"ok": true}


func help_request(request_id: String) -> Dictionary:
	if not is_in_alliance():
		return {"ok": false, "error": "Not in an alliance."}

	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		return {"ok": false, "error": "Alliance not found."}

	var entry: Dictionary = local_alliances[index]
	_normalize_alliance_entry(entry)
	var requests: Array = entry.get("help_requests", [])
	var req_index: int = _find_help_request_index(requests, request_id)
	if req_index == -1:
		return {"ok": false, "error": "Help request not found."}

	requests.remove_at(req_index)
	entry["help_requests"] = requests
	local_alliances[index] = entry
	save_alliance()
	alliance_changed.emit()
	return {"ok": true}


func help_all_requests() -> Dictionary:
	if not is_in_alliance():
		return {"ok": false, "error": "Not in an alliance."}

	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		return {"ok": false, "error": "Alliance not found."}

	var entry: Dictionary = local_alliances[index]
	_normalize_alliance_entry(entry)
	var removed: int = entry.get("help_requests", []).size()
	entry["help_requests"] = []
	local_alliances[index] = entry
	save_alliance()
	alliance_changed.emit()
	return {"ok": true, "removed": removed}


func save_alliance() -> Error:
	var path: String = get_save_path()
	var save := ConfigFile.new()
	save.set_value("membership", "alliance_id", alliance_id)
	save.set_value("membership", "alliance_name", alliance_name)
	save.set_value("membership", "alliance_tag", alliance_tag)
	save.set_value("membership", "role", role)
	save.set_value("membership", "joined_unix", joined_unix)
	# Untyped Array avoids typed-array JSON edge cases across Godot versions.
	save.set_value("registry", "alliances_json", _registry_to_json())
	save.set_value("research_attempts", "current_attempts", current_attempts)
	save.set_value("research_attempts", "max_attempts", max_attempts)
	save.set_value("research_attempts", "last_attempt_timestamp", last_attempt_timestamp)
	save.set_value("meta", "save_version", 4)
	var err: Error = save.save(path)
	if err != OK:
		push_error("[AllianceState] ConfigFile.save(%s) failed: %s" % [path, error_string(err)])
	else:
		_log_alliance("Saved %s | id=%s role=%s alliances=%d" % [
			path, alliance_id, role, local_alliances.size()
		])
	return err


func load_alliance() -> void:
	var path: String = get_save_path()
	var save := ConfigFile.new()
	var load_err: Error = save.load(path)
	if load_err != OK:
		_clear_membership("save file missing or unreadable (%s)" % error_string(load_err))
		local_alliances.clear()
		_log_alliance("Load failed for %s: %s" % [path, error_string(load_err)])
		return

	alliance_id = str(save.get_value("membership", "alliance_id", ""))
	alliance_name = str(save.get_value("membership", "alliance_name", ""))
	alliance_tag = str(save.get_value("membership", "alliance_tag", ""))
	role = str(save.get_value("membership", "role", ""))
	joined_unix = int(save.get_value("membership", "joined_unix", 0))

	local_alliances.clear()
	var raw: String = str(save.get_value("registry", "alliances_json", "[]"))
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) == TYPE_ARRAY:
		for item: Variant in parsed:
			if typeof(item) == TYPE_DICTIONARY:
				local_alliances.append(item)
	else:
		_log_alliance("Registry JSON parse failed; keeping membership and empty registry.")

	_normalize_all_alliances()
	_repair_membership_consistency()
	_sync_player_role_from_roster()

	current_attempts = int(save.get_value("research_attempts", "current_attempts", MAX_RESEARCH_ATTEMPTS))
	max_attempts = int(save.get_value("research_attempts", "max_attempts", MAX_RESEARCH_ATTEMPTS))
	last_attempt_timestamp = int(save.get_value("research_attempts", "last_attempt_timestamp", 0))
	if max_attempts <= 0:
		max_attempts = MAX_RESEARCH_ATTEMPTS
	current_attempts = clampi(current_attempts, 0, max_attempts)
	refresh_research_attempts(true)

	_log_alliance(
		"Loaded %s | id=%s role=%s alliances=%d in_alliance=%s"
		% [path, alliance_id, role, local_alliances.size(), str(is_in_alliance())]
	)


func _registry_to_json() -> String:
	var payload: Array = []
	for entry: Dictionary in local_alliances:
		payload.append(entry)
	return JSON.stringify(payload)


func _set_membership(id: String, name_text: String, tag_text: String, role_id: String) -> void:
	alliance_id = id
	alliance_name = name_text
	alliance_tag = tag_text
	role = role_id
	joined_unix = int(Time.get_unix_time_from_system())


func _clear_membership(reason: String = "") -> void:
	if reason != "":
		_log_alliance("Clearing membership: %s" % reason)
	alliance_id = ""
	alliance_name = ""
	alliance_tag = ""
	role = ""
	joined_unix = 0


func _repair_membership_consistency() -> void:
	if not is_in_alliance():
		return

	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		if alliance_name != "" and alliance_tag != "":
			_log_alliance("Repairing missing registry entry for id=%s" % alliance_id)
			_repair_missing_alliance_entry()
			index = _find_alliance_by_id(alliance_id)
		else:
			_clear_membership("membership id not in registry and cannot repair")
			return

	if index == -1:
		_clear_membership("repair failed to recreate alliance entry")
		return

	var member_index: int = _find_member_index(local_alliances[index], LOCAL_PLAYER_ID)
	if member_index == -1:
		_log_alliance("Repairing missing local_player roster row for id=%s role=%s" % [alliance_id, role])
		var entry: Dictionary = local_alliances[index]
		var members: Array = entry.get("members", [])
		var repair_role: String = role if role != "" else ROLE_MEMBER
		members.append(_make_member(
			LOCAL_PLAYER_ID,
			LOCAL_PLAYER_NAME,
			repair_role,
			int(GameState.power) if has_node("/root/GameState") else 1614990,
			"online",
			joined_unix if joined_unix > 0 else int(Time.get_unix_time_from_system())
		))
		entry["members"] = members
		entry["member_count"] = members.size()
		if repair_role == ROLE_LEADER:
			entry["leader_id"] = LOCAL_PLAYER_ID
		local_alliances[index] = entry


func _repair_missing_alliance_entry() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var repair_role: String = role if role != "" else ROLE_LEADER
	var members: Array = [
		_make_member(
			LOCAL_PLAYER_ID,
			LOCAL_PLAYER_NAME,
			repair_role,
			int(GameState.power) if has_node("/root/GameState") else 1614990,
			"online",
			joined_unix if joined_unix > 0 else now
		)
	]
	local_alliances.append({
		"id": alliance_id,
		"name": alliance_name,
		"tag": alliance_tag,
		"leader_id": LOCAL_PLAYER_ID if repair_role == ROLE_LEADER else "",
		"member_count": members.size(),
		"members": members,
		"applications": [],
		"announcement": "Alliance restored from membership save.",
		"treasury": _empty_treasury(),
		"help_requests": [],
		"created_unix": now,
	})
	_normalize_alliance_entry(local_alliances[local_alliances.size() - 1])


func _find_alliance_by_id(id: String) -> int:
	for i: int in range(local_alliances.size()):
		if str(local_alliances[i].get("id", "")) == id:
			return i
	return -1


func _find_alliance_by_tag(tag_text: String) -> int:
	var upper: String = tag_text.to_upper()
	for i: int in range(local_alliances.size()):
		if str(local_alliances[i].get("tag", "")).to_upper() == upper:
			return i
	return -1


func _find_member_index(entry: Dictionary, member_id: String) -> int:
	var members: Array = entry.get("members", [])
	for i: int in range(members.size()):
		if typeof(members[i]) == TYPE_DICTIONARY and _member_id(members[i]) == member_id:
			return i
	return -1


func _find_application_index(apps: Array, application_id: String) -> int:
	for i: int in range(apps.size()):
		if typeof(apps[i]) == TYPE_DICTIONARY and str(apps[i].get("application_id", "")) == application_id:
			return i
	return -1


func _find_help_request_index(requests: Array, request_id: String) -> int:
	for i: int in range(requests.size()):
		if typeof(requests[i]) == TYPE_DICTIONARY and str(requests[i].get("request_id", "")) == request_id:
			return i
	return -1


func _empty_treasury() -> Dictionary:
	return {"food": 0, "wood": 0, "stone": 0, "iron": 0}


func _parse_embassy_help_capacity(effect_text: String) -> int:
	# buildings.json: "Supports up to 11 coalition speed-ups..."
	var regex := RegEx.new()
	if regex.compile("Supports up to (\\d+)") != OK:
		return 0
	var matched: RegExMatch = regex.search(effect_text)
	if matched == null:
		return 0
	return int(matched.get_string(1))


func _make_seed_help_requests(now: int) -> Array:
	return [
		{
			"request_id": "help_seed_1",
			"player_name": "Sir Rowan",
			"help_type": HELP_TYPE_CONSTRUCTION,
			"remaining_time": 5400,
			"timestamp": now - 600,
		},
		{
			"request_id": "help_seed_2",
			"player_name": "Archer Nyx",
			"help_type": HELP_TYPE_RESEARCH,
			"remaining_time": 7200,
			"timestamp": now - 300,
		},
		{
			"request_id": "help_seed_3",
			"player_name": "Squire Tobin",
			"help_type": HELP_TYPE_TRAINING,
			"remaining_time": 1800,
			"timestamp": now - 120,
		},
		{
			"request_id": "help_seed_4",
			"player_name": "Lady Mira",
			"help_type": HELP_TYPE_HEALING,
			"remaining_time": 2400,
			"timestamp": now - 60,
		},
	]


func _is_alnum_tag(tag_text: String) -> bool:
	for i: int in range(tag_text.length()):
		var code: int = tag_text.unicode_at(i)
		var is_digit: bool = code >= 48 and code <= 57
		var is_upper: bool = code >= 65 and code <= 90
		var is_lower: bool = code >= 97 and code <= 122
		if not (is_digit or is_upper or is_lower):
			return false
	return true


func _get_role_data(role_id: String) -> Dictionary:
	var data: Dictionary = DataManager.get_alliance_data()
	var roles: Dictionary = data.get("allianceRoles", {})
	var role_data: Variant = roles.get(role_id, {})
	if typeof(role_data) == TYPE_DICTIONARY:
		return role_data
	return {}


func _get_role_permission_list(role_id: String) -> Array:
	return _get_role_data(role_id).get("permissions", [])


func _member_id(member: Dictionary) -> String:
	var mid: String = str(member.get("member_id", ""))
	if mid != "":
		return mid
	return str(member.get("id", ""))


func _member_name(member: Dictionary) -> String:
	var pname: String = str(member.get("player_name", ""))
	if pname != "":
		return pname
	return str(member.get("name", "Unknown"))


func _make_member(
	member_id: String,
	player_name: String,
	role_id: String,
	power: int,
	online_status: String,
	joined_timestamp: int
) -> Dictionary:
	var member: Dictionary = {
		"member_id": member_id,
		"id": member_id,
		"player_name": player_name,
		"name": player_name,
		"role": role_id,
		"power": power,
		"online_status": online_status,
		"joined_timestamp": joined_timestamp,
		"contribution_points": 0,
	}
	return member


func _sync_member_aliases(member: Dictionary) -> void:
	if str(member.get("member_id", "")) == "" and str(member.get("id", "")) != "":
		member["member_id"] = str(member.get("id", ""))
	if str(member.get("id", "")) == "" and str(member.get("member_id", "")) != "":
		member["id"] = str(member.get("member_id", ""))
	if str(member.get("player_name", "")) == "" and str(member.get("name", "")) != "":
		member["player_name"] = str(member.get("name", ""))
	if str(member.get("name", "")) == "" and str(member.get("player_name", "")) != "":
		member["name"] = str(member.get("player_name", ""))
	if not member.has("power"):
		member["power"] = 0
	if not member.has("online_status"):
		member["online_status"] = "offline"
	if not member.has("joined_timestamp"):
		member["joined_timestamp"] = int(member.get("joined_unix", 0))
	if not member.has("contribution_points"):
		member["contribution_points"] = 0


func _make_seed_applications(now: int) -> Array:
	return [
		{
			"application_id": "app_seed_1",
			"player_name": "Lady Corinne",
			"player_power": 310000,
			"submitted_timestamp": now - 7200,
			"status": STATUS_PENDING,
		},
		{
			"application_id": "app_seed_2",
			"player_name": "Baron Vex",
			"player_power": 505000,
			"submitted_timestamp": now - 3600,
			"status": STATUS_PENDING,
		},
		{
			"application_id": "app_seed_3",
			"player_name": "Scout Elara",
			"player_power": 120000,
			"submitted_timestamp": now - 1800,
			"status": STATUS_PENDING,
		},
	]


func _normalize_all_alliances() -> void:
	for i: int in range(local_alliances.size()):
		var entry: Dictionary = local_alliances[i]
		_normalize_alliance_entry(entry)
		local_alliances[i] = entry


func _normalize_alliance_entry(entry: Dictionary) -> void:
	var members: Array = entry.get("members", [])
	var normalized_members: Array = []
	for member: Variant in members:
		if typeof(member) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = member
		_sync_member_aliases(m)
		normalized_members.append(m)
	entry["members"] = normalized_members
	entry["member_count"] = normalized_members.size()

	if not entry.has("announcement"):
		entry["announcement"] = "Alliance bulletin board."

	var apps: Array = []
	if entry.has("applications") and typeof(entry["applications"]) == TYPE_ARRAY:
		for app: Variant in entry["applications"]:
			if typeof(app) == TYPE_DICTIONARY:
				var a: Dictionary = app
				if not a.has("application_id"):
					a["application_id"] = "app_%d" % apps.size()
				if not a.has("status"):
					a["status"] = STATUS_PENDING
				if not a.has("player_power"):
					a["player_power"] = 0
				if not a.has("submitted_timestamp"):
					a["submitted_timestamp"] = 0
				apps.append(a)
	else:
		# Sprint 1A saves had no applications — seed only for demo alliances.
		var entry_id: String = str(entry.get("id", ""))
		if entry_id.begins_with("demo_"):
			apps = _make_seed_applications(int(Time.get_unix_time_from_system()))
		else:
			apps = []
	entry["applications"] = apps

	if not entry.has("treasury") or typeof(entry["treasury"]) != TYPE_DICTIONARY:
		entry["treasury"] = _empty_treasury()
	else:
		var treasury: Dictionary = entry["treasury"]
		entry["treasury"] = {
			"food": int(treasury.get("food", 0)),
			"wood": int(treasury.get("wood", 0)),
			"stone": int(treasury.get("stone", 0)),
			"iron": int(treasury.get("iron", 0)),
		}

	entry["alliance_coins"] = max(0, int(entry.get("alliance_coins", 0)))

	var helps: Array = []
	if entry.has("help_requests") and typeof(entry["help_requests"]) == TYPE_ARRAY:
		for req: Variant in entry["help_requests"]:
			if typeof(req) != TYPE_DICTIONARY:
				continue
			var h: Dictionary = req
			if not h.has("request_id"):
				h["request_id"] = "help_%d" % helps.size()
			if not h.has("player_name"):
				h["player_name"] = "Unknown"
			if not h.has("help_type"):
				h["help_type"] = HELP_TYPE_CONSTRUCTION
			if not h.has("remaining_time"):
				h["remaining_time"] = 3600
			if not h.has("timestamp"):
				h["timestamp"] = 0
			helps.append(h)
	else:
		var entry_id: String = str(entry.get("id", ""))
		if entry_id.begins_with("demo_") or entry_id.begins_with("all_"):
			# Seed help for demo alliances and freshly created ones missing the field.
			helps = _make_seed_help_requests(int(Time.get_unix_time_from_system()))
		else:
			helps = []
	# Cap to Embassy capacity for the local player context.
	var capacity: int = get_embassy_help_capacity()
	if helps.size() > capacity:
		helps = helps.slice(0, capacity)
	entry["help_requests"] = helps

	if not entry.has("research") or typeof(entry["research"]) != TYPE_DICTIONARY:
		entry["research"] = _empty_research_state()
	else:
		var research: Dictionary = entry["research"]
		var nodes_raw: Variant = research.get("nodes", {})
		var clean_nodes: Dictionary = {}
		if typeof(nodes_raw) == TYPE_DICTIONARY:
			for key: Variant in nodes_raw.keys():
				var node: Variant = nodes_raw[key]
				if typeof(node) != TYPE_DICTIONARY:
					continue
				clean_nodes[str(key)] = {
					"level": max(0, int(node.get("level", 0))),
					"progress": max(0, int(node.get("progress", 0))),
				}
		entry["research"] = {
			"active_research_id": str(research.get("active_research_id", "")),
			"nodes": clean_nodes,
		}

	if not entry.has("leader_id") or str(entry.get("leader_id", "")) == "":
		for member: Dictionary in normalized_members:
			if str(member.get("role", "")) == ROLE_LEADER:
				entry["leader_id"] = _member_id(member)
				break


func _sync_player_role_from_roster() -> void:
	if not is_in_alliance():
		return
	var index: int = _find_alliance_by_id(alliance_id)
	if index == -1:
		return
	var member_index: int = _find_member_index(local_alliances[index], LOCAL_PLAYER_ID)
	if member_index == -1:
		return
	var member: Dictionary = local_alliances[index]["members"][member_index]
	role = str(member.get("role", role))


func _seed_demo_alliances() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	local_alliances = [
		{
			"id": "demo_iron_covenant",
			"name": "Iron Covenant",
			"tag": "IRON",
			"leader_id": "demo_leader_1",
			"announcement": "Iron holds the line. Apply with honor.",
			"members": [
				_make_member("demo_leader_1", "Ser Aldric", ROLE_LEADER, 890000, "online", now - 864000),
				_make_member("demo_2", "Lady Mira", "R3", 510000, "online", now - 432000),
				_make_member("demo_3", "Scout Bren", ROLE_MEMBER, 140000, "offline", now - 86400),
			],
			"applications": _make_seed_applications(now),
			"treasury": {"food": 25000, "wood": 20000, "stone": 15000, "iron": 5000},
			"help_requests": _make_seed_help_requests(now),
			"created_unix": 0,
		},
		{
			"id": "demo_crown_wardens",
			"name": "Crown Wardens",
			"tag": "CRWN",
			"leader_id": "demo_leader_2",
			"announcement": "Wardens of the Crown stand ready.",
			"members": [
				_make_member("demo_leader_2", "Warden Kael", ROLE_LEADER, 940000, "offline", now - 900000),
				_make_member("demo_4", "Keeper Lyra", "R2", 260000, "online", now - 200000),
			],
			"applications": _make_seed_applications(now + 1),
			"treasury": _empty_treasury(),
			"help_requests": _make_seed_help_requests(now + 1),
			"created_unix": 0,
		},
	]
	for i: int in range(local_alliances.size()):
		_normalize_alliance_entry(local_alliances[i])


## Automated Sprint 1B checks. Uses isolated save path — never touches player alliance.cfg.
func run_sprint_1b_smoke_test() -> bool:
	_begin_smoke_isolation()
	var ok: bool = true
	var tag: String = "S%03d" % (randi() % 1000)

	if is_in_alliance():
		leave_alliance()

	var created: Dictionary = create_alliance("Smoke Test Order", tag)
	if not created.get("ok", false) or role != ROLE_LEADER:
		push_error("[AllianceState] 1B smoke: create/R5 failed")
		return false

	if get_members().size() < 2:
		push_error("[AllianceState] 1B smoke: seeded roster missing")
		ok = false

	if not has_permission("promote_members") or not has_permission("review_applications"):
		push_error("[AllianceState] 1B smoke: leader permissions missing")
		ok = false

	var promote: Dictionary = promote_member("seed_squire_1")
	if not promote.get("ok", false) or str(promote.get("role", "")) != "R2":
		push_error("[AllianceState] 1B smoke: promote failed")
		ok = false

	var demote: Dictionary = demote_member("seed_squire_1")
	if not demote.get("ok", false) or str(demote.get("role", "")) != ROLE_MEMBER:
		push_error("[AllianceState] 1B smoke: demote failed")
		ok = false

	var bad_self_remove: Dictionary = remove_member(LOCAL_PLAYER_ID)
	if bad_self_remove.get("ok", false):
		push_error("[AllianceState] 1B smoke: self-remove should fail")
		ok = false

	var remove: Dictionary = remove_member("seed_ranger_1")
	if not remove.get("ok", false):
		push_error("[AllianceState] 1B smoke: remove failed")
		ok = false

	var transfer: Dictionary = transfer_leadership("seed_knight_1")
	if not transfer.get("ok", false) or role != "R4":
		push_error("[AllianceState] 1B smoke: transfer failed")
		ok = false

	var knight: Dictionary = get_member("seed_knight_1")
	if str(knight.get("role", "")) != ROLE_LEADER:
		push_error("[AllianceState] 1B smoke: new leader not R5")
		ok = false

	if not has_permission("review_applications"):
		push_error("[AllianceState] 1B smoke: R4 should review apps")
		ok = false

	var pending_before: int = get_pending_applications().size()
	if pending_before < 1:
		push_error("[AllianceState] 1B smoke: expected seeded applications")
		ok = false
	else:
		var first_id: String = str(get_pending_applications()[0].get("application_id", ""))
		var accept: Dictionary = accept_application(first_id)
		if not accept.get("ok", false):
			push_error("[AllianceState] 1B smoke: accept failed")
			ok = false
		else:
			var added: Dictionary = get_member("app_%s" % first_id)
			if str(added.get("role", "")) != ROLE_MEMBER:
				push_error("[AllianceState] 1B smoke: accepted member not R1")
				ok = false

		var remaining: Array[Dictionary] = get_pending_applications()
		if not remaining.is_empty():
			var reject: Dictionary = reject_application(str(remaining[0].get("application_id", "")))
			if not reject.get("ok", false):
				push_error("[AllianceState] 1B smoke: reject failed")
				ok = false

	save_alliance()
	var saved_id: String = alliance_id
	var saved_role: String = role
	load_alliance()
	if alliance_id != saved_id or role != saved_role:
		push_error("[AllianceState] 1B smoke: reload membership failed")
		ok = false
	if get_members().is_empty():
		push_error("[AllianceState] 1B smoke: roster lost on reload")
		ok = false

	# Equal/higher rank guard: R4 cannot demote R5
	var demote_leader: Dictionary = demote_member("seed_knight_1")
	if demote_leader.get("ok", false):
		push_error("[AllianceState] 1B smoke: demote higher rank should fail")
		ok = false

	leave_alliance()

	if ok:
		print("[AllianceState] Sprint 1B smoke test PASSED")
	_end_smoke_isolation()
	return ok


## Automated Sprint 1C checks. Uses isolated save path — never touches player alliance.cfg.
func run_sprint_1c_smoke_test() -> bool:
	_begin_smoke_isolation()
	var ok: bool = true
	var tag: String = "C%03d" % (randi() % 1000)

	if is_in_alliance():
		leave_alliance()

	if has_node("/root/GameState"):
		GameState.add_food(100000)
		GameState.add_wood(100000)
		GameState.add_stone(100000)
		GameState.add_iron(100000)

	var created: Dictionary = create_alliance("Smoke Donate Order", tag)
	if not created.get("ok", false):
		push_error("[AllianceState] 1C smoke: create failed")
		return false

	if get_embassy_help_capacity() < 1:
		push_error("[AllianceState] 1C smoke: embassy capacity invalid")
		ok = false

	if get_help_requests().size() < 1:
		push_error("[AllianceState] 1C smoke: seeded help missing")
		ok = false

	var donate: Dictionary = donate_resources("food", DONATION_AMOUNTS[0])
	if not donate.get("ok", false):
		push_error("[AllianceState] 1C smoke: donate failed")
		ok = false
	if get_player_contribution_points() < 1:
		push_error("[AllianceState] 1C smoke: contribution not updated")
		ok = false
	if int(get_treasury().get("food", 0)) < DONATION_AMOUNTS[0]:
		push_error("[AllianceState] 1C smoke: treasury not updated")
		ok = false

	var before_help: int = get_help_requests().size()
	var created_help: Dictionary = create_help_request(HELP_TYPE_CONSTRUCTION, 1200)
	if not created_help.get("ok", false):
		push_error("[AllianceState] 1C smoke: create help failed")
		ok = false
	elif get_help_requests().size() != before_help + 1:
		push_error("[AllianceState] 1C smoke: help queue size wrong after create")
		ok = false

	var first_help_id: String = str(get_help_requests()[0].get("request_id", ""))
	var helped: Dictionary = help_request(first_help_id)
	if not helped.get("ok", false):
		push_error("[AllianceState] 1C smoke: help failed")
		ok = false

	var help_all: Dictionary = help_all_requests()
	if not help_all.get("ok", false) or not get_help_requests().is_empty():
		push_error("[AllianceState] 1C smoke: help all failed")
		ok = false

	var points_before_reload: int = get_player_contribution_points()
	var food_treasury: int = int(get_treasury().get("food", 0))
	# Re-seed one help to verify persistence of queue field + contribution/treasury
	create_help_request(HELP_TYPE_RESEARCH, 900)
	save_alliance()
	load_alliance()
	if get_player_contribution_points() != points_before_reload:
		push_error("[AllianceState] 1C smoke: contribution lost on reload")
		ok = false
	if int(get_treasury().get("food", 0)) != food_treasury:
		push_error("[AllianceState] 1C smoke: treasury lost on reload")
		ok = false
	if get_help_requests().is_empty():
		push_error("[AllianceState] 1C smoke: help queue lost on reload")
		ok = false

	leave_alliance()

	if ok:
		print("[AllianceState] Sprint 1C smoke test PASSED")
	_end_smoke_isolation()
	return ok


func _begin_smoke_isolation() -> void:
	_save_path_override = SMOKE_SAVE_PATH
	_clear_membership("enter smoke isolation")
	local_alliances.clear()
	current_attempts = MAX_RESEARCH_ATTEMPTS
	max_attempts = MAX_RESEARCH_ATTEMPTS
	last_attempt_timestamp = int(Time.get_unix_time_from_system())
	# Wipe previous smoke file so tests start clean.
	if FileAccess.file_exists(SMOKE_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SMOKE_SAVE_PATH))
	_log_alliance("Smoke isolation ON → %s" % SMOKE_SAVE_PATH)


func _end_smoke_isolation() -> void:
	_save_path_override = ""
	load_alliance()
	_log_alliance(
		"Smoke isolation OFF → restored player save | id=%s role=%s alliances=%d"
		% [alliance_id, role, local_alliances.size()]
	)


## Persistence regression across create / join / leave + reload (isolated save only).
func run_persistence_smoke_test() -> bool:
	_begin_smoke_isolation()
	var ok: bool = true

	# Ensure demos exist for join test.
	_seed_demo_alliances()
	save_alliance()

	# Test 1: create persists as R5
	var created: Dictionary = create_alliance("Persist Test", "PST")
	if not created.get("ok", false) or role != ROLE_LEADER:
		push_error("[AllianceState] persistence: create/R5 failed")
		_end_smoke_isolation()
		return false

	var created_id: String = alliance_id
	load_alliance()
	if alliance_id != created_id or role != ROLE_LEADER or not is_in_alliance():
		push_error("[AllianceState] persistence: create did not survive reload")
		ok = false
	if get_member(LOCAL_PLAYER_ID).is_empty():
		push_error("[AllianceState] persistence: player missing from roster after create reload")
		ok = false

	# Test 2: leave then join demo as R1 persists
	leave_alliance()
	load_alliance()
	if is_in_alliance():
		push_error("[AllianceState] persistence: leave did not survive reload")
		ok = false

	var joinable: Array[Dictionary] = get_joinable_alliances()
	if joinable.is_empty():
		push_error("[AllianceState] persistence: no joinable alliance")
		ok = false
	else:
		var join_id: String = str(joinable[0].get("id", ""))
		var joined: Dictionary = join_alliance(join_id)
		if not joined.get("ok", false) or role != ROLE_MEMBER:
			push_error("[AllianceState] persistence: join/R1 failed")
			ok = false
		load_alliance()
		if alliance_id != join_id or role != ROLE_MEMBER:
			push_error("[AllianceState] persistence: join did not survive reload")
			ok = false

	# Test 3: leave persists outside alliance
	leave_alliance()
	load_alliance()
	if is_in_alliance():
		push_error("[AllianceState] persistence: final leave did not survive reload")
		ok = false

	if ok:
		print("[AllianceState] Persistence smoke test PASSED")
	_end_smoke_isolation()
	return ok


## Alliance Research contribution + attempts + tree unlocks + persistence.
func run_research_smoke_test() -> bool:
	_begin_smoke_isolation()
	var ok: bool = true

	var created: Dictionary = create_alliance("Research Test", "RSH")
	if not created.get("ok", false) or role != ROLE_LEADER:
		push_error("[AllianceState] research smoke: create/R5 failed")
		_end_smoke_isolation()
		return false

	if current_attempts != MAX_RESEARCH_ATTEMPTS:
		push_error("[AllianceState] research smoke: should start with max attempts")
		ok = false

	var research_id: String = "all_eco_tillage"
	var locked_id: String = "all_eco_masonry"
	var deep_locked_id: String = "all_eco_commerce"

	if get_research_status(research_id) != "AVAILABLE":
		push_error("[AllianceState] research smoke: starter tech should be AVAILABLE")
		ok = false
	if get_research_status(locked_id) != "LOCKED":
		push_error("[AllianceState] research smoke: tier-2 tech should start LOCKED")
		ok = false

	var locked_select: Dictionary = set_active_research(locked_id)
	if locked_select.get("ok", false):
		push_error("[AllianceState] research smoke: selecting locked research should fail")
		ok = false

	var set_active: Dictionary = set_active_research(research_id)
	if not set_active.get("ok", false):
		push_error("[AllianceState] research smoke: set_active failed: %s" % str(set_active.get("error", "")))
		ok = false

	if has_node("/root/GameState"):
		GameState.food = 500000
		GameState.wood = 500000
		GameState.stone = 500000
		GameState.iron = 500000
		GameState.diamonds = 500
		GameState.save_resources()

	# No contributions without an active project.
	var index: int = _find_alliance_by_id(alliance_id)
	if index != -1:
		var entry: Dictionary = local_alliances[index]
		var research: Dictionary = entry.get("research", _empty_research_state())
		research["active_research_id"] = ""
		entry["research"] = research
		local_alliances[index] = entry
	var no_active: Dictionary = contribute_to_research(research_id, false)
	if no_active.get("ok", false):
		push_error("[AllianceState] research smoke: contribute without active should fail")
		ok = false
	set_active_research(research_id)

	var attempts_before: int = current_attempts
	var cost: Dictionary = get_research_contribution_cost(research_id)
	var resource_id: String = str(cost.get("resource", "food"))
	var amount: int = int(cost.get("amount", 0))
	var food_before: int = int(GameState.food) if has_node("/root/GameState") else 0
	var wood_before: int = int(GameState.wood) if has_node("/root/GameState") else 0
	var stone_before: int = int(GameState.stone) if has_node("/root/GameState") else 0
	var iron_before: int = int(GameState.iron) if has_node("/root/GameState") else 0
	var pts_before: int = get_player_contribution_points()
	var coins_before: int = get_alliance_coins()
	var expected_points: int = get_research_points_per_contribution(research_id)
	var expected_rewards: Dictionary = get_research_contribution_rewards(research_id)
	var required: int = get_research_requirement(research_id, 0)

	if resource_id != "food":
		push_error("[AllianceState] research smoke: tillage should cost food")
		ok = false

	var contrib: Dictionary = contribute_to_research(research_id, false)
	if not contrib.get("ok", false):
		push_error("[AllianceState] research smoke: contribute failed: %s" % str(contrib.get("error", "")))
		ok = false
	if current_attempts != attempts_before - 1:
		push_error("[AllianceState] research smoke: attempt not consumed")
		ok = false
	if has_node("/root/GameState"):
		if resource_id == "food" and int(GameState.food) != food_before - amount:
			push_error("[AllianceState] research smoke: food not deducted correctly")
			ok = false
		if int(GameState.wood) != wood_before:
			push_error("[AllianceState] research smoke: wood should be unchanged")
			ok = false
		if int(GameState.stone) != stone_before:
			push_error("[AllianceState] research smoke: stone should be unchanged")
			ok = false
		if int(GameState.iron) != iron_before:
			push_error("[AllianceState] research smoke: iron should be unchanged")
			ok = false
	if get_player_contribution_points() != pts_before + int(expected_rewards.get("personal_contribution", 0)):
		push_error("[AllianceState] research smoke: personal contribution reward wrong")
		ok = false
	if get_alliance_coins() != coins_before + int(expected_rewards.get("alliance_coins", 0)):
		push_error("[AllianceState] research smoke: alliance coins reward wrong")
		ok = false
	if int(get_research_node_runtime(research_id).get("progress", 0)) != expected_points:
		push_error("[AllianceState] research smoke: research_points progress wrong")
		ok = false

	# Higher-tier nodes should cost more than tier-1 tillage.
	if get_research_contribution_amount("all_eco_commerce") <= amount:
		push_error("[AllianceState] research smoke: higher-tier cost should exceed tier-1")
		ok = false
	if get_research_contribution_resource("all_eco_timber") != "wood":
		push_error("[AllianceState] research smoke: timber should cost wood")
		ok = false
	if get_research_contribution_resource("all_mil_drills") != "iron":
		push_error("[AllianceState] research smoke: drills should cost iron")
		ok = false

	# Force near-complete then contribute to verify level-up + unlock.
	var idx_force: int = _find_alliance_by_id(alliance_id)
	if idx_force != -1:
		var entry_force: Dictionary = local_alliances[idx_force]
		var research_force: Dictionary = entry_force.get("research", _empty_research_state())
		var nodes_force: Dictionary = research_force.get("nodes", {})
		nodes_force[research_id] = {
			"level": 0,
			"progress": max(0, required - expected_points),
		}
		research_force["nodes"] = nodes_force
		research_force["active_research_id"] = research_id
		entry_force["research"] = research_force
		local_alliances[idx_force] = entry_force

	var level_contrib: Dictionary = contribute_to_research(research_id, false)
	if not level_contrib.get("ok", false):
		push_error("[AllianceState] research smoke: level-up contribute failed")
		ok = false
	elif int(get_research_node_runtime(research_id).get("level", 0)) < 1:
		push_error("[AllianceState] research smoke: expected level-up after near-complete contribute")
		ok = false
	elif get_active_research_id() != "":
		push_error("[AllianceState] research smoke: active should clear after level complete")
		ok = false

	if get_research_status(locked_id) != "AVAILABLE":
		push_error("[AllianceState] research smoke: masonry should unlock after tillage Lv1")
		ok = false
	if get_research_status(deep_locked_id) != "LOCKED":
		push_error("[AllianceState] research smoke: commerce should remain locked")
		ok = false

	var blocked_until_select: Dictionary = contribute_to_active_research(false)
	if blocked_until_select.get("ok", false):
		push_error("[AllianceState] research smoke: contribute after clear should fail until re-select")
		ok = false

	var reselect: Dictionary = set_active_research(research_id)
	if not reselect.get("ok", false):
		push_error("[AllianceState] research smoke: re-select after level-up failed")
		ok = false

	var blocked: Dictionary = contribute_to_research(locked_id, false)
	if blocked.get("ok", false):
		push_error("[AllianceState] research smoke: non-active contribute should fail")
		ok = false

	# Drain attempts then verify diamond bypass.
	current_attempts = 0
	last_attempt_timestamp = int(Time.get_unix_time_from_system())
	var no_attempt: Dictionary = contribute_to_active_research(false)
	if no_attempt.get("ok", false):
		push_error("[AllianceState] research smoke: contribute with 0 attempts should fail")
		ok = false

	# Diamonds alone must not bypass resource requirements.
	var diamonds_before: int = int(GameState.diamonds)
	GameState.food = 0
	GameState.save_resources()
	var diamond_no_res: Dictionary = contribute_to_active_research(true)
	if diamond_no_res.get("ok", false):
		push_error("[AllianceState] research smoke: diamonds must not bypass resources")
		ok = false
	if int(GameState.diamonds) != diamonds_before:
		push_error("[AllianceState] research smoke: diamonds deducted without valid contribute")
		ok = false

	GameState.food = 500000
	GameState.wood = 500000
	GameState.stone = 500000
	GameState.iron = 500000
	GameState.save_resources()
	var diamond_ok: Dictionary = contribute_to_active_research(true)
	if not diamond_ok.get("ok", false):
		push_error("[AllianceState] research smoke: diamond bypass failed: %s" % str(diamond_ok.get("error", "")))
		ok = false
	elif int(GameState.diamonds) != diamonds_before - RESEARCH_DIAMOND_BYPASS_COST:
		push_error("[AllianceState] research smoke: diamonds not deducted for bypass")
		ok = false
	elif current_attempts != 0:
		push_error("[AllianceState] research smoke: diamond bypass should not consume attempts")
		ok = false

	# Offline regen: set last timestamp in the past.
	current_attempts = 0
	last_attempt_timestamp = int(Time.get_unix_time_from_system()) - (ATTEMPT_REGEN_SECONDS * 3) - 10
	refresh_research_attempts(false)
	if current_attempts < 3:
		push_error("[AllianceState] research smoke: attempts did not regenerate from timestamp")
		ok = false

	role = ROLE_MEMBER
	var denied: Dictionary = set_active_research(research_id)
	if denied.get("ok", false):
		push_error("[AllianceState] research smoke: R1 should not select_research")
		ok = false
	role = ROLE_LEADER

	# Ensure active for R1 contribute (may have been cleared by diamond contribute level-up).
	if get_active_research_id() == "":
		set_active_research(research_id)
	role = ROLE_MEMBER
	var member_contrib: Dictionary = contribute_to_active_research(false)
	if not member_contrib.get("ok", false):
		push_error("[AllianceState] research smoke: R1 contribute failed: %s" % str(member_contrib.get("error", "")))
		ok = false
	role = ROLE_LEADER

	var level_saved: int = int(get_research_node_runtime(research_id).get("level", 0))
	var progress_saved: int = int(get_research_node_runtime(research_id).get("progress", 0))
	var active_saved: String = get_active_research_id()
	var attempts_saved: int = current_attempts
	var coins_saved: int = get_alliance_coins()
	var masonry_status_saved: String = get_research_status(locked_id)
	load_alliance()
	if get_active_research_id() != active_saved:
		push_error("[AllianceState] research smoke: active research lost on reload")
		ok = false
	if int(get_research_node_runtime(research_id).get("level", 0)) != level_saved:
		push_error("[AllianceState] research smoke: level lost on reload")
		ok = false
	if int(get_research_node_runtime(research_id).get("progress", 0)) != progress_saved:
		push_error("[AllianceState] research smoke: progress lost on reload")
		ok = false
	if get_research_status(locked_id) != masonry_status_saved:
		push_error("[AllianceState] research smoke: unlock status lost on reload")
		ok = false
	if current_attempts != attempts_saved:
		push_error("[AllianceState] research smoke: attempts lost on reload")
		ok = false
	if get_alliance_coins() != coins_saved:
		push_error("[AllianceState] research smoke: alliance coins lost on reload")
		ok = false

	leave_alliance()
	if ok:
		print("[AllianceState] Research smoke test PASSED")
	_end_smoke_isolation()
	return ok
