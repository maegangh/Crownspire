extends Node

## Canonical World resource tile state (Food/Wood/Stone/Iron).
## Persist: user://resource_tiles.cfg
## Live nodes are reconciled by WorldAutoSpawner; MarchState owns gather marches.

signal tiles_changed

const SAVE_PATH := "user://resource_tiles.cfg"
const SMOKE_SAVE_PATH := "user://resource_tiles_smoke_test.cfg"
const META_SECTION := "meta"
const LAYOUT_CONTRACT_KEY := "layout_contract_id"
const LAYOUT_KINGDOM_KEY := "layout_kingdom_id"
const CONTRACT_ID := "crownspire_map_blockers_v1"

const STATUS_AVAILABLE := "AVAILABLE"
const STATUS_RESERVED := "RESERVED"
const STATUS_GATHERING := "GATHERING"
const STATUS_DEPLETED := "DEPLETED"

## Beta placeholder — JSON respawnTimeSec is 0; ResourceSpawnManager pool timer is unrelated.
const BETA_RESOURCE_RESPAWN_SEC: int = 180

var tiles: Dictionary = {} # tile_id -> Dictionary state
var _live_nodes: Dictionary = {} # tile_id -> Node2D
var _save_path_override: String = ""
var _next_index_by_type: Dictionary = {"food": 0, "wood": 0, "stone": 0, "iron": 0}
var _layout_contract_id: String = ""
var _layout_kingdom_id: String = ""


func _ready() -> void:
	load_tiles()
	process_respawns()
	# MarchState catch-up runs after this autoload; repair once marches are loaded.
	call_deferred("repair_stale_reservations")


func _process(_delta: float) -> void:
	# Lightweight respawn checks (City or World) so offline depletes recover.
	process_respawns()


func get_save_path() -> String:
	if _save_path_override != "":
		return _save_path_override
	return SAVE_PATH


func begin_smoke_isolation() -> void:
	_save_path_override = SMOKE_SAVE_PATH
	tiles.clear()
	_live_nodes.clear()
	_layout_contract_id = ""
	_layout_kingdom_id = ""
	_next_index_by_type = {"food": 0, "wood": 0, "stone": 0, "iron": 0}
	if FileAccess.file_exists(SMOKE_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SMOKE_SAVE_PATH))


func end_smoke_isolation() -> void:
	_save_path_override = ""
	load_tiles()


func has_saved_tiles() -> bool:
	for tid: Variant in tiles.keys():
		var t: Dictionary = tiles[tid]
		if str(t.get("resource_type", "")) in ["food", "wood", "stone", "iron"]:
			return true
	return false


func get_all_tiles() -> Array:
	var out: Array = []
	for tid: Variant in tiles.keys():
		out.append((tiles[tid] as Dictionary).duplicate(true))
	return out


func get_tile(tile_id: String) -> Dictionary:
	if not tiles.has(tile_id):
		return {}
	return (tiles[tile_id] as Dictionary).duplicate(true)


func get_remaining(tile_id: String) -> int:
	var t: Dictionary = tiles.get(tile_id, {})
	if t.is_empty():
		return 0
	return maxi(0, int(t.get("remaining_amount", 0)))


func get_status(tile_id: String) -> String:
	var t: Dictionary = tiles.get(tile_id, {})
	return str(t.get("status", ""))


func make_tile_id(resource_type: String, index: int) -> String:
	return "resource_%s_%d" % [resource_type.strip_edges().to_lower(), index]


func allocate_tile_id(resource_type: String) -> String:
	var rtype: String = resource_type.strip_edges().to_lower()
	var idx: int = int(_next_index_by_type.get(rtype, 0))
	_next_index_by_type[rtype] = idx + 1
	return make_tile_id(rtype, idx)


## Stable id keyed to shared map contract index (not obsolete random coordinates).
func make_contract_tile_id(contract_index: int, resource_type: String) -> String:
	var rtype: String = resource_type.strip_edges().to_lower()
	return "%s:resource:%d:%s" % [CONTRACT_ID, maxi(0, contract_index), rtype]


