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
## image_68a78d6f is fixed-angle isometric facing BOTTOM-RIGHT (SE).
## Orientation uses flip_h only — never continuous rotation.

const STATUS_MARCHING: String = "MARCHING_TO_TARGET"
const STATUS_IN_COMBAT: String = "IN_COMBAT"
const STATUS_GATHERING: String = "GATHERING"
const STATUS_RETURNING: String = "RETURNING"
const STATUS_COMPLETED: String = "COMPLETED"

## Beta placeholder gather rate (resources / second). Tunable — not final economy balance.
## Same base rate for Food/Wood/Stone/Iron in Step 2.
const BASE_GATHER_RATE_PER_SEC: float = 50.0
const MIN_GATHER_SECONDS: int = 1

## Legacy single-timer API (WorldMap / monster popup).
var march_active: bool = false
var march_type: String = ""
var target_name: String = ""
var finish_time: int = 0

var active_marches: Array[Dictionary] = []
var _visuals: Dictionary = {} # march_id -> Node2D
var _gather_indicators: Dictionary = {} # march_id -> Node2D (tile badge)
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
		if status in [STATUS_MARCHING, STATUS_IN_COMBAT, STATUS_GATHERING, STATUS_RETURNING]:
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


## World aim point for a Wildling (sprite/collision center, not offset root).
func get_wildling_aim_position(wildling: Node2D) -> Vector2:
	if wildling == null or not is_instance_valid(wildling):
		return Vector2.ZERO
	var sprite: Sprite2D = wildling.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		return sprite.global_position
	var click_shape: CollisionShape2D = wildling.get_node_or_null("ClickArea/CollisionShape2D") as CollisionShape2D
	if click_shape != null:
		return click_shape.global_position
	return wildling.global_position


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
	# Re-lock destination from the live selected Wildling — never nearest/stale guess.
	var live_wildling: Node2D = _resolve_wildling_node(target)
	var target_pos: Vector2 = get_wildling_aim_position(live_wildling)
	if target_pos == Vector2.ZERO:
		target_pos = Vector2(
			float(target.get("position", {}).get("x", 0)),
			float(target.get("position", {}).get("y", 0))
		)
	# Persist refreshed world aim into the march target payload.
	target = target.duplicate(true)
	target["position"] = {"x": target_pos.x, "y": target_pos.y}
	if live_wildling != null:
		target["instance_id"] = live_wildling.get_instance_id()
		target["node_path"] = str(live_wildling.get_path())

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
		"mail_report_created": false,
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
	var now_f: float = Time.get_unix_time_from_system()
	var now: int = int(now_f)
	var changed: bool = false
	var finished_ids: Array[String] = []

	for i: int in range(active_marches.size()):
		var march: Dictionary = active_marches[i]
		var status: String = str(march.get("status", ""))
		var mtype: String = str(march.get("march_type", ""))
		match status:
			STATUS_MARCHING:
				_update_visual_progress(march, now_f)
				if now >= int(march.get("arrival_timestamp", 0)):
					if mtype == "gather":
						_begin_gathering(march)
					else:
						_resolve_battle(march)
					active_marches[i] = march
					changed = true
			STATUS_GATHERING:
				_update_visual_progress(march, now_f)
				if now >= int(march.get("gather_end_unix", 0)):
					_finish_gathering(march)
					active_marches[i] = march
					changed = true
			STATUS_RETURNING:
				_update_visual_progress(march, now_f)
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

	_create_battle_mail_report(march, result)
	march_battle_resolved.emit(str(march.get("march_id", "")), result)
	_begin_return(march)


## Persist exactly one Mail battle report per resolved march (no reward re-grant).
func _create_battle_mail_report(march: Dictionary, result: Dictionary) -> void:
	if bool(march.get("mail_report_created", false)):
		return
	if not has_node("/root/MailManager"):
		return
	if not MailManager.has_method("add_wildling_battle_report"):
		return
	var created: bool = bool(MailManager.add_wildling_battle_report(march, result))
	if created or MailManager.has_report_for_march(str(march.get("march_id", ""))):
		march["mail_report_created"] = true


## Gathering Report after home credit — once per march (offline-safe).
func _create_gathering_mail_report(march: Dictionary) -> void:
	if bool(march.get("mail_report_created", false)):
		return
	if not has_node("/root/MailManager"):
		return
	if not MailManager.has_method("add_gathering_report"):
		return
	var mid: String = str(march.get("march_id", ""))
	var created: bool = bool(MailManager.add_gathering_report(march))
	if created or MailManager.has_gathering_report_for_march(mid):
		march["mail_report_created"] = true


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
	_begin_return_at(march, now)


func _begin_return_at(march: Dictionary, start_unix: int) -> void:
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
	march["departure_timestamp"] = start_unix
	march["arrival_timestamp"] = start_unix # outbound complete
	march["return_arrival_timestamp"] = start_unix + travel_sec


func _gather_tile_id(march: Dictionary) -> String:
	var tile_id: String = str(march.get("resource_tile_id", ""))
	if tile_id != "":
		return tile_id
	if typeof(march.get("target_data", {})) == TYPE_DICTIONARY:
		return str((march.get("target_data", {}) as Dictionary).get("resource_tile_id", ""))
	return ""


