extends Node

## Crownspire multiplayer Alliance authority (Nakama Groups + RPCs).
## Phase 4: roster, ranks, applications, invites, permissions.
## Separate from local AllianceState — do NOT merge saves.
##
## Dual-state rule:
##   When authenticated + has_profile → membership UI MUST use this node.
##   Alliance Help uses this node when authenticated (not AllianceState seeds).
##   AllianceState remains for research tree / treasury until later phases.
##
## Rank mapping:
##   Nakama Superadmin (0) -> R5
##   Nakama Admin (1)      -> R4
##   Member + storage      -> R1–R3 (approve defaults R1)

signal profile_changed(profile: Dictionary)
signal alliance_changed(alliance: Dictionary)
signal roster_changed(members: Array)
signal applications_changed(applications: Array)
signal invites_changed(invites: Array)
signal permissions_changed(permissions: Dictionary)
signal operation_failed(reason: String)
signal help_requests_changed(eligible: Array, mine: Array)
signal help_eligible_count_changed(count: int)
signal auto_help_status_changed(status: Dictionary)
signal help_applied(result: Dictionary)

const RPC_GET_PROFILE := "crownspire_get_profile"
const RPC_SET_DISPLAY_NAME := "crownspire_set_display_name"
const RPC_GET_PUBLIC_PROFILE := "crownspire_get_public_profile"
const RPC_CREATE_ALLIANCE := "crownspire_create_alliance"
const RPC_JOIN_ALLIANCE := "crownspire_join_alliance"
const RPC_LEAVE_ALLIANCE := "crownspire_leave_alliance"
const RPC_LIST_JOIN_REQUESTS := "crownspire_list_alliance_join_requests"
const RPC_APPROVE_JOIN := "crownspire_approve_alliance_join"
const RPC_REJECT_JOIN := "crownspire_reject_alliance_join"
const RPC_KICK_MEMBER := "crownspire_kick_alliance_member"
const RPC_CHAT_REPORT := "crownspire_chat_report"
const RPC_GET_ALLIANCE_PROFILE := "crownspire_get_alliance_profile"
const RPC_LIST_MEMBERS := "crownspire_list_members"
const RPC_LIST_ALLIANCES := "crownspire_list_alliances"
const RPC_UPDATE_PROFILE := "crownspire_update_alliance_profile"
const RPC_SET_MEMBER_RANK := "crownspire_set_member_rank"
const RPC_TRANSFER_LEADERSHIP := "crownspire_transfer_leadership"
const RPC_INVITE_PLAYER := "crownspire_invite_player"
const RPC_LIST_MY_INVITES := "crownspire_list_my_invites"
const RPC_ACCEPT_INVITE := "crownspire_accept_invite"
const RPC_REJECT_INVITE := "crownspire_reject_invite"
const RPC_GET_MY_PERMISSIONS := "crownspire_get_my_permissions"
const RPC_CREATE_HELP_REQUEST := "crownspire_create_help_request"
const RPC_HELP_ONE := "crownspire_help_one"
const RPC_HELP_ALL := "crownspire_help_all"
const RPC_LIST_ELIGIBLE_HELP := "crownspire_list_eligible_help_requests"
const RPC_LIST_MY_HELP := "crownspire_list_my_active_help_requests"
const RPC_COMPLETE_CANCEL_HELP := "crownspire_complete_or_cancel_help_request"
const RPC_GET_MY_ENTITLEMENTS := "crownspire_get_my_entitlements"
const RPC_UPDATE_PLAYER_IDENTITY := "crownspire_update_player_identity"
	const RPC_PRESENCE_HEARTBEAT := "crownspire_presence_heartbeat"
	const RPC_LIST_KINGDOM_CASTLES := "crownspire_list_kingdom_castles"

## TODO (Production): Replace beta_alliance_auto_help with production
## alliance_auto_help entitlement verified through Google Play Billing.
## Production subscription: Ultra Value Monthly Card
## Benefit: Alliance Auto-Help
const ENTITLEMENT_BETA_AUTO_HELP := "beta_alliance_auto_help"
const ENTITLEMENT_PRODUCTION_AUTO_HELP := "alliance_auto_help"
const HELP_NOTIF_CODE: int = 5001

