extends Node

## Crownspire MarchState — Wildling hunt marches + legacy timer API.
## Persist: user://marches.cfg (or isolated smoke path).

signal marches_changed
signal march_battle_resolved(march_id: String, result: Dictionary)
signal march_completed(march_id: String)

const SAVE_PATH: String = "user://marches.cfg"
const SMOKE_SAVE_PATH: String = "user://marches_smoke_test.cfg"
const MAX_ACTIVE_MARCHES: int = 2
const MAX_HEROES_PER_MARCH: int = 3
const MARCH_SPEED_PX_PER_SEC: float = 220.0
const BASE_MARCH_CAPACITY: int = 5000
const CAPACITY_PER_CASTLE_LEVEL: int = 1000

const STATUS_MARCHING: String = "MARCHING_TO_TARGET"
const STATUS_IN_COMBAT: String = "IN_COMBAT"
const STATUS_RETURNING: String = "RETURNING"
const STATUS_COMPLETED: String = "COMPLETED"

## Legacy single-timer API (WorldMap / monster popup).
var march_active: bool = false
var march_type: String = ""
var target_name: String = ""
var finish_time: int = 0

var active_marches: Array[Dictionary] = []
var _visuals: Dictionary = {} # march_id -> Node2D
var _save_path_override: String = ""
var _rewards_table: Dictionary = {}
var _march_icon_scene: PackedScene = null


func _ready() -> void:
	_load_rewards_table()
	_march_icon_scene = load("res://Scenes/World/MarchIcon.tscn") as PackedScene
	load_marches()
	call_deferred("_sync_visuals")


func _process(_delta: float) -> void:
	_tick_marches()


func get_save_path() -> String:
	if _save_path_override != "":
		return _save_path_override
	return SAVE_PATH


# --- Legacy API ---

func start_march(type, target, seconds) -> bool:
	if march_active:
		return false
	march_active = true
	march_type = str(type)
	target_name = str(target)
	finish_time = int(Time.get_unix_time_from_system()) + int(seconds)
	return true


func get_time_left() -> int:
	if not march_active:
		return 0
	return max(0, finish_time - int(Time.get_unix_time_from_system()))


func finish_march() -> void:
	march_active = false
	march_type = ""
	target_name = ""
	finish_time = 0


# --- Capacity / helpers ---

func get_march_capacity() -> int:
	var castle_level: int = 1
	if has_node("/root/GameState"):
		castle_level = max(1, int(GameState.castle_level))
	# Centralized beta fallback: castle level is the only current capacity hook.
	return BASE_MARCH_CAPACITY + (castle_level * CAPACITY_PER_CASTLE_LEVEL)


func get_active_march_count() -> int:
	var count: int = 0
	for march: Dictionary in active_marches:
		var status: String = str(march.get("status", ""))
		if status in [STATUS_MARCHING, STATUS_IN_COMBAT, STATUS_RETURNING]:
			count += 1
	return count


func can_start_wildling_march() -> Dictionary:
	if get_active_march_count() >= MAX_ACTIVE_MARCHES:
		return {"ok": false, "error": "Active march limit reached."}
	return {"ok": true}


func estimate_travel_seconds(from_pos: Vector2, to_pos: Vector2) -> int:
	var dist: float = from_pos.distance_to(to_pos)
	return max(5, int(ceil(dist / MARCH_SPEED_PX_PER_SEC)))


func calculate_march_power(troops: Dictionary, hero_ids: Array) -> int:
	var power: int = 0
	power += int(troops.get("infantry", 0)) * 10
	power += int(troops.get("marksmen", 0)) * 12
	power += int(troops.get("cavalry", 0)) * 15
	power += hero_ids.size() * 500
	return power


func get_castle_world_position() -> Vector2:
	var world: Node = get_tree().current_scene
	if world == null:
		return Vector2.ZERO
	var marker: Node2D = world.get_node_or_null("PlayerCastleMarker") as Node2D
	if marker != null:
		return marker.global_position
	var main_castle: Node2D = world.get_node_or_null("MainCastle") as Node2D
	if main_castle != null:
		return main_castle.global_position
	return Vector2.ZERO


