extends Node2D

const WildlingLairDatabase = preload("res://Scripts/World/WildlingLairDatabase.gd")
const MapPlacementContractScript = preload("res://Scripts/World/MapPlacementContract.gd")

@export var resource_node_scene: PackedScene
@export var wildling_node_scene: PackedScene
@export var wildling_lair_node_scene: PackedScene

@export var food_texture: Texture2D
@export var wood_texture: Texture2D
@export var stone_texture: Texture2D
@export var iron_texture: Texture2D
@export var crystal_texture: Texture2D

@export var wolf_texture: Texture2D
@export var bear_texture: Texture2D
@export var spider_texture: Texture2D
@export var boar_texture: Texture2D
@export var troll_texture: Texture2D
@export var dragon_texture: Texture2D

@export var wolf_card: Texture2D
@export var bear_card: Texture2D
@export var spider_card: Texture2D
@export var boar_card: Texture2D
@export var troll_card: Texture2D
@export var dragon_card: Texture2D

@export var resource_count: int = 40
@export var wildling_count: int = 30
## Conservative beta count — Alliance Lairs Lv.1–5 band (see wildling_lairs.json).
@export var wildling_lair_count: int = 10
@export var map_size: Vector2 = Vector2(8192, 8192)
@export var edge_margin: float = 300.0
@export var resource_min_distance: float = 160.0
## Raised from 280 → 360 for larger dedicated Lair art footprint.
@export var lair_min_distance: float = 360.0
@export var castle_exclusion_radius: float = 500.0
## When true, kingdom-seeded RNG so all clients share the same Alliance Lair IDs/positions.
@export var use_deterministic_lair_seed: bool = true

@onready var resource_spawns: Node2D = $ResourceSpawns
@onready var wildling_spawns: Node2D = $WildlingSpawns
@onready var wildling_lair_spawns: Node2D = get_node_or_null("WildlingLairSpawns")

var rng := RandomNumberGenerator.new()
## slot_index -> live WildlingNode (contract-spawned only).
var _live_wildling_by_slot: Dictionary = {}

func _wildling_spawn_state() -> Node:
	return get_node_or_null("/root/WildlingSpawnState")


func _ready() -> void:
	rng.randomize()
	_ensure_wildling_lair_spawns_root()
	_ensure_teleport_controller()
	await _ensure_and_refresh_castles()
	if has_node("/root/ResourceTileState"):
		ResourceTileState.clear_live_nodes()
		ResourceTileState.process_respawns()
	var wss: Node = _wildling_spawn_state()
	if wss != null:
		if wss.has_method("purge_expired"):
			wss.call("purge_expired")
		if wss.has_signal("slot_ready_to_respawn") and not wss.is_connected("slot_ready_to_respawn", _on_wildling_slot_ready_to_respawn):
			wss.connect("slot_ready_to_respawn", _on_wildling_slot_ready_to_respawn)
	spawn_resources()
	spawn_wildlings()
	spawn_wildling_lairs()
	if has_node("/root/ResourceTileState"):
		# After live nodes exist + marches already loaded by autoload order.
		ResourceTileState.repair_stale_reservations()


func _exit_tree() -> void:
	# Wildling cooldown live-respawn: drop Autoload signal + transient slot map.
	var wss: Node = _wildling_spawn_state()
	if wss != null and wss.has_signal("slot_ready_to_respawn"):
		if wss.is_connected("slot_ready_to_respawn", _on_wildling_slot_ready_to_respawn):
			wss.disconnect("slot_ready_to_respawn", _on_wildling_slot_ready_to_respawn)
	_live_wildling_by_slot.clear()
	# Existing resource-tile live-node cleanup (City↔World scene unload).
	if has_node("/root/ResourceTileState"):
		ResourceTileState.clear_live_nodes()


func _ensure_teleport_controller() -> void:
	var parent_map: Node = _map_root()
	if parent_map == null:
		return
	if parent_map.get_node_or_null("CityTeleportController") != null:
		return
	var ctrl := Node2D.new()
	ctrl.name = "CityTeleportController"
	ctrl.set_script(load("res://Scripts/World/CityTeleportController.gd"))
	parent_map.add_child(ctrl)
	if get_tree() != null and get_tree().has_meta("pending_city_teleport"):
		call_deferred("_start_pending_teleport", ctrl)