func _begin_gathering(march: Dictionary) -> void:
	var arrival: int = int(march.get("arrival_timestamp", Time.get_unix_time_from_system()))
	var tile_id: String = _gather_tile_id(march)
	var march_id: String = str(march.get("march_id", ""))
	var cargo: int = maxi(0, int(march.get("cargo_capacity", 0)))
	var gather_amount: int = 0

	if has_node("/root/ResourceTileState") and tile_id != "":
		var begin_res: Dictionary = ResourceTileState.begin_gathering_on_tile(tile_id, march_id)
		if not bool(begin_res.get("ok", false)):
			# Reservation mismatch / missing tile — fail safe, return empty cargo.
			march["gather_target_amount"] = 0
			march["gathered_amount"] = 0
			march["gather_seconds"] = 0
			march["gather_started_unix"] = arrival
			march["gather_end_unix"] = arrival
			march["status"] = STATUS_RETURNING
			_begin_return_at(march, arrival)
			return
		gather_amount = mini(cargo, int(begin_res.get("remaining", 0)))
	else:
		gather_amount = mini(cargo, int(march.get("gather_target_amount", 0)))

	if gather_amount <= 0:
		if has_node("/root/ResourceTileState") and tile_id != "":
			ResourceTileState.release_reservation(tile_id, march_id)
		march["gather_target_amount"] = 0
		march["gathered_amount"] = 0
		march["gather_seconds"] = 0
		march["gather_started_unix"] = arrival
		march["gather_end_unix"] = arrival
		_begin_return_at(march, arrival)
		return

	var gather_sec: int = calculate_gather_seconds(gather_amount)
	march["gather_target_amount"] = gather_amount
	march["gather_seconds"] = gather_sec
	march["status"] = STATUS_GATHERING
	march["gather_started_unix"] = arrival
	march["gather_end_unix"] = arrival + gather_sec
	# Tile amount is reduced on gather complete; GameState credit only on home return.


func _finish_gathering(march: Dictionary) -> void:
	var amount: int = maxi(0, int(march.get("gather_target_amount", 0)))
	march["gathered_amount"] = amount
	if not bool(march.get("tile_amount_applied", false)):
		var tile_id: String = _gather_tile_id(march)
		if has_node("/root/ResourceTileState") and tile_id != "":
			ResourceTileState.apply_gather_completion(
				tile_id,
				str(march.get("march_id", "")),
				amount
			)
		march["tile_amount_applied"] = true
	var gather_end: int = int(march.get("gather_end_unix", Time.get_unix_time_from_system()))
	_begin_return_at(march, gather_end)


func _complete_return(march: Dictionary) -> void:
	var mtype: String = str(march.get("march_type", ""))
	if mtype == "gather":
		if not bool(march.get("troops_returned", false)):
			if has_node("/root/TroopState"):
				var tiers: Dictionary = march.get("original_troop_tiers", march.get("troop_tiers", {}))
				if typeof(tiers) == TYPE_DICTIONARY and not tiers.is_empty():
					TroopState.return_troops_by_tiers(tiers)
				else:
					var troops: Dictionary = march.get("original_troops", march.get("troops", {}))
					TroopState.return_troops(
						int(troops.get("infantry", 0)),
						int(troops.get("marksmen", 0)),
						int(troops.get("cavalry", 0))
					)
			march["troops_returned"] = true
		if not bool(march.get("resources_credited", false)):
			_credit_gather_cargo(march)
			march["resources_credited"] = true
		_create_gathering_mail_report(march)
		if has_node("/root/HeroState"):
			for hid: Variant in march.get("hero_ids", []):
				HeroState.set_hero_on_march(str(hid), false)
		march["status"] = STATUS_COMPLETED
		return

	var survivors: Dictionary = march.get("surviving_troops", {})
	if has_node("/root/TroopState"):
		TroopState.return_troops(
			int(survivors.get("infantry", 0)),
			int(survivors.get("marksmen", 0)),
			int(survivors.get("cavalry", 0))
		)
	if has_node("/root/HeroState"):
		for hid2: Variant in march.get("hero_ids", []):
			HeroState.set_hero_on_march(str(hid2), false)
	march["status"] = STATUS_COMPLETED


func _credit_gather_cargo(march: Dictionary) -> void:
	if not has_node("/root/GameState"):
		return
	var amount: int = maxi(0, int(march.get("gathered_amount", 0)))
	if amount <= 0:
		return
	var rtype: String = str(march.get("resource_type", "")).strip_edges().to_lower()
	if rtype == "" and typeof(march.get("target_data", {})) == TYPE_DICTIONARY:
		rtype = str((march.get("target_data", {}) as Dictionary).get("resource_type", "")).strip_edges().to_lower()
	match rtype:
		"food":
			GameState.add_food(amount)
		"wood":
			GameState.add_wood(amount)
		"stone":
			GameState.add_stone(amount)
		"iron":
			GameState.add_iron(amount)
		_:
			push_warning("[MarchState] Unknown gather resource_type '%s' — no credit." % rtype)


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
		if status in [STATUS_MARCHING, STATUS_RETURNING, STATUS_IN_COMBAT, STATUS_GATHERING]:
			_ensure_visual(march)
			_update_visual_progress(march, Time.get_unix_time_from_system())


func _get_marches_root() -> Node2D:
	var world: Node = get_tree().current_scene
	if world == null:
		return null
	var root: Node2D = world.get_node_or_null("Marches") as Node2D
	if root == null:
		root = Node2D.new()
		root.name = "Marches"
		world.add_child(root)
	# Resource tiles use z_index 100 — marches must draw above them while gathering.
	root.z_index = 250
	root.y_sort_enabled = false
	return root