const HELP_TYPE_CONSTRUCTION := "CONSTRUCTION"
const HELP_TYPE_RESEARCH := "RESEARCH"
const HELP_TYPE_HEALING := "HEALING"

const REPORT_REASONS: Array[String] = [
	"spam",
	"harassment",
	"hate_or_abuse",
	"sexual_content",
	"cheating_or_scam",
	"impersonation",
	"inappropriate_name",
	"other",
]

const ROLE_DISPLAY_NAMES := {
	"R5": "Leader",
	"R4": "Officer",
	"R3": "Veteran",
	"R2": "Member",
	"R1": "Recruit",
}

var _profile: Dictionary = {}
var _alliance: Dictionary = {}
var _members: Array = []
var _applications: Array = []
var _invites: Array = []
var _permissions: Dictionary = {}
var _eligible_help: Array = []
var _my_help_requests: Array = []
var _auto_help_status: Dictionary = {}
var _auto_help_running: bool = false
var _help_socket_bound: bool = false
var _presence_timer: Timer = null
const PRESENCE_INTERVAL_SEC: float = 30.0


func _nakama_connection() -> Node:
	return get_node_or_null("/root/NakamaConnection")


func _ready() -> void:
	call_deferred("_bind_nakama")
	call_deferred("_bind_local_timer_completion")


func _bind_local_timer_completion() -> void:
	## Close matching server Help requests when local timers finish.
	if has_node("/root/ConstructionState"):
		var cs: Node = get_node("/root/ConstructionState")
		if cs.has_signal("construction_completed") and not cs.construction_completed.is_connected(_on_local_construction_completed):
			cs.construction_completed.connect(_on_local_construction_completed)
	if has_node("/root/ResearchState"):
		var rs: Node = get_node("/root/ResearchState")
		if rs.has_signal("research_completed") and not rs.research_completed.is_connected(_on_local_research_completed):
			rs.research_completed.connect(_on_local_research_completed)
	if has_node("/root/HealingState"):
		var hs: Node = get_node("/root/HealingState")
		if hs.has_signal("healing_completed") and not hs.healing_completed.is_connected(_on_local_healing_completed):
			hs.healing_completed.connect(_on_local_healing_completed)


func _on_local_construction_completed(building_id: String, _new_level: int) -> void:
	await _complete_my_help_for_project(HELP_TYPE_CONSTRUCTION, building_id)


func _on_local_research_completed(research_id: String, _level: int) -> void:
	await _complete_my_help_for_project(HELP_TYPE_RESEARCH, research_id)


func _on_local_healing_completed(job_id: String, _quantity: int) -> void:
	await _complete_my_help_for_project(HELP_TYPE_HEALING, job_id)


func _complete_my_help_for_project(project_type: String, project_id: String) -> void:
	if not is_help_authority() or project_id.strip_edges() == "":
		return
	var want_type: String = project_type.to_upper()
	var want_id: String = project_id.strip_edges()
	for req in _my_help_requests:
		if typeof(req) != TYPE_DICTIONARY:
			continue
		if str(req.get("project_type", "")).to_upper() != want_type:
			continue
		if str(req.get("project_id", "")) != want_id:
			continue
		var rid: String = str(req.get("request_id", "")).strip_edges()
		if rid == "":
			continue
		await complete_or_cancel_help_request(rid, "complete")
		return


## True when multiplayer membership UI should use this backend (not AllianceState).
func is_membership_authority() -> bool:
	var nc: Node = _nakama_connection()
	return nc != null and nc.is_authenticated() and has_profile()


func get_profile() -> Dictionary:
	return _profile.duplicate(true)


func get_display_name() -> String:
	return str(_profile.get("display_name", "")).strip_edges()


func get_kingdom_id() -> String:
	return str(_profile.get("kingdom_id", "")).strip_edges()


func get_alliance_id() -> String:
	return str(_profile.get("alliance_id", "")).strip_edges()


