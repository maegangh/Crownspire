extends Node2D

const WildlingLairDatabase = preload("res://scripts/World/WildlingLairDatabase.gd")

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
## Conservative beta count — one lair per level band (Lv.1–10).
@export var wildling_lair_count: int = 10
@export var map_size: Vector2 = Vector2(8192, 8192)
@export var edge_margin: float = 300.0
@export var resource_min_distance: float = 160.0
## Raised from 280 → 360 for larger dedicated Lair art footprint.
@export var lair_min_distance: float = 360.0
@export var castle_exclusion_radius: float = 500.0

@onready var resource_spawns: Node2D = $ResourceSpawns
@onready var wildling_spawns: Node2D = $WildlingSpawns
@onready var wildling_lair_spawns: Node2D = get_node_or_null("WildlingLairSpawns")

var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	_ensure_wildling_lair_spawns_root()
	if has_node("/root/ResourceTileState"):
		ResourceTileState.clear_live_nodes()
		ResourceTileState.process_respawns()
	spawn_resources()
	spawn_wildlings()
	spawn_wildling_lairs()
	if has_node("/root/ResourceTileState"):
		# After live nodes exist + marches already loaded by autoload order.
		ResourceTileState.repair_stale_reservations()


func _exit_tree() -> void:
	if has_node("/root/ResourceTileState"):
		ResourceTileState.clear_live_nodes()


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

	if has_node("/root/ResourceTileState") and ResourceTileState.has_saved_tiles():
		_spawn_resources_from_saved_state()
		return
	_spawn_resources_fresh()


func _spawn_resources_from_saved_state() -> void:
	for state_v: Variant in ResourceTileState.get_all_tiles():
		if typeof(state_v) != TYPE_DICTIONARY:
			continue
		var state: Dictionary = state_v
		var rtype: String = str(state.get("resource_type", "")).strip_edges().to_lower()
		if rtype not in ["food", "wood", "stone", "iron"]:
			continue
		var pos_d: Dictionary = state.get("world_position", {}) as Dictionary
		var pos := Vector2(float(pos_d.get("x", 0.0)), float(pos_d.get("y", 0.0)))
		_instantiate_resource_tile(
			str(state.get("tile_id", "")),
			rtype,
			int(state.get("level", 1)),
			int(state.get("max_amount", get_resource_amount(int(state.get("level", 1))))),
			int(state.get("remaining_amount", 0)),
			pos,
			false
		)


func _spawn_resources_fresh() -> void:
	# Crystal is out of gather scope for Step 3 — only persist Food/Wood/Stone/Iron.
	var types: Array[String] = ["food", "wood", "stone", "iron"]
	for _i: int in range(resource_count):
		var resource_type: String = types[rng.randi_range(0, types.size() - 1)]
		var level: int = rng.randi_range(1, 7)
		var amount: int = get_resource_amount(level)
		var pos: Vector2 = _find_clear_resource_position()
		var tile_id: String = ""
		if has_node("/root/ResourceTileState"):
			tile_id = ResourceTileState.allocate_tile_id(resource_type)
		_instantiate_resource_tile(tile_id, resource_type, level, amount, amount, pos, true)

	if has_node("/root/ResourceTileState"):
		ResourceTileState.save_tiles()


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
	var castle: Node2D = get_parent().get_node_or_null("PlayerCastleMarker") as Node2D
	if castle == null:
		return false
	return pos.distance_to(castle.global_position) < castle_exclusion_radius


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
	for i in range(wildling_count):
		var level: int = rng.randi_range(1, 30)

		var node: Node2D = wildling_node_scene.instantiate()
		wildling_spawns.add_child(node)
		node.position = random_map_position()
		node.scale = Vector2(0.68, 0.68)
		node.z_index = 100

		var sprite: Sprite2D = node.get_node_or_null("Sprite2D")
		if sprite:
			sprite.texture = get_wildling_texture(level)

		var click = node.get_node_or_null("ClickArea")
		if click:
			click.level = level
			click.power = level * 2500
			click.species = get_wildling_species(level)
			click.card_texture = get_wildling_card(level)


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