func _start_pending_teleport(ctrl: Node) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if ctrl != null and is_instance_valid(ctrl) and ctrl.has_method("begin_placement"):
		ctrl.call("begin_placement")
	if get_tree() != null and get_tree().has_meta("pending_city_teleport"):
		get_tree().remove_meta("pending_city_teleport")


func _map_root() -> Node:
	## KingdomMap attaches this script to WorldRoot itself.
	## WorldCastleLayer must remain under WorldRoot.
	return self

func _ensure_and_refresh_castles() -> void:
	var parent_map: Node = _map_root()
	if parent_map == null:
		return
	var layer: Node = parent_map.get_node_or_null("WorldCastleLayer")
	# Migrate a layer that was incorrectly parented under the scene tree root.
	if layer == null and get_tree() != null:
		var misplaced: Node = get_tree().root.get_node_or_null("WorldCastleLayer")
		if misplaced != null and misplaced.get_parent() != parent_map:
			var old_parent: Node = misplaced.get_parent()
			if old_parent != null:
				old_parent.remove_child(misplaced)
			parent_map.add_child(misplaced)
			layer = misplaced
			print("[WorldCastle] reparented WorldCastleLayer under %s" % str(parent_map.get_path()))
	if layer == null:
		layer = Node2D.new()
		layer.name = "WorldCastleLayer"
		layer.set_script(load("res://Scripts/World/WorldCastleLayer.gd"))
		parent_map.add_child(layer)
		# Keep castles above terrain, below HUD.
		parent_map.move_child(layer, parent_map.get_child_count() - 1)
	if layer.has_method("refresh_castles"):
		await layer.refresh_castles()


func random_map_position() -> Vector2:
	return Vector2(
		rng.randf_range(edge_margin, map_size.x - edge_margin),
		rng.randf_range(edge_margin, map_size.y - edge_margin)
	)


func spawn_resources() -> void:
	while resource_spawns.get_child_count() > 0:
		var child: Node = resource_spawns.get_child(0)
		resource_spawns.remove_child(child)
		child.free()
	## Always spawn from crownspire_map_blockers_v1 — never prefer stale saved coordinates.
	_spawn_resources_from_contract()


func _spawn_resources_from_contract() -> void:
	# Crystal is out of gather scope for Step 3 — only persist Food/Wood/Stone/Iron.
	var types: Array[String] = ["food", "wood", "stone", "iron"]
	var kid: String = _kingdom_id_for_contract()
	var resources: Array = MapPlacementContractScript.blockers_of_kinds(kid, PackedStringArray(["resource"]))
	var count: int = mini(resource_count, resources.size())
	var contract_spots: Array = []
	for i: int in range(count):
		contract_spots.append({
			"index": i,
			"resource_type": types[i % types.size()],
			"x": float(resources[i].get("x", 0.0)),
			"y": float(resources[i].get("y", 0.0)),
			"level": 1 + (i % 7),
			"max_amount": get_resource_amount(1 + (i % 7)),
		})
	if has_node("/root/ResourceTileState") and ResourceTileState.has_method("reconcile_to_contract_layout"):
		ResourceTileState.reconcile_to_contract_layout(kid, contract_spots)
	for spot_v: Variant in contract_spots:
		var spot: Dictionary = spot_v
		var resource_type: String = str(spot.get("resource_type", "food"))
		var level: int = int(spot.get("level", 1))
		var max_amount: int = int(spot.get("max_amount", get_resource_amount(level)))
		var pos := Vector2(float(spot.get("x", 0.0)), float(spot.get("y", 0.0)))
		var tile_id: String = ""
		var remaining: int = max_amount
		if has_node("/root/ResourceTileState"):
			if ResourceTileState.has_method("make_contract_tile_id"):
				tile_id = ResourceTileState.make_contract_tile_id(int(spot.get("index", 0)), resource_type)
			else:
				tile_id = ResourceTileState.allocate_tile_id(resource_type)
			var prior: Dictionary = ResourceTileState.get_tile(tile_id)
			if not prior.is_empty():
				remaining = int(prior.get("remaining_amount", remaining))
				max_amount = int(prior.get("max_amount", max_amount))
				level = int(prior.get("level", level))
		_instantiate_resource_tile(tile_id, resource_type, level, max_amount, remaining, pos, true)

	if has_node("/root/ResourceTileState"):
		ResourceTileState.save_tiles()