func get_alliance_tag() -> String:
	return str(_profile.get("alliance_tag", "")).strip_edges()


func get_alliance_name() -> String:
	return str(_profile.get("alliance_name", "")).strip_edges()


func get_crownspire_rank() -> String:
	return str(_profile.get("crownspire_rank", "")).strip_edges()


func get_avatar_id() -> String:
	var id: String = str(_profile.get("avatar_id", "avatar_01")).strip_edges()
	return id if id != "" else "avatar_01"


func get_power() -> int:
	return int(_profile.get("power", 0))


func get_citadel_level() -> int:
	return maxi(1, int(_profile.get("citadel_level", 1)))


func get_vip_level() -> int:
	return maxi(0, int(_profile.get("vip_level", 0)))


func update_player_identity(fields: Dictionary) -> Dictionary:
	var result: Dictionary = await _rpc(RPC_UPDATE_PLAYER_IDENTITY, fields)
	if bool(result.get("ok", false)) and typeof(result.get("profile")) == TYPE_DICTIONARY:
		_set_profile(result.get("profile", {}))
	return result


func presence_heartbeat() -> Dictionary:
	var payload: Dictionary = _local_identity_snapshot()
	var result: Dictionary = await _rpc(RPC_PRESENCE_HEARTBEAT, payload)
	if bool(result.get("ok", false)) and typeof(result.get("profile")) == TYPE_DICTIONARY:
		_set_profile(result.get("profile", {}))
	return result


func sync_identity_from_local() -> Dictionary:
	## Push local GameState power/citadel/VIP + keep presence fresh.
	return await update_player_identity(_local_identity_snapshot())


func _local_identity_snapshot() -> Dictionary:
	var payload: Dictionary = {}
	if has_node("/root/GameState"):
		payload["power"] = int(GameState.power)
		payload["citadel_level"] = maxi(1, int(GameState.castle_level))
		payload["vip_level"] = maxi(0, int(GameState.vip_level))
	if _profile.has("avatar_id"):
		payload["avatar_id"] = get_avatar_id()
	return payload


func _ensure_presence_timer() -> void:
	if _presence_timer != null and is_instance_valid(_presence_timer):
		return
	_presence_timer = Timer.new()
	_presence_timer.name = "PresenceHeartbeat"
	_presence_timer.wait_time = PRESENCE_INTERVAL_SEC
	_presence_timer.autostart = false
	_presence_timer.one_shot = false
	add_child(_presence_timer)
	_presence_timer.timeout.connect(_on_presence_tick)


func _start_presence() -> void:
	_ensure_presence_timer()
	if _presence_timer.is_stopped():
		_presence_timer.start()
	presence_heartbeat()


func _stop_presence() -> void:
	if _presence_timer != null and is_instance_valid(_presence_timer):
		_presence_timer.stop()


func _on_presence_tick() -> void:
	var nc: Node = _nakama_connection()
	if nc == null or not nc.is_authenticated() or not nc.is_socket_connected():
		_stop_presence()
		return
	await presence_heartbeat()


func get_role_display_name(rank: String = "") -> String:
	var r: String = rank.strip_edges()
	if r == "":
		r = get_crownspire_rank()
	return str(ROLE_DISPLAY_NAMES.get(r, r if r != "" else "?"))


func is_in_backend_alliance() -> bool:
	return get_alliance_id() != ""


func has_profile() -> bool:
	return str(_profile.get("user_id", "")) != ""


func get_cached_alliance() -> Dictionary:
	return _alliance.duplicate(true)


func get_cached_members() -> Array:
	return _members.duplicate(true)


func get_cached_applications() -> Array:
	return _applications.duplicate(true)


func get_cached_invites() -> Array:
	return _invites.duplicate(true)


func get_cached_permissions() -> Dictionary:
	return _permissions.duplicate(true)


func has_permission(perm: String) -> bool:
	return bool(_permissions.get(perm, false))


func refresh_profile() -> Dictionary:
	var result: Dictionary = await _rpc(RPC_GET_PROFILE, {})
	if bool(result.get("ok", false)) and typeof(result.get("profile")) == TYPE_DICTIONARY:
		_set_profile(result.get("profile", {}))
	return result


