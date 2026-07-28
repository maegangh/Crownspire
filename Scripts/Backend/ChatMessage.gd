extends RefCounted
class_name CrownspireChatMessage

## Crownspire structured chat message model (client-side view of Nakama channel content).
## Schema version allows future types without rewriting Chat UI.

const SCHEMA_VERSION: int = 1

const TYPE_TEXT: String = "TEXT"
const TYPE_SYSTEM: String = "SYSTEM"
const TYPE_MAP_LOCATION: String = "MAP_LOCATION"
const TYPE_RALLY: String = "RALLY"
const TYPE_BATTLE_REPORT: String = "BATTLE_REPORT" ## reserved
const TYPE_ALLIANCE_INVITE: String = "ALLIANCE_INVITE" ## reserved
const TYPE_PLAYER_SHARE: String = "PLAYER_SHARE" ## reserved
const TYPE_ITEM_SHARE: String = "ITEM_SHARE" ## reserved

const SUPPORTED_SEND_TYPES: Array[String] = [
	TYPE_TEXT,
	TYPE_MAP_LOCATION,
	TYPE_RALLY,
]

const MAX_TEXT_LENGTH: int = 280
const MAX_LABEL_LENGTH: int = 64
const MAX_COORD: float = 1000000.0

var message_id: String = ""
var channel_id: String = ""
var kingdom_id: String = ""
var sender_user_id: String = ""
var sender_display_name: String = ""
## Non-authoritative display cache from message content.
## Trusted multiplayer tag = AllianceBackend / server profile, not this field alone.
var sender_alliance_tag: String = ""
var sender_username: String = "" ## Nakama username (server-side handle; not Crownspire display name)
var timestamp_unix: int = 0
var create_time_raw: String = ""
var message_type: String = TYPE_TEXT
var text: String = ""
var payload: Dictionary = {}
var metadata: Dictionary = {}
var is_persistent: bool = false
var parse_ok: bool = true
var parse_error: String = ""


static func type_is_known(message_type: String) -> bool:
	return message_type in [
		TYPE_TEXT,
		TYPE_SYSTEM,
		TYPE_MAP_LOCATION,
		TYPE_RALLY,
		TYPE_BATTLE_REPORT,
		TYPE_ALLIANCE_INVITE,
		TYPE_PLAYER_SHARE,
		TYPE_ITEM_SHARE,
	]


static func build_outbound_content(
	message_type: String,
	text_value: String,
	display_name: String,
	alliance_tag: String,
	payload_value: Dictionary = {},
	metadata_value: Dictionary = {},
	kingdom_id: String = ""
) -> Dictionary:
	return {
		"v": SCHEMA_VERSION,
		"message_type": message_type,
		"text": text_value,
		"sender_display_name": display_name,
		"sender_alliance_tag": alliance_tag,
		"kingdom_id": kingdom_id,
		"payload": payload_value.duplicate(true),
		"metadata": metadata_value.duplicate(true),
	}