func _kingdom_id_for_contract() -> String:
	if has_node("/root/AllianceLairState") and AllianceLairState.has_method("get_kingdom_id"):
		return str(AllianceLairState.get_kingdom_id())
	if has_node("/root/AllianceBackend") and AllianceBackend.has_method("get_profile"):
		var kid: String = str(AllianceBackend.get_profile().get("kingdom_id", "")).strip_edges()
		if kid != "":
			return kid
	return "kingdom_dev_001"


func _instantiate_resource_tile(
	tile_id: String,
	resource_type: String,
	level: int,
	max_amount: int,
	remaining_amount: int,
	pos: Vector2,
	register_new: bool
) -> void:
	if resource_node_scene == null:
		return
	var node: Node2D = resource_node_scene.instantiate()
	resource_spawns.add_child(node)
	node.position = pos
	node.scale = Vector2(0.10, 0.10)
	node.z_index = 100

	var sprite: Sprite2D = node.get_node_or_null("Sprite2D")
	if sprite:
		sprite.texture = get_resource_texture(resource_type)

	var click = node.get_node_or_null("ClickArea")
	if click:
		click.resource_type = resource_type
		click.level = level
		click.amount = remaining_amount
		if "tile_id" in click:
			click.tile_id = tile_id
		click.input_pickable = true
		click.monitoring = true

	# Match ClickArea hitbox to visible sprite (ResourceNode default shape is 20×20;
	# at scale 0.10 that is a 2×2 world hitbox — taps never land on release).
	_sync_resource_click_shape(node)

	if has_node("/root/ResourceTileState") and tile_id != "":
		if register_new:
			ResourceTileState.register_or_update_tile(
				tile_id,
				resource_type,
				level,
				max_amount,
				remaining_amount,
				node.global_position,
				ResourceTileState.STATUS_AVAILABLE
			)
		ResourceTileState.bind_live_node(tile_id, node)


## Keep CollisionShape2D aligned with Sprite2D so tap/release both hit the same tile art.
func _sync_resource_click_shape(node: Node2D) -> void:
	if node == null:
		return
	var sprite: Sprite2D = node.get_node_or_null("Sprite2D") as Sprite2D
	var click: Area2D = node.get_node_or_null("ClickArea") as Area2D
	if sprite == null or click == null or sprite.texture == null:
		return
	var shape_node: CollisionShape2D = click.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		shape_node = CollisionShape2D.new()
		shape_node.name = "CollisionShape2D"
		click.add_child(shape_node)
	var rect := RectangleShape2D.new()
	# Local space size; parent Node2D scale (0.10) applies to world picking.
	rect.size = sprite.texture.get_size() * sprite.scale.abs()
	shape_node.shape = rect
	shape_node.position = sprite.position
	shape_node.disabled = false
	shape_node.visible = false
	click.input_pickable = true


func _find_clear_resource_position() -> Vector2:
	var pos: Vector2 = random_map_position()
	for _attempt: int in range(48):
		pos = random_map_position()
		if is_near_player_castle(pos):
			continue
		if is_position_clear(pos, resource_min_distance):
			return pos
	return pos


func is_near_player_castle(pos: Vector2) -> bool:
	var parent_map: Node = _map_root()
	if parent_map != null:
		var layer: Node = parent_map.get_node_or_null("WorldCastleLayer")
		if layer != null and layer.has_method("get_reserved_castle_positions"):
			var reserved: Array = layer.call("get_reserved_castle_positions")
			for p_v in reserved:
				if typeof(p_v) == TYPE_VECTOR2 and pos.distance_to(p_v) < castle_exclusion_radius:
					return true
		var castle: Node2D = parent_map.get_node_or_null("PlayerCastleMarker") as Node2D
		if castle != null:
			return pos.distance_to(castle.global_position) < castle_exclusion_radius
	return false


func get_wildling_card(level: int) -> Texture2D:
	if level <= 5:
		return wolf_card
	elif level <= 10:
		return bear_card
	elif level <= 15:
		return spider_card
	elif level <= 20:
		return boar_card
	elif level <= 25:
		return troll_card
	else:
		return dragon_card

func spawn_wildlings() -> void:
	_live_wildling_by_slot.clear()
	while wildling_spawns.get_child_count() > 0:
		var child: Node = wildling_spawns.get_child(0)
		wildling_spawns.remove_child(child)
		child.free()
	var kid: String = _kingdom_id_for_contract()
	var wss: Node = _wildling_spawn_state()
	if wss != null and wss.has_method("purge_expired"):
		wss.call("purge_expired")
	var spots: Array = MapPlacementContractScript.blockers_of_kinds(kid, PackedStringArray(["wildling"]))
	var count: int = mini(wildling_count, spots.size())
	for i in range(count):
		if wildling_node_scene == null:
			return
		var slot_id: String = ""
		if wss != null and wss.has_method("make_slot_id"):
			slot_id = str(wss.call("make_slot_id", kid, i))
			# City→World must not resurrect slots still on cooldown.
			if wss.has_method("is_slot_on_cooldown") and bool(wss.call("is_slot_on_cooldown", slot_id)):
				continue
		_spawn_wildling_at_slot(i, spots[i], kid, slot_id)


