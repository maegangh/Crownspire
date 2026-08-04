extends Node

## Crownspire Alliance Rally client — Nakama-authoritative rally state.
## Local MarchState handles travel / combat presentation after launch.

signal rallies_changed(rallies: Array)
signal rally_updated(rally: Dictionary)
signal rally_launched(rally: Dictionary)
signal rally_completed(rally: Dictionary)
signal rally_cancelled(rally: Dictionary)
signal operation_failed(reason: String)

const RPC_CREATE := "crownspire_rally_create"
const RPC_JOIN := "crownspire_rally_join"
const RPC_LEAVE := "crownspire_rally_leave"
const RPC_CANCEL := "crownspire_rally_cancel"
const RPC_LAUNCH := "crownspire_rally_launch"
const RPC_GET := "crownspire_rally_get"
const RPC_LIST := "crownspire_rally_list_active"
const RPC_COMPLETE := "crownspire_rally_complete"
const RALLY_NOTIF_CODE: int = 5002

const COUNTDOWN_OPTIONS: Array[int] = [60, 300, 600]

var _rallies: Array = []
var _active_rally: Dictionary = {}
var _poll_timer: Timer = null
var _socket_bound: bool = false
var _launching_local: bool = false
var _completing_local: bool = false
var _dispatched_launch_ids: Dictionary = {}


func _nakama_connection() -> Node:
	return get_node_or_null("/root/NakamaConnection")


func _alliance_backend() -> Node:
	return get_node_or_null("/root/AllianceBackend")


func _ready() -> void:
	_ensure_poll_timer()
	call_deferred("_bind_nakama")


func get_active_rallies() -> Array:
	return _rallies.duplicate(true)


func get_focused_rally() -> Dictionary:
	return _active_rally.duplicate(true)


func is_in_rally(rally_id: String = "") -> bool:
	var rid: String = rally_id.strip_edges()
	var uid: String = ""
	var nc: Node = _nakama_connection()
	if nc != null:
		uid = nc.get_user_id()
	for r in _rallies:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		if rid != "" and str(r.get("rally_id", "")) != rid:
			continue
		for p in r.get("participants", []):
			if typeof(p) == TYPE_DICTIONARY and str(p.get("user_id", "")) == uid:
				return true
	return false


func refresh_rallies() -> Dictionary:
	var ab: Node = _alliance_backend()
	if ab == null or not ab.is_membership_authority():
		_rallies = []
		rallies_changed.emit(_rallies)
		_update_map_indicators()
		return {"ok": false, "error": "Alliance required"}
	var result: Dictionary = await _rpc(RPC_LIST, {})
	if bool(result.get("ok", false)):
		_rallies = result.get("rallies", [])
		rallies_changed.emit(_rallies.duplicate(true))
		_maybe_auto_launch()
		_update_map_indicators()
	return result


func create_rally(payload: Dictionary) -> Dictionary:
	var result: Dictionary = await _rpc(RPC_CREATE, payload)
	if bool(result.get("ok", false)):
		_active_rally = result.get("rally", {})
		await refresh_rallies()
		rally_updated.emit(_active_rally.duplicate(true))
	else:
		operation_failed.emit(str(result.get("error", "Create failed")))
	return result


func join_rally(rally_id: String, payload: Dictionary) -> Dictionary:
	var body: Dictionary = payload.duplicate(true)
	body["rally_id"] = rally_id
	var result: Dictionary = await _rpc(RPC_JOIN, body)
	if bool(result.get("ok", false)):
		_active_rally = result.get("rally", {})
		await refresh_rallies()
		rally_updated.emit(_active_rally.duplicate(true))
	else:
		operation_failed.emit(str(result.get("error", "Join failed")))
	return result


func leave_rally(rally_id: String) -> Dictionary:
	var result: Dictionary = await _rpc(RPC_LEAVE, {"rally_id": rally_id})
	if bool(result.get("ok", false)):
		if has_node("/root/MarchState") and MarchState.has_method("refund_rally_reservation"):
			MarchState.refund_rally_reservation(rally_id)
		await refresh_rallies()
	return result


