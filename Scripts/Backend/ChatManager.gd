extends Node

## Crownspire ChatManager — Kingdom Chat + production-ready chat foundation.
## Depends on NakamaConnection for client/session/socket only.
## Does NOT treat local AllianceState as server-authoritative membership.

const ChatMessageScript = preload("res://scripts/Backend/ChatMessage.gd")
const ChatTranslationServiceScript = preload("res://scripts/Backend/ChatTranslationService.gd")

signal kingdom_joined(channel_id: String)
signal kingdom_join_failed(reason: String)
signal alliance_joined(channel_id: String)
signal alliance_join_failed(reason: String)
signal private_joined(peer_user_id: String, channel_id: String)
signal private_join_failed(reason: String)
signal messages_loaded(channel_kind: String)
signal message_received(message: RefCounted)
signal message_sent(message: RefCounted)
signal send_failed(reason: String)
signal availability_changed(available: bool)
signal moderation_event(kind: String, payload: Dictionary)
signal dm_unread_changed(total: int)

## Configurable development kingdom. Replace later with production kingdom assignment.
## Nakama Room name == kingdom_id (no extra prefix rewrite needed later).
const DEV_KINGDOM_ID: String = "kingdom_dev_001"

const HISTORY_PAGE_SIZE: int = 40
const CLIENT_SEND_COOLDOWN_MS: int = 1500
const MAX_PENDING_REPORTS: int = 100

const BLOCK_MUTE_PATH: String = "user://chat_moderation_local.cfg"
const DISPLAY_NAME_PATH: String = "user://chat_display_name.cfg"
const REPORTS_PATH: String = "user://chat_reports_pending.cfg"

## TEMPORARY local-only moderation stores. Migrate to account/backend later.
## Block/mute here are client filters only — not server punishment.

var translation_service: RefCounted = ChatTranslationServiceScript.new()

var _kingdom_id: String = DEV_KINGDOM_ID
var _kingdom_channel_id: String = ""
var _kingdom_room_name: String = ""
var _joined_kingdom: bool = false
var _joining: bool = false
var _history_cursor: String = ""
var _history_has_more: bool = false

var _alliance_channel_id: String = ""
var _alliance_group_id: String = ""
var _joined_alliance: bool = false
var _joining_alliance: bool = false
var _alliance_history_cursor: String = ""
var _alliance_history_has_more: bool = false
var _alliance_messages: Array[RefCounted] = []

## Private DirectMessage channels keyed by peer user_id.
var _dm_channel_ids: Dictionary = {} ## peer_uid -> channel_id
var _dm_messages: Dictionary = {} ## peer_uid -> Array[RefCounted]
var _dm_unread: Dictionary = {} ## peer_uid -> int
var _dm_display_names: Dictionary = {} ## peer_uid -> String
var _active_dm_peer: String = ""
var _joining_dm: bool = false

var _messages: Array[RefCounted] = [] ## ChatMessage kingdom
var _blocked_user_ids: Dictionary = {} ## user_id -> true
var _muted_user_ids: Dictionary = {} ## user_id -> true

var _last_send_ms: int = 0
var _last_send_fingerprint: String = ""
var _socket_bound: bool = false
var _display_name_cache: String = "" ## non-authoritative local fallback only
var _active_channel_kind: String = "kingdom"


func _nakama_connection() -> Node:
	return get_node_or_null("/root/NakamaConnection")


func _alliance_backend() -> Node:
	return get_node_or_null("/root/AllianceBackend")


func _nakama() -> Node:
	return get_node_or_null("/root/Nakama")


func _ready() -> void:
	if _kingdom_id.strip_edges() == "":
		_kingdom_id = DEV_KINGDOM_ID
	_load_moderation_local()
	_load_display_name()
	call_deferred("_bind_nakama_signals")
	_ready_smoke_maybe()


func get_kingdom_id() -> String:
	return _kingdom_id


func set_kingdom_id(kingdom_id: String) -> void:
	var cleaned: String = kingdom_id.strip_edges()
	if cleaned == "":
		return
	if cleaned == _kingdom_id:
		return
	_kingdom_id = cleaned
	_reset_kingdom_channel_state()


func get_kingdom_room_name(kingdom_id: String = "") -> String:
	var kid: String = kingdom_id.strip_edges()
	if kid == "":
		kid = _kingdom_id
	# Room name is the kingdom identifier itself.
	return kid


func is_chat_available() -> bool:
	var nc: Node = _nakama_connection()
	return nc != null and nc.is_authenticated() and nc.is_socket_connected()


func is_kingdom_joined() -> bool:
	return _joined_kingdom and _kingdom_channel_id != ""


func get_kingdom_channel_id() -> String:
	return _kingdom_channel_id


func get_messages() -> Array[RefCounted]:
	var out: Array[RefCounted] = []
	for m: RefCounted in _messages:
		if _should_render(m):
			out.append(m)
	return out


func get_history_has_more() -> bool:
	return _history_has_more


func get_local_user_id() -> String:
	var nc: Node = _nakama_connection()
	if nc != null:
		return nc.get_user_id()
	return ""


func get_display_name() -> String:
	## Prefer server-backed AllianceBackend profile display name.
	var ab: Node = _alliance_backend()
	if ab != null:
		var server_name: String = ab.get_display_name()
		if server_name != "":
			return server_name
	## Local cache is non-authoritative fallback only.
	if _display_name_cache != "":
		return _display_name_cache
	return "DevPlayer"


func set_display_name_dev(display_name: String) -> void:
	## Prefer server RPC when available.
	var ab_set: Node = _alliance_backend()
	var nc_set: Node = _nakama_connection()
	if ab_set != null and nc_set != null and nc_set.is_authenticated():
		ab_set.set_display_name(display_name)
		return
	var cleaned: String = display_name.strip_edges()
	if cleaned == "":
		return
	if cleaned.length() > 24:
		cleaned = cleaned.substr(0, 24)
	_display_name_cache = cleaned
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "display_name", cleaned)
	cfg.set_value("profile", "temporary_dev_only", true)
	cfg.set_value("profile", "non_authoritative_fallback", true)
	cfg.save(DISPLAY_NAME_PATH)


func get_server_alliance_tag() -> String:
	## Trusted multiplayer tag source = AllianceBackend (Nakama Groups).
	var ab: Node = _alliance_backend()
	if ab != null:
		return ab.get_alliance_tag()
	return ""


func get_claimed_alliance_tag() -> String:
	## Deprecated for authority. Kept as non-authoritative UI fallback only.
	return get_server_alliance_tag()


func is_alliance_chat_available() -> bool:
	var ab: Node = _alliance_backend()
	return is_chat_available() and ab != null and ab.is_in_backend_alliance()


func get_alliance_chat_unavailable_reason() -> String:
	if not is_chat_available():
		return "Disconnected — Alliance Chat unavailable."
	var ab_reason: Node = _alliance_backend()
	if ab_reason == null or not ab_reason.is_in_backend_alliance():
		return "You are not currently in an Alliance."
	return "Alliance Chat unavailable."


func is_alliance_joined() -> bool:
	return _joined_alliance and _alliance_channel_id != ""


func get_alliance_channel_id() -> String:
	return _alliance_channel_id


func get_alliance_messages() -> Array[RefCounted]:
	var out: Array[RefCounted] = []
	for m: RefCounted in _alliance_messages:
		if _should_render(m):
			out.append(m)
	return out


func get_alliance_history_has_more() -> bool:
	return _alliance_history_has_more