func _ensure_visual(march: Dictionary) -> void:
	var march_id: String = str(march.get("march_id", ""))
	if march_id == "":
		return
	if _visuals.has(march_id):
		var existing: Node2D = _visuals[march_id] as Node2D
		if existing != null and is_instance_valid(existing):
			return
		_visuals.erase(march_id)
	var root: Node2D = _get_marches_root()
	if root == null:
		return
	var icon: Node2D
	if _march_icon_scene != null:
		icon = _march_icon_scene.instantiate() as Node2D
	else:
		# Fallback: build the intended animated march sprite (never the old arrow).
		icon = _make_animated_march_icon()
	icon.name = march_id
	icon.z_index = 1
	root.add_child(icon)
	_play_march_walk(icon)
	_visuals[march_id] = icon


func _make_animated_march_icon() -> Node2D:
	var icon := Node2D.new()
	var anim := AnimatedSprite2D.new()
	anim.name = "AnimatedSprite2D"
	anim.scale = Vector2(0.45, 0.45)
	var sheet_path := "res://assets/MarchSkins/image_68a78d6f-removebg-preview.png"
	if ResourceLoader.exists(sheet_path):
		var sheet: Texture2D = load(sheet_path) as Texture2D
		var frames := SpriteFrames.new()
		frames.add_animation("walk")
		frames.set_animation_speed("walk", 10.0)
		frames.set_animation_loop("walk", true)
		for region: Rect2 in [
			Rect2(2, 0, 248, 235),
			Rect2(253, 0, 248, 235),
			Rect2(504, 0, 248, 235),
			Rect2(755, 0, 248, 235),
		]:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = region
			frames.add_frame("walk", atlas)
		anim.sprite_frames = frames
		anim.animation = &"walk"
	icon.add_child(anim)
	return icon


func _play_march_walk(icon: Node2D) -> void:
	if icon == null:
		return
	var anim: AnimatedSprite2D = icon.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim == null:
		anim = icon as AnimatedSprite2D
	if anim != null and anim.sprite_frames != null:
		anim.play("walk")


func _pause_march_walk(icon: Node2D) -> void:
	if icon == null:
		return
	var anim: AnimatedSprite2D = icon.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim == null:
		anim = icon as AnimatedSprite2D
	if anim != null:
		anim.pause()


## World position for HUD camera focus (same lerp rules as march visuals).
func get_march_world_position(march_id: String) -> Vector2:
	for march: Dictionary in active_marches:
		if str(march.get("march_id", "")) != march_id:
			continue
		return _compute_march_world_position(march, Time.get_unix_time_from_system())
	return Vector2.ZERO


func _compute_march_world_position(march: Dictionary, now: float) -> Vector2:
	var start_pos: Vector2 = Vector2(
		float(march.get("start_position", {}).get("x", 0)),
		float(march.get("start_position", {}).get("y", 0))
	)
	var target_pos: Vector2 = Vector2(
		float(march.get("target_position", {}).get("x", 0)),
		float(march.get("target_position", {}).get("y", 0))
	)
	var status: String = str(march.get("status", ""))
	if status == STATUS_GATHERING or status == STATUS_IN_COMBAT:
		return target_pos
	var from_pos: Vector2
	var to_pos: Vector2
	var t0: float
	var t1: float
	if status == STATUS_RETURNING:
		from_pos = target_pos
		to_pos = start_pos
		t0 = float(march.get("departure_timestamp", now))
		t1 = float(march.get("return_arrival_timestamp", now + 1))
	else:
		from_pos = start_pos
		to_pos = target_pos
		t0 = float(march.get("departure_timestamp", now))
		t1 = float(march.get("arrival_timestamp", now + 1))
	var duration: float = max(1.0, t1 - t0)
	var alpha: float = clampf((now - t0) / duration, 0.0, 1.0)
	return from_pos.lerp(to_pos, alpha)


func _destroy_visual(march_id: String) -> void:
	_clear_gather_indicator(march_id)
	if not _visuals.has(march_id):
		return
	var node: Node2D = _visuals[march_id]
	_visuals.erase(march_id)
	if is_instance_valid(node):
		node.queue_free()


func _update_visual_progress(march: Dictionary, now: float) -> void:
	var march_id: String = str(march.get("march_id", ""))
	if not _visuals.has(march_id):
		_ensure_visual(march)
	if not _visuals.has(march_id):
		return
	var icon: Node2D = _visuals[march_id]
	if not is_instance_valid(icon):
		_visuals.erase(march_id)
		_ensure_visual(march)
		if not _visuals.has(march_id):
			return
		icon = _visuals[march_id]
		if not is_instance_valid(icon):
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
	var t0: float
	var t1: float
	if status == STATUS_RETURNING:
		_clear_gather_indicator(march_id)
		icon.visible = true
		from_pos = target_pos
		to_pos = start_pos
		t0 = float(march.get("departure_timestamp", now))
		t1 = float(march.get("return_arrival_timestamp", now + 1))
	elif status == STATUS_GATHERING:
		# Hide walking march; show compact tile indicator + timer instead.
		icon.visible = false
		icon.global_position = target_pos
		_ensure_gather_indicator(march, target_pos)
		_update_gather_indicator(march_id, now)
		return
	elif status == STATUS_IN_COMBAT:
		_clear_gather_indicator(march_id)
		icon.visible = true
		icon.global_position = target_pos
		_apply_march_visual_direction(icon, Vector2(1, 0))
		_pause_march_walk(icon)
		return
	else:
		_clear_gather_indicator(march_id)
		icon.visible = true
		from_pos = start_pos
		to_pos = target_pos
		t0 = float(march.get("departure_timestamp", now))
		t1 = float(march.get("arrival_timestamp", now + 1))

	var duration: float = max(1.0, t1 - t0)
	var alpha: float = clampf((now - t0) / duration, 0.0, 1.0)
	icon.global_position = from_pos.lerp(to_pos, alpha)
	_apply_march_visual_direction(icon, to_pos - from_pos)
	_play_march_walk(icon)