static func from_nakama_channel_message(raw: Object, fallback_kingdom_id: String = "") -> CrownspireChatMessage:
	var msg := CrownspireChatMessage.new()
	if raw == null:
		msg.parse_ok = false
		msg.parse_error = "null channel message"
		return msg

	msg.message_id = str(raw.message_id) if _has(raw, "message_id") else ""
	msg.channel_id = str(raw.channel_id) if _has(raw, "channel_id") else ""
	msg.sender_user_id = str(raw.sender_id) if _has(raw, "sender_id") else ""
	msg.sender_username = str(raw.username) if _has(raw, "username") else ""
	msg.create_time_raw = str(raw.create_time) if _has(raw, "create_time") else ""
	msg.timestamp_unix = _parse_nakama_time(msg.create_time_raw)
	msg.is_persistent = bool(raw.persistent) if _has(raw, "persistent") else false

	var content_raw: String = str(raw.content) if _has(raw, "content") else ""
	var content: Variant = _parse_content_json(content_raw)
	if typeof(content) != TYPE_DICTIONARY:
		msg.parse_ok = false
		msg.parse_error = "malformed content JSON"
		msg.message_type = TYPE_TEXT
		msg.text = "[Unsupported message]"
		return msg

	var dict: Dictionary = content
	msg.message_type = str(dict.get("message_type", TYPE_TEXT)).strip_edges().to_upper()
	if msg.message_type == "":
		msg.message_type = TYPE_TEXT
	if not type_is_known(msg.message_type):
		# Render safely; do not crash on unknown future types.
		msg.text = str(dict.get("text", "")).strip_edges()
		if msg.text == "":
			msg.text = "[Unsupported message type]"
		msg.payload = {}
		msg.metadata = {"unsupported_type": msg.message_type}
		msg.message_type = TYPE_TEXT
		msg.sender_display_name = str(dict.get("sender_display_name", "")).strip_edges()
		msg.sender_alliance_tag = str(dict.get("sender_alliance_tag", "")).strip_edges()
		msg.kingdom_id = str(dict.get("kingdom_id", fallback_kingdom_id)).strip_edges()
		return msg

	msg.text = str(dict.get("text", ""))
	msg.sender_display_name = str(dict.get("sender_display_name", "")).strip_edges()
	msg.sender_alliance_tag = str(dict.get("sender_alliance_tag", "")).strip_edges()
	msg.kingdom_id = str(dict.get("kingdom_id", fallback_kingdom_id)).strip_edges()
	if typeof(dict.get("payload", {})) == TYPE_DICTIONARY:
		msg.payload = (dict.get("payload", {}) as Dictionary).duplicate(true)
	if typeof(dict.get("metadata", {})) == TYPE_DICTIONARY:
		msg.metadata = (dict.get("metadata", {}) as Dictionary).duplicate(true)

	if msg.sender_display_name == "":
		msg.sender_display_name = msg.sender_username if msg.sender_username != "" else "Unknown"
	if msg.message_type == TYPE_SYSTEM:
		msg.sender_display_name = "System"
		msg.sender_alliance_tag = ""

	var valid: Dictionary = validate_parsed(msg)
	if not bool(valid.get("ok", false)):
		msg.parse_ok = false
		msg.parse_error = str(valid.get("error", "invalid message"))
		msg.text = "[Invalid message]"
		msg.payload = {}
	return msg


static func validate_outbound_text(text_value: String) -> Dictionary:
	var cleaned: String = text_value.strip_edges()
	if cleaned == "":
		return {"ok": false, "error": "Message is empty."}
	if cleaned.length() > MAX_TEXT_LENGTH:
		return {"ok": false, "error": "Message exceeds %d characters." % MAX_TEXT_LENGTH}
	return {"ok": true, "text": cleaned}


static func validate_map_payload(payload_value: Dictionary, kingdom_id: String) -> Dictionary:
	if payload_value.is_empty():
		return {"ok": false, "error": "Map location payload missing."}
	if not payload_value.has("x") or not payload_value.has("y"):
		return {"ok": false, "error": "Map location requires x and y."}
	if typeof(payload_value.get("x")) != TYPE_FLOAT and typeof(payload_value.get("x")) != TYPE_INT:
		return {"ok": false, "error": "Invalid map x coordinate."}
	if typeof(payload_value.get("y")) != TYPE_FLOAT and typeof(payload_value.get("y")) != TYPE_INT:
		return {"ok": false, "error": "Invalid map y coordinate."}
	var x: float = float(payload_value.get("x"))
	var y: float = float(payload_value.get("y"))
	if absf(x) > MAX_COORD or absf(y) > MAX_COORD:
		return {"ok": false, "error": "Map coordinates out of range."}
	var kid: String = str(payload_value.get("kingdom_id", kingdom_id)).strip_edges()
	if kid == "":
		return {"ok": false, "error": "Map location requires kingdom_id."}
	var label: String = str(payload_value.get("label", "Location")).strip_edges()
	if label.length() > MAX_LABEL_LENGTH:
		label = label.substr(0, MAX_LABEL_LENGTH)
	var out: Dictionary = {
		"kingdom_id": kid,
		"x": x,
		"y": y,
		"label": label if label != "" else "Location",
		"target_type": str(payload_value.get("target_type", "coord")).strip_edges(),
		"target_id": str(payload_value.get("target_id", "")).strip_edges(),
	}
	return {"ok": true, "payload": out}