func validate_wildling_dispatch(
	target: Dictionary,
	troops: Dictionary,
	hero_ids: Array
) -> Dictionary:
	var gate: Dictionary = can_start_wildling_march()
	if not gate.get("ok", false):
		return gate

	var inf: int = int(troops.get("infantry", 0))
	var mar: int = int(troops.get("marksmen", 0))
	var cav: int = int(troops.get("cavalry", 0))
	var total: int = inf + mar + cav
	if total <= 0:
		return {"ok": false, "error": "Select at least one troop."}

	if not has_node("/root/TroopState"):
		return {"ok": false, "error": "TroopState unavailable."}
	if TroopState.get_available_count("Infantry") < inf:
		return {"ok": false, "error": "Not enough Infantry."}
	if TroopState.get_available_count("Marksmen") < mar:
		return {"ok": false, "error": "Not enough Marksmen."}
	if TroopState.get_available_count("Cavalry") < cav:
		return {"ok": false, "error": "Not enough Cavalry."}

	var capacity: int = get_march_capacity()
	if total > capacity:
		return {"ok": false, "error": "Troops exceed march capacity (%d)." % capacity}

	if hero_ids.size() > MAX_HEROES_PER_MARCH:
		return {"ok": false, "error": "Too many heroes (max %d)." % MAX_HEROES_PER_MARCH}

	if has_node("/root/HeroState"):
		var roster_size: int = HeroState.recruited_heroes.size()
		if roster_size > 0 and hero_ids.is_empty():
			return {"ok": false, "error": "Select at least one hero."}
		for hero_id: Variant in hero_ids:
			var hid: String = str(hero_id)
			if HeroState.is_hero_on_march(hid):
				return {"ok": false, "error": "Hero already on a march."}
			if HeroState.get_hero_index(hid) == -1:
				return {"ok": false, "error": "Unknown hero selected."}

	if str(target.get("species", "")) == "" or not target.has("position"):
		return {"ok": false, "error": "Invalid Wildling target."}

	var wildling: Node2D = _resolve_wildling_node(target)
	if wildling == null or not is_instance_valid(wildling) or not wildling.visible:
		return {"ok": false, "error": "Wildling target no longer exists."}

	return {"ok": true}


func dispatch_wildling_march(
	target: Dictionary,
	troops: Dictionary,
	hero_ids: Array
) -> Dictionary:
	var check: Dictionary = validate_wildling_dispatch(target, troops, hero_ids)
	if not check.get("ok", false):
		return check

	var start_pos: Vector2 = get_castle_world_position()
	var target_pos: Vector2 = Vector2(
		float(target.get("position", {}).get("x", 0)),
		float(target.get("position", {}).get("y", 0))
	)
	var travel_sec: int = estimate_travel_seconds(start_pos, target_pos)
	var now: int = int(Time.get_unix_time_from_system())
	var troop_payload: Dictionary = {
		"infantry": int(troops.get("infantry", 0)),
		"marksmen": int(troops.get("marksmen", 0)),
		"cavalry": int(troops.get("cavalry", 0)),
	}
	var hero_payload: Array = []
	for hid: Variant in hero_ids:
		hero_payload.append(str(hid))

	if not TroopState.deploy_troops(
		troop_payload["infantry"],
		troop_payload["marksmen"],
		troop_payload["cavalry"]
	):
		return {"ok": false, "error": "Failed to deploy troops."}

	for hid: Variant in hero_payload:
		HeroState.set_hero_on_march(str(hid), true)

	var march_id: String = "march_%d_%d" % [now, randi() % 100000]
	var march: Dictionary = {
		"march_id": march_id,
		"march_type": "wildling_hunt",
		"owner_id": "local_player",
		"target_id": str(target.get("instance_id", "")),
		"target_type": "wildling",
		"target_data": target.duplicate(true),
		"start_position": {"x": start_pos.x, "y": start_pos.y},
		"target_position": {"x": target_pos.x, "y": target_pos.y},
		"departure_timestamp": now,
		"arrival_timestamp": now + travel_sec,
		"return_arrival_timestamp": 0,
		"status": STATUS_MARCHING,
		"hero_ids": hero_payload,
		"troops": troop_payload.duplicate(true),
		"original_troops": troop_payload.duplicate(true),
		"surviving_troops": troop_payload.duplicate(true),
		"march_power": calculate_march_power(troop_payload, hero_payload),
		"battle_resolved": false,
		"battle_result": {},
		"rewards_granted": false,
	}
	active_marches.append(march)
	save_marches()
	_ensure_visual(march)
	marches_changed.emit()
	return {"ok": true, "march_id": march_id, "travel_seconds": travel_sec}