func set_display_name(display_name: String) -> Dictionary:
	var result: Dictionary = await _rpc(RPC_SET_DISPLAY_NAME, {"display_name": display_name})
	if bool(result.get("ok", false)) and typeof(result.get("profile")) == TYPE_DICTIONARY:
		_set_profile(result.get("profile", {}))
	return result


func get_public_profile(user_id: String) -> Dictionary:
	return await _rpc(RPC_GET_PUBLIC_PROFILE, {"user_id": user_id})


func get_my_alliance() -> Dictionary:
	return await get_alliance_profile("")


func get_alliance_profile(alliance_id: String = "") -> Dictionary:
	var payload: Dictionary = {}
	if alliance_id.strip_edges() != "":
		payload["alliance_id"] = alliance_id.strip_edges()
	var result: Dictionary = await _rpc(RPC_GET_ALLIANCE_PROFILE, payload)
	if bool(result.get("ok", false)) and typeof(result.get("alliance")) == TYPE_DICTIONARY:
		_alliance = result.get("alliance", {})
		alliance_changed.emit(_alliance.duplicate(true))
	return result


func list_members() -> Dictionary:
	var result: Dictionary = await _rpc(RPC_LIST_MEMBERS, {})
	if bool(result.get("ok", false)):
		_members = result.get("members", [])
		roster_changed.emit(_members.duplicate(true))
	return result


func list_alliances(query: String = "") -> Dictionary:
	return await _rpc(RPC_LIST_ALLIANCES, {"query": query})


func list_kingdom_castles() -> Dictionary:
	## Returns real kingdom player castles with stable world coordinates.
	return await _rpc(RPC_LIST_KINGDOM_CASTLES, {})


func update_alliance_profile(fields: Dictionary) -> Dictionary:
	var result: Dictionary = await _rpc(RPC_UPDATE_PROFILE, fields)
	if bool(result.get("ok", false)):
		if typeof(result.get("alliance")) == TYPE_DICTIONARY:
			_alliance = result.get("alliance", {})
			alliance_changed.emit(_alliance.duplicate(true))
		if typeof(result.get("profile")) == TYPE_DICTIONARY:
			_set_profile(result.get("profile", {}))
		await refresh_membership_caches()
	return result


func create_alliance(name_text: String, tag_text: String, options: Dictionary = {}) -> Dictionary:
	## Create a Nakama-backed alliance. Requires authenticated profile.
	var ready: Dictionary = await ensure_ready_for_alliance_ops()
	if not bool(ready.get("ok", false)):
		return ready
	var payload: Dictionary = {
		"name": name_text,
		"tag": tag_text,
		"description": str(options.get("description", "")),
		"language": str(options.get("language", "en")),
		"join_type": str(options.get("join_type", "apply")),
		"min_citadel_level": int(options.get("min_citadel_level", 0)),
	}
	var result: Dictionary = await _rpc(RPC_CREATE_ALLIANCE, payload)
	if bool(result.get("ok", false)):
		if typeof(result.get("profile")) == TYPE_DICTIONARY:
			_set_profile(result.get("profile", {}))
		if typeof(result.get("alliance")) == TYPE_DICTIONARY:
			_alliance = result.get("alliance", {})
		alliance_changed.emit(_alliance.duplicate(true))
		await refresh_membership_caches()
	return result


func apply_to_alliance(alliance_id: String, message: String = "") -> Dictionary:
	## Alias for join request / open join workflow.
	return await join_alliance(alliance_id, message)


func join_alliance(alliance_id: String, message: String = "") -> Dictionary:
	## Open alliances join immediately (pending=false). Apply alliances return pending=true.
	var ready: Dictionary = await ensure_ready_for_alliance_ops()
	if not bool(ready.get("ok", false)):
		return ready
	var payload: Dictionary = {"alliance_id": alliance_id}
	if message.strip_edges() != "":
		payload["message"] = message.strip_edges()
	var result: Dictionary = await _rpc(RPC_JOIN_ALLIANCE, payload)
	if bool(result.get("ok", false)) and not bool(result.get("pending", true)):
		if typeof(result.get("profile")) == TYPE_DICTIONARY:
			_set_profile(result.get("profile", {}))
		if typeof(result.get("alliance")) == TYPE_DICTIONARY:
			_alliance = result.get("alliance", {})
			alliance_changed.emit(_alliance.duplicate(true))
		await refresh_membership_caches()
	return result