static func validate_rally_payload(payload_value: Dictionary, kingdom_id: String) -> Dictionary:
	if payload_value.is_empty():
		return {"ok": false, "error": "Rally payload missing."}
	var kid: String = str(payload_value.get("kingdom_id", kingdom_id)).strip_edges()
	if kid == "":
		return {"ok": false, "error": "Rally requires kingdom_id."}
	var out: Dictionary = {
		"rally_id": str(payload_value.get("rally_id", "")).strip_edges(),
		"leader_user_id": str(payload_value.get("leader_user_id", "")).strip_edges(),
		"target_id": str(payload_value.get("target_id", "")).strip_edges(),
		"target_type": str(payload_value.get("target_type", "")).strip_edges(),
		"target_name": str(payload_value.get("target_name", "Rally Target")).strip_edges(),
		"kingdom_id": kid,
		"x": float(payload_value.get("x", 0.0)),
		"y": float(payload_value.get("y", 0.0)),
		"expiry_unix": int(payload_value.get("expiry_unix", 0)),
	}
	if out["target_name"].length() > MAX_LABEL_LENGTH:
		out["target_name"] = str(out["target_name"]).substr(0, MAX_LABEL_LENGTH)
	if absf(float(out["x"])) > MAX_COORD or absf(float(out["y"])) > MAX_COORD:
		return {"ok": false, "error": "Rally coordinates out of range."}
	return {"ok": true, "payload": out}


static func validate_parsed(msg: CrownspireChatMessage) -> Dictionary:
	if msg == null:
		return {"ok": false, "error": "null"}
	if msg.message_type == TYPE_TEXT or msg.message_type == TYPE_SYSTEM:
		if msg.text.strip_edges() == "" and msg.message_type == TYPE_TEXT:
			return {"ok": false, "error": "empty text"}
		if msg.text.length() > MAX_TEXT_LENGTH * 2:
			msg.text = msg.text.substr(0, MAX_TEXT_LENGTH * 2)
		return {"ok": true}
	if msg.message_type == TYPE_MAP_LOCATION:
		return validate_map_payload(msg.payload, msg.kingdom_id)
	if msg.message_type == TYPE_RALLY:
		return validate_rally_payload(msg.payload, msg.kingdom_id)
	return {"ok": true}


static func _parse_content_json(content_raw: String) -> Variant:
	if content_raw.strip_edges() == "":
		return null
	var json := JSON.new()
	if json.parse(content_raw) != OK:
		return null
	return json.data


static func _parse_nakama_time(raw: String) -> int:
	# Nakama create_time is typically RFC3339 / ISO-8601 UTC string.
	if raw == "":
		return 0
	# Prefer Godot parser when available.
	if raw.is_valid_int():
		return int(raw)
	var unix: int = int(Time.get_unix_time_from_datetime_string(raw))
	if unix > 0:
		return unix
	# Fallback: strip fractional seconds / Z
	var cleaned: String = raw.replace("Z", "").split(".")[0]
	cleaned = cleaned.replace("T", " ")
	unix = int(Time.get_unix_time_from_datetime_string(cleaned))
	return unix if unix > 0 else 0


static func _has(obj: Object, prop: String) -> bool:
	return obj != null and prop in obj


func is_system() -> bool:
	return message_type == TYPE_SYSTEM


func is_from_user(user_id: String) -> bool:
	return user_id != "" and sender_user_id == user_id


func format_timestamp_local() -> String:
	if timestamp_unix <= 0:
		return ""
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(timestamp_unix)
	var hour24: int = int(dt.get("hour", 0))
	var minute: int = int(dt.get("minute", 0))
	var am: bool = hour24 < 12
	var hour12: int = hour24 % 12
	if hour12 == 0:
		hour12 = 12
	return "%d:%02d %s" % [hour12, minute, "AM" if am else "PM"]