func get_active_marches() -> Array[Dictionary]:
	return active_marches.duplicate(true)


# --- Tick / resolve ---

func _tick_marches() -> void:
	if active_marches.is_empty():
		return
	var now: int = int(Time.get_unix_time_from_system())
	var changed: bool = false
	var finished_ids: Array[String] = []

	for i: int in range(active_marches.size()):
		var march: Dictionary = active_marches[i]
		var status: String = str(march.get("status", ""))
		match status:
			STATUS_MARCHING:
				_update_visual_progress(march, now)
				if now >= int(march.get("arrival_timestamp", 0)):
					_resolve_battle(march)
					active_marches[i] = march
					changed = true
			STATUS_RETURNING:
				_update_visual_progress(march, now)
				if now >= int(march.get("return_arrival_timestamp", 0)):
					_complete_return(march)
					finished_ids.append(str(march.get("march_id", "")))
					changed = true
			STATUS_IN_COMBAT:
				# Should transition immediately inside _resolve_battle.
				pass

	if not finished_ids.is_empty():
		var remaining: Array[Dictionary] = []
		for march: Dictionary in active_marches:
			if str(march.get("march_id", "")) not in finished_ids:
				remaining.append(march)
			else:
				_destroy_visual(str(march.get("march_id", "")))
				march_completed.emit(str(march.get("march_id", "")))
		active_marches = remaining

	if changed:
		save_marches()
		marches_changed.emit()


func _resolve_battle(march: Dictionary) -> void:
	if bool(march.get("battle_resolved", false)):
		# Already resolved (e.g. offline); ensure returning.
		if str(march.get("status", "")) == STATUS_MARCHING:
			_begin_return(march)
		return

	march["status"] = STATUS_IN_COMBAT
	var target: Dictionary = march.get("target_data", {})
	var wildling: Node2D = _resolve_wildling_node(target)
	var wildling_alive: bool = wildling != null and is_instance_valid(wildling) and wildling.visible
	var wildling_power: int = int(target.get("power", 100))
	var march_power: int = int(march.get("march_power", 0))

	var result: Dictionary = resolve_wildling_combat(
		march.get("troops", {}),
		march_power,
		wildling_power,
		int(target.get("level", 1)),
		wildling_alive
	)
	march["battle_result"] = result
	march["battle_resolved"] = true
	march["surviving_troops"] = result.get("surviving_troops", {}).duplicate(true)

	if result.get("victory", false) and wildling_alive:
		_defeat_wildling(wildling, target)
		if not bool(march.get("rewards_granted", false)):
			var rewards: Dictionary = _grant_wildling_rewards(target)
			march["rewards_granted"] = true
			result["rewards"] = rewards
			if has_node("/root/GameEvents"):
				GameEvents.emit_wildling_defeated(1)

	march_battle_resolved.emit(str(march.get("march_id", "")), result)
	_begin_return(march)