func cancel_rally(rally_id: String) -> Dictionary:
	var result: Dictionary = await _rpc(RPC_CANCEL, {"rally_id": rally_id})
	if bool(result.get("ok", false)):
		_active_rally = result.get("rally", {})
		rally_cancelled.emit(_active_rally.duplicate(true))
		await refresh_rallies()
		_refund_local_troops_for_cancelled(_active_rally)
	return result


func launch_rally(rally_id: String, auto: bool = false) -> Dictionary:
	var result: Dictionary = await _rpc(RPC_LAUNCH, {"rally_id": rally_id, "auto": auto})
	if bool(result.get("ok", false)):
		_active_rally = result.get("rally", {})
		rally_launched.emit(_active_rally.duplicate(true))
		await refresh_rallies()
		await _start_local_rally_marches(_active_rally)
	return result


func get_rally(rally_id: String) -> Dictionary:
	var result: Dictionary = await _rpc(RPC_GET, {"rally_id": rally_id})
	if bool(result.get("ok", false)):
		_active_rally = result.get("rally", {})
		rally_updated.emit(_active_rally.duplicate(true))
	return result


func complete_rally(rally_id: String, battle_result: Dictionary) -> Dictionary:
	if _completing_local:
		return {"ok": false, "error": "Already completing"}
	_completing_local = true
	var result: Dictionary = await _rpc(RPC_COMPLETE, {
		"rally_id": rally_id,
		"result": battle_result,
	})
	_completing_local = false
	if bool(result.get("ok", false)):
		_active_rally = result.get("rally", {})
		rally_completed.emit(_active_rally.duplicate(true))
		if has_node("/root/MarchState") and MarchState.has_method("apply_shared_rally_result"):
			MarchState.apply_shared_rally_result(_active_rally)
		await refresh_rallies()
		_open_report_if_present(_active_rally)
	return result


func _maybe_auto_launch() -> void:
	if _launching_local:
		return
	var nc: Node = _nakama_connection()
	var uid: String = nc.get_user_id() if nc != null else ""
	for r in _rallies:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		if str(r.get("status", "")) != "FORMING":
			continue
		if int(r.get("remaining_seconds", 1)) > 0:
			continue
		if str(r.get("leader_user_id", "")) != uid:
			continue
		_launching_local = true
		await launch_rally(str(r.get("rally_id", "")), true)
		_launching_local = false
		return


func _start_local_rally_marches(rally: Dictionary) -> void:
	if not has_node("/root/MarchState"):
		return
	var rid: String = str(rally.get("rally_id", ""))
	if rid != "" and _dispatched_launch_ids.has(rid):
		return
	if MarchState.has_method("has_active_rally_march") and MarchState.has_active_rally_march(rid):
		_dispatched_launch_ids[rid] = true
		return
	if MarchState.has_method("dispatch_rally_march"):
		var res: Dictionary = MarchState.dispatch_rally_march(rally)
		if bool(res.get("ok", false)):
			_dispatched_launch_ids[rid] = true
		else:
			push_warning("[RallyBackend] dispatch_rally_march failed: %s" % str(res.get("error", "")))


func _refund_local_troops_for_cancelled(rally: Dictionary) -> void:
	## Cancel returns troops — MarchState helper if marches were not yet launched.
	if has_node("/root/MarchState") and MarchState.has_method("refund_rally_reservation"):
		MarchState.refund_rally_reservation(str(rally.get("rally_id", "")))


func _open_report_if_present(rally: Dictionary) -> void:
	var report: Node = get_tree().root.find_child("RallyReportScreen", true, false)
	if report != null and report.has_method("open_for_rally"):
		report.call("open_for_rally", rally.duplicate(true))