func ensure_kingdom_joined() -> void:
	_sync_kingdom_from_profile()
	if not is_chat_available():
		availability_changed.emit(false)
		kingdom_join_failed.emit("Nakama unavailable")
		return
	if _joined_kingdom and _kingdom_channel_id != "":
		return
	await join_kingdom_chat()


func ensure_alliance_joined() -> void:
	if not is_alliance_chat_available():
		_reset_alliance_channel_state()
		alliance_join_failed.emit(get_alliance_chat_unavailable_reason())
		return
	var ab: Node = _alliance_backend()
	var group_id: String = ab.get_alliance_id() if ab != null else ""
	if _joined_alliance and _alliance_channel_id != "" and _alliance_group_id == group_id:
		return
	await join_alliance_chat()


func join_kingdom_chat() -> Dictionary:
	if _joining:
		return {"ok": false, "error": "Join already in progress."}
	if not is_chat_available():
		availability_changed.emit(false)
		var err := "Nakama unavailable"
		kingdom_join_failed.emit(err)
		return {"ok": false, "error": err}

	_sync_kingdom_from_profile()
	_joining = true
	_bind_socket_message_handler()

	var nc: Node = _nakama_connection()
	var socket: NakamaSocket = nc.get_socket() if nc != null else null
	if socket == null:
		_joining = false
		var err2 := "Nakama unavailable"
		kingdom_join_failed.emit(err2)
		return {"ok": false, "error": err2}
	var room: String = get_kingdom_room_name()
	_kingdom_room_name = room

	var channel: NakamaRTAPI.Channel = await socket.join_chat_async(
		room,
		NakamaSocket.ChannelType.Room,
		true, ## persistence — Nakama stores history
		false
	)
	_joining = false

	if channel == null or channel.is_exception():
		var reason: String = "Failed to join kingdom chat"
		if channel != null and channel.get_exception() != null:
			reason = str(channel.get_exception().message)
		kingdom_join_failed.emit(reason)
		return {"ok": false, "error": reason}

	_kingdom_channel_id = str(channel.id)
	_joined_kingdom = true
	availability_changed.emit(true)
	print("[Chat] Joined kingdom room '%s' channel_id=%s" % [room, _kingdom_channel_id])
	kingdom_joined.emit(_kingdom_channel_id)

	await load_kingdom_history(true)
	return {"ok": true, "channel_id": _kingdom_channel_id, "room": room}


func join_alliance_chat() -> Dictionary:
	## Secure Alliance Chat: Group channel ID comes ONLY from server-backed membership.
	if _joining_alliance:
		return {"ok": false, "error": "Alliance join already in progress."}
	if not is_alliance_chat_available():
		var reason := get_alliance_chat_unavailable_reason()
		alliance_join_failed.emit(reason)
		return {"ok": false, "error": reason}

	var ab_join: Node = _alliance_backend()
	var group_id: String = ab_join.get_alliance_id().strip_edges() if ab_join != null else ""
	if group_id == "":
		var reason2 := "You are not currently in an Alliance."
		alliance_join_failed.emit(reason2)
		return {"ok": false, "error": reason2}

	_joining_alliance = true
	_bind_socket_message_handler()
	var nc_a: Node = _nakama_connection()
	var socket: NakamaSocket = nc_a.get_socket() if nc_a != null else null
	if socket == null:
		_joining_alliance = false
		var reason3 := "Nakama unavailable"
		alliance_join_failed.emit(reason3)
		return {"ok": false, "error": reason3}
	var channel: NakamaRTAPI.Channel = await socket.join_chat_async(
		group_id,
		NakamaSocket.ChannelType.Group,
		true,
		false
	)
	_joining_alliance = false

	if channel == null or channel.is_exception():
		var fail: String = "Failed to join alliance chat"
		if channel != null and channel.get_exception() != null:
			fail = str(channel.get_exception().message)
		_reset_alliance_channel_state()
		alliance_join_failed.emit(fail)
		return {"ok": false, "error": fail}

	_alliance_group_id = group_id
	_alliance_channel_id = str(channel.id)
	_joined_alliance = true
	print("[Chat] Joined alliance group chat group_id=%s channel_id=%s" % [group_id, _alliance_channel_id])
	alliance_joined.emit(_alliance_channel_id)
	await load_alliance_history(true)
	return {"ok": true, "channel_id": _alliance_channel_id, "group_id": group_id}


func join_private_chat(peer_user_id: String, peer_display_name: String = "") -> Dictionary:
	## Nakama DirectMessage channel with the other player's user id.
	var peer: String = peer_user_id.strip_edges()
	if peer == "":
		return {"ok": false, "error": "Missing player id."}
	if peer == get_local_user_id():
		return {"ok": false, "error": "Cannot message yourself."}
	if is_blocked(peer):
		return {"ok": false, "error": "Player is blocked."}
	if _joining_dm:
		return {"ok": false, "error": "Private join already in progress."}
	if not is_chat_available():
		var err := "Nakama unavailable"
		private_join_failed.emit(err)
		return {"ok": false, "error": err}

	if peer_display_name.strip_edges() != "":
		_dm_display_names[peer] = peer_display_name.strip_edges()

	if _dm_channel_ids.has(peer) and str(_dm_channel_ids[peer]) != "":
		_active_dm_peer = peer
		_clear_dm_unread(peer)
		private_joined.emit(peer, str(_dm_channel_ids[peer]))
		await load_private_history(peer, true)
		return {"ok": true, "channel_id": str(_dm_channel_ids[peer]), "peer_user_id": peer}

	_joining_dm = true
	_bind_socket_message_handler()
	var nc: Node = _nakama_connection()
	var socket: NakamaSocket = nc.get_socket() if nc != null else null
	if socket == null:
		_joining_dm = false
		var err2 := "Nakama unavailable"
		private_join_failed.emit(err2)
		return {"ok": false, "error": err2}

	var channel: NakamaRTAPI.Channel = await socket.join_chat_async(
		peer,
		NakamaSocket.ChannelType.DirectMessage,
		true, ## persistence — store conversation history
		false
	)
	_joining_dm = false
	if channel == null or channel.is_exception():
		var fail: String = "Failed to open private chat"
		if channel != null and channel.get_exception() != null:
			fail = str(channel.get_exception().message)
		private_join_failed.emit(fail)
		return {"ok": false, "error": fail}

	var channel_id: String = str(channel.id)
	_dm_channel_ids[peer] = channel_id
	if not _dm_messages.has(peer):
		_dm_messages[peer] = [] as Array[RefCounted]
	_active_dm_peer = peer
	_clear_dm_unread(peer)
	print("[Chat] Joined private DM peer=%s channel_id=%s" % [peer, channel_id])
	private_joined.emit(peer, channel_id)
	await load_private_history(peer, true)
	return {"ok": true, "channel_id": channel_id, "peer_user_id": peer}


func ensure_private_joined(peer_user_id: String, peer_display_name: String = "") -> Dictionary:
	return await join_private_chat(peer_user_id, peer_display_name)