func resolve_wildling_combat(
	troops: Dictionary,
	march_power: int,
	wildling_power: int,
	wildling_level: int,
	wildling_exists: bool
) -> Dictionary:
	var inf: int = int(troops.get("infantry", 0))
	var mar: int = int(troops.get("marksmen", 0))
	var cav: int = int(troops.get("cavalry", 0))
	var total: int = max(1, inf + mar + cav)

	if not wildling_exists:
		return {
			"victory": false,
			"summary": "The Wildling fled before your march arrived.",
			"surviving_troops": troops.duplicate(true),
			"losses": {"infantry": 0, "marksmen": 0, "cavalry": 0},
		}

	var threshold: float = float(wildling_power) * 0.75
	var victory: bool = float(march_power) >= threshold
	var loss_ratio: float = 0.12 if victory else 0.45
	loss_ratio += clampf(float(wildling_level) * 0.005, 0.0, 0.2)

	var lose_inf: int = int(floor(float(inf) * loss_ratio))
	var lose_mar: int = int(floor(float(mar) * loss_ratio))
	var lose_cav: int = int(floor(float(cav) * loss_ratio))
	if not victory and (lose_inf + lose_mar + lose_cav) == 0 and total > 0:
		lose_inf = mini(inf, 1)

	var surv: Dictionary = {
		"infantry": max(0, inf - lose_inf),
		"marksmen": max(0, mar - lose_mar),
		"cavalry": max(0, cav - lose_cav),
	}
	return {
		"victory": victory,
		"summary": "Victory!" if victory else "Defeat. Your survivors retreat.",
		"surviving_troops": surv,
		"losses": {"infantry": lose_inf, "marksmen": lose_mar, "cavalry": lose_cav},
		"march_power": march_power,
		"wildling_power": wildling_power,
	}


func _begin_return(march: Dictionary) -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var start_pos: Vector2 = Vector2(
		float(march.get("start_position", {}).get("x", 0)),
		float(march.get("start_position", {}).get("y", 0))
	)
	var cur_pos: Vector2 = Vector2(
		float(march.get("target_position", {}).get("x", 0)),
		float(march.get("target_position", {}).get("y", 0))
	)
	var travel_sec: int = estimate_travel_seconds(cur_pos, start_pos)
	march["status"] = STATUS_RETURNING
	march["departure_timestamp"] = now
	march["arrival_timestamp"] = now # outbound complete
	march["return_arrival_timestamp"] = now + travel_sec
	# Return path uses target_position as "from" visually via status RETURNING.


func _complete_return(march: Dictionary) -> void:
	var survivors: Dictionary = march.get("surviving_troops", {})
	if has_node("/root/TroopState"):
		TroopState.return_troops(
			int(survivors.get("infantry", 0)),
			int(survivors.get("marksmen", 0)),
			int(survivors.get("cavalry", 0))
		)
	if has_node("/root/HeroState"):
		for hid: Variant in march.get("hero_ids", []):
			HeroState.set_hero_on_march(str(hid), false)
	march["status"] = STATUS_COMPLETED


func _defeat_wildling(wildling: Node2D, target: Dictionary) -> void:
	if wildling == null or not is_instance_valid(wildling):
		return
	wildling.visible = false
	var area: Area2D = wildling.get_node_or_null("ClickArea") as Area2D
	if area:
		area.input_pickable = false
	# Soft respawn after delay (existing panel behavior).
	_respawn_wildling_later(wildling, area, 12.0)


func _respawn_wildling_later(wildling: Node2D, area: Area2D, delay_sec: float) -> void:
	await get_tree().create_timer(delay_sec).timeout
	if wildling != null and is_instance_valid(wildling):
		wildling.visible = true
		if area != null and is_instance_valid(area):
			area.input_pickable = true


func _grant_wildling_rewards(target: Dictionary) -> Dictionary:
	var species: String = str(target.get("species", "wolf"))
	var level: int = int(target.get("level", 1))
	var drop_types: Array = _rewards_table.get(species, ["food", "wood", "hero_xp"])
	var granted: Dictionary = {}
	var amount: int = 200 + level * 50

	for drop: Variant in drop_types:
		var key: String = str(drop)
		match key:
			"food":
				if has_node("/root/GameState"):
					GameState.add_food(amount)
				granted[key] = amount
			"wood":
				if has_node("/root/GameState"):
					GameState.add_wood(amount)
				granted[key] = amount
			"stone":
				if has_node("/root/GameState"):
					GameState.add_stone(amount)
				granted[key] = amount
			"iron":
				if has_node("/root/GameState"):
					GameState.add_iron(amount)
				granted[key] = amount
			"diamond":
				if has_node("/root/GameState"):
					GameState.diamonds += max(1, int(level / 5.0))
					GameState.save_resources()
				granted[key] = max(1, int(level / 5.0))
			"hero_xp":
				if has_node("/root/HeroState"):
					HeroState.add_hero_xp(100 + level * 25)
				granted[key] = 100 + level * 25
			_:
				if has_node("/root/InventoryState"):
					InventoryState.add_item(key, 1)
				granted[key] = 1
	return granted