## Rebuild tile map from contract spots. Preserve depletion/timers by contract tile id
## or by legacy type+index when migrating older saves.
func reconcile_to_contract_layout(kingdom_id: String, contract_spots: Array) -> void:
	var kid: String = str(kingdom_id).strip_edges()
	if kid == "":
		kid = "kingdom_dev_001"
	var prior: Dictionary = tiles.duplicate(true)
	var legacy_by_type_index: Dictionary = {}
	for tid_v: Variant in prior.keys():
		var tid: String = str(tid_v)
		var t: Dictionary = prior[tid] as Dictionary
		var rtype: String = str(t.get("resource_type", "")).strip_edges().to_lower()
		if rtype not in ["food", "wood", "stone", "iron"]:
			continue
		# Legacy ids: resource_food_0
		if tid.begins_with("resource_%s_" % rtype):
			var parts: PackedStringArray = tid.split("_")
			if parts.size() >= 3:
				var idx: int = int(parts[parts.size() - 1])
				legacy_by_type_index["%s:%d" % [rtype, idx]] = t
	var next: Dictionary = {}
	for spot_v: Variant in contract_spots:
		if typeof(spot_v) != TYPE_DICTIONARY:
			continue
		var spot: Dictionary = spot_v
		var idx: int = int(spot.get("index", 0))
		var rtype: String = str(spot.get("resource_type", "food")).strip_edges().to_lower()
		var tid: String = make_contract_tile_id(idx, rtype)
		var existing: Dictionary = {}
		if prior.has(tid):
			existing = prior[tid] as Dictionary
		elif legacy_by_type_index.has("%s:%d" % [rtype, idx]):
			existing = legacy_by_type_index["%s:%d" % [rtype, idx]] as Dictionary
		var level: int = int(spot.get("level", int(existing.get("level", 1))))
		var max_amount: int = int(spot.get("max_amount", int(existing.get("max_amount", 0))))
		var remaining: int = max_amount
		var status: String = STATUS_AVAILABLE
		var reserved: String = ""
		var respawn_unix: int = 0
		var applied: Array = []
		if not existing.is_empty():
			remaining = maxi(0, int(existing.get("remaining_amount", remaining)))
			max_amount = int(existing.get("max_amount", max_amount))
			level = int(existing.get("level", level))
			status = str(existing.get("status", status))
			reserved = str(existing.get("reserved_by_march_id", ""))
			respawn_unix = int(existing.get("respawn_unix", 0))
			var prev_applied: Variant = existing.get("tile_amount_applied_march_ids", [])
			if typeof(prev_applied) == TYPE_ARRAY:
				applied = prev_applied
		var pos_x: float = float(spot.get("x", 0.0))
		var pos_y: float = float(spot.get("y", 0.0))
		next[tid] = {
			"tile_id": tid,
			"resource_type": rtype,
			"level": level,
			"max_amount": max_amount,
			"remaining_amount": remaining,
			"status": status,
			"reserved_by_march_id": reserved,
			"respawn_unix": respawn_unix,
			"world_position": {"x": pos_x, "y": pos_y},
			"tile_amount_applied_march_ids": applied,
			"contract_index": idx,
		}
		_bump_index_from_id(tid)
	tiles = next
	_layout_contract_id = CONTRACT_ID
	_layout_kingdom_id = kid
	_live_nodes.clear()
	save_tiles()
	tiles_changed.emit()