func load_private_history(peer_user_id: String, reset: bool = false) -> Dictionary:
	var peer: String = peer_user_id.strip_edges()
	var channel_id: String = str(_dm_channel_ids.get(peer, ""))
	if not is_chat_available() or channel_id == "":
		return {"ok": false, "error": "Not joined"}
	var nc_h: Node = _nakama_connection()
	var client: NakamaClient = nc_h.get_client() if nc_h != null else null
	var session: NakamaSession = nc_h.get_session() if nc_h != null else null
	if client == null or session == null:
		return {"ok": false, "error": "Missing client/session"}

	var result: NakamaAPI.ApiChannelMessageList = await client.list_channel_messages_async(
		session, channel_id, HISTORY_PAGE_SIZE, true, null
	)
	if result == null or result.is_exception():
		var reason: String = "Failed to load private history"
		if result != null and result.get_exception() != null:
			reason = str(result.get_exception().message)
		return {"ok": false, "error": reason}

	var incoming: Array = []
	if "messages" in result:
		incoming = result.messages
	var parsed: Array[RefCounted] = []
	for raw in incoming:
		var msg: RefCounted = ChatMessageScript.from_nakama_channel_message(raw, _kingdom_id)
		parsed.append(msg)
	parsed.reverse()
	if reset or not _dm_messages.has(peer):
		_dm_messages[peer] = parsed
	else:
		var merged: Array[RefCounted] = []
		merged.append_array(parsed)
		merged.append_array(_dm_messages[peer])
		_dm_messages[peer] = merged
	messages_loaded.emit("private")
	return {"ok": true, "count": parsed.size()}


func get_private_messages(peer_user_id: String = "") -> Array[RefCounted]:
	var peer: String = peer_user_id.strip_edges()
	if peer == "":
		peer = _active_dm_peer
	var out: Array[RefCounted] = []
	if not _dm_messages.has(peer):
		return out
	for m in _dm_messages[peer]:
		if _should_render(m):
			out.append(m)
	return out


func get_active_dm_peer() -> String:
	return _active_dm_peer


func get_dm_display_name(peer_user_id: String) -> String:
	return str(_dm_display_names.get(peer_user_id.strip_edges(), "Player"))


func set_active_dm_peer(peer_user_id: String) -> void:
	_active_dm_peer = peer_user_id.strip_edges()
	if _active_dm_peer != "":
		_clear_dm_unread(_active_dm_peer)


func get_dm_unread_total() -> int:
	var total: int = 0
	for k in _dm_unread.keys():
		total += int(_dm_unread[k])
	return total


func _clear_dm_unread(peer: String) -> void:
	if _dm_unread.has(peer):
		_dm_unread[peer] = 0
		dm_unread_changed.emit(get_dm_unread_total())


func _peer_for_dm_channel(channel_id: String) -> String:
	for peer in _dm_channel_ids.keys():
		if str(_dm_channel_ids[peer]) == channel_id:
			return str(peer)
	return ""


func load_kingdom_history(reset: bool = false) -> Dictionary:
	return await _load_history("kingdom", reset)


func load_alliance_history(reset: bool = false) -> Dictionary:
	return await _load_history("alliance", reset)


func _load_history(kind: String, reset: bool = false) -> Dictionary:
	var channel_id: String = _kingdom_channel_id if kind == "kingdom" else _alliance_channel_id
	if not is_chat_available() or channel_id == "":
		return {"ok": false, "error": "Not joined"}
	var nc_h: Node = _nakama_connection()
	var client: NakamaClient = nc_h.get_client() if nc_h != null else null
	var session: NakamaSession = nc_h.get_session() if nc_h != null else null
	if client == null or session == null:
		return {"ok": false, "error": "Missing client/session"}

	var cursor = null
	if kind == "kingdom":
		if not reset and _history_cursor != "":
			cursor = _history_cursor
	else:
		if not reset and _alliance_history_cursor != "":
			cursor = _alliance_history_cursor

	var result: NakamaAPI.ApiChannelMessageList = await client.list_channel_messages_async(
		session,
		channel_id,
		HISTORY_PAGE_SIZE,
		false,
		cursor
	)
	if result == null or result.is_exception():
		var reason: String = "History load failed"
		if result != null and result.get_exception() != null:
			reason = str(result.get_exception().message)
		return {"ok": false, "error": reason}

	var incoming: Array = []
	if "messages" in result:
		incoming = result.messages

	var parsed: Array[RefCounted] = []
	for raw in incoming:
		var msg: RefCounted = ChatMessageScript.from_nakama_channel_message(raw, _kingdom_id)
		parsed.append(msg)
	parsed.reverse()

	if kind == "kingdom":
		if reset:
			_messages.clear()
			_messages.append_array(parsed)
		else:
			var merged: Array[RefCounted] = []
			merged.append_array(parsed)
			merged.append_array(_messages)
			_messages = merged
		_history_cursor = str(result.next_cursor) if str(result.next_cursor) != "" else ""
		_history_has_more = _history_cursor != ""
	else:
		if reset:
			_alliance_messages.clear()
			_alliance_messages.append_array(parsed)
		else:
			var merged_a: Array[RefCounted] = []
			merged_a.append_array(parsed)
			merged_a.append_array(_alliance_messages)
			_alliance_messages = merged_a
		_alliance_history_cursor = str(result.next_cursor) if str(result.next_cursor) != "" else ""
		_alliance_history_has_more = _alliance_history_cursor != ""

	messages_loaded.emit(kind)
	return {"ok": true, "count": parsed.size(), "has_more": true if kind == "alliance" and _alliance_history_has_more else _history_has_more}


func send_text_message(text_value: String, channel_kind: String = "kingdom") -> Dictionary:
	var validated: Dictionary = ChatMessageScript.validate_outbound_text(text_value)
	if not bool(validated.get("ok", false)):
		send_failed.emit(str(validated.get("error", "Invalid message")))
		return validated
	return await _send_structured(
		ChatMessageScript.TYPE_TEXT,
		str(validated.get("text", "")),
		{},
		channel_kind
	)


func send_map_location(payload_value: Dictionary, channel_kind: String = "kingdom") -> Dictionary:
	var validated: Dictionary = ChatMessageScript.validate_map_payload(payload_value, _kingdom_id)
	if not bool(validated.get("ok", false)):
		send_failed.emit(str(validated.get("error", "Invalid location")))
		return validated
	var payload: Dictionary = validated.get("payload", {})
	var label: String = str(payload.get("label", "Location"))
	var text_value: String = "%s (X:%.0f Y:%.0f)" % [label, float(payload.get("x", 0.0)), float(payload.get("y", 0.0))]
	return await _send_structured(ChatMessageScript.TYPE_MAP_LOCATION, text_value, payload, channel_kind)


func send_rally_preview(payload_value: Dictionary, channel_kind: String = "kingdom") -> Dictionary:
	## Schema/render foundation only — does NOT create or join server rallies.
	var validated: Dictionary = ChatMessageScript.validate_rally_payload(payload_value, _kingdom_id)
	if not bool(validated.get("ok", false)):
		send_failed.emit(str(validated.get("error", "Invalid rally payload")))
		return validated
	var payload: Dictionary = validated.get("payload", {})
	var text_value: String = "Rally: %s" % str(payload.get("target_name", "Target"))
	return await _send_structured(ChatMessageScript.TYPE_RALLY, text_value, payload, channel_kind)


func request_translate(message: RefCounted) -> Dictionary:
	if message == null:
		return {"ok": false, "error": "No message"}
	if str(message.message_type) == ChatMessageScript.TYPE_SYSTEM:
		return {"ok": false, "error": "System messages cannot be translated."}
	return translation_service.translate_text(str(message.text))


func block_user(user_id: String) -> Dictionary:
	var uid: String = user_id.strip_edges()
	if uid == "" or uid == get_local_user_id():
		return {"ok": false, "error": "Cannot block this user."}
	_blocked_user_ids[uid] = true
	_save_moderation_local()
	moderation_event.emit("block", {"user_id": uid})
	messages_loaded.emit("kingdom")
	return {"ok": true}


func unblock_user(user_id: String) -> Dictionary:
	var uid: String = user_id.strip_edges()
	_blocked_user_ids.erase(uid)
	_save_moderation_local()
	moderation_event.emit("unblock", {"user_id": uid})
	messages_loaded.emit("kingdom")
	return {"ok": true}


