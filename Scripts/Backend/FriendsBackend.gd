extends Node

## Crownspire Friends — backend-authoritative via Nakama Friends API.
## Relationship identity is always Nakama user_id (never display_name).
## States: friend / invite_sent / invite_received / blocked / none

signal friends_changed()
signal friend_request_received(user_id: String, display_name: String)
signal friend_accepted(user_id: String, display_name: String)
signal relationship_changed(user_id: String, state: String)
signal operation_failed(reason: String)

## Nakama friendship states
const STATE_FRIEND: int = 0
const STATE_INVITE_SENT: int = 1
const STATE_INVITE_RECEIVED: int = 2
const STATE_BLOCKED: int = 3

const LIST_LIMIT: int = 100

var _friends: Array[Dictionary] = [] ## accepted
var _outgoing: Array[Dictionary] = []
var _incoming: Array[Dictionary] = []
var _blocked: Array[Dictionary] = []
var _by_id: Dictionary = {} ## user_id -> {user_id, display_name, state, online_status, avatar_id}
var _refreshing: bool = false
var _seen_incoming: Dictionary = {} ## user_id -> true (dedupe notifications)
var _known_friends: Dictionary = {} ## user_id -> true (track accept transitions)
var _initial_loaded: bool = false
var _bound: bool = false


func _ready() -> void:
	call_deferred("_bind")


func _bind() -> void:
	if _bound:
		return
	_bound = true
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc == null:
		return
	if nc.has_signal("authenticated") and not nc.authenticated.is_connected(_on_auth):
		nc.authenticated.connect(_on_auth)
	if nc.has_signal("socket_connected") and not nc.socket_connected.is_connected(_on_socket):
		nc.socket_connected.connect(_on_socket)
	if nc.is_authenticated():
		refresh_friends()


func _on_auth(_session: Variant = null) -> void:
	refresh_friends()


func _on_socket() -> void:
	refresh_friends()


func is_available() -> bool:
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	return nc != null and nc.is_authenticated() and nc.get_client() != null and nc.get_session() != null


func get_friends() -> Array[Dictionary]:
	return _friends.duplicate(true)


func get_outgoing_requests() -> Array[Dictionary]:
	return _outgoing.duplicate(true)


func get_incoming_requests() -> Array[Dictionary]:
	return _incoming.duplicate(true)


func get_blocked() -> Array[Dictionary]:
	return _blocked.duplicate(true)


func get_relationship(user_id: String) -> String:
	var uid: String = user_id.strip_edges()
	if uid == "":
		return "none"
	if not _by_id.has(uid):
		return "none"
	return str(_by_id[uid].get("state", "none"))


func is_friend(user_id: String) -> bool:
	return get_relationship(user_id) == "friend"


func has_outgoing_request(user_id: String) -> bool:
	return get_relationship(user_id) == "invite_sent"


func has_incoming_request(user_id: String) -> bool:
	return get_relationship(user_id) == "invite_received"


func is_blocked(user_id: String) -> bool:
	return get_relationship(user_id) == "blocked"


func refresh_friends() -> Dictionary:
	if not is_available():
		return {"ok": false, "error": "Not authenticated"}
	if _refreshing:
		return {"ok": false, "error": "Refresh in progress"}
	_refreshing = true
	var nc: Node = get_node("/root/NakamaConnection")
	var client: NakamaClient = nc.get_client()
	var session: NakamaSession = nc.get_session()

	var result: Dictionary = await _list_all_states(client, session)
	_refreshing = false
	if not bool(result.get("ok", false)):
		operation_failed.emit(str(result.get("error", "Friends refresh failed")))
		return result

	_emit_relationship_notifications()
	friends_changed.emit()
	return {"ok": true, "friends": _friends.size(), "incoming": _incoming.size(), "outgoing": _outgoing.size()}


func send_friend_request(user_id: String) -> Dictionary:
	var uid: String = user_id.strip_edges()
	if uid == "":
		return {"ok": false, "error": "Missing player id"}
	var local_id: String = _local_user_id()
	if uid == local_id:
		return {"ok": false, "error": "Cannot friend yourself"}
	if is_blocked(uid) or _chat_is_blocked(uid):
		return {"ok": false, "error": "Player is blocked"}
	if not is_available():
		return {"ok": false, "error": "Not authenticated"}

	var nc: Node = get_node("/root/NakamaConnection")
	var res: NakamaAsyncResult = await nc.get_client().add_friends_async(
		nc.get_session(), PackedStringArray([uid]), null
	)
	if res == null or res.is_exception():
		var err: String = "Friend request failed"
		if res != null and res.get_exception() != null:
			err = str(res.get_exception().message)
		operation_failed.emit(err)
		return {"ok": false, "error": err}

	print("[Friends] request sent user=%s" % uid)
	await refresh_friends()
	relationship_changed.emit(uid, get_relationship(uid))
	return {"ok": true, "state": get_relationship(uid)}