func _load_rewards_table() -> void:
	var path: String = "res://data/wildling_rewards.json"
	if not FileAccess.file_exists(path):
		_rewards_table = {}
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_rewards_table = {}
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_rewards_table = parsed
	else:
		_rewards_table = {}


func _resolve_wildling_node(target: Dictionary) -> Node2D:
	var path_str: String = str(target.get("node_path", ""))
	if path_str != "":
		var node: Node = get_tree().root.get_node_or_null(NodePath(path_str))
		if node is Node2D:
			return node as Node2D
	var want_id: int = int(target.get("instance_id", 0))
	if want_id == 0:
		return null
	var world: Node = get_tree().current_scene
	if world == null:
		return null
	return _find_node_by_instance_id(world, want_id)


func _find_node_by_instance_id(root: Node, want_id: int) -> Node2D:
	if root is Node2D and root.get_instance_id() == want_id:
		return root as Node2D
	for child: Node in root.get_children():
		var found: Node2D = _find_node_by_instance_id(child, want_id)
		if found != null:
			return found
	return null


# --- Visuals ---

func _sync_visuals() -> void:
	for march: Dictionary in active_marches:
		var status: String = str(march.get("status", ""))
		if status in [STATUS_MARCHING, STATUS_RETURNING, STATUS_IN_COMBAT]:
			_ensure_visual(march)
			_update_visual_progress(march, int(Time.get_unix_time_from_system()))


func _get_marches_root() -> Node2D:
	var world: Node = get_tree().current_scene
	if world == null:
		return null
	var root: Node2D = world.get_node_or_null("Marches") as Node2D
	if root == null:
		root = Node2D.new()
		root.name = "Marches"
		world.add_child(root)
	return root


func _ensure_visual(march: Dictionary) -> void:
	var march_id: String = str(march.get("march_id", ""))
	if march_id == "" or _visuals.has(march_id):
		return
	var root: Node2D = _get_marches_root()
	if root == null:
		return
	var icon: Node2D
	if _march_icon_scene != null:
		icon = _march_icon_scene.instantiate() as Node2D
	else:
		icon = Node2D.new()
		var poly := Polygon2D.new()
		poly.color = Color(0.85, 0.65, 0.15, 1)
		poly.polygon = PackedVector2Array([Vector2(-15, -10), Vector2(20, 0), Vector2(-15, 10), Vector2(-8, 0)])
		icon.add_child(poly)
	icon.name = march_id
	root.add_child(icon)
	_visuals[march_id] = icon


func _destroy_visual(march_id: String) -> void:
	if not _visuals.has(march_id):
		return
	var node: Node2D = _visuals[march_id]
	_visuals.erase(march_id)
	if is_instance_valid(node):
		node.queue_free()


func _update_visual_progress(march: Dictionary, now: int) -> void:
	var march_id: String = str(march.get("march_id", ""))
	if not _visuals.has(march_id):
		_ensure_visual(march)
	if not _visuals.has(march_id):
		return
	var icon: Node2D = _visuals[march_id]
	if not is_instance_valid(icon):
		_visuals.erase(march_id)
		return

	var start_pos: Vector2 = Vector2(
		float(march.get("start_position", {}).get("x", 0)),
		float(march.get("start_position", {}).get("y", 0))
	)
	var target_pos: Vector2 = Vector2(
		float(march.get("target_position", {}).get("x", 0)),
		float(march.get("target_position", {}).get("y", 0))
	)
	var status: String = str(march.get("status", ""))
	var from_pos: Vector2
	var to_pos: Vector2
	var t0: int
	var t1: int
	if status == STATUS_RETURNING:
		from_pos = target_pos
		to_pos = start_pos
		t0 = int(march.get("departure_timestamp", now))
		t1 = int(march.get("return_arrival_timestamp", now + 1))
	else:
		from_pos = start_pos
		to_pos = target_pos
		t0 = int(march.get("departure_timestamp", now))
		t1 = int(march.get("arrival_timestamp", now + 1))

	var duration: float = max(1.0, float(t1 - t0))
	var alpha: float = clampf(float(now - t0) / duration, 0.0, 1.0)
	icon.global_position = from_pos.lerp(to_pos, alpha)
	var dir: Vector2 = (to_pos - from_pos)
	if dir.length() > 0.1:
		icon.rotation = dir.angle()


