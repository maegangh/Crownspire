extends Node

## Crownspire Mail — battle reports + system inbox.
## Persist: user://mail.cfg (or isolated smoke path).
## Opening mail never grants rewards; reports only display already-granted results.

signal mail_changed

const SAVE_PATH: String = "user://mail.cfg"
const SMOKE_SAVE_PATH: String = "user://mail_smoke_test.cfg"
const SAVE_VERSION: int = 1
const MAX_MESSAGES: int = 100

var messages: Array[Dictionary] = []
var _save_path_override: String = ""


func _ready() -> void:
	load_mail()


func get_save_path() -> String:
	if _save_path_override != "":
		return _save_path_override
	if has_node("/root/AccountSavePaths"):
		return AccountSavePaths.path_for("mail.cfg")
	return SAVE_PATH


func begin_smoke_isolation() -> void:
	_save_path_override = SMOKE_SAVE_PATH
	messages.clear()
	if FileAccess.file_exists(SMOKE_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SMOKE_SAVE_PATH))


func end_smoke_isolation() -> void:
	_save_path_override = ""
	load_mail()


func get_unread_count() -> int:
	var count: int = 0
	for msg: Dictionary in messages:
		if not bool(msg.get("read", false)):
			count += 1
	return count


func get_battle_report_count() -> int:
	var count: int = 0
	for msg: Dictionary in messages:
		if str(msg.get("type", "")) == "wildling_battle":
			count += 1
	return count