func mute_user(user_id: String) -> Dictionary:
	var uid: String = user_id.strip_edges()
	if uid == "" or uid == get_local_user_id():
		return {"ok": false, "error": "Cannot mute this user."}
	_muted_user_ids[uid] = true
	_save_moderation_local()
	moderation_event.emit("mute", {"user_id": uid})
	messages_loaded.emit("kingdom")
	return {"ok": true}


func unmute_user(user_id: String) -> Dictionary:
	var uid: String = user_id.strip_edges()
	_muted_user_ids.erase(uid)
	_save_moderation_local()
	moderation_event.emit("unmute", {"user_id": uid})
	messages_loaded.emit("kingdom")
	return {"ok": true}


func is_blocked(user_id: String) -> bool:
	return _blocked_user_ids.has(user_id)


func is_muted(user_id: String) -> bool:
	return _muted_user_ids.has(user_id)


func submit_report(message: RefCounted, reason: String) -> Dictionary:
	## Reporting does NOT mute/ban/delete the other player.
	## Uses server RPC crownspire_chat_report. Reporter identity comes from auth context.
	if message == null:
		return {"ok": false, "error": "No message to report."}
	if str(message.message_type) == ChatMessageScript.TYPE_SYSTEM:
		return {"ok": false, "error": "System messages cannot be reported."}
	if get_local_user_id() == "":
		return {"ok": false, "error": "Not authenticated."}
	var cleaned_reason: String = reason.strip_edges()
	if cleaned_reason == "":
		return {"ok": false, "error": "Report reason required."}

	var report: Dictionary = {
		"message_id": str(message.message_id),
		"reported_user_id": str(message.sender_user_id),
		"channel_id": str(message.channel_id),
		"message_type": str(message.message_type),
		"message_text": str(message.text),
		"create_time": str(message.create_time_raw),
		"reason": cleaned_reason,
	}

	var ab_report: Node = _alliance_backend()
	if ab_report != null:
		var result: Dictionary = await ab_report.submit_chat_report(report)
		if bool(result.get("ok", false)):
			moderation_event.emit("report", result)
			print("[Chat] REPORT accepted report_id=%s" % str(result.get("report_id", "")))
			return result
		return result

	## Fallback local queue if runtime unavailable.
	report["status"] = "local_fallback_queue"
	_persist_pending_report(report)
	moderation_event.emit("report", report)
	return {"ok": false, "error": "AllianceBackend unavailable; report queued locally only."}


func navigate_to_map_location(payload_value: Dictionary) -> Dictionary:
	var validated: Dictionary = ChatMessageScript.validate_map_payload(payload_value, _kingdom_id)
	if not bool(validated.get("ok", false)):
		return validated
	var payload: Dictionary = validated.get("payload", {})
	var msg_kingdom: String = str(payload.get("kingdom_id", "")).strip_edges()
	if msg_kingdom != "" and _kingdom_id != "" and msg_kingdom != _kingdom_id:
		return {
			"ok": false,
			"error": "That location is in another kingdom.",
			"navigated": false,
		}

	var world_pos := Vector2(float(payload.get("x")), float(payload.get("y")))
	world_pos = _clamp_world_map_pos(world_pos)

	# Close chat / clear UIManager screen so world input works.
	var hud: Node = _find_game_hud()
	if hud != null:
		var mgr: Node = hud.get_node_or_null("UIManager")
		if mgr != null and mgr.has_method("close_current_screen"):
			mgr.call("close_current_screen")

	# Ensure World Map is active.
	if not _is_on_world_map():
		if get_tree() == null:
			return {"ok": false, "error": "Unable to open World Map.", "navigated": false}
		get_tree().change_scene_to_file("res://Scenes/World/KingdomMap.tscn")
		var ready: bool = await _wait_for_world_camera(6.0)
		if not ready:
			return {"ok": false, "error": "World Map is still loading. Try again.", "navigated": false}

	var camera := _find_map_camera()
	if camera == null or not camera.has_method("focus_world_position"):
		return {
			"ok": false,
			"error": "World Map camera unavailable.",
			"navigated": false,
			"world_pos": world_pos,
		}
	camera.call("focus_world_position", world_pos)
	_spawn_location_ping(world_pos)
	return {"ok": true, "navigated": true, "world_pos": world_pos}


func _clamp_world_map_pos(pos: Vector2) -> Vector2:
	const MARGIN := 64.0
	const SIZE := 8192.0
	return Vector2(clampf(pos.x, MARGIN, SIZE - MARGIN), clampf(pos.y, MARGIN, SIZE - MARGIN))


func _is_on_world_map() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var scene := tree.current_scene
	if scene == null:
		return false
	return str(scene.name) == "KingdomMap" or scene.get_node_or_null("PlayerCastleMarker") != null


func _wait_for_world_camera(timeout_sec: float) -> bool:
	var elapsed: float = 0.0
	while elapsed < timeout_sec:
		if not is_inside_tree():
			return false
		if _find_map_camera() != null:
			# Allow MapCamera _ready clamp to finish.
			await get_tree().process_frame
			await get_tree().process_frame
			return true
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	return false


func _find_game_hud() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var group := tree.get_nodes_in_group("game_hud")
	if not group.is_empty():
		return group[0]
	return tree.root.find_child("GameHUD", true, false)


func _spawn_location_ping(world_pos: Vector2) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var scene: Node = tree.current_scene
	var existing: Node = scene.get_node_or_null("LocationPing")
	if existing != null:
		existing.queue_free()
	var ping := Node2D.new()
	ping.name = "LocationPing"
	ping.z_index = 40
	ping.global_position = world_pos
	scene.add_child(ping)
	var ring := Polygon2D.new()
	ring.color = Color(0.35, 0.75, 1.0, 0.55)
	ring.polygon = PackedVector2Array([
		Vector2(-28, 0), Vector2(0, -28), Vector2(28, 0), Vector2(0, 28),
	])
	ping.add_child(ring)
	var tween := ping.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(2.2, 2.2), 1.1)
	tween.tween_property(ring, "modulate:a", 0.0, 1.1)
	tween.chain().tween_callback(ping.queue_free)


func _find_map_camera() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene: Node = tree.current_scene
	if scene != null:
		var cam: Node = scene.get_node_or_null("Camera2D")
		if cam != null and cam.has_method("focus_world_position"):
			return cam
		var named: Node = scene.get_node_or_null("MapCamera")
		if named != null and named.has_method("focus_world_position"):
			return named
	var root := tree.get_root()
	if root == null:
		return null
	# Prefer live KingdomMap Camera2D over any leftover city camera.
	var cameras: Array[Node] = []
	_collect_cameras(root, cameras)
	for c in cameras:
		if c.has_method("focus_world_position") and str(c.get_path()).find("KingdomMap") >= 0:
			return c
	for c in cameras:
		if c.has_method("focus_world_position") and str(c.name) in ["Camera2D", "MapCamera"]:
			# Prefer map-sized limit cameras.
			if "map_size" in c or c.get("limit_right") == 8192:
				return c
	for c in cameras:
		if c.has_method("focus_world_position"):
			return c
	return root.find_child("MapCamera", true, false)


func _collect_cameras(node: Node, out: Array[Node]) -> void:
	if node is Camera2D:
		out.append(node)
	for child in node.get_children():
		_collect_cameras(child, out)