func _ensure_gather_indicator(march: Dictionary, target_pos: Vector2) -> void:
	var march_id: String = str(march.get("march_id", ""))
	if march_id == "":
		return
	if _gather_indicators.has(march_id):
		var existing: Node2D = _gather_indicators[march_id] as Node2D
		if existing != null and is_instance_valid(existing):
			existing.global_position = target_pos + Vector2(0.0, -72.0)
			return
		_gather_indicators.erase(march_id)

	var root: Node2D = _get_marches_root()
	if root == null:
		return
	var badge: Node2D = _make_gather_indicator()
	badge.name = "GatherIndicator_%s" % march_id
	root.add_child(badge)
	badge.global_position = target_pos + Vector2(0.0, -72.0)
	_gather_indicators[march_id] = badge


func _make_gather_indicator() -> Node2D:
	var root := Node2D.new()
	root.z_index = 260
	var visual := Node2D.new()
	visual.name = "Visual"
	root.add_child(visual)

	var bg := ColorRect.new()
	bg.name = "BadgeBg"
	bg.color = Color(0.08, 0.07, 0.12, 0.90)
	bg.size = Vector2(92, 56)
	bg.position = Vector2(-46, -28)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(bg)

	var border := ColorRect.new()
	border.name = "BadgeBorder"
	border.color = Color(0.86, 0.70, 0.32, 0.95)
	border.size = Vector2(92, 3)
	border.position = Vector2(-46, -28)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(border)

	var label := Label.new()
	label.name = "TimerLabel"
	label.text = "GATHER\n00:00"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(-46, -26)
	label.size = Vector2(92, 52)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.78, 1.0))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(label)
	return root


func _update_gather_indicator(march_id: String, now: float) -> void:
	if not _gather_indicators.has(march_id):
		return
	var badge: Node2D = _gather_indicators[march_id] as Node2D
	if badge == null or not is_instance_valid(badge):
		_gather_indicators.erase(march_id)
		return
	# Keep badge roughly constant on-screen size while the map zooms.
	var cam: Camera2D = get_viewport().get_camera_2d() if get_viewport() != null else null
	var zoom_x: float = cam.zoom.x if cam != null else 1.0
	var visual: Node2D = badge.get_node_or_null("Visual") as Node2D
	if visual != null:
		var s: float = 1.0 / maxf(0.35, zoom_x)
		visual.scale = Vector2(s, s)

	var remain: int = 0
	for march: Dictionary in active_marches:
		if str(march.get("march_id", "")) != march_id:
			continue
		remain = maxi(0, int(march.get("gather_end_unix", 0)) - int(now))
		break
	var label: Label = badge.get_node_or_null("Visual/TimerLabel") as Label
	if label != null:
		label.text = "GATHER\n%s" % _format_mmss(remain)


func _format_mmss(total_sec: int) -> String:
	var sec: int = maxi(0, total_sec)
	return "%02d:%02d" % [int(sec / 60), sec % 60]


func _clear_gather_indicator(march_id: String) -> void:
	if not _gather_indicators.has(march_id):
		return
	var badge: Node2D = _gather_indicators[march_id] as Node2D
	_gather_indicators.erase(march_id)
	if badge != null and is_instance_valid(badge):
		badge.queue_free()


## Single canonical orientation for outbound AND return.
## Source art (image_68a78d6f) is fixed-angle isometric facing BOTTOM-RIGHT (SE).
## It is NOT designed for continuous rotation — rotating it causes upside-down /
## sideways walking. Keep rotation at 0; use flip_h for left vs right travel.
## Limitation: pure up/down travel still shows the SE/SW isometric pose (no up-facing frames exist).
func _apply_march_visual_direction(march_visual: Node2D, travel_vector: Vector2) -> void:
	if march_visual == null or travel_vector.length() <= 0.1:
		return
	march_visual.rotation = 0.0
	march_visual.scale = Vector2(1, 1)
	var anim: AnimatedSprite2D = march_visual.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim == null:
		return
	anim.rotation = 0.0
	anim.flip_v = false
	# Preserve positive scale; never invert with negative scale.
	anim.scale = Vector2(absf(anim.scale.x) if anim.scale.x != 0.0 else 0.45, absf(anim.scale.y) if anim.scale.y != 0.0 else 0.45)
	# Leftward travel → mirror to face bottom-left; otherwise keep native SE.
	anim.flip_h = travel_vector.x < 0.0


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
	# Cascade transitions (outbound → gather → return → complete) until stable.
	for _pass: int in range(12):
		var progressed: bool = false
		for i: int in range(active_marches.size()):
			var march: Dictionary = active_marches[i]
			var mid: String = str(march.get("march_id", ""))
			if mid in finished_ids:
				continue
			var status: String = str(march.get("status", ""))
			var mtype: String = str(march.get("march_type", ""))
			if status == STATUS_MARCHING and now >= int(march.get("arrival_timestamp", 0)):
				if mtype == "gather":
					_begin_gathering(march)
				else:
					_resolve_battle(march)
				active_marches[i] = march
				progressed = true
			elif status == STATUS_GATHERING and now >= int(march.get("gather_end_unix", 0)):
				_finish_gathering(march)
				active_marches[i] = march
				progressed = true
			elif status == STATUS_RETURNING and now >= int(march.get("return_arrival_timestamp", 0)):
				_complete_return(march)
				finished_ids.append(mid)
				active_marches[i] = march
				progressed = true
			elif status == STATUS_IN_COMBAT:
				_begin_return(march)
				active_marches[i] = march
				progressed = true
		if not progressed:
			break
	if not finished_ids.is_empty():
		var remaining: Array[Dictionary] = []
		for march2: Dictionary in active_marches:
			var mid2: String = str(march2.get("march_id", ""))
			if mid2 not in finished_ids:
				remaining.append(march2)
			else:
				_destroy_visual(mid2)
		active_marches = remaining