func get_messages_by_category(category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for msg: Dictionary in messages:
		var msg_type: String = str(msg.get("type", ""))
		if category == "battle" and msg_type == "wildling_battle":
			out.append(msg)
		elif category == "system" and msg_type in ["system", "gathering_report"]:
			out.append(msg)
	return out


func get_message(report_id: String) -> Dictionary:
	for msg: Dictionary in messages:
		if str(msg.get("report_id", "")) == report_id:
			return msg
	return {}


func has_report_for_march(march_id: String) -> bool:
	if march_id == "":
		return false
	var report_id: String = _report_id_for_march(march_id)
	return not get_message(report_id).is_empty()


func has_gathering_report_for_march(march_id: String) -> bool:
	if march_id == "":
		return false
	return not get_message(_gathering_report_id_for_march(march_id)).is_empty()


func mark_read(report_id: String) -> void:
	for i: int in range(messages.size()):
		if str(messages[i].get("report_id", "")) == report_id:
			if bool(messages[i].get("read", false)):
				return
			messages[i]["read"] = true
			save_mail()
			mail_changed.emit()
			return


## Create exactly one wildling battle report from an already-resolved march result.
## Returns true if a new report was inserted.
func add_wildling_battle_report(march: Dictionary, result: Dictionary) -> bool:
	var march_id: String = str(march.get("march_id", ""))
	if march_id == "":
		return false
	var report_id: String = _report_id_for_march(march_id)
	if not get_message(report_id).is_empty():
		return false

	var target: Dictionary = march.get("target_data", {})
	if typeof(target) != TYPE_DICTIONARY:
		target = {}
	var species: String = str(target.get("species", "wildling"))
	var level: int = int(target.get("level", 1))
	var troops: Dictionary = march.get("original_troops", march.get("troops", {}))
	if typeof(troops) != TYPE_DICTIONARY:
		troops = {}
	var losses: Dictionary = result.get("losses", {})
	if typeof(losses) != TYPE_DICTIONARY:
		losses = {}
	var survivors: Dictionary = result.get("surviving_troops", {})
	if typeof(survivors) != TYPE_DICTIONARY:
		survivors = {}
	var rewards: Dictionary = result.get("rewards", {})
	if typeof(rewards) != TYPE_DICTIONARY:
		rewards = {}
	var hero_ids: Array = []
	for hid: Variant in march.get("hero_ids", []):
		hero_ids.append(str(hid))

	var wounded: Dictionary = result.get("wounded", losses)
	if typeof(wounded) != TYPE_DICTIONARY:
		wounded = losses
	var player_stats: Dictionary = result.get("player_stats", {})
	if typeof(player_stats) != TYPE_DICTIONARY:
		player_stats = {}
	var wildling_stats: Dictionary = result.get("wildling_stats", {})
	if typeof(wildling_stats) != TYPE_DICTIONARY:
		wildling_stats = {}

	var report: Dictionary = {
		"report_id": report_id,
		"type": "wildling_battle",
		"category": "battle",
		"timestamp": int(Time.get_unix_time_from_system()),
		"read": false,
		"march_id": march_id,
		"target": {
			"species": species,
			"display_name": _species_display_name(species),
			"level": level,
			"power": int(target.get("power", 0)),
		},
		"result": {
			"victory": bool(result.get("victory", false)),
			"summary": str(result.get("summary", "")),
			"rounds": int(result.get("rounds", 0)),
		},
		"march": {
			"hero_ids": hero_ids,
			"infantry": int(troops.get("infantry", 0)),
			"marksmen": int(troops.get("marksmen", 0)),
			"cavalry": int(troops.get("cavalry", 0)),
			"march_power": int(result.get("march_power", march.get("march_power", 0))),
		},
		"losses": {
			"infantry": int(losses.get("infantry", 0)),
			"marksmen": int(losses.get("marksmen", 0)),
			"cavalry": int(losses.get("cavalry", 0)),
		},
		"wounded": {
			"infantry": int(wounded.get("infantry", 0)),
			"marksmen": int(wounded.get("marksmen", 0)),
			"cavalry": int(wounded.get("cavalry", 0)),
		},
		"wounded_routing": _routing_summary(result.get("wounded_routing", march.get("wounded_routing", {}))),
		"survivors": {
			"infantry": int(survivors.get("infantry", 0)),
			"marksmen": int(survivors.get("marksmen", 0)),
			"cavalry": int(survivors.get("cavalry", 0)),
		},
		"player_stats": {
			"attack": int(player_stats.get("attack", 0)),
			"defense": int(player_stats.get("defense", 0)),
			"health": int(player_stats.get("health", 0)),
		},
		"wildling_stats": {
			"attack": int(wildling_stats.get("attack", 0)),
			"defense": int(wildling_stats.get("defense", 0)),
			"health": int(wildling_stats.get("health", 0)),
		},
		"rewards": rewards.duplicate(true),
	}

	messages.insert(0, report)
	while messages.size() > MAX_MESSAGES:
		messages.pop_back()
	save_mail()
	mail_changed.emit()
	return true


func _routing_summary(raw: Variant) -> Dictionary:
	var out := {"hospital": 0, "sanctuary": 0, "total": 0}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = raw as Dictionary
	out["hospital"] = int(d.get("hospital_count", 0))
	out["sanctuary"] = int(d.get("sanctuary_count", 0))
	out["total"] = int(out["hospital"]) + int(out["sanctuary"])
	return out


## Create exactly one gathering report after home return + resource credit.
## Returns true if a new report was inserted.
func add_gathering_report(march: Dictionary) -> bool:
	var march_id: String = str(march.get("march_id", ""))
	if march_id == "":
		return false
	var report_id: String = _gathering_report_id_for_march(march_id)
	if not get_message(report_id).is_empty():
		return false

	var target: Dictionary = march.get("target_data", {})
	if typeof(target) != TYPE_DICTIONARY:
		target = {}
	var rtype: String = str(march.get("resource_type", target.get("resource_type", ""))).strip_edges().to_lower()
	var display_name: String = str(target.get("display_name", "")).strip_edges()
	if display_name == "":
		display_name = _resource_display_name(rtype)
	var level: int = int(target.get("resource_level", target.get("level", 1)))
	var amount: int = maxi(0, int(march.get("gathered_amount", 0)))
	var troops: Dictionary = march.get("original_troops", march.get("troops", {}))
	if typeof(troops) != TYPE_DICTIONARY:
		troops = {}
	var hero_ids: Array = []
	for hid: Variant in march.get("hero_ids", []):
		hero_ids.append(str(hid))

	var report: Dictionary = {
		"report_id": report_id,
		"type": "gathering_report",
		"category": "system",
		"timestamp": int(Time.get_unix_time_from_system()),
		"read": false,
		"march_id": march_id,
		"title": "Gathering Report",
		"status": "Successful",
		"resource": {
			"type": rtype,
			"display_type": rtype.capitalize(),
			"amount": amount,
		},
		"source": {
			"display_name": display_name,
			"level": level,
		},
		"march": {
			"hero_ids": hero_ids,
			"infantry": int(troops.get("infantry", 0)),
			"marksmen": int(troops.get("marksmen", 0)),
			"cavalry": int(troops.get("cavalry", 0)),
			"cargo_capacity": int(march.get("cargo_capacity", 0)),
			"departure_timestamp": int(march.get("departure_timestamp", 0)),
			"gather_started_unix": int(march.get("gather_started_unix", 0)),
			"gather_end_unix": int(march.get("gather_end_unix", 0)),
			"return_arrival_timestamp": int(march.get("return_arrival_timestamp", 0)),
		},
		"preview": "%s Lv.%d\n+%s %s" % [
			display_name,
			level,
			_format_amount(amount),
			rtype.capitalize(),
		],
		"summary": "March returned safely.",
	}

	messages.insert(0, report)
	while messages.size() > MAX_MESSAGES:
		messages.pop_back()
	save_mail()
	mail_changed.emit()
	return true


func save_mail() -> void:
	var save := ConfigFile.new()
	save.set_value("meta", "save_version", SAVE_VERSION)
	save.set_value("inbox", "messages_json", JSON.stringify(messages))
	save.save(get_save_path())
	if has_node("/root/AccountCloudSave"):
		AccountCloudSave.mark_dirty("mail")


func load_mail() -> void:
	messages.clear()
	var save := ConfigFile.new()
	if save.load(get_save_path()) != OK:
		return
	var raw: String = str(save.get_value("inbox", "messages_json", "[]"))
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_ARRAY:
		return
	for item: Variant in parsed:
		if typeof(item) == TYPE_DICTIONARY:
			messages.append(item)


func _report_id_for_march(march_id: String) -> String:
	return "wildling_battle_%s" % march_id


func _gathering_report_id_for_march(march_id: String) -> String:
	return "gathering_report_%s" % march_id


func _species_display_name(species: String) -> String:
	var cleaned: String = species.strip_edges()
	if cleaned == "":
		return "Wildling"
	return "Wildling %s" % cleaned.capitalize()


func _resource_display_name(resource_type: String) -> String:
	match resource_type.strip_edges().to_lower():
		"food":
			return "Fertile Wheat Farm"
		"wood":
			return "Cedar Lumber Camp"
		"stone":
			return "Granite Stone Quarry"
		"iron":
			return "Magnetic Iron Lode"
		_:
			return resource_type.capitalize()


func _format_amount(value: int) -> String:
	var raw: String = str(maxi(0, value))
	var out: String = ""
	var count: int = 0
	for i: int in range(raw.length() - 1, -1, -1):
		out = raw[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