## Debug helper: second identity uses CROWNSPIR_NAKAMA_DEVICE_SLOT=2 (see NakamaConnection).
func debug_describe_identity() -> Dictionary:
	return {
		"user_id": get_local_user_id(),
		"display_name": get_display_name(),
		"kingdom_id": _kingdom_id,
		"room": get_kingdom_room_name(),
		"channel_id": _kingdom_channel_id,
		"device_slot": OS.get_environment("CROWNSPIR_NAKAMA_DEVICE_SLOT"),
	}


func _send_structured(
	message_type: String,
	text_value: String,
	payload_value: Dictionary,
	channel_kind: String = "kingdom"
) -> Dictionary:
	var channel_id: String = _kingdom_channel_id
	if channel_kind == "alliance":
		if not is_alliance_joined():
			var err_a := "Alliance Chat unavailable"
			send_failed.emit(err_a)
			return {"ok": false, "error": err_a}
		channel_id = _alliance_channel_id
	elif channel_kind == "private":
		var peer: String = _active_dm_peer
		channel_id = str(_dm_channel_ids.get(peer, ""))
		if peer == "" or channel_id == "":
			var err_p := "Private chat unavailable"
			send_failed.emit(err_p)
			return {"ok": false, "error": err_p}
	elif not is_chat_available() or not is_kingdom_joined():
		var err := "Chat unavailable"
		send_failed.emit(err)
		return {"ok": false, "error": err}

	var now_ms: int = Time.get_ticks_msec()
	var fingerprint: String = "%s|%s|%s|%s" % [channel_kind, message_type, text_value, JSON.stringify(payload_value)]
	if now_ms - _last_send_ms < CLIENT_SEND_COOLDOWN_MS:
		var err2 := "Please wait a moment before sending again."
		send_failed.emit(err2)
		return {"ok": false, "error": err2, "rate_limited": true}
	if fingerprint == _last_send_fingerprint and now_ms - _last_send_ms < CLIENT_SEND_COOLDOWN_MS * 2:
		var err3 := "Duplicate send blocked."
		send_failed.emit(err3)
		return {"ok": false, "error": err3, "duplicate": true}

	## Client cooldown is UX only. Server RPCs for report/name/alliance are rate-limited.
	## Chat message flood protection for production should add a runtime beforeHook later.

	var content: Dictionary = ChatMessageScript.build_outbound_content(
		message_type,
		text_value,
		get_display_name(),
		get_server_alliance_tag(), ## server-backed tag (may be empty)
		payload_value,
		{
			"client_schema": ChatMessageScript.SCHEMA_VERSION,
			"tag_authority": "alliance_backend",
			"display_name_authority": "alliance_backend",
		},
		_kingdom_id
	)

	var nc_send: Node = _nakama_connection()
	var socket: NakamaSocket = nc_send.get_socket() if nc_send != null else null
	if socket == null:
		var err_sock := "Chat unavailable"
		send_failed.emit(err_sock)
		return {"ok": false, "error": err_sock}
	var ack = await socket.write_chat_message_async(channel_id, content)
	if ack == null or ack.is_exception():
		var reason: String = "Send failed"
		if ack != null and ack.get_exception() != null:
			reason = str(ack.get_exception().message)
		send_failed.emit(reason)
		return {"ok": false, "error": reason}

	_last_send_ms = now_ms
	_last_send_fingerprint = fingerprint

	var echo := ChatMessageScript.new()
	echo.message_id = str(ack.message_id) if ("message_id" in ack) else ""
	echo.channel_id = channel_id
	echo.kingdom_id = _kingdom_id
	echo.sender_user_id = get_local_user_id()
	echo.sender_display_name = get_display_name()
	echo.sender_alliance_tag = get_server_alliance_tag()
	echo.timestamp_unix = int(Time.get_unix_time_from_system())
	echo.create_time_raw = str(ack.create_time) if ("create_time" in ack) else ""
	if echo.create_time_raw != "":
		echo.timestamp_unix = ChatMessageScript._parse_nakama_time(echo.create_time_raw)
	echo.message_type = message_type
	echo.text = text_value
	echo.payload = payload_value.duplicate(true)
	echo.is_persistent = true
	_append_message(echo, channel_kind)
	message_sent.emit(echo)
	return {"ok": true, "message_id": echo.message_id}


func _bind_nakama_signals() -> void:
	var nc: Node = _nakama_connection()
	if nc == null:
		return
	if not nc.socket_connected.is_connected(_on_socket_connected):
		nc.socket_connected.connect(_on_socket_connected)
	if not nc.connection_failed.is_connected(_on_connection_failed):
		nc.connection_failed.connect(_on_connection_failed)
	var ab: Node = _alliance_backend()
	if ab != null:
		if not ab.profile_changed.is_connected(_on_profile_changed):
			ab.profile_changed.connect(_on_profile_changed)
		if not ab.alliance_changed.is_connected(_on_alliance_membership_changed):
			ab.alliance_changed.connect(_on_alliance_membership_changed)
	if nc.is_socket_connected():
		_on_socket_connected()


func _on_socket_connected() -> void:
	availability_changed.emit(true)
	_bind_socket_message_handler()
	_sync_kingdom_from_profile()
	## Rejoin after connect/reconnect — channel IDs can go stale when the socket drops.
	_joined_kingdom = false
	_kingdom_channel_id = ""
	join_kingdom_chat()
	var ab: Node = _alliance_backend()
	if ab != null and ab.has_method("is_in_backend_alliance") and ab.is_in_backend_alliance():
		_joined_alliance = false
		_alliance_channel_id = ""
		join_alliance_chat()


func _on_connection_failed(_reason: String) -> void:
	_reset_kingdom_channel_state()
	_reset_alliance_channel_state()
	availability_changed.emit(false)


func _on_profile_changed(_profile: Dictionary) -> void:
	_sync_kingdom_from_profile()


func _on_alliance_membership_changed(_alliance: Dictionary) -> void:
	var ab: Node = _alliance_backend()
	var group_id: String = ab.get_alliance_id() if ab != null else ""
	if group_id == "":
		_reset_alliance_channel_state()
		messages_loaded.emit("alliance")
		return
	if _alliance_group_id != "" and _alliance_group_id != group_id:
		_reset_alliance_channel_state()
	## Soft rejoin when membership becomes available.
	if is_alliance_chat_available() and not is_alliance_joined():
		join_alliance_chat()


func _sync_kingdom_from_profile() -> void:
	var ab: Node = _alliance_backend()
	if ab != null:
		var kid: String = ab.get_kingdom_id().strip_edges()
		if kid != "":
			if kid != _kingdom_id:
				_kingdom_id = kid
				_reset_kingdom_channel_state()


func _bind_socket_message_handler() -> void:
	var nc: Node = _nakama_connection()
	if nc == null:
		return
	var socket: NakamaSocket = nc.get_socket()
	if socket == null:
		return
	if not socket.received_channel_message.is_connected(_on_channel_message):
		socket.received_channel_message.connect(_on_channel_message)
	_socket_bound = true


func _on_channel_message(raw) -> void:
	if raw == null:
		return
	var channel_id: String = str(raw.channel_id) if ("channel_id" in raw) else ""
	var kind: String = ""
	var dm_peer: String = ""
	if channel_id != "" and channel_id == _kingdom_channel_id:
		kind = "kingdom"
	elif channel_id != "" and channel_id == _alliance_channel_id:
		kind = "alliance"
	else:
		dm_peer = _peer_for_dm_channel(channel_id)
		if dm_peer == "":
			return
		kind = "private"
	var msg: RefCounted = ChatMessageScript.from_nakama_channel_message(raw, _kingdom_id)
	_append_message(msg, kind, dm_peer)
	if kind == "private" and dm_peer != "" and dm_peer != _active_dm_peer:
		_dm_unread[dm_peer] = int(_dm_unread.get(dm_peer, 0)) + 1
		dm_unread_changed.emit(get_dm_unread_total())
	if _should_render(msg):
		message_received.emit(msg)