func ensure_ready_for_alliance_ops() -> Dictionary:
	## Ensures Nakama auth + Crownspire profile before alliance mutations.
	var nc: Node = _nakama_connection()
	if nc == null or not nc.is_authenticated():
		return _fail("Connect to multiplayer before creating or joining an Alliance.")
	if not has_profile():
		await refresh_profile()
	if not has_profile():
		return _fail("Still loading your profile. Try again in a moment.")
	return {"ok": true}


func leave_alliance() -> Dictionary:
	var result: Dictionary = await _rpc(RPC_LEAVE_ALLIANCE, {})
	if bool(result.get("ok", false)):
		if typeof(result.get("profile")) == TYPE_DICTIONARY:
			_set_profile(result.get("profile", {}))
		_alliance = {}
		_members = []
		_applications = []
		_permissions = {}
		alliance_changed.emit({})
		roster_changed.emit([])
		applications_changed.emit([])
		permissions_changed.emit({})
	return result


func list_applications() -> Dictionary:
	return await list_join_requests()


func list_join_requests() -> Dictionary:
	var result: Dictionary = await _rpc(RPC_LIST_JOIN_REQUESTS, {})
	if bool(result.get("ok", false)):
		_applications = result.get("applications", result.get("requests", []))
		applications_changed.emit(_applications.duplicate(true))
	return result


func approve_application(user_id: String) -> Dictionary:
	return await approve_join(user_id)


func approve_join(user_id: String) -> Dictionary:
	var result: Dictionary = await _rpc(RPC_APPROVE_JOIN, {"user_id": user_id})
	if bool(result.get("ok", false)):
		await list_join_requests()
		await list_members()
	return result


func reject_application(user_id: String) -> Dictionary:
	var result: Dictionary = await _rpc(RPC_REJECT_JOIN, {"user_id": user_id})
	if bool(result.get("ok", false)):
		await list_join_requests()
	return result


func kick_member(user_id: String) -> Dictionary:
	var result: Dictionary = await _rpc(RPC_KICK_MEMBER, {"user_id": user_id})
	if bool(result.get("ok", false)):
		await list_members()
	return result


func set_member_rank(user_id: String, rank: String) -> Dictionary:
	var result: Dictionary = await _rpc(RPC_SET_MEMBER_RANK, {"user_id": user_id, "rank": rank})
	if bool(result.get("ok", false)):
		await list_members()
		await refresh_permissions()
	return result


func promote_member(user_id: String) -> Dictionary:
	var current: String = _find_member_rank(user_id)
	var next: String = _next_rank_up(current)
	if next == "":
		return _fail("Cannot promote further")
	return await set_member_rank(user_id, next)


func demote_member(user_id: String) -> Dictionary:
	var current: String = _find_member_rank(user_id)
	var next: String = _next_rank_down(current)
	if next == "":
		return _fail("Cannot demote further")
	return await set_member_rank(user_id, next)


func transfer_leadership(user_id: String) -> Dictionary:
	var result: Dictionary = await _rpc(RPC_TRANSFER_LEADERSHIP, {"user_id": user_id})
	if bool(result.get("ok", false)):
		await refresh_profile()
		await refresh_membership_caches()
	return result


func invite_player(user_id: String) -> Dictionary:
	return await _rpc(RPC_INVITE_PLAYER, {"user_id": user_id})


func list_my_invites() -> Dictionary:
	var result: Dictionary = await _rpc(RPC_LIST_MY_INVITES, {})
	if bool(result.get("ok", false)):
		_invites = result.get("invites", [])
		invites_changed.emit(_invites.duplicate(true))
	return result