## Session-local Wildling Lairs (presentation). Not multiplayer-persisted.
## Stable IDs encode level + grid cell so UI/search/future RPC can key lairs.
func spawn_wildling_lairs() -> void:
	_ensure_wildling_lair_spawns_root()
	while wildling_lair_spawns.get_child_count() > 0:
		var child: Node = wildling_lair_spawns.get_child(0)
		wildling_lair_spawns.remove_child(child)
		child.free()

	if wildling_lair_node_scene == null:
		push_warning("[WildlingLair] wildling_lair_node_scene not assigned")
		return

	var level_min: int = WildlingLairDatabase.level_min()
	var level_max: int = WildlingLairDatabase.level_max()
	var spawned: int = 0
	var variant_counts := {"beast": 0, "horror": 0, "ancient": 0}
	for i: int in range(wildling_lair_count):
		# Spread levels across 1–10 for beta search coverage.
		var level: int = level_min + (i % (level_max - level_min + 1))
		var def: Dictionary = WildlingLairDatabase.get_level_def(level)
		if def.is_empty():
			continue
		var pos: Vector2 = _find_clear_lair_position()
		var lair_id: String = _make_stable_lair_id(level, pos, i)
		var node: Node2D = wildling_lair_node_scene.instantiate()
		wildling_lair_spawns.add_child(node)
		node.position = pos
		node.scale = Vector2.ONE
		node.z_index = 105
		if node.has_method("setup_from_def"):
			node.call("setup_from_def", def, lair_id)
		var variant: String = str(def.get("visual_variant", "beast"))
		if variant_counts.has(variant):
			variant_counts[variant] = int(variant_counts[variant]) + 1
		spawned += 1
	print("[WildlingLair] Spawned %d lairs (beta session-local) variants=%s" % [
		spawned,
		str(variant_counts),
	])
	_smoke_wildling_lairs()


func _smoke_wildling_lairs() -> void:
	if wildling_lair_spawns == null:
		push_warning("[WildlingLair] smoke FAILED: no WildlingLairSpawns root")
		return
	var count: int = wildling_lair_spawns.get_child_count()
	if count <= 0:
		push_warning("[WildlingLair] smoke FAILED: zero lairs")
		return
	var min_d: float = INF
	var nodes: Array = wildling_lair_spawns.get_children()
	for i: int in range(nodes.size()):
		var a: Node2D = nodes[i] as Node2D
		if a == null:
			continue
		if is_near_player_castle(a.global_position):
			push_warning("[WildlingLair] smoke WARN: lair near castle %s" % a.name)
		for j: int in range(i + 1, nodes.size()):
			var b: Node2D = nodes[j] as Node2D
			if b == null:
				continue
			min_d = minf(min_d, a.global_position.distance_to(b.global_position))
	if min_d < lair_min_distance * 0.5:
		push_warning("[WildlingLair] smoke WARN: lairs closer than expected (%.1f)" % min_d)
	# WorldAutoSpawner is attached to WorldRoot — look up HUD on self, not parent.
	var panel: Node = get_node_or_null("HUD/WildlingLairPanel")
	if panel == null:
		push_warning("[WildlingLair] smoke WARN: WildlingLairPanel missing under HUD")
	print("[WildlingLair] smoke OK lairs=%d min_pair_dist=%.1f panel=%s" % [
		count,
		min_d if min_d < INF else -1.0,
		str(panel != null),
	])


func _make_stable_lair_id(level: int, pos: Vector2, seq: int) -> String:
	var gx: int = int(floor(pos.x / 32.0))
	var gy: int = int(floor(pos.y / 32.0))
	return "lair_L%d_x%d_y%d_s%02d" % [level, gx, gy, seq]


func _find_clear_lair_position() -> Vector2:
	var pos: Vector2 = random_map_position()
	for _attempt: int in range(64):
		pos = random_map_position()
		if is_near_player_castle(pos):
			continue
		if is_position_clear(pos, lair_min_distance):
			return pos
	return pos


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