## Build target payload from a live Wildling node + panel metadata.
func build_wildling_target(wildling: Node2D, species: String, level: int, power: int) -> Dictionary:
	if wildling == null or not is_instance_valid(wildling):
		return {}
	var aim: Vector2 = get_wildling_aim_position(wildling)
	return {
		"instance_id": wildling.get_instance_id(),
		"node_path": str(wildling.get_path()),
		"species": species,
		"level": level,
		"power": power,
		"position": {"x": aim.x, "y": aim.y},
	}


## Build target payload from a live World resource tile (Step 1 handoff to MarchSetup).
## Does NOT start a march. Canonical remaining comes from ResourceTileState.
func build_resource_target(
	resource_node: Node2D,
	resource_type: String,
	level: int,
	amount: int,
	tile_id: String = ""
) -> Dictionary:
	if resource_node == null or not is_instance_valid(resource_node):
		return {}
	var rtype: String = resource_type.strip_edges().to_lower()
	if rtype not in ["food", "wood", "stone", "iron"]:
		return {}
	var resolved_tile_id: String = tile_id
	if resolved_tile_id == "":
		var click: Node = resource_node.get_node_or_null("ClickArea")
		if click != null and "tile_id" in click:
			resolved_tile_id = str(click.get("tile_id"))
	var live_level: int = level
	var live_amount: int = amount
	if has_node("/root/ResourceTileState") and resolved_tile_id != "":
		var state: Dictionary = ResourceTileState.get_tile(resolved_tile_id)
		if not state.is_empty():
			live_level = int(state.get("level", live_level))
			live_amount = int(state.get("remaining_amount", live_amount))
			rtype = str(state.get("resource_type", rtype))
	var pos: Vector2 = resource_node.global_position
	return {
		"target_type": "resource",
		"resource_tile_id": resolved_tile_id,
		"resource_type": rtype,
		"resource_level": live_level,
		"resource_amount": live_amount,
		"level": live_level,
		"display_name": _resource_display_name(rtype),
		"instance_id": resource_node.get_instance_id(),
		"node_path": str(resource_node.get_path()),
		"world_position": {"x": pos.x, "y": pos.y},
		"position": {"x": pos.x, "y": pos.y},
	}


func _resource_display_name(resource_type: String) -> String:
	match resource_type:
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


## Gate for opening March Setup from a resource Gather CTA (no wildling combat).
func can_start_resource_setup() -> Dictionary:
	if get_active_march_count() >= MAX_ACTIVE_MARCHES:
		return {"ok": false, "error": "All march slots are busy."}
	return {"ok": true}


## Validate troop/hero selection for a resource target without dispatching.
func validate_resource_setup(
	target: Dictionary,
	troops: Dictionary,
	hero_ids: Array
) -> Dictionary:
	if str(target.get("target_type", "")) != "resource":
		return {"ok": false, "error": "Invalid resource target."}
	var rtype: String = str(target.get("resource_type", "")).strip_edges().to_lower()
	if rtype not in ["food", "wood", "stone", "iron"]:
		return {"ok": false, "error": "Unsupported resource type."}
	if not target.has("position"):
		return {"ok": false, "error": "Missing resource world position."}
	var tile_id: String = str(target.get("resource_tile_id", ""))
	if tile_id == "":
		return {"ok": false, "error": "Missing resource tile id."}
	if not has_node("/root/ResourceTileState"):
		return {"ok": false, "error": "Resource tile state unavailable."}
	var remaining: int = ResourceTileState.get_remaining(tile_id)
	if remaining <= 0:
		return {"ok": false, "error": "Resource node has no available amount."}
	var occ: Dictionary = ResourceTileState.can_reserve(tile_id)
	if not bool(occ.get("ok", false)):
		return {"ok": false, "error": str(occ.get("error", "Resource tile is already occupied."))}

	var gate: Dictionary = can_start_resource_setup()
	if not bool(gate.get("ok", false)):
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

	return {"ok": true}