func accept_invite(invite_id: String) -> Dictionary:
	var result: Dictionary = await _rpc(RPC_ACCEPT_INVITE, {"invite_id": invite_id})
	if bool(result.get("ok", false)):
		if typeof(result.get("profile")) == TYPE_DICTIONARY:
			_set_profile(result.get("profile", {}))
		await refresh_membership_caches()
		alliance_changed.emit(_alliance.duplicate(true))
	return result


func reject_invite(invite_id: String) -> Dictionary:
	var result: Dictionary = await _rpc(RPC_REJECT_INVITE, {"invite_id": invite_id})
	if bool(result.get("ok", false)):
		await list_my_invites()
	return result


func refresh_permissions() -> Dictionary:
	var result: Dictionary = await _rpc(RPC_GET_MY_PERMISSIONS, {})
	if bool(result.get("ok", false)):
		_permissions = result.get("permissions", {})
		permissions_changed.emit(_permissions.duplicate(true))
	return result


func refresh_membership_caches() -> void:
	if not is_in_backend_alliance():
		_alliance = {}
		_members = []
		_applications = []
		_permissions = {}
		return
	await get_alliance_profile()
	await list_members()
	await refresh_permissions()
	if has_permission("view_applications"):
		await list_join_requests()


func submit_chat_report(report_payload: Dictionary) -> Dictionary:
	var reason: String = str(report_payload.get("reason", "")).strip_edges()
	if reason not in REPORT_REASONS:
		return {"ok": false, "error": "Invalid report reason"}
	return await _rpc(RPC_CHAT_REPORT, report_payload)


# --- Phase 5 Alliance Help (backend-authoritative) -------------------------------

func is_help_authority() -> bool:
	## Backend Help only when authenticated with profile + alliance. Never use AllianceState seeds.
	return is_membership_authority() and is_in_backend_alliance()


func get_eligible_help_requests() -> Array:
	return _eligible_help.duplicate(true)


func get_my_active_help_requests() -> Array:
	return _my_help_requests.duplicate(true)


func get_eligible_help_count() -> int:
	return _eligible_help.size()


func get_auto_help_status() -> Dictionary:
	return _auto_help_status.duplicate(true)


func is_auto_help_active() -> bool:
	## Server-derived only — never trust a client boolean entitlement flag.
	return bool(_auto_help_status.get("active", false))


func refresh_help_requests() -> Dictionary:
	if not is_authenticated_for_help():
		_eligible_help = []
		_my_help_requests = []
		help_eligible_count_changed.emit(0)
		help_requests_changed.emit([], [])
		return {"ok": false, "error": "Help unavailable — not connected to Alliance backend."}

	var eligible_res: Dictionary = await _rpc(RPC_LIST_ELIGIBLE_HELP, {})
	var mine_res: Dictionary = await _rpc(RPC_LIST_MY_HELP, {})
	if bool(eligible_res.get("ok", false)):
		_eligible_help = eligible_res.get("requests", [])
		if typeof(eligible_res.get("auto_help")) == TYPE_DICTIONARY:
			_set_auto_help_status(eligible_res.get("auto_help", {}))
	if bool(mine_res.get("ok", false)):
		_my_help_requests = mine_res.get("requests", [])
		if typeof(mine_res.get("auto_help")) == TYPE_DICTIONARY:
			_set_auto_help_status(mine_res.get("auto_help", {}))

	help_eligible_count_changed.emit(_eligible_help.size())
	help_requests_changed.emit(_eligible_help.duplicate(true), _my_help_requests.duplicate(true))
	await _maybe_run_auto_help()
	return {
		"ok": true,
		"eligible": _eligible_help.duplicate(true),
		"mine": _my_help_requests.duplicate(true),
		"auto_help": _auto_help_status.duplicate(true),
	}


func create_help_request(project_type: String, project_id: String, project_display_name: String, original_finish_time: int) -> Dictionary:
	if not is_help_authority():
		return _fail("Alliance Help unavailable — backend Alliance required.")
	var result: Dictionary = await _rpc(RPC_CREATE_HELP_REQUEST, {
		"project_type": project_type,
		"project_id": project_id,
		"project_display_name": project_display_name,
		"original_finish_time": original_finish_time,
	})
	if bool(result.get("ok", false)):
		await refresh_help_requests()
	return result