func register_or_update_tile(
	tile_id: String,
	resource_type: String,
	level: int,
	max_amount: int,
	remaining_amount: int,
	world_pos: Vector2,
	status: String = STATUS_AVAILABLE
) -> Dictionary:
	var rtype: String = resource_type.strip_edges().to_lower()
	if rtype not in ["food", "wood", "stone", "iron"]:
		return {}
	var existing: Dictionary = tiles.get(tile_id, {}) as Dictionary
	var state: Dictionary = {
		"tile_id": tile_id,
		"resource_type": rtype,
		"level": level,
		"max_amount": max_amount,
		"remaining_amount": maxi(0, remaining_amount),
		"status": status if status != "" else STATUS_AVAILABLE,
		"reserved_by_march_id": str(existing.get("reserved_by_march_id", "")),
		"respawn_unix": int(existing.get("respawn_unix", 0)),
		## Authoritative spawn always writes contract coordinates (never keep stale saves).
		"world_position": {"x": world_pos.x, "y": world_pos.y},
		"tile_amount_applied_march_ids": existing.get("tile_amount_applied_march_ids", []),
	}
	# Prefer existing remaining/status when reloading a known tile.
	if not existing.is_empty():
		state["remaining_amount"] = maxi(0, int(existing.get("remaining_amount", remaining_amount)))
		state["max_amount"] = int(existing.get("max_amount", max_amount))
		state["level"] = int(existing.get("level", level))
		state["status"] = str(existing.get("status", status))
		state["reserved_by_march_id"] = str(existing.get("reserved_by_march_id", ""))
		state["respawn_unix"] = int(existing.get("respawn_unix", 0))
	tiles[tile_id] = state
	_bump_index_from_id(tile_id)
	return state.duplicate(true)


func bind_live_node(tile_id: String, node: Node2D) -> void:
	if tile_id == "" or node == null:
		return
	_live_nodes[tile_id] = node
	if "tile_id" in node:
		node.set("tile_id", tile_id)
	var click: Node = node.get_node_or_null("ClickArea")
	if click != null and "tile_id" in click:
		click.set("tile_id", tile_id)
	_apply_visual_state(tile_id)


func get_live_node(tile_id: String) -> Node2D:
	if not _live_nodes.has(tile_id):
		return null
	var n: Node2D = _live_nodes[tile_id] as Node2D
	if n == null or not is_instance_valid(n):
		_live_nodes.erase(tile_id)
		return null
	return n


func clear_live_nodes() -> void:
	_live_nodes.clear()


func can_reserve(tile_id: String) -> Dictionary:
	var t: Dictionary = tiles.get(tile_id, {})
	if t.is_empty():
		return {"ok": false, "error": "Resource tile not found."}
	process_respawns()
	t = tiles.get(tile_id, {})
	var status: String = str(t.get("status", ""))
	if status == STATUS_DEPLETED:
		return {"ok": false, "error": "Resource tile is depleted."}
	if status == STATUS_RESERVED or status == STATUS_GATHERING:
		return {"ok": false, "error": "Resource tile is already occupied."}
	if int(t.get("remaining_amount", 0)) <= 0:
		return {"ok": false, "error": "Resource tile has no remaining resources."}
	return {"ok": true}


func reserve_tile(tile_id: String, march_id: String) -> Dictionary:
	var gate: Dictionary = can_reserve(tile_id)
	if not bool(gate.get("ok", false)):
		return gate
	var t: Dictionary = tiles[tile_id]
	t["status"] = STATUS_RESERVED
	t["reserved_by_march_id"] = march_id
	tiles[tile_id] = t
	save_tiles()
	_apply_visual_state(tile_id)
	tiles_changed.emit()
	return {"ok": true}


func release_reservation(tile_id: String, march_id: String = "") -> void:
	if not tiles.has(tile_id):
		return
	var t: Dictionary = tiles[tile_id]
	var reserved: String = str(t.get("reserved_by_march_id", ""))
	if march_id != "" and reserved != "" and reserved != march_id:
		return
	if str(t.get("status", "")) == STATUS_DEPLETED:
		t["reserved_by_march_id"] = ""
		tiles[tile_id] = t
		save_tiles()
		return
	t["reserved_by_march_id"] = ""
	if int(t.get("remaining_amount", 0)) <= 0:
		_mark_depleted(tile_id, false)
		return
	t["status"] = STATUS_AVAILABLE
	tiles[tile_id] = t
	save_tiles()
	_apply_visual_state(tile_id)
	tiles_changed.emit()