## Build lowest-tier-first composition for aggregate counts (string tier keys).
func build_troop_tier_composition(troops: Dictionary) -> Dictionary:
	if not has_node("/root/TroopState"):
		return {}
	var inf_plan: Dictionary = TroopState.plan_tier_allocation("Infantry", int(troops.get("infantry", 0)))
	var mar_plan: Dictionary = TroopState.plan_tier_allocation("Marksmen", int(troops.get("marksmen", 0)))
	var cav_plan: Dictionary = TroopState.plan_tier_allocation("Cavalry", int(troops.get("cavalry", 0)))
	if int(troops.get("infantry", 0)) > 0 and inf_plan.is_empty():
		return {}
	if int(troops.get("marksmen", 0)) > 0 and mar_plan.is_empty():
		return {}
	if int(troops.get("cavalry", 0)) > 0 and cav_plan.is_empty():
		return {}
	return {
		"infantry": inf_plan,
		"marksmen": mar_plan,
		"cavalry": cav_plan,
	}


## Sum(qty × TroopDatabase.load) for a tier composition.
func calculate_troop_load(composition: Dictionary) -> int:
	var total: int = 0
	if not has_node("/root/TroopDatabase"):
		return 0
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = composition.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			continue
		for tier_key: Variant in by_tier.keys():
			var qty: int = int(by_tier[tier_key])
			if qty <= 0:
				continue
			var troop: Dictionary = TroopDatabase.get_troop(kind, int(tier_key))
			var unit_load: int = int(troop.get("load", 0))
			total += qty * unit_load
	return total


func calculate_gather_seconds(gather_amount: int) -> int:
	if gather_amount <= 0:
		return MIN_GATHER_SECONDS
	var rate: float = maxf(0.001, BASE_GATHER_RATE_PER_SEC)
	return maxi(MIN_GATHER_SECONDS, int(ceil(float(gather_amount) / rate)))