# --- Save / load ---

func save_marches() -> void:
	var save := ConfigFile.new()
	save.set_value("meta", "save_version", 1)
	save.set_value("registry", "marches_json", JSON.stringify(active_marches))
	save.save(get_save_path())


func load_marches() -> void:
	active_marches.clear()
	var save := ConfigFile.new()
	if save.load(get_save_path()) != OK:
		return
	var raw: String = str(save.get_value("registry", "marches_json", "[]"))
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_ARRAY:
		return
	for item: Variant in parsed:
		if typeof(item) == TYPE_DICTIONARY:
			active_marches.append(item)
	# Catch up offline progress once.
	_catch_up_offline()
	save_marches()


func _catch_up_offline() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var finished_ids: Array[String] = []
	for i: int in range(active_marches.size()):
		var march: Dictionary = active_marches[i]
		var status: String = str(march.get("status", ""))
		if status == STATUS_MARCHING and now >= int(march.get("arrival_timestamp", 0)):
			_resolve_battle(march)
			active_marches[i] = march
			status = str(march.get("status", ""))
		if status == STATUS_RETURNING and now >= int(march.get("return_arrival_timestamp", 0)):
			_complete_return(march)
			finished_ids.append(str(march.get("march_id", "")))
			active_marches[i] = march
	if not finished_ids.is_empty():
		var remaining: Array[Dictionary] = []
		for march: Dictionary in active_marches:
			var mid: String = str(march.get("march_id", ""))
			if mid not in finished_ids:
				remaining.append(march)
			else:
				_destroy_visual(mid)
		active_marches = remaining


## Build target payload from a live Wildling node + panel metadata.
func build_wildling_target(wildling: Node2D, species: String, level: int, power: int) -> Dictionary:
	if wildling == null or not is_instance_valid(wildling):
		return {}
	return {
		"instance_id": wildling.get_instance_id(),
		"node_path": str(wildling.get_path()),
		"species": species,
		"level": level,
		"power": power,
		"position": {"x": wildling.global_position.x, "y": wildling.global_position.y},
	}


# --- Smoke ---

func begin_smoke_isolation() -> void:
	_save_path_override = SMOKE_SAVE_PATH
	active_marches.clear()
	for key: Variant in _visuals.keys():
		_destroy_visual(str(key))
	if FileAccess.file_exists(SMOKE_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SMOKE_SAVE_PATH))


func end_smoke_isolation() -> void:
	_save_path_override = ""
	load_marches()


func resync_map_visuals() -> void:
	# Clear stale icons then rebuild for the current World Map scene.
	for key: Variant in _visuals.keys():
		_destroy_visual(str(key))
	_sync_visuals()