func _update_map_indicators() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var lairs: Array = tree.get_nodes_in_group("wildling_lairs")
	var by_lair: Dictionary = {}
	for r in _rallies:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var status: String = str(r.get("status", ""))
		if status != "FORMING" and status != "LAUNCHED":
			continue
		by_lair[str(r.get("lair_id", ""))] = r
	var uid: String = ""
	var nc: Node = _nakama_connection()
	if nc != null:
		uid = nc.get_user_id()
	for node in lairs:
		if node == null or not is_instance_valid(node):
			continue
		var lid: String = ""
		if "lair_id" in node:
			lid = str(node.get("lair_id"))
		var rally: Dictionary = by_lair.get(lid, {}) as Dictionary
		if node.has_method("set_rally_indicator"):
			if rally.is_empty():
				node.call("set_rally_indicator", false, 0, 0, false, false)
			else:
				var joined := false
				for p in rally.get("participants", []):
					if typeof(p) == TYPE_DICTIONARY and str(p.get("user_id", "")) == uid:
						joined = true
						break
				var remain: int = int(rally.get("remaining_seconds", 0))
				var launch_at: int = int(rally.get("launch_at", 0))
				var status: String = str(rally.get("status", ""))
				var launched: bool = status == "LAUNCHED"
				if status == "FORMING" and launch_at > 0:
					remain = maxi(0, launch_at - int(Time.get_unix_time_from_system()))
				if node.has_method("set_rally_indicator"):
					node.call(
						"set_rally_indicator",
						true,
						remain,
						int(rally.get("participant_count", rally.get("participants", []).size())),
						joined,
						launched
					)


func _ensure_poll_timer() -> void:
	if _poll_timer != null and is_instance_valid(_poll_timer):
		return
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 2.0
	_poll_timer.one_shot = false
	add_child(_poll_timer)
	_poll_timer.timeout.connect(func():
		var ab: Node = _alliance_backend()
		if ab != null and ab.is_membership_authority():
			refresh_rallies()
	)


func _bind_nakama() -> void:
	var nc: Node = _nakama_connection()
	if nc == null:
		return
	if nc.has_signal("authenticated") and not nc.authenticated.is_connected(_on_auth):
		nc.authenticated.connect(_on_auth)
	if nc.has_signal("socket_connected") and not nc.socket_connected.is_connected(_on_socket):
		nc.socket_connected.connect(_on_socket)
	if nc.is_authenticated():
		_on_auth()


func _on_auth() -> void:
	_bind_notifications()
	await refresh_rallies()
	if _poll_timer != null and _poll_timer.is_stopped():
		_poll_timer.start()


func _on_socket() -> void:
	_bind_notifications()
	await refresh_rallies()


func _bind_notifications() -> void:
	var nc: Node = _nakama_connection()
	if nc == null or _socket_bound:
		return
	var socket = nc.get_socket()
	if socket == null:
		return
	if socket.has_signal("received_notification") and not socket.received_notification.is_connected(_on_notification):
		socket.received_notification.connect(_on_notification)
	_socket_bound = true


func _on_notification(notification) -> void:
	if notification == null:
		return
	var code: int = int(notification.code) if ("code" in notification) else -1
	if code != RALLY_NOTIF_CODE:
		return
	await refresh_rallies()
	var content = notification.content if ("content" in notification) else {}
	if typeof(content) == TYPE_DICTIONARY and typeof(content.get("rally")) == TYPE_DICTIONARY:
		var rally: Dictionary = content.get("rally", {})
		_active_rally = rally
		var ev: String = str(content.get("event", ""))
		match ev:
			"rally_launched":
				rally_launched.emit(rally)
				await _start_local_rally_marches(rally)
			"rally_cancelled":
				rally_cancelled.emit(rally)
				_refund_local_troops_for_cancelled(rally)
			"rally_victory", "rally_defeat":
				rally_completed.emit(rally)
				if has_node("/root/MarchState") and MarchState.has_method("apply_shared_rally_result"):
					MarchState.apply_shared_rally_result(rally)
				_open_report_if_present(rally)
			_:
				rally_updated.emit(rally)
	_update_map_indicators()


func _rpc(rpc_id: String, payload: Dictionary) -> Dictionary:
	var nc: Node = _nakama_connection()
	if nc == null or not nc.is_authenticated():
		return {"ok": false, "error": "Not connected"}
	var client = nc.get_client()
	var session = nc.get_session()
	if client == null or session == null:
		return {"ok": false, "error": "Missing session"}
	var result = await client.rpc_async(session, rpc_id, JSON.stringify(payload))
	if result == null or result.is_exception():
		var reason := "RPC failed"
		if result != null and result.get_exception() != null:
			reason = str(result.get_exception().message)
		return {"ok": false, "error": reason}
	var raw: String = str(result.payload) if ("payload" in result) else ""
	if raw == "":
		return {"ok": false, "error": "Empty RPC payload"}
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Invalid RPC JSON"}
	return parsed