func _append_message(msg: RefCounted, channel_kind: String = "kingdom", dm_peer: String = "") -> void:
	if msg == null:
		return
	var bucket: Array[RefCounted]
	if channel_kind == "private":
		var peer: String = dm_peer if dm_peer != "" else _active_dm_peer
		if peer == "":
			return
		if not _dm_messages.has(peer):
			_dm_messages[peer] = [] as Array[RefCounted]
		bucket = _dm_messages[peer]
	elif channel_kind == "alliance":
		bucket = _alliance_messages
	else:
		bucket = _messages
	var mid: String = str(msg.message_id)
	if mid != "":
		for existing: RefCounted in bucket:
			if str(existing.message_id) == mid:
				return
	bucket.append(msg)
	if bucket.size() > 300:
		bucket = bucket.slice(bucket.size() - 300, bucket.size())
	if channel_kind == "private":
		var peer2: String = dm_peer if dm_peer != "" else _active_dm_peer
		_dm_messages[peer2] = bucket
	elif channel_kind == "kingdom":
		_messages = bucket
	else:
		_alliance_messages = bucket


func _should_render(msg: RefCounted) -> bool:
	if msg == null:
		return false
	if str(msg.message_type) == ChatMessageScript.TYPE_SYSTEM:
		return true
	var uid: String = str(msg.sender_user_id)
	if uid != "" and is_blocked(uid):
		return false
	if uid != "" and is_muted(uid):
		return false
	return true


func _reset_kingdom_channel_state() -> void:
	_joined_kingdom = false
	_joining = false
	_kingdom_channel_id = ""
	_kingdom_room_name = ""
	_history_cursor = ""
	_history_has_more = false
	_messages.clear()


func _reset_alliance_channel_state() -> void:
	_joined_alliance = false
	_joining_alliance = false
	_alliance_channel_id = ""
	_alliance_group_id = ""
	_alliance_history_cursor = ""
	_alliance_history_has_more = false
	_alliance_messages.clear()


func _load_display_name() -> void:
	## Local fallback only — server profile overrides via AllianceBackend.
	var cfg := ConfigFile.new()
	if cfg.load(DISPLAY_NAME_PATH) == OK:
		_display_name_cache = str(cfg.get_value("profile", "display_name", "")).strip_edges()
	if _display_name_cache == "":
		var slot: String = OS.get_environment("CROWNSPIR_NAKAMA_DEVICE_SLOT").strip_edges()
		if slot != "" and slot != "1":
			_display_name_cache = "DevPlayer_%s" % slot
		else:
			_display_name_cache = "DevPlayer"


func _load_moderation_local() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(BLOCK_MUTE_PATH) != OK:
		return
	var blocked: PackedStringArray = PackedStringArray(cfg.get_value("moderation", "blocked", PackedStringArray()))
	var muted: PackedStringArray = PackedStringArray(cfg.get_value("moderation", "muted", PackedStringArray()))
	_blocked_user_ids.clear()
	_muted_user_ids.clear()
	for id in blocked:
		_blocked_user_ids[str(id)] = true
	for id in muted:
		_muted_user_ids[str(id)] = true


func _save_moderation_local() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("moderation", "blocked", PackedStringArray(_blocked_user_ids.keys()))
	cfg.set_value("moderation", "muted", PackedStringArray(_muted_user_ids.keys()))
	cfg.set_value("moderation", "temporary_local_only", true)
	cfg.save(BLOCK_MUTE_PATH)