func begin_gathering_on_tile(tile_id: String, march_id: String) -> Dictionary:
	if not tiles.has(tile_id):
		return {"ok": false, "error": "Resource tile missing.", "remaining": 0}
	var t: Dictionary = tiles[tile_id]
	var reserved: String = str(t.get("reserved_by_march_id", ""))
	if reserved != "" and reserved != march_id:
		return {"ok": false, "error": "Reservation mismatch.", "remaining": 0}
	var remaining: int = maxi(0, int(t.get("remaining_amount", 0)))
	if remaining <= 0:
		_mark_depleted(tile_id, false)
		return {"ok": false, "error": "Tile already depleted.", "remaining": 0}
	t["status"] = STATUS_GATHERING
	t["reserved_by_march_id"] = march_id
	tiles[tile_id] = t
	save_tiles()
	_apply_visual_state(tile_id)
	tiles_changed.emit()
	return {"ok": true, "remaining": remaining}


## Apply gather reduction once per march_id. Returns post-state summary.
func apply_gather_completion(tile_id: String, march_id: String, gathered_amount: int) -> Dictionary:
	if not tiles.has(tile_id):
		return {"ok": false, "error": "Tile missing.", "depleted": false, "remaining": 0}
	var t: Dictionary = tiles[tile_id]
	var applied: Array = t.get("tile_amount_applied_march_ids", [])
	if typeof(applied) != TYPE_ARRAY:
		applied = []
	if march_id in applied:
		# Idempotent — already reduced for this march.
		return {
			"ok": true,
			"already_applied": true,
			"depleted": str(t.get("status", "")) == STATUS_DEPLETED,
			"remaining": int(t.get("remaining_amount", 0)),
		}
	var take: int = maxi(0, gathered_amount)
	var remaining: int = maxi(0, int(t.get("remaining_amount", 0)) - take)
	t["remaining_amount"] = remaining
	applied.append(march_id)
	t["tile_amount_applied_march_ids"] = applied
	t["reserved_by_march_id"] = ""
	tiles[tile_id] = t
	if remaining <= 0:
		_mark_depleted(tile_id, true)
		return {"ok": true, "depleted": true, "remaining": 0, "already_applied": false}
	t["status"] = STATUS_AVAILABLE
	tiles[tile_id] = t
	save_tiles()
	_sync_click_amount(tile_id)
	_apply_visual_state(tile_id)
	tiles_changed.emit()
	return {"ok": true, "depleted": false, "remaining": remaining, "already_applied": false}


func _mark_depleted(tile_id: String, set_respawn: bool) -> void:
	if not tiles.has(tile_id):
		return
	var t: Dictionary = tiles[tile_id]
	t["status"] = STATUS_DEPLETED
	t["remaining_amount"] = 0
	t["reserved_by_march_id"] = ""
	if set_respawn or int(t.get("respawn_unix", 0)) <= 0:
		t["respawn_unix"] = int(Time.get_unix_time_from_system()) + BETA_RESOURCE_RESPAWN_SEC
	tiles[tile_id] = t
	save_tiles()
	_apply_visual_state(tile_id)
	tiles_changed.emit()


func process_respawns() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var changed: bool = false
	for tid: Variant in tiles.keys():
		var t: Dictionary = tiles[tid]
		if str(t.get("status", "")) != STATUS_DEPLETED:
			continue
		var respawn_unix: int = int(t.get("respawn_unix", 0))
		if respawn_unix <= 0 or now < respawn_unix:
			continue
		t["status"] = STATUS_AVAILABLE
		t["remaining_amount"] = int(t.get("max_amount", 0))
		t["reserved_by_march_id"] = ""
		t["respawn_unix"] = 0
		tiles[tid] = t
		_apply_visual_state(str(tid))
		_sync_click_amount(str(tid))
		changed = true
	if changed:
		save_tiles()
		tiles_changed.emit()