func accept_friend_request(user_id: String) -> Dictionary:
	## Accepting = add_friends again for an invite_received peer.
	var uid: String = user_id.strip_edges()
	if uid == "":
		return {"ok": false, "error": "Missing player id"}
	if not is_available():
		return {"ok": false, "error": "Not authenticated"}
	var nc: Node = get_node("/root/NakamaConnection")
	var res: NakamaAsyncResult = await nc.get_client().add_friends_async(
		nc.get_session(), PackedStringArray([uid]), null
	)
	if res == null or res.is_exception():
		var err: String = "Accept failed"
		if res != null and res.get_exception() != null:
			err = str(res.get_exception().message)
		return {"ok": false, "error": err}
	print("[Friends] accepted user=%s" % uid)
	await refresh_friends() ## emits friend_accepted once via notification diff
	relationship_changed.emit(uid, "friend")
	return {"ok": true, "state": "friend"}


func decline_friend_request(user_id: String) -> Dictionary:
	return await _delete_relationship(user_id, "declined")


func cancel_friend_request(user_id: String) -> Dictionary:
	return await _delete_relationship(user_id, "cancelled")


func remove_friend(user_id: String) -> Dictionary:
	return await _delete_relationship(user_id, "removed")


func block_player(user_id: String) -> Dictionary:
	var uid: String = user_id.strip_edges()
	if uid == "" or uid == _local_user_id():
		return {"ok": false, "error": "Cannot block this player"}
	if not is_available():
		return {"ok": false, "error": "Not authenticated"}
	var nc: Node = get_node("/root/NakamaConnection")
	var res: NakamaAsyncResult = await nc.get_client().block_friends_async(
		nc.get_session(), PackedStringArray([uid]), null
	)
	if res == null or res.is_exception():
		var err: String = "Block failed"
		if res != null and res.get_exception() != null:
			err = str(res.get_exception().message)
		return {"ok": false, "error": err}
	# Mirror into ChatManager local filter for DM send/join guards.
	var cm_block: Node = get_node_or_null("/root/ChatManager")
	if cm_block != null and cm_block.has_method("block_user"):
		cm_block.block_user(uid)
	print("[Friends] blocked user=%s" % uid)
	await refresh_friends()
	relationship_changed.emit(uid, "blocked")
	return {"ok": true, "state": "blocked"}


func unblock_player(user_id: String) -> Dictionary:
	var uid: String = user_id.strip_edges()
	if uid == "":
		return {"ok": false, "error": "Missing player id"}
	# Nakama unblock = delete the blocked friendship record.
	var del: Dictionary = await _delete_relationship(uid, "unblocked")
	var cm_unblock: Node = get_node_or_null("/root/ChatManager")
	if cm_unblock != null and cm_unblock.has_method("unblock_user"):
		cm_unblock.unblock_user(uid)
	return del


func _delete_relationship(user_id: String, reason: String) -> Dictionary:
	var uid: String = user_id.strip_edges()
	if uid == "":
		return {"ok": false, "error": "Missing player id"}
	if not is_available():
		return {"ok": false, "error": "Not authenticated"}
	var nc: Node = get_node("/root/NakamaConnection")
	var res: NakamaAsyncResult = await nc.get_client().delete_friends_async(
		nc.get_session(), PackedStringArray([uid]), null
	)
	if res == null or res.is_exception():
		var err: String = "Relationship update failed"
		if res != null and res.get_exception() != null:
			err = str(res.get_exception().message)
		return {"ok": false, "error": err}
	print("[Friends] %s user=%s" % [reason, uid])
	await refresh_friends()
	relationship_changed.emit(uid, get_relationship(uid))
	return {"ok": true, "state": get_relationship(uid)}