## Live respawn after beta cooldown while the player remains on the World Map.
func _on_wildling_slot_ready_to_respawn(slot_id: String, kingdom_id: String, slot_index: int) -> void:
	var kid: String = _kingdom_id_for_contract()
	if kingdom_id.strip_edges() != "" and kingdom_id.strip_edges() != kid:
		return
	if _live_wildling_by_slot.has(slot_index):
		var existing: Variant = _live_wildling_by_slot[slot_index]
		if is_instance_valid(existing):
			return
		_live_wildling_by_slot.erase(slot_index)
	var spots: Array = MapPlacementContractScript.blockers_of_kinds(kid, PackedStringArray(["wildling"]))
	if slot_index < 0 or slot_index >= spots.size() or slot_index >= wildling_count:
		return
	var wss: Node = _wildling_spawn_state()
	if wss != null and wss.has_method("is_slot_on_cooldown") and bool(wss.call("is_slot_on_cooldown", slot_id)):
		return
	_spawn_wildling_at_slot(slot_index, spots[slot_index], kid, slot_id)


func _spawn_wildling_at_slot(slot_index: int, spot: Dictionary, kingdom_id: String, slot_id: String = "") -> Node2D:
	if wildling_node_scene == null or wildling_spawns == null:
		return null
	var level: int = 1 + (slot_index % 30)
	var resolved_slot: String = slot_id.strip_edges()
	var wss: Node = _wildling_spawn_state()
	if resolved_slot.is_empty() and wss != null and wss.has_method("make_slot_id"):
		resolved_slot = str(wss.call("make_slot_id", kingdom_id, slot_index))
	var node: Node2D = wildling_node_scene.instantiate()
	wildling_spawns.add_child(node)
	node.position = Vector2(float(spot.get("x", 0.0)), float(spot.get("y", 0.0)))
	node.scale = Vector2(0.68, 0.68)
	node.z_index = 100
	node.set_meta("wildling_slot_id", resolved_slot)
	node.set_meta("wildling_slot_index", slot_index)
	node.set_meta("wildling_kingdom_id", kingdom_id)
	node.name = "WildlingSlot_%d" % slot_index

	var sprite: Sprite2D = node.get_node_or_null("Sprite2D")
	if sprite:
		sprite.texture = get_wildling_texture(level)

	var click = node.get_node_or_null("ClickArea")
	if click:
		click.level = level
		click.power = level * 2500
		click.species = get_wildling_species(level)
		click.card_texture = get_wildling_card(level)
		if "spawn_slot_id" in click:
			click.spawn_slot_id = resolved_slot
		click.set_meta("wildling_slot_id", resolved_slot)
		click.set_meta("wildling_slot_index", slot_index)

	_live_wildling_by_slot[slot_index] = node
	return node


## Called when MarchState removes a defeated wildling node mid-session.
func unregister_wildling_slot(slot_index: int) -> void:
	if _live_wildling_by_slot.has(slot_index):
		_live_wildling_by_slot.erase(slot_index)


## DEBUG / Shift+F9 — force-respawn tutorial L1 if the World Map is live.
func debug_respawn_tutorial_l1_if_present() -> bool:
	if not OS.is_debug_build():
		return false
	var kid: String = _kingdom_id_for_contract()
	var slot_index: int = 0
	var wss: Node = _wildling_spawn_state()
	if wss != null:
		var idx_v: Variant = wss.get("TUTORIAL_L1_SLOT_INDEX")
		if idx_v != null:
			slot_index = int(idx_v)
		if wss.has_method("make_slot_id") and wss.has_method("clear_slot"):
			wss.call("clear_slot", wss.call("make_slot_id", kid, slot_index))
	if _live_wildling_by_slot.has(slot_index) and is_instance_valid(_live_wildling_by_slot[slot_index]):
		return true
	var spots: Array = MapPlacementContractScript.blockers_of_kinds(kid, PackedStringArray(["wildling"]))
	if spots.is_empty():
		return false
	_spawn_wildling_at_slot(slot_index, spots[slot_index], kid)
	return true