func repair_stale_reservations() -> void:
	var active_gather_ids: Dictionary = {}
	if has_node("/root/MarchState"):
		for march: Dictionary in MarchState.get_active_marches():
			if str(march.get("march_type", "")) != "gather":
				continue
			var status: String = str(march.get("status", ""))
			# RETURNING marches have already released the tile at gather completion.
			if status in ["MARCHING_TO_TARGET", "GATHERING"]:
				active_gather_ids[str(march.get("march_id", ""))] = true
	var changed: bool = false
	for tid: Variant in tiles.keys():
		var t: Dictionary = tiles[tid]
		var status: String = str(t.get("status", ""))
		if status != STATUS_RESERVED and status != STATUS_GATHERING:
			continue
		var mid: String = str(t.get("reserved_by_march_id", ""))
		if mid != "" and active_gather_ids.has(mid):
			continue
		# Stale lock.
		t["reserved_by_march_id"] = ""
		if int(t.get("remaining_amount", 0)) <= 0:
			t["status"] = STATUS_DEPLETED
			if int(t.get("respawn_unix", 0)) <= 0:
				t["respawn_unix"] = int(Time.get_unix_time_from_system()) + BETA_RESOURCE_RESPAWN_SEC
		else:
			t["status"] = STATUS_AVAILABLE
		tiles[tid] = t
		_apply_visual_state(str(tid))
		changed = true
	if changed:
		save_tiles()
		tiles_changed.emit()


func _apply_visual_state(tile_id: String) -> void:
	var node: Node2D = get_live_node(tile_id)
	if node == null:
		return
	var t: Dictionary = tiles.get(tile_id, {})
	var status: String = str(t.get("status", STATUS_AVAILABLE))
	var click: Area2D = node.get_node_or_null("ClickArea") as Area2D
	if status == STATUS_DEPLETED:
		node.visible = false
		if click:
			click.input_pickable = false
		return
	node.visible = true
	if click:
		click.input_pickable = true
	_sync_click_amount(tile_id)


func _sync_click_amount(tile_id: String) -> void:
	var node: Node2D = get_live_node(tile_id)
	if node == null:
		return
	var t: Dictionary = tiles.get(tile_id, {})
	var click: Node = node.get_node_or_null("ClickArea")
	if click != null and "amount" in click:
		click.set("amount", int(t.get("remaining_amount", 0)))
	if click != null and "level" in click:
		click.set("level", int(t.get("level", 1)))


func _bump_index_from_id(tile_id: String) -> void:
	# resource_food_3 → keep next index above 3
	var parts: PackedStringArray = tile_id.split("_")
	if parts.size() < 3:
		return
	var rtype: String = parts[1]
	var idx: int = int(parts[parts.size() - 1])
	var cur: int = int(_next_index_by_type.get(rtype, 0))
	if idx + 1 > cur:
		_next_index_by_type[rtype] = idx + 1


func save_tiles() -> void:
	var save := ConfigFile.new()
	save.set_value("meta", "save_version", 2)
	save.set_value("meta", "next_index_json", JSON.stringify(_next_index_by_type))
	save.set_value("meta", LAYOUT_CONTRACT_KEY, _layout_contract_id)
	save.set_value("meta", LAYOUT_KINGDOM_KEY, _layout_kingdom_id)
	var list: Array = []
	for tid: Variant in tiles.keys():
		list.append(tiles[tid])
	save.set_value("registry", "tiles_json", JSON.stringify(list))
	save.save(get_save_path())


func load_tiles() -> void:
	tiles.clear()
	_layout_contract_id = ""
	_layout_kingdom_id = ""
	var save := ConfigFile.new()
	if save.load(get_save_path()) != OK:
		return
	var idx_raw: String = str(save.get_value("meta", "next_index_json", "{}"))
	var idx_parsed: Variant = JSON.parse_string(idx_raw)
	if typeof(idx_parsed) == TYPE_DICTIONARY:
		_next_index_by_type = idx_parsed
	_layout_contract_id = str(save.get_value("meta", LAYOUT_CONTRACT_KEY, ""))
	_layout_kingdom_id = str(save.get_value("meta", LAYOUT_KINGDOM_KEY, ""))
	var raw: String = str(save.get_value("registry", "tiles_json", "[]"))
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_ARRAY:
		return
	for item: Variant in parsed:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var tid: String = str(d.get("tile_id", ""))
		if tid == "":
			continue
		tiles[tid] = d
		_bump_index_from_id(tid)