func _list_all_states(client: NakamaClient, session: NakamaSession) -> Dictionary:
	var friends: Array[Dictionary] = []
	var outgoing: Array[Dictionary] = []
	var incoming: Array[Dictionary] = []
	var blocked: Array[Dictionary] = []
	var by_id: Dictionary = {}

	for state_code in [STATE_FRIEND, STATE_INVITE_SENT, STATE_INVITE_RECEIVED, STATE_BLOCKED]:
		var list_res = await client.list_friends_async(session, state_code, LIST_LIMIT, null)
		if list_res == null or list_res.is_exception():
			var err: String = "list_friends failed"
			if list_res != null and list_res.get_exception() != null:
				err = str(list_res.get_exception().message)
			return {"ok": false, "error": err}
		var rows: Array = []
		if "friends" in list_res and list_res.friends != null:
			rows = list_res.friends
		for fr in rows:
			var entry: Dictionary = _friend_to_dict(fr, state_code)
			var uid: String = str(entry.get("user_id", ""))
			if uid == "":
				continue
			by_id[uid] = entry
			match state_code:
				STATE_FRIEND:
					friends.append(entry)
				STATE_INVITE_SENT:
					outgoing.append(entry)
				STATE_INVITE_RECEIVED:
					incoming.append(entry)
				STATE_BLOCKED:
					blocked.append(entry)

	# Enrich online status from public profiles (best-effort, non-blocking batch).
	await _enrich_online(friends)

	_friends = friends
	_outgoing = outgoing
	_incoming = incoming
	_blocked = blocked
	_by_id = by_id
	return {"ok": true}


func _friend_to_dict(fr: Variant, state_code: int) -> Dictionary:
	var user = fr.user if fr != null and ("user" in fr) else null
	var uid: String = ""
	var display: String = "Player"
	var avatar: String = "avatar_01"
	if user != null:
		uid = str(user.id) if ("id" in user) else ""
		display = str(user.display_name) if ("display_name" in user) and str(user.display_name) != "" else str(user.username) if ("username" in user) else "Player"
		# avatar_url unused; Crownspire uses avatar_id from public profile later.
	var state_name: String = _state_name(state_code)
	return {
		"user_id": uid,
		"display_name": display,
		"state": state_name,
		"state_code": state_code,
		"online_status": "unknown",
		"avatar_id": avatar,
	}


func _enrich_online(friends: Array[Dictionary]) -> void:
	if not has_node("/root/AllianceBackend"):
		return
	var ab: Node = get_node("/root/AllianceBackend")
	if not ab.has_method("get_public_profile"):
		return
	# Cap enrichment to avoid RPC storms.
	var limit: int = mini(friends.size(), 20)
	for i in range(limit):
		var entry: Dictionary = friends[i]
		var uid: String = str(entry.get("user_id", ""))
		if uid == "":
			continue
		var res: Dictionary = await ab.get_public_profile(uid)
		if bool(res.get("ok", false)) and typeof(res.get("profile")) == TYPE_DICTIONARY:
			var p: Dictionary = res.get("profile", {})
			entry["online_status"] = str(p.get("online_status", "offline"))
			entry["avatar_id"] = str(p.get("avatar_id", "avatar_01"))
			entry["display_name"] = str(p.get("display_name", entry.get("display_name", "Player")))
			entry["power"] = int(p.get("power", 0))
			friends[i] = entry
			_by_id[uid] = entry


func _emit_relationship_notifications() -> void:
	## First successful refresh seeds state without toast spam.
	if not _initial_loaded:
		for entry in _incoming:
			var seed_uid: String = str(entry.get("user_id", ""))
			if seed_uid != "":
				_seen_incoming[seed_uid] = true
		for entry in _friends:
			var fuid: String = str(entry.get("user_id", ""))
			if fuid != "":
				_known_friends[fuid] = true
		_initial_loaded = true
		return

	for entry in _incoming:
		var uid: String = str(entry.get("user_id", ""))
		if uid == "" or _seen_incoming.has(uid):
			continue
		_seen_incoming[uid] = true
		friend_request_received.emit(uid, str(entry.get("display_name", "Player")))

	for entry in _friends:
		var fuid2: String = str(entry.get("user_id", ""))
		if fuid2 == "" or _known_friends.has(fuid2):
			continue
		_known_friends[fuid2] = true
		friend_accepted.emit(fuid2, str(entry.get("display_name", "Player")))

	# Drop stale known friends that were removed.
	var keep: Dictionary = {}
	for entry in _friends:
		keep[str(entry.get("user_id", ""))] = true
	for old_uid in _known_friends.keys():
		if not keep.has(str(old_uid)):
			_known_friends.erase(old_uid)


func _state_name(code: int) -> String:
	match code:
		STATE_FRIEND:
			return "friend"
		STATE_INVITE_SENT:
			return "invite_sent"
		STATE_INVITE_RECEIVED:
			return "invite_received"
		STATE_BLOCKED:
			return "blocked"
		_:
			return "none"


func _local_user_id() -> String:
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc != null and nc.has_method("get_user_id"):
		return str(nc.get_user_id())
	return ""


func _chat_is_blocked(uid: String) -> bool:
	## Local ChatManager block only — do not call is_blocked_for_social (recursion).
	var cm: Node = get_node_or_null("/root/ChatManager")
	if cm != null and cm.has_method("is_locally_blocked"):
		return bool(cm.is_locally_blocked(uid))
	return false