func _ensure_wildling_lair_spawns_root() -> void:
	if wildling_lair_spawns != null and is_instance_valid(wildling_lair_spawns):
		return
	wildling_lair_spawns = get_node_or_null("WildlingLairSpawns") as Node2D
	if wildling_lair_spawns != null:
		return
	# Migrate temporary Phase-1 node name if present.
	var legacy: Node2D = get_node_or_null("MonsterDenSpawns") as Node2D
	if legacy != null:
		legacy.name = "WildlingLairSpawns"
		wildling_lair_spawns = legacy
		return
	wildling_lair_spawns = Node2D.new()
	wildling_lair_spawns.name = "WildlingLairSpawns"
	add_child(wildling_lair_spawns)


## Deterministic kingdom-seeded Alliance Lairs for multiplayer rally targets.
## Stable IDs are kingdom + level + sequence (not random-position based).
func spawn_wildling_lairs() -> void:
	_ensure_wildling_lair_spawns_root()
	while wildling_lair_spawns.get_child_count() > 0:
		var child: Node = wildling_lair_spawns.get_child(0)
		wildling_lair_spawns.remove_child(child)
		child.free()

	if wildling_lair_node_scene == null:
		push_warning("[AllianceLair] wildling_lair_node_scene not assigned")
		return

	if has_node("/root/AllianceLairState"):
		AllianceLairState.clear_spawn_registry()

	var level_min: int = WildlingLairDatabase.beta_spawn_level_min()
	var level_max: int = WildlingLairDatabase.beta_spawn_level_max()
	var spawn_count: int = WildlingLairDatabase.beta_spawn_count()
	if wildling_lair_count > 0:
		spawn_count = wildling_lair_count
	# Prefer beta band (1–5) even if export still says 10.
	spawn_count = clampi(spawn_count, 4, 20)
	var band: int = maxi(1, level_max - level_min + 1)
	var kingdom_id: String = _kingdom_id_for_contract()
	var lair_spots: Array = MapPlacementContractScript.blockers_of_kinds(
		kingdom_id, PackedStringArray(["lair"])
	)
	spawn_count = mini(spawn_count, lair_spots.size())

	var spawned: int = 0
	var variant_counts := {"beast": 0, "horror": 0, "ancient": 0}
	for i: int in range(spawn_count):
		var level: int = level_min + (i % band)
		var def: Dictionary = WildlingLairDatabase.get_level_def(level)
		if def.is_empty():
			continue
		var pos: Vector2 = Vector2(
			float(lair_spots[i].get("x", 0.0)),
			float(lair_spots[i].get("y", 0.0))
		)
		var lair_id: String = _make_stable_lair_id(kingdom_id, level, i)
		var node: Node2D = wildling_lair_node_scene.instantiate()
		wildling_lair_spawns.add_child(node)
		node.position = pos
		node.scale = Vector2.ONE
		node.z_index = 110
		if node.has_method("setup_from_def"):
			node.call("setup_from_def", def, lair_id)
		if has_node("/root/AllianceLairState"):
			var registered: Dictionary = AllianceLairState.register_spawned_lair({
				"lair_id": lair_id,
				"lair_type": str(def.get("lair_type", "alliance_lair")),
				"lair_level": level,
				"level": level,
				"display_name": str(def.get("display_name", "Alliance Lair")),
				"kingdom_id": kingdom_id,
				"world_x": pos.x,
				"world_y": pos.y,
				"world_position": {"x": pos.x, "y": pos.y},
				"max_hp": int(def.get("max_hp", 5000)),
				"recommended_power": int(def.get("recommended_power", 0)),
				"difficulty": str(def.get("difficulty", "Normal")),
				"rally_required": bool(def.get("rally_required", true)),
				"reward_table_id": str(def.get("reward_table_id", "")),
				"respawn_seconds": int(def.get("respawn_seconds", WildlingLairDatabase.default_respawn_seconds())),
				"species": str(def.get("species", "")),
				"visual_variant": str(def.get("visual_variant", "")),
				"level_def": def,
			})
			if node.has_method("apply_runtime_state") and bool(registered.get("ok", false)):
				node.call("apply_runtime_state", registered.get("lair", {}))
		var variant: String = str(def.get("visual_variant", "beast"))
		if variant_counts.has(variant):
			variant_counts[variant] = int(variant_counts[variant]) + 1
		spawned += 1
	print("[AllianceLair] Spawned %d lairs kingdom=%s contract=%s variants=%s" % [
		spawned,
		kingdom_id,
		MapPlacementContractScript.CONTRACT_ID,
		str(variant_counts),
	])
	_smoke_wildling_lairs()