## Headless Step 3 audit — reservation, remaining, deplete, respawn, stale repair, idempotency.
func run_resource_tile_step3_smoke_test() -> bool:
	begin_smoke_isolation()
	var failed: int = 0
	var tile_id: String = allocate_tile_id("food")
	register_or_update_tile(tile_id, "food", 1, 10000, 10000, Vector2(100, 200), STATUS_AVAILABLE)
	save_tiles()

	var mid_a: String = "march_test_a"
	var mid_b: String = "march_test_b"
	var r1: Dictionary = reserve_tile(tile_id, mid_a)
	if not bool(r1.get("ok", false)):
		push_error("[ResourceTileState] smoke: reserve failed")
		failed += 1
	if get_status(tile_id) != STATUS_RESERVED:
		push_error("[ResourceTileState] smoke: expected RESERVED")
		failed += 1
	var r2: Dictionary = reserve_tile(tile_id, mid_b)
	if bool(r2.get("ok", false)):
		push_error("[ResourceTileState] smoke: second reserve must fail")
		failed += 1
	if str(r2.get("error", "")) != "Resource tile is already occupied.":
		push_error("[ResourceTileState] smoke: wrong occupied message")
		failed += 1

	var begin_ok: Dictionary = begin_gathering_on_tile(tile_id, mid_a)
	if not bool(begin_ok.get("ok", false)) or int(begin_ok.get("remaining", 0)) != 10000:
		push_error("[ResourceTileState] smoke: begin gathering failed")
		failed += 1
	if get_status(tile_id) != STATUS_GATHERING:
		push_error("[ResourceTileState] smoke: expected GATHERING")
		failed += 1

	# Partial gather by cargo 3000
	var part: Dictionary = apply_gather_completion(tile_id, mid_a, 3000)
	if not bool(part.get("ok", false)) or int(part.get("remaining", -1)) != 7000:
		push_error("[ResourceTileState] smoke: partial remaining wrong")
		failed += 1
	if get_status(tile_id) != STATUS_AVAILABLE:
		push_error("[ResourceTileState] smoke: partial should return AVAILABLE")
		failed += 1
	# Idempotent re-apply
	var part2: Dictionary = apply_gather_completion(tile_id, mid_a, 3000)
	if not bool(part2.get("already_applied", false)) or get_remaining(tile_id) != 7000:
		push_error("[ResourceTileState] smoke: idempotent reduce failed")
		failed += 1

	# Full deplete with another march
	var mid_c: String = "march_test_c"
	if not bool(reserve_tile(tile_id, mid_c).get("ok", false)):
		push_error("[ResourceTileState] smoke: re-reserve after partial failed")
		failed += 1
	begin_gathering_on_tile(tile_id, mid_c)
	var dep: Dictionary = apply_gather_completion(tile_id, mid_c, 7000)
	if not bool(dep.get("depleted", false)) or get_status(tile_id) != STATUS_DEPLETED:
		push_error("[ResourceTileState] smoke: deplete failed")
		failed += 1
	var tdep: Dictionary = get_tile(tile_id)
	if int(tdep.get("respawn_unix", 0)) <= 0:
		push_error("[ResourceTileState] smoke: respawn_unix missing")
		failed += 1

	# Force respawn due
	tiles[tile_id]["respawn_unix"] = int(Time.get_unix_time_from_system()) - 1
	process_respawns()
	if get_status(tile_id) != STATUS_AVAILABLE or get_remaining(tile_id) != 10000:
		push_error("[ResourceTileState] smoke: respawn restore failed")
		failed += 1

	# Stale reservation repair
	tiles[tile_id]["status"] = STATUS_RESERVED
	tiles[tile_id]["reserved_by_march_id"] = "ghost_march"
	repair_stale_reservations()
	if get_status(tile_id) != STATUS_AVAILABLE or str(get_tile(tile_id).get("reserved_by_march_id", "")) != "":
		push_error("[ResourceTileState] smoke: stale reservation repair failed")
		failed += 1

	# Persist round-trip
	save_tiles()
	tiles.clear()
	load_tiles()
	if get_remaining(tile_id) != 10000:
		push_error("[ResourceTileState] smoke: save/load remaining failed")
		failed += 1

	end_smoke_isolation()
	if failed == 0:
		print("[ResourceTileState] Step 3 smoke test PASSED")
		return true
	push_error("[ResourceTileState] Step 3 smoke test FAILED (%d)" % failed)
	return false