func _persist_pending_report(report: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(REPORTS_PATH)
	var raw: String = str(cfg.get_value("reports", "pending_json", "[]"))
	var parsed: Variant = JSON.parse_string(raw)
	var list: Array = parsed if typeof(parsed) == TYPE_ARRAY else []
	list.append(report)
	while list.size() > MAX_PENDING_REPORTS:
		list.remove_at(0)
	cfg.set_value("reports", "pending_json", JSON.stringify(list))
	cfg.set_value("reports", "backend_todo", "crownspire_chat_report RPC")
	cfg.save(REPORTS_PATH)


func _ready_smoke_maybe() -> void:
	var phase3: String = OS.get_environment("CROWNSPIR_PHASE3_SMOKE").strip_edges()
	var phase2: String = OS.get_environment("CROWNSPIR_CHAT_SMOKE").strip_edges()
	print("[ChatManager] smoke env CHAT=%s PHASE3=%s" % [phase2, phase3])
	if phase2 == "1":
		call_deferred("_run_smoke_deferred")
	elif phase3 == "1":
		call_deferred("_run_phase3_smoke_deferred")


func _run_smoke_deferred() -> void:
	await get_tree().create_timer(1.5).timeout
	await run_phase2_smoke_test()


func _run_phase3_smoke_deferred() -> void:
	print("[Phase3Smoke] deferred start — waiting for Nakama/profile")
	await get_tree().create_timer(1.5).timeout
	var passed: bool = await run_phase3_alliance_smoke_test()
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(0 if passed else 1)


func run_phase2_smoke_test() -> bool:
	## Two-user Kingdom Chat verification. Does not destroy primary device account.
	print("[ChatSmoke] BEGIN")
	var fails: Array[String] = []

	# Wait for primary NakamaConnection socket.
	for _i in 40:
		if is_chat_available():
			break
		await get_tree().create_timer(0.25).timeout
	if not is_chat_available():
		print("[ChatSmoke] FAIL primary Nakama unavailable")
		return false

	var join_a: Dictionary = await join_kingdom_chat()
	if not bool(join_a.get("ok", false)):
		fails.append("A join failed: %s" % join_a.get("error"))

	var token_a: String = "smokeA-%d" % int(Time.get_unix_time_from_system())
	var send_a: Dictionary = await send_text_message("Hello kingdom %s" % token_a)
	if not bool(send_a.get("ok", false)):
		fails.append("A send failed: %s" % send_a.get("error"))

	# Second identity via fresh client (not ChatManager singleton).
	var nakama: Node = _nakama()
	if nakama == null:
		fails.append("Nakama autoload missing")
		_print_smoke_result(fails)
		return false
	var client_b: NakamaClient = nakama.create_client("defaultkey", "127.0.0.1", 7350, "http", 3, NakamaLogger.LOG_LEVEL.ERROR)
	client_b.auto_retry = false
	var device_b: String = "crownspire-smoke-b-%s" % str(int(Time.get_unix_time_from_system()))
	var session_b: NakamaSession = await client_b.authenticate_device_async(device_b)
	if session_b == null or session_b.is_exception():
		fails.append("B auth failed")
		_print_smoke_result(fails)
		return false
	var socket_b: NakamaSocket = nakama.create_socket_from(client_b)
	var sock_res = await socket_b.connect_async(session_b)
	if sock_res == null or sock_res.is_exception() or not socket_b.is_connected_to_host():
		fails.append("B socket failed")
		_print_smoke_result(fails)
		return false

	var received_b: Array[String] = []
	socket_b.received_channel_message.connect(func(raw):
		var parsed: RefCounted = ChatMessageScript.from_nakama_channel_message(raw, _kingdom_id)
		received_b.append(str(parsed.text))
	)

	var channel_b: NakamaRTAPI.Channel = await socket_b.join_chat_async(
		get_kingdom_room_name(),
		NakamaSocket.ChannelType.Room,
		true,
		false
	)
	if channel_b == null or channel_b.is_exception():
		fails.append("B join failed")
		_print_smoke_result(fails)
		return false

	# Wait for realtime delivery of A's message (or history fallback).
	await get_tree().create_timer(1.0).timeout
	var saw_a := false
	for t in received_b:
		if str(t).find(token_a) >= 0:
			saw_a = true
			break
	if not saw_a:
		var hist_b: NakamaAPI.ApiChannelMessageList = await client_b.list_channel_messages_async(
			session_b, str(channel_b.id), 40, false, null
		)
		if hist_b != null and not hist_b.is_exception():
			for raw in hist_b.messages:
				var parsed2: RefCounted = ChatMessageScript.from_nakama_channel_message(raw, _kingdom_id)
				if str(parsed2.text).find(token_a) >= 0:
					saw_a = true
					break
	if not saw_a:
		fails.append("B did not receive A's text")

	var token_b: String = "smokeB-%d" % int(Time.get_unix_time_from_system())
	var content_b: Dictionary = ChatMessageScript.build_outbound_content(
		ChatMessageScript.TYPE_TEXT,
		"Reply %s" % token_b,
		"DevPlayer_B",
		"",
		{},
		{},
		_kingdom_id
	)
	var ack_b = await socket_b.write_chat_message_async(str(channel_b.id), content_b)
	if ack_b == null or ack_b.is_exception():
		fails.append("B send failed")

	await get_tree().create_timer(1.0).timeout
	var saw_b := false
	for m in _messages:
		if str(m.text).find(token_b) >= 0:
			saw_b = true
			break
	if not saw_b:
		fails.append("A did not receive B's reply")

	# History reopen simulation
	var hist_reload: Dictionary = await load_kingdom_history(true)
	if not bool(hist_reload.get("ok", false)):
		fails.append("history reload failed")
	else:
		var has_ids := false
		var has_ts := false
		for m2 in get_messages():
			if str(m2.message_id) != "":
				has_ids = true
			if int(m2.timestamp_unix) > 0 or str(m2.create_time_raw) != "":
				has_ts = true
		if not has_ids:
			fails.append("message IDs missing")
		if not has_ts:
			fails.append("server timestamps missing")

	# Structured messages
	var map_bad: Dictionary = await send_map_location({"x": "bad", "y": 1})
	if bool(map_bad.get("ok", false)):
		fails.append("invalid map payload should fail")
	var map_ok: Dictionary = await send_map_location({
		"kingdom_id": _kingdom_id,
		"x": 428,
		"y": 719,
		"label": "Wildling Lv.18",
		"target_type": "wildling",
		"target_id": "smoke_lair",
	})
	if not bool(map_ok.get("ok", false)):
		fails.append("map send failed: %s" % map_ok.get("error"))

	await get_tree().create_timer(1.6).timeout
	var rally_ok: Dictionary = await send_rally_preview({
		"rally_id": "preview_only",
		"leader_user_id": get_local_user_id(),
		"target_id": "lair_x",
		"target_type": "wildling_lair",
		"target_name": "Wildling Lair Lv.20",
		"kingdom_id": _kingdom_id,
		"x": 100,
		"y": 200,
		"expiry_unix": int(Time.get_unix_time_from_system()) + 300,
	})
	if not bool(rally_ok.get("ok", false)):
		fails.append("rally preview send failed: %s" % rally_ok.get("error"))

	# Block / mute against B
	var b_uid: String = str(session_b.user_id)
	block_user(b_uid)
	if not is_blocked(b_uid):
		fails.append("block failed")
	var visible_after_block := false
	for m3 in get_messages():
		if str(m3.sender_user_id) == b_uid:
			visible_after_block = true
	if visible_after_block:
		fails.append("blocked user still rendered")
	unblock_user(b_uid)
	mute_user(b_uid)
	if not is_muted(b_uid):
		fails.append("mute failed")
	unmute_user(b_uid)

	# Report contract
	var sample: RefCounted = null
	for m4 in _messages:
		if str(m4.sender_user_id) == b_uid or str(m4.text).find(token_b) >= 0:
			sample = m4
			break
	if sample != null:
		var rep: Dictionary = await submit_report(sample, "spam")
		if not bool(rep.get("ok", false)):
			fails.append("report failed: %s" % rep.get("error"))
		elif str(rep.get("report_id", "")) == "":
			fails.append("report missing report_id")
	else:
		fails.append("no sample message for report")

	# Translate unavailable
	if sample != null:
		var tr: Dictionary = request_translate(sample)
		if bool(tr.get("ok", false)):
			fails.append("translate should be unavailable")
		if str(tr.get("error", "")).find("not configured") < 0:
			fails.append("translate error text unexpected")

	socket_b.close()
	_print_smoke_result(fails)
	return fails.is_empty()


func run_phase3_alliance_smoke_test() -> bool:
	## Two-user Alliance create/join/chat/kick + fake group ID rejection + kingdom regression.
	## Local AllianceState is intentionally untouched.
	print("[Phase3Smoke] BEGIN")
	var fails: Array[String] = []
	var ab: Node = _alliance_backend()
	var nakama: Node = _nakama()

	for _i in 40:
		ab = _alliance_backend()
		if is_chat_available() and ab != null and ab.has_profile():
			break
		await get_tree().create_timer(0.25).timeout
	ab = _alliance_backend()
	if not is_chat_available() or ab == null or not ab.has_profile():
		print("[Phase3Smoke] FAIL primary auth/profile unavailable")
		return false
	if nakama == null:
		print("[Phase3Smoke] FAIL Nakama autoload missing")
		return false

	# Ensure A is not already in a leftover alliance.
	if ab.is_in_backend_alliance():
		await ab.leave_alliance()
		await ab.refresh_profile()

	var stamp: int = int(Time.get_unix_time_from_system())
	var tag: String = "P3%02d" % (stamp % 100)
	var ally_name: String = "P3Smoke%s" % str(stamp).substr(str(stamp).length() - 6, 6)
	var create_a: Dictionary = await ab.create_alliance(ally_name, tag)
	if not bool(create_a.get("ok", false)):
		fails.append("A create alliance failed: %s" % create_a.get("error"))
		_print_phase3_result(fails)
		return false
	var alliance_id: String = ab.get_alliance_id()
	if alliance_id == "" or ab.get_alliance_tag() != tag:
		fails.append("A profile missing alliance after create")

	var join_chat_a: Dictionary = await join_alliance_chat()
	if not bool(join_chat_a.get("ok", false)):
		fails.append("A alliance chat join failed: %s" % join_chat_a.get("error"))

	# User B via fresh client
	var client_b: NakamaClient = nakama.create_client("defaultkey", "127.0.0.1", 7350, "http", 3, NakamaLogger.LOG_LEVEL.ERROR)
	client_b.auto_retry = false
	var device_b: String = "crownspire-p3-b-%s" % str(int(Time.get_unix_time_from_system()))
	var session_b: NakamaSession = await client_b.authenticate_device_async(device_b)
	if session_b == null or session_b.is_exception():
		fails.append("B auth failed")
		_print_phase3_result(fails)
		return false
	var b_uid: String = str(session_b.user_id)

	var prof_b = await client_b.rpc_async(session_b, "crownspire_get_profile", "{}")
	if prof_b == null or prof_b.is_exception():
		fails.append("B get_profile failed")

	var join_req = await client_b.rpc_async(session_b, "crownspire_join_alliance", JSON.stringify({"alliance_id": alliance_id}))
	if join_req == null or join_req.is_exception():
		fails.append("B join request failed")
	else:
		var join_parsed: Variant = JSON.parse_string(str(join_req.payload))
		if typeof(join_parsed) != TYPE_DICTIONARY or not bool(join_parsed.get("pending", false)):
			fails.append("B join should be pending approval")

	var list_req: Dictionary = await ab.list_join_requests()
	if not bool(list_req.get("ok", false)):
		fails.append("list join requests failed: %s" % list_req.get("error"))
	var approve: Dictionary = await ab.approve_join(b_uid)
	if not bool(approve.get("ok", false)):
		fails.append("A approve B failed: %s" % approve.get("error"))

	var prof_b2 = await client_b.rpc_async(session_b, "crownspire_get_profile", "{}")
	var b_alliance_id := ""
	var b_tag := ""
	if prof_b2 != null and not prof_b2.is_exception():
		var pb: Variant = JSON.parse_string(str(prof_b2.payload))
		if typeof(pb) == TYPE_DICTIONARY:
			var profile_b: Dictionary = pb.get("profile", {})
			b_alliance_id = str(profile_b.get("alliance_id", ""))
			b_tag = str(profile_b.get("alliance_tag", ""))
	if b_alliance_id != alliance_id:
		fails.append("B alliance_id mismatch after approve")
	if b_tag != tag:
		fails.append("B alliance_tag not server-backed")

	await ab.refresh_profile()
	if ab.get_alliance_id() != alliance_id:
		fails.append("A alliance_id drifted")

	var socket_b: NakamaSocket = nakama.create_socket_from(client_b)
	var sock_res = await socket_b.connect_async(session_b)
	if sock_res == null or sock_res.is_exception() or not socket_b.is_connected_to_host():
		fails.append("B socket failed")
		_print_phase3_result(fails)
		return false

	var received_b: Array[String] = []
	socket_b.received_channel_message.connect(func(raw):
		var parsed: RefCounted = ChatMessageScript.from_nakama_channel_message(raw, _kingdom_id)
		received_b.append(str(parsed.text))
	)

	var channel_b: NakamaRTAPI.Channel = await socket_b.join_chat_async(
		alliance_id,
		NakamaSocket.ChannelType.Group,
		true,
		false
	)
	if channel_b == null or channel_b.is_exception():
		fails.append("B alliance chat join failed")
	else:
		var token_a: String = "p3A-%d" % int(Time.get_unix_time_from_system())
		await get_tree().create_timer(1.6).timeout
		var send_a: Dictionary = await send_text_message("Alliance hello %s" % token_a, "alliance")
		if not bool(send_a.get("ok", false)):
			fails.append("A alliance send failed: %s" % send_a.get("error"))
		await get_tree().create_timer(1.0).timeout
		var saw_a := false
		for t in received_b:
			if str(t).find(token_a) >= 0:
				saw_a = true
				break
		if not saw_a:
			fails.append("B did not receive A alliance message")

		var token_b: String = "p3B-%d" % int(Time.get_unix_time_from_system())
		var content_b: Dictionary = ChatMessageScript.build_outbound_content(
			ChatMessageScript.TYPE_TEXT,
			"Alliance reply %s" % token_b,
			"DevPlayer_B",
			b_tag,
			{},
			{"tag_authority": "alliance_backend"},
			_kingdom_id
		)
		var ack_b = await socket_b.write_chat_message_async(str(channel_b.id), content_b)
		if ack_b == null or ack_b.is_exception():
			fails.append("B alliance send failed")
		await get_tree().create_timer(1.0).timeout
		var saw_b := false
		for m in _alliance_messages:
			if str(m.text).find(token_b) >= 0:
				saw_b = true
				break
		if not saw_b:
			fails.append("A did not receive B alliance reply")

		var hist: Dictionary = await load_alliance_history(true)
		if not bool(hist.get("ok", false)):
			fails.append("alliance history reload failed")

	# Outside user C cannot join alliance chat
	var client_c: NakamaClient = nakama.create_client("defaultkey", "127.0.0.1", 7350, "http", 3, NakamaLogger.LOG_LEVEL.ERROR)
	client_c.auto_retry = false
	var session_c: NakamaSession = await client_c.authenticate_device_async("crownspire-p3-c-%s" % str(int(Time.get_unix_time_from_system())))
	if session_c != null and not session_c.is_exception():
		var socket_c: NakamaSocket = nakama.create_socket_from(client_c)
		await socket_c.connect_async(session_c)
		var channel_c: NakamaRTAPI.Channel = await socket_c.join_chat_async(
			alliance_id,
			NakamaSocket.ChannelType.Group,
			true,
			false
		)
		if channel_c != null and not channel_c.is_exception():
			fails.append("outsider C joined alliance chat (should fail)")
		socket_c.close()
	else:
		fails.append("C auth failed")

	# Fake group ID injection must fail for A (ChatManager never accepts client group IDs)
	var fake_id: String = "00000000-0000-0000-0000-000000000099"
	var nc_a: Node = _nakama_connection()
	var socket_a: NakamaSocket = nc_a.get_socket() if nc_a != null else null
	if socket_a == null:
		fails.append("A socket missing for fake join check")
	else:
		var fake_join: NakamaRTAPI.Channel = await socket_a.join_chat_async(
			fake_id,
			NakamaSocket.ChannelType.Group,
			true,
			false
		)
		if fake_join != null and not fake_join.is_exception():
			fails.append("fake group ID injection unexpectedly succeeded")

	# Kick B and confirm chat access lost
	var kick: Dictionary = await ab.kick_member(b_uid)
	if not bool(kick.get("ok", false)):
		fails.append("kick B failed: %s" % kick.get("error"))
	else:
		var channel_b2: NakamaRTAPI.Channel = await socket_b.join_chat_async(
			alliance_id,
			NakamaSocket.ChannelType.Group,
			true,
			false
		)
		if channel_b2 != null and not channel_b2.is_exception():
			fails.append("kicked B still joined alliance chat")
		var prof_b3 = await client_b.rpc_async(session_b, "crownspire_get_profile", "{}")
		if prof_b3 != null and not prof_b3.is_exception():
			var pb3: Variant = JSON.parse_string(str(prof_b3.payload))
			if typeof(pb3) == TYPE_DICTIONARY:
				var profile_b3: Dictionary = pb3.get("profile", {})
				if str(profile_b3.get("alliance_id", "")) != "":
					fails.append("kicked B profile still has alliance_id")

	# Kingdom chat regression
	var kjoin: Dictionary = await join_kingdom_chat()
	if not bool(kjoin.get("ok", false)):
		fails.append("kingdom regression join failed: %s" % kjoin.get("error"))
	else:
		await get_tree().create_timer(1.6).timeout
		var ksend: Dictionary = await send_text_message("phase3 kingdom ok %d" % int(Time.get_unix_time_from_system()), "kingdom")
		if not bool(ksend.get("ok", false)):
			fails.append("kingdom regression send failed: %s" % ksend.get("error"))

	# Cleanup A alliance (leave) — do not touch AllianceState
	await ab.leave_alliance()
	_reset_alliance_channel_state()
	socket_b.close()
	_print_phase3_result(fails)
	return fails.is_empty()


func _print_smoke_result(fails: Array[String]) -> void:
	if fails.is_empty():
		print("[ChatSmoke] PASS")
	else:
		for f in fails:
			print("[ChatSmoke] FAIL: %s" % f)
		print("[ChatSmoke] FAILED count=%d" % fails.size())


func _print_phase3_result(fails: Array[String]) -> void:
	if fails.is_empty():
		print("[Phase3Smoke] PASS")
	else:
		for f in fails:
			print("[Phase3Smoke] FAIL: %s" % f)
		print("[Phase3Smoke] FAILED count=%d" % fails.size())