func help_one(request_id: String) -> Dictionary:
	if not is_help_authority():
		return _fail("Alliance Help unavailable.")
	var result: Dictionary = await _rpc(RPC_HELP_ONE, {"request_id": request_id})
	if bool(result.get("ok", false)):
		_apply_local_timer_reduction(result.get("request", {}), int(result.get("seconds_reduced", 0)))
		help_applied.emit(result)
		await refresh_help_requests()
	return result


func help_all(as_auto_help: bool = false) -> Dictionary:
	if not is_help_authority():
		return _fail("Alliance Help unavailable.")
	var result: Dictionary = await _rpc(RPC_HELP_ALL, {"as_auto_help": as_auto_help})
	if bool(result.get("ok", false)):
		var helped: Array = result.get("helped", [])
		for entry in helped:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			_apply_local_timer_reduction(entry.get("request", {}), int(entry.get("seconds_reduced", 0)))
		help_applied.emit(result)
		await refresh_help_requests()
	return result


func complete_or_cancel_help_request(request_id: String, action: String = "complete") -> Dictionary:
	var result: Dictionary = await _rpc(RPC_COMPLETE_CANCEL_HELP, {
		"request_id": request_id,
		"action": action,
	})
	if bool(result.get("ok", false)):
		await refresh_help_requests()
	return result


func refresh_entitlements() -> Dictionary:
	var result: Dictionary = await _rpc(RPC_GET_MY_ENTITLEMENTS, {})
	if bool(result.get("ok", false)) and typeof(result.get("auto_help")) == TYPE_DICTIONARY:
		_set_auto_help_status(result.get("auto_help", {}))
	return result


func is_authenticated_for_help() -> bool:
	var nc: Node = _nakama_connection()
	return nc != null and nc.is_authenticated() and nc.is_socket_connected() and has_profile()


func _set_auto_help_status(status: Dictionary) -> void:
	_auto_help_status = status.duplicate(true)
	auto_help_status_changed.emit(_auto_help_status.duplicate(true))


func _maybe_run_auto_help() -> void:
	## Online-only Auto-Help: client drives Help All through the same server validation.
	## Server never impersonates offline users.
	if _auto_help_running:
		return
	if not is_auto_help_active():
		return
	if not is_authenticated_for_help() or not is_in_backend_alliance():
		return
	if _eligible_help.is_empty():
		return
	_auto_help_running = true
	var result: Dictionary = await help_all(true)
	_auto_help_running = false
	if bool(result.get("ok", false)):
		print("[AllianceBackend] Auto-Help applied count=%s" % str(result.get("helped_count", 0)))


func _apply_local_timer_reduction(request: Dictionary, seconds_reduced: int) -> void:
	## Owner applies server-calculated reduction to the matching local timer.
	if seconds_reduced <= 0 or typeof(request) != TYPE_DICTIONARY:
		return
	var nc: Node = _nakama_connection()
	var local_uid: String = nc.get_user_id() if nc != null else ""
	if local_uid == "" or str(request.get("owner_user_id", "")) != local_uid:
		return
	var project_type: String = str(request.get("project_type", "")).to_upper()
	var project_id: String = str(request.get("project_id", ""))
	match project_type:
		HELP_TYPE_CONSTRUCTION:
			if has_node("/root/ConstructionState"):
				ConstructionState.speedup_construction(project_id, seconds_reduced)
		HELP_TYPE_RESEARCH:
			if has_node("/root/ResearchState"):
				ResearchState.speedup_research(project_id, float(seconds_reduced))
		HELP_TYPE_HEALING:
			if has_node("/root/HealingState") and HealingState.has_method("speedup_healing"):
				HealingState.speedup_healing(project_id, seconds_reduced)


func _bind_help_notifications() -> void:
	var nc: Node = _nakama_connection()
	if nc == null or _help_socket_bound:
		return
	var socket = nc.get_socket()
	if socket == null:
		return
	if socket.has_signal("received_notification") and not socket.received_notification.is_connected(_on_help_notification):
		socket.received_notification.connect(_on_help_notification)
	_help_socket_bound = true