func run_wildling_march_smoke_test() -> bool:
	begin_smoke_isolation()
	var ok: bool = true

	var bak_inf: int = 0
	var bak_mar: int = 0
	var bak_cav: int = 0
	if has_node("/root/TroopState"):
		bak_inf = TroopState.infantry
		bak_mar = TroopState.marksmen
		bak_cav = TroopState.cavalry
		TroopState.infantry = 100
		TroopState.marksmen = 50
		TroopState.cavalry = 20
		# Do not save — keep player troop save untouched.

	var dummy: Node2D = Node2D.new()
	dummy.name = "SmokeWildlingTarget"
	dummy.visible = true
	var world: Node = get_tree().current_scene
	if world != null:
		world.add_child(dummy)
		dummy.global_position = Vector2(4500, 4200)
	var target: Dictionary = build_wildling_target(dummy, "wolf", 3, 50)
	if target.is_empty():
		target = {
			"instance_id": dummy.get_instance_id() if dummy != null else 1,
			"node_path": str(dummy.get_path()) if dummy != null and dummy.is_inside_tree() else "",
			"species": "wolf",
			"level": 3,
			"power": 50,
			"position": {"x": 4500.0, "y": 4200.0},
		}

	# Validation: zero troops blocked.
	var zero: Dictionary = validate_wildling_dispatch(target, {"infantry": 0, "marksmen": 0, "cavalry": 0}, [])
	if zero.get("ok", false):
		push_error("[MarchState] smoke: zero troops should fail")
		ok = false

	var over: Dictionary = validate_wildling_dispatch(target, {"infantry": 999999, "marksmen": 0, "cavalry": 0}, [])
	if over.get("ok", false):
		push_error("[MarchState] smoke: over-available troops should fail")
		ok = false

	var over_cap: Dictionary = validate_wildling_dispatch(
		target,
		{"infantry": get_march_capacity() + 1, "marksmen": 0, "cavalry": 0},
		[]
	)
	# May fail for availability first if capacity > 100; force capacity check via temp boost.
	if has_node("/root/TroopState"):
		TroopState.infantry = get_march_capacity() + 50
	over_cap = validate_wildling_dispatch(
		target,
		{"infantry": get_march_capacity() + 1, "marksmen": 0, "cavalry": 0},
		[]
	)
	if over_cap.get("ok", false):
		push_error("[MarchState] smoke: over-capacity should fail")
		ok = false

	# Missing wildling blocked.
	var ghost: Dictionary = {
		"instance_id": 999999001,
		"node_path": "",
		"species": "wolf",
		"level": 1,
		"power": 10,
		"position": {"x": 1.0, "y": 1.0},
	}
	var missing: Dictionary = dispatch_wildling_march(ghost, {"infantry": 10, "marksmen": 0, "cavalry": 0}, [])
	if missing.get("ok", false):
		push_error("[MarchState] smoke: missing wildling should fail dispatch")
		ok = false

	# Valid dispatch against live dummy.
	if has_node("/root/TroopState"):
		TroopState.infantry = 100
		TroopState.marksmen = 50
		TroopState.cavalry = 20
	var hero_ids: Array = []
	if has_node("/root/HeroState"):
		for hero: Dictionary in HeroState.get_available_heroes():
			hero_ids.append(str(hero.get("id", "")))
			break
	var dispatched: Dictionary = dispatch_wildling_march(target, {"infantry": 10, "marksmen": 5, "cavalry": 0}, hero_ids)
	if not dispatched.get("ok", false):
		push_error("[MarchState] smoke: valid dispatch failed: %s" % str(dispatched.get("error", "")))
		ok = false
	else:
		# Clean up without touching real save path (still in smoke isolation).
		for march: Dictionary in active_marches.duplicate(true):
			_complete_return(march)
			_destroy_visual(str(march.get("march_id", "")))
		active_marches.clear()
		save_marches()

	# Combat resolver unit check.
	var win: Dictionary = resolve_wildling_combat({"infantry": 100, "marksmen": 0, "cavalry": 0}, 5000, 100, 1, true)
	if not win.get("victory", false):
		push_error("[MarchState] smoke: expected combat victory")
		ok = false
	var lose: Dictionary = resolve_wildling_combat({"infantry": 1, "marksmen": 0, "cavalry": 0}, 10, 5000, 20, true)
	if lose.get("victory", false):
		push_error("[MarchState] smoke: expected combat defeat")
		ok = false

	if get_march_capacity() < BASE_MARCH_CAPACITY:
		push_error("[MarchState] smoke: capacity too low")
		ok = false

	if dummy != null and is_instance_valid(dummy):
		dummy.queue_free()

	if has_node("/root/TroopState"):
		TroopState.infantry = bak_inf
		TroopState.marksmen = bak_mar
		TroopState.cavalry = bak_cav

	if ok:
		print("[MarchState] Wildling march smoke test PASSED")
	end_smoke_isolation()
	return ok