func _smoke_wildling_lairs() -> void:
	if wildling_lair_spawns == null:
		push_warning("[AllianceLair] smoke FAILED: no WildlingLairSpawns root")
		return
	var count: int = wildling_lair_spawns.get_child_count()
	if count <= 0:
		push_warning("[AllianceLair] smoke FAILED: zero lairs")
		return
	var min_d: float = INF
	var nodes: Array = wildling_lair_spawns.get_children()
	for i: int in range(nodes.size()):
		var a: Node2D = nodes[i] as Node2D
		if a == null:
			continue
		if is_near_player_castle(a.global_position):
			push_warning("[AllianceLair] smoke WARN: lair near castle %s" % a.name)
		for j: int in range(i + 1, nodes.size()):
			var b: Node2D = nodes[j] as Node2D
			if b == null:
				continue
			min_d = minf(min_d, a.global_position.distance_to(b.global_position))
	if min_d < lair_min_distance * 0.5:
		push_warning("[AllianceLair] smoke WARN: lairs closer than expected (%.1f)" % min_d)
	var panel: Node = get_node_or_null("HUD/WildlingLairPanel")
	if panel == null:
		push_warning("[AllianceLair] smoke WARN: WildlingLairPanel missing under HUD")
	print("[AllianceLair] smoke OK lairs=%d min_pair_dist=%.1f panel=%s" % [
		count,
		min_d if min_d < INF else -1.0,
		str(panel != null),
	])


func _make_stable_lair_id(kingdom_id: String, level: int, seq: int) -> String:
	var kid: String = kingdom_id.strip_edges().replace(" ", "_")
	if kid.length() > 24:
		kid = kid.substr(0, 24)
	return "alair_%s_L%d_%02d" % [kid, level, seq]


func _find_clear_lair_position_seeded(lair_rng: RandomNumberGenerator) -> Vector2:
	var pos: Vector2 = _random_map_position_seeded(lair_rng)
	for _attempt: int in range(80):
		pos = _random_map_position_seeded(lair_rng)
		if is_near_player_castle(pos):
			continue
		if is_position_clear(pos, lair_min_distance):
			return pos
	return pos


func _random_map_position_seeded(lair_rng: RandomNumberGenerator) -> Vector2:
	return Vector2(
		lair_rng.randf_range(edge_margin, map_size.x - edge_margin),
		lair_rng.randf_range(edge_margin, map_size.y - edge_margin)
	)


func _find_clear_lair_position() -> Vector2:
	return _find_clear_lair_position_seeded(rng)


func get_resource_texture(resource_type: String) -> Texture2D:
	match resource_type:
		"food": return food_texture
		"wood": return wood_texture
		"stone": return stone_texture
		"iron": return iron_texture
		"crystal": return crystal_texture
	return null

func get_resource_amount(level: int) -> int:
	var amounts := {
		1: 10000,
		2: 25000,
		3: 50000,
		4: 100000,
		5: 200000,
		6: 400000,
		7: 800000
	}
	return amounts[level]

func get_wildling_texture(level: int) -> Texture2D:
	if level <= 5: return wolf_texture
	if level <= 10: return bear_texture
	if level <= 15: return spider_texture
	if level <= 20: return boar_texture
	if level <= 25: return troll_texture
	return dragon_texture

func get_wildling_species(level: int) -> String:
	if level <= 5:
		return "wolf"
	elif level <= 10:
		return "bear"
	elif level <= 15:
		return "spider"
	elif level <= 20:
		return "boar"
	elif level <= 25:
		return "troll"
	else:
		return "dragon"

func is_position_clear(pos: Vector2, min_distance: float) -> bool:
	for node in get_tree().get_nodes_in_group("world_blockers"):
		if node.global_position.distance_to(pos) < min_distance:
			return false

	for node in resource_spawns.get_children():
		if node.global_position.distance_to(pos) < min_distance:
			return false

	for node in wildling_spawns.get_children():
		if node.global_position.distance_to(pos) < min_distance:
			return false

	if wildling_lair_spawns != null:
		for node in wildling_lair_spawns.get_children():
			if node.global_position.distance_to(pos) < min_distance:
				return false

	return true