func _on_help_notification(notification) -> void:
	if notification == null:
		return
	var code: int = int(notification.code) if ("code" in notification) else -1
	if code != HELP_NOTIF_CODE:
		return
	## Modest realtime refresh — no aggressive polling; no chat spam.
	await refresh_help_requests()


func _bind_nakama() -> void:
	var nc: Node = _nakama_connection()
	if nc == null:
		return
	if not nc.authenticated.is_connected(_on_authenticated):
		nc.authenticated.connect(_on_authenticated)
	if not nc.socket_connected.is_connected(_on_socket_connected):
		nc.socket_connected.connect(_on_socket_connected)
	if nc.is_authenticated():
		_on_authenticated()


func _on_authenticated() -> void:
	await refresh_profile()
	await list_my_invites()
	await refresh_entitlements()
	await sync_identity_from_local()
	_start_presence()
	if is_in_backend_alliance():
		await refresh_membership_caches()
		await refresh_help_requests()


func _on_socket_connected() -> void:
	if not has_profile():
		await refresh_profile()
	_bind_help_notifications()
	_help_socket_bound = false
	_bind_help_notifications()
	_start_presence()
	if is_in_backend_alliance():
		await refresh_help_requests()


func _set_profile(profile: Dictionary) -> void:
	var prev_alliance: String = str(_profile.get("alliance_id", ""))
	_profile = profile.duplicate(true)
	profile_changed.emit(_profile.duplicate(true))
	var next_alliance: String = str(_profile.get("alliance_id", ""))
	if prev_alliance != next_alliance:
		alliance_changed.emit(_alliance.duplicate(true) if next_alliance != "" else {})
	print(
		"[AllianceBackend] Profile user=%s name=%s kingdom=%s alliance=%s tag=%s rank=%s"
		% [
			str(_profile.get("user_id", "")),
			str(_profile.get("display_name", "")),
			str(_profile.get("kingdom_id", "")),
			str(_profile.get("alliance_id", "")),
			str(_profile.get("alliance_tag", "")),
			str(_profile.get("crownspire_rank", "")),
		]
	)


func _find_member_rank(user_id: String) -> String:
	for m in _members:
		if typeof(m) == TYPE_DICTIONARY and str(m.get("user_id", "")) == user_id:
			return str(m.get("rank", "R1"))
	return "R1"


func _next_rank_up(rank: String) -> String:
	match rank:
		"R1":
			return "R2"
		"R2":
			return "R3"
		"R3":
			return "R4"
		_:
			return ""


func _next_rank_down(rank: String) -> String:
	match rank:
		"R4":
			return "R3"
		"R3":
			return "R2"
		"R2":
			return "R1"
		_:
			return ""


func _rpc(rpc_id: String, payload: Dictionary) -> Dictionary:
	var nc: Node = _nakama_connection()
	if nc == null:
		return _fail("NakamaConnection missing")
	if not nc.is_authenticated():
		return _fail("Not authenticated")
	var client: NakamaClient = nc.get_client()
	var session: NakamaSession = nc.get_session()
	if client == null or session == null:
		return _fail("Missing client/session")

	var raw = await client.rpc_async(session, rpc_id, JSON.stringify(payload))
	if raw == null or raw.is_exception():
		var reason: String = "RPC failed"
		if raw != null and raw.get_exception() != null:
			reason = str(raw.get_exception().message)
		return _fail(reason)

	var payload_str: String = str(raw.payload) if ("payload" in raw) else ""
	if payload_str.strip_edges() == "":
		return {"ok": true}
	var parsed: Variant = JSON.parse_string(payload_str)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("Invalid RPC response")
	var dict: Dictionary = parsed
	if dict.has("ok") and not bool(dict.get("ok", false)):
		return _fail(str(dict.get("error", "RPC rejected")))
	return dict


func _fail(reason: String) -> Dictionary:
	operation_failed.emit(reason)
	print("[AllianceBackend] %s" % reason)
	return {"ok": false, "error": reason}
