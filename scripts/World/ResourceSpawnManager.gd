# ==============================================================================
# Crownspire MMO - Resource Spawn Manager Script
# Godot 4.6 / GDScript 2.0 Deterministic resource spawn coordinator with object pooling
# ==============================================================================

extends Node2D

signal resource_node_clicked(node: ResourceNode)

@export_category("Asset Configs")
@export var resource_node_scene: PackedScene

@export_group("Textures")
@export var food_texture: Texture2D
@export var wood_texture: Texture2D
@export var stone_texture: Texture2D
@export var iron_texture: Texture2D
@export var crystal_texture: Texture2D

@export_category("Spawning Balance")
@export var respawn_interval_sec: float = 45.0
@export var initial_spawn_fill_ratio: float = 0.6 # Fill 60% of max limits on startup

# Resource levels to quantity maps
const QUANTITY_BY_LEVEL = {
	1: 10000,
	2: 25000,
	3: 50000,
	4: 100000,
	5: 200000,
	6: 400000,
	7: 800000
}

# Object Pool structures
var _pool: Array[ResourceNode] = []
var _active_nodes: Array[ResourceNode] = []
var _regions: Array[KingdomSpawnRegion] = []
var _respawn_timer: Timer

func _ready() -> void:
	_respawn_timer = Timer.new()
	_respawn_timer.wait_time = respawn_interval_sec
	_respawn_timer.autostart = true
	_respawn_timer.timeout.connect(_on_respawn_timeout)
	add_child(_respawn_timer)

# Initializes deterministic region-based spawning
func initialize_spawning(regions: Array[KingdomSpawnRegion], random_seed: int) -> void:
	seed(random_seed) # Seed RNG for determinism
	_regions = regions
	
	# Pre-populate object pool with initial cache of nodes to prevent frame drops
	_warm_pool(120)
	
	# Initial spawn pass to make map feel alive instantly
	for region in _regions:
		if region.region_type != "Resource":
			continue
		var target_count = clampi(int(region.max_active_spawns * initial_spawn_fill_ratio), 1, region.max_active_spawns)
		for i in range(target_count):
			spawn_resource_in_region(region)

# Pool warmer
func _warm_pool(size: int) -> void:
	if not resource_node_scene:
		push_error("ResourceSpawnManager: ResourceNode scene asset is NOT assigned!")
		return
		
	for i in range(size):
		var node = resource_node_scene.instantiate() as ResourceNode
		node.visible = false
		node.clicked.connect(_on_node_clicked)
		add_child(node)
		_pool.append(node)

# Get node from pool or instantiate if exhausted
func _get_pooled_node() -> ResourceNode:
	for node in _pool:
		if not node.visible:
			node.visible = true
			return node
			
	# Exhausted pool, scale dynamically
	var node = resource_node_scene.instantiate() as ResourceNode
	node.clicked.connect(_on_node_clicked)
	add_child(node)
	_pool.append(node)
	node.visible = true
	return node

# Cleanses and recycles a resource node
func recycle_node(node: ResourceNode) -> void:
	if _active_nodes.has(node):
		_active_nodes.erase(node)
	node.visible = false
	# Relocate offsite safely
	node.global_position = Vector2(-99999, -99999)

# Core Spawn Calculation
func spawn_resource_in_region(region: KingdomSpawnRegion) -> void:
	if not region.can_spawn_more():
		return
		
	var allowed_types = region.allowed_spawn_types
	if allowed_types.is_empty():
		allowed_types = ["food", "wood", "stone", "iron"]
		
	var type = allowed_types[randi() % allowed_types.size()]
	var level = randi_range(region.min_level, region.max_level)
	level = clampi(level, 1, 7) # Clamped strictly to maximum levels
	var amount = QUANTITY_BY_LEVEL.get(level, 10000)
	
	var tex: Texture2D = null
	match type.to_lower():
		"food": tex = food_texture
		"wood": tex = wood_texture
		"stone": tex = stone_texture
		"iron": tex = iron_texture
		"crystal": tex = crystal_texture
		_: tex = food_texture
		
	var spawn_pos = region.get_random_spawn_point()
	
	var node = _get_pooled_node()
	node.global_position = spawn_pos
	node.setup_node(type, level, amount, tex)
	_active_nodes.append(node)
	region.register_spawn(node)

func _on_node_clicked(node: ResourceNode) -> void:
	resource_node_clicked.emit(node)

func _on_respawn_timeout() -> void:
	# Keep the kingdom alive with a steady influx of nodes
	for region in _regions:
		if region.region_type == "Resource" and region.can_spawn_more():
			# Chance based on spawn weight
			if randf() <= region.spawn_weight * 0.4:
				spawn_resource_in_region(region)
