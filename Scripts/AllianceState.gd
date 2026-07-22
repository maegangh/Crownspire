extends Node

## Player Alliance membership runtime state.
## Kept separate from GameState: GameState owns economy/building scalars in
## user://resources.cfg and cannot cleanly host membership, local alliance
## registry, or role APIs without mixing save domains.

signal alliance_changed

const SAVE_PATH: String = "user://alliance.cfg"
const ROLE_MEMBER: String = "R1"
const ROLE_LEADER: String = "R5"
const MAX_TAG_LENGTH: int = 4
const MIN_TAG_LENGTH: int = 3
const MIN_NAME_LENGTH: int = 3
const MAX_NAME_LENGTH: int = 24

## Current player membership (empty alliance_id means not in an alliance).
var alliance_id: String = ""
var alliance_name: String = ""
var alliance_tag: String = ""
var role: String = ""
var joined_unix: int = 0

## Offline-local registry of alliances created/joinable on this device.
var local_alliances: Array[Dictionary] = []


func _ready() -> void:
	load_alliance()
	if local_alliances.is_empty():
		_seed_demo_alliances()
		save_alliance()


func is_in_alliance() -> bool:
	return alliance_id != ""


func get_role_permissions() -> Array:
	if role == "":
		return []
	var data: Dictionary = DataManager.get_alliance_data()
	var roles: Dictionary = data.get("allianceRoles", {})
	var role_data: Variant = roles.get(role, {})
	if typeof(role_data) != TYPE_DICTIONARY:
		return []
	return role_data.get("permissions", [])


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

	var new_id: String = "all_%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 100000]
	var entry: Dictionary = {
		"id": new_id,
		"name": str(check["name"]),
		"tag": str(check["tag"]),
		"leader_id": "local_player",
		"member_count": 1,
		"members": [
			{
				"id": "local_player",
				"name": "Player",
				"role": ROLE_LEADER,
			}
		],
		"created_unix": int(Time.get_unix_time_from_system()),
	}

	local_alliances.append(entry)
	_set_membership(new_id, str(check["name"]), str(check["tag"]), ROLE_LEADER)
	save_alliance()
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
	var members: Array = entry.get("members", [])
	for member: Variant in members:
		if typeof(member) == TYPE_DICTIONARY and str(member.get("id", "")) == "local_player":
			return {"ok": false, "error": "Already listed in that alliance."}

	members.append({
		"id": "local_player",
		"name": "Player",
		"role": ROLE_MEMBER,
	})
	entry["members"] = members
	entry["member_count"] = members.size()
	local_alliances[index] = entry

	_set_membership(
		str(entry.get("id", "")),
		str(entry.get("name", "")),
		str(entry.get("tag", "")),
		ROLE_MEMBER
	)
	save_alliance()
	alliance_changed.emit()
	return {"ok": true}


func leave_alliance() -> Dictionary:
	if not is_in_alliance():
		return {"ok": false, "error": "Not in an alliance."}

	var index: int = _find_alliance_by_id(alliance_id)
	if index != -1:
		var entry: Dictionary = local_alliances[index]
		var members: Array = entry.get("members", [])
		var remaining: Array = []
		for member: Variant in members:
			if typeof(member) != TYPE_DICTIONARY:
				continue
			if str(member.get("id", "")) == "local_player":
				continue
			remaining.append(member)

		if remaining.is_empty():
			local_alliances.remove_at(index)
		else:
			entry["members"] = remaining
			entry["member_count"] = remaining.size()
			if str(entry.get("leader_id", "")) == "local_player":
				var promote: Dictionary = remaining[0]
				promote["role"] = ROLE_LEADER
				remaining[0] = promote
				entry["leader_id"] = str(promote.get("id", ""))
				entry["members"] = remaining
			local_alliances[index] = entry

	_clear_membership()
	save_alliance()
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
		}
	return local_alliances[index].duplicate(true)


func save_alliance() -> void:
	var save := ConfigFile.new()
	save.set_value("membership", "alliance_id", alliance_id)
	save.set_value("membership", "alliance_name", alliance_name)
	save.set_value("membership", "alliance_tag", alliance_tag)
	save.set_value("membership", "role", role)
	save.set_value("membership", "joined_unix", joined_unix)
	save.set_value("registry", "alliances_json", JSON.stringify(local_alliances))
	save.save(SAVE_PATH)


func load_alliance() -> void:
	var save := ConfigFile.new()
	if save.load(SAVE_PATH) != OK:
		_clear_membership()
		local_alliances.clear()
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


func _set_membership(id: String, name_text: String, tag_text: String, role_id: String) -> void:
	alliance_id = id
	alliance_name = name_text
	alliance_tag = tag_text
	role = role_id
	joined_unix = int(Time.get_unix_time_from_system())


func _clear_membership() -> void:
	alliance_id = ""
	alliance_name = ""
	alliance_tag = ""
	role = ""
	joined_unix = 0


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


func _is_alnum_tag(tag_text: String) -> bool:
	for i: int in range(tag_text.length()):
		var code: int = tag_text.unicode_at(i)
		var is_digit: bool = code >= 48 and code <= 57
		var is_upper: bool = code >= 65 and code <= 90
		var is_lower: bool = code >= 97 and code <= 122
		if not (is_digit or is_upper or is_lower):
			return false
	return true


func _seed_demo_alliances() -> void:
	## Offline join targets so Join is usable before the player creates one.
	local_alliances = [
		{
			"id": "demo_iron_covenant",
			"name": "Iron Covenant",
			"tag": "IRON",
			"leader_id": "demo_leader_1",
			"member_count": 3,
			"members": [
				{"id": "demo_leader_1", "name": "Ser Aldric", "role": ROLE_LEADER},
				{"id": "demo_2", "name": "Lady Mira", "role": "R3"},
				{"id": "demo_3", "name": "Scout Bren", "role": ROLE_MEMBER},
			],
			"created_unix": 0,
		},
		{
			"id": "demo_crown_wardens",
			"name": "Crown Wardens",
			"tag": "CRWN",
			"leader_id": "demo_leader_2",
			"member_count": 2,
			"members": [
				{"id": "demo_leader_2", "name": "Warden Kael", "role": ROLE_LEADER},
				{"id": "demo_4", "name": "Keeper Lyra", "role": "R2"},
			],
			"created_unix": 0,
		},
	]