## Dispatch a gather march. Removes troops once after validation; never uses wildling combat.
func dispatch_gather_march(
	target: Dictionary,
	troops: Dictionary,
	hero_ids: Array
) -> Dictionary:
	var check: Dictionary = validate_resource_setup(target, troops, hero_ids)
	if not bool(check.get("ok", false)):
		return check

	var composition: Dictionary = build_troop_tier_composition(troops)
	if composition.is_empty():
		return {"ok": false, "error": "Could not allocate troop tiers."}

	var cargo_capacity: int = calculate_troop_load(composition)
	if cargo_capacity <= 0:
		return {"ok": false, "error": "Selected troops have no cargo load."}

	var tile_id: String = str(target.get("resource_tile_id", ""))
	var remaining_live: int = ResourceTileState.get_remaining(tile_id)
	var gather_target_amount: int = mini(cargo_capacity, remaining_live)
	if gather_target_amount <= 0:
		return {"ok": false, "error": "Nothing to gather."}

	var gather_seconds: int = calculate_gather_seconds(gather_target_amount)
	var start_pos: Vector2 = get_castle_world_position()
	var target_pos := Vector2(
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

	# Reserve tile before consuming troops / march slot.
	var march_id: String = "march_%d_%d" % [now, randi() % 100000]
	var reserved: Dictionary = ResourceTileState.reserve_tile(tile_id, march_id)
	if not bool(reserved.get("ok", false)):
		return {"ok": false, "error": str(reserved.get("error", "Resource tile is already occupied."))}

	# Remove troops only after reservation succeeded.
	if not TroopState.deploy_troops_by_tiers(composition):
		ResourceTileState.release_reservation(tile_id, march_id)
		return {"ok": false, "error": "Failed to deploy troops by tier."}

	if has_node("/root/HeroState"):
		for hid2: Variant in hero_payload:
			HeroState.set_hero_on_march(str(hid2), true)

	var rtype: String = str(target.get("resource_type", "")).strip_edges().to_lower()
	var target_payload: Dictionary = target.duplicate(true)
	target_payload["resource_tile_id"] = tile_id
	target_payload["resource_amount"] = remaining_live
	var march: Dictionary = {
		"march_id": march_id,
		"march_type": "gather",
		"owner_id": "local_player",
		"target_id": tile_id,
		"resource_tile_id": tile_id,
		"target_type": "resource",
		"resource_type": rtype,
		"target_data": target_payload,
		"start_position": {"x": start_pos.x, "y": start_pos.y},
		"target_position": {"x": target_pos.x, "y": target_pos.y},
		"departure_timestamp": now,
		"arrival_timestamp": now + travel_sec,
		"return_arrival_timestamp": 0,
		"status": STATUS_MARCHING,
		"hero_ids": hero_payload,
		"troops": troop_payload.duplicate(true),
		"original_troops": troop_payload.duplicate(true),
		"troop_tiers": composition.duplicate(true),
		"original_troop_tiers": composition.duplicate(true),
		"surviving_troops": troop_payload.duplicate(true),
		"cargo_capacity": cargo_capacity,
		"gather_target_amount": gather_target_amount,
		"gathered_amount": 0,
		"gather_seconds": gather_seconds,
		"gather_started_unix": 0,
		"gather_end_unix": 0,
		"gather_rate_per_sec": BASE_GATHER_RATE_PER_SEC,
		"tile_amount_applied": false,
		"resources_credited": false,
		"troops_returned": false,
		"march_power": calculate_march_power(troop_payload, hero_payload),
		"battle_resolved": false,
		"battle_result": {},
		"rewards_granted": false,
		"mail_report_created": false,
	}
	active_marches.append(march)
	save_marches()
	_ensure_visual(march)
	marches_changed.emit()
	return {
		"ok": true,
		"march_id": march_id,
		"travel_seconds": travel_sec,
		"gather_seconds": gather_seconds,
		"cargo_capacity": cargo_capacity,
		"gather_target_amount": gather_target_amount,
		"troop_tiers": composition.duplicate(true),
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
	# Clear stale icons/indicators then rebuild for the current World Map scene.
	for key: Variant in _visuals.keys():
		_destroy_visual(str(key))
	for key: Variant in _gather_indicators.keys():
		_clear_gather_indicator(str(key))
	_sync_visuals()


## Step 3: gather reservation + live remaining + deplete/credit timing (isolated saves).
func run_gather_tile_sync_smoke_test() -> bool:
	begin_smoke_isolation()
	if has_node("/root/ResourceTileState"):
		ResourceTileState.begin_smoke_isolation()
	var failed: int = 0

	var bak_inf_map: Dictionary = {}
	var bak_mar_map: Dictionary = {}
	var bak_cav_map: Dictionary = {}
	if has_node("/root/TroopState"):
		bak_inf_map = TroopState.infantry_by_tier.duplicate(true)
		bak_mar_map = TroopState.marksmen_by_tier.duplicate(true)
		bak_cav_map = TroopState.cavalry_by_tier.duplicate(true)
		TroopState.infantry_by_tier = {1: 200}
		TroopState.marksmen_by_tier = {}
		TroopState.cavalry_by_tier = {}
		TroopState._resync_totals()

	var food_before: int = 0
	if has_node("/root/GameState"):
		food_before = int(GameState.food)

	var tile_id: String = ResourceTileState.allocate_tile_id("food")
	ResourceTileState.register_or_update_tile(
		tile_id, "food", 1, 10000, 10000, Vector2(4200, 4100), ResourceTileState.STATUS_AVAILABLE
	)
	ResourceTileState.save_tiles()

	var target: Dictionary = {
		"target_type": "resource",
		"resource_tile_id": tile_id,
		"resource_type": "food",
		"resource_level": 1,
		"resource_amount": 10000,
		"level": 1,
		"display_name": "Fertile Wheat Farm",
		"instance_id": 1,
		"node_path": "",
		"world_position": {"x": 4200.0, "y": 4100.0},
		"position": {"x": 4200.0, "y": 4100.0},
	}

	var troops: Dictionary = {"infantry": 10, "marksmen": 0, "cavalry": 0}
	var hero_ids: Array = []
	if has_node("/root/HeroState"):
		for hero: Dictionary in HeroState.get_available_heroes():
			hero_ids.append(str(hero.get("id", "")))
			break
	var d1: Dictionary = dispatch_gather_march(target, troops, hero_ids)
	if not bool(d1.get("ok", false)):
		push_error("[MarchState] gather smoke: dispatch failed: %s" % str(d1.get("error", "")))
		failed += 1
	if ResourceTileState.get_status(tile_id) != ResourceTileState.STATUS_RESERVED:
		push_error("[MarchState] gather smoke: tile not RESERVED after dispatch")
		failed += 1

	var d2: Dictionary = dispatch_gather_march(target, troops, hero_ids)
	if bool(d2.get("ok", false)):
		push_error("[MarchState] gather smoke: second dispatch must be rejected")
		failed += 1

	if not active_marches.is_empty():
		var march: Dictionary = active_marches[0]
		var now: int = int(Time.get_unix_time_from_system())
		# Arrive immediately and gather briefly.
		march["arrival_timestamp"] = now - 1
		_begin_gathering(march)
		active_marches[0] = march
		if str(march.get("status", "")) != STATUS_GATHERING:
			push_error("[MarchState] gather smoke: expected GATHERING")
			failed += 1
		if ResourceTileState.get_status(tile_id) != ResourceTileState.STATUS_GATHERING:
			push_error("[MarchState] gather smoke: tile status not GATHERING")
			failed += 1
		var cargo: int = int(march.get("cargo_capacity", 0))
		var target_amt: int = int(march.get("gather_target_amount", 0))
		if target_amt != mini(cargo, 10000) or target_amt <= 0:
			push_error("[MarchState] gather smoke: gather_target_amount not from live remaining")
			failed += 1
		march["gather_end_unix"] = now - 1
		_finish_gathering(march)
		active_marches[0] = march
		var expect_rem: int = 10000 - target_amt
		if ResourceTileState.get_remaining(tile_id) != expect_rem:
			push_error("[MarchState] gather smoke: remaining not reduced at gather complete")
			failed += 1
		if has_node("/root/GameState") and int(GameState.food) != food_before:
			push_error("[MarchState] gather smoke: GameState credited before home return")
			failed += 1
		if bool(march.get("tile_amount_applied", false)) != true:
			push_error("[MarchState] gather smoke: tile_amount_applied missing")
			failed += 1
		# Idempotent finish
		_finish_gathering(march)
		if ResourceTileState.get_remaining(tile_id) != expect_rem:
			push_error("[MarchState] gather smoke: double reduce on finish")
			failed += 1
		# Home return credits once
		march["return_arrival_timestamp"] = now - 1
		_complete_return(march)
		active_marches[0] = march
		if has_node("/root/GameState") and int(GameState.food) != food_before + target_amt:
			push_error("[MarchState] gather smoke: home credit amount wrong")
			failed += 1
		_complete_return(march)
		if has_node("/root/GameState") and int(GameState.food) != food_before + target_amt:
			push_error("[MarchState] gather smoke: duplicate credit")
			failed += 1

	# Restore troops / wallet side-effects carefully.
	if has_node("/root/GameState"):
		GameState.food = food_before
		if GameState.has_method("save_resources"):
			GameState.save_resources()
	if has_node("/root/TroopState"):
		TroopState.infantry_by_tier = bak_inf_map
		TroopState.marksmen_by_tier = bak_mar_map
		TroopState.cavalry_by_tier = bak_cav_map
		TroopState._resync_totals()

	if has_node("/root/ResourceTileState"):
		ResourceTileState.end_smoke_isolation()
	end_smoke_isolation()
	if failed == 0:
		print("[MarchState] Gather tile sync smoke test PASSED")
		return true
	push_error("[MarchState] Gather tile sync smoke test FAILED (%d)" % failed)
	return false


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
	# Simulate production WildlingNode sprite offset so aim != root.
	var offset_sprite := Sprite2D.new()
	offset_sprite.name = "Sprite2D"
	offset_sprite.position = Vector2(640, 307)
	dummy.add_child(offset_sprite)

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
	else:
		var aim: Vector2 = get_wildling_aim_position(dummy)
		var stored := Vector2(float(target.get("position", {}).get("x", 0)), float(target.get("position", {}).get("y", 0)))
		if stored.distance_to(aim) > 0.5:
			push_error("[MarchState] smoke: target position must use Wildling aim point")
			ok = false
		if stored.distance_to(dummy.global_position) < 1.0:
			push_error("[MarchState] smoke: target incorrectly used root position instead of sprite aim")
			ok = false

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
		# Visual must be the animated march asset, not the old Polygon2D arrow.
		if not active_marches.is_empty():
			var mid: String = str(active_marches[0].get("march_id", ""))
			if _visuals.has(mid):
				var icon: Node2D = _visuals[mid]
				if icon.get_node_or_null("Body") is Polygon2D:
					push_error("[MarchState] smoke: arrow placeholder Body still present")
					ok = false
				if icon.get_node_or_null("AnimatedSprite2D") == null and not (icon is AnimatedSprite2D):
					push_error("[MarchState] smoke: animated march sprite missing")
					ok = false
				# Orientation: fixed SE isometric art — rotation 0, flip_h only.
				var start := Vector2(
					float(active_marches[0].get("start_position", {}).get("x", 0)),
					float(active_marches[0].get("start_position", {}).get("y", 0))
				)
				var dest_orient := Vector2(
					float(active_marches[0].get("target_position", {}).get("x", 0)),
					float(active_marches[0].get("target_position", {}).get("y", 0))
				)
				var out_dir: Vector2 = dest_orient - start
				_apply_march_visual_direction(icon, out_dir)
				var anim_chk: AnimatedSprite2D = icon.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
				if anim_chk != null:
					if absf(anim_chk.rotation) > 0.001 or absf(icon.rotation) > 0.001:
						push_error("[MarchState] smoke: march must not use continuous rotation")
						ok = false
					if anim_chk.flip_v:
						push_error("[MarchState] smoke: flip_v must stay false")
						ok = false
					if anim_chk.flip_h != (out_dir.x < 0.0):
						push_error("[MarchState] smoke: outbound flip_h incorrect")
						ok = false
					var ret_dir: Vector2 = start - dest_orient
					_apply_march_visual_direction(icon, ret_dir)
					if absf(anim_chk.rotation) > 0.001:
						push_error("[MarchState] smoke: return must not rotate sprite")
						ok = false
					if anim_chk.flip_h != (ret_dir.x < 0.0):
						push_error("[MarchState] smoke: return flip_h incorrect")
						ok = false
					# Same function for pure vertical — never invert.
					_apply_march_visual_direction(icon, Vector2(0, -100))
					if absf(anim_chk.rotation) > 0.001 or anim_chk.flip_v or anim_chk.flip_h:
						push_error("[MarchState] smoke: upward travel must stay upright (no rot/flip_v)")
						ok = false
					_apply_march_visual_direction(icon, Vector2(0, 100))
					if absf(anim_chk.rotation) > 0.001 or anim_chk.flip_v or anim_chk.flip_h:
						push_error("[MarchState] smoke: downward travel must stay upright (no rot/flip_v)")
						ok = false
			var dest := Vector2(
				float(active_marches[0].get("target_position", {}).get("x", 0)),
				float(active_marches[0].get("target_position", {}).get("y", 0))
			)
			if dest.distance_to(get_wildling_aim_position(dummy)) > 0.5:
				push_error("[MarchState] smoke: dispatched destination != selected Wildling aim")
				ok = false
		# Battle report mail: one report, no AcceptDialog path required.
		if has_node("/root/MailManager") and not active_marches.is_empty():
			MailManager.begin_smoke_isolation()
			var mcopy: Dictionary = active_marches[0].duplicate(true)
			var fake_result: Dictionary = {
				"victory": true,
				"summary": "Victory!",
				"surviving_troops": {"infantry": 9, "marksmen": 5, "cavalry": 0},
				"losses": {"infantry": 1, "marksmen": 0, "cavalry": 0},
				"rewards": {"food": 350},
				"march_power": int(mcopy.get("march_power", 0)),
			}
			_create_battle_mail_report(mcopy, fake_result)
			_create_battle_mail_report(mcopy, fake_result) # duplicate must no-op
			if MailManager.get_battle_report_count() != 1:
				push_error("[MarchState] smoke: expected exactly one battle mail report")
				ok = false
			MailManager.end_smoke_isolation()
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
