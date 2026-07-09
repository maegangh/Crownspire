# ==============================================================================
# Crownspire MMO - Wildling Spawn Manager Script
# Godot 4.6 / GDScript 2.0 Spatial Density and Level scaling near Central Royal Keep
# ==============================================================================

class_name WildlingSpawnManager
extends Node2D

signal wildling_node_clicked(node: WildlingNode)

@export_category("Asset Configs")
@export var wildling_node_scene: PackedScene

@export_group("Species Textures")
@export var wolf_texture: Texture2D
@export var bear_texture: Texture2D
@export var spider_texture: Texture2D
@export var boar_texture: Texture2D
@export var troll_texture: Texture2D
@export var dragon_texture: Texture2D

@export_group("Species Cards")
@export var wolf_card: Texture2D
@export var bear_card: Texture2D
@export var spider_card: Texture2D
@export var boar_card: Texture2D
@export var troll_card: Texture2D
@export var dragon_card: Texture2D

@export_category("Spatial Rules")
@export var center_position: Vector2 = Vector2.ZERO # Center point of the map (Royal Keep)
@export var max_map_radius: float = 8000.0 # Maximum width or coordinate radius of map
@export var spawn_interval_sec: float = 30.0

# Species categories and base difficulty scaling
const SPECIES_LEVEL_RANGES = [
	{"min_level": 1,  "max_level": 5,  "species": "Wolf",    "power_factor": 150},
	{"min_level": 6,  "max_level": 10, "species": "Bear",    "power_factor": 450},
	{"min_level": 11, "max_level": 15, "species": "Spider",  "power_factor": 1200},
	{"min_level": 16, "max_level": 20, "species": "Boar",    "power_factor": 3500},
	{"min_level": 21, "max_level": 25, "species": "Troll",   "power_factor": 9800},
	{"min_level": 26, "max_level": 30, "species": "Dragon",  "power_factor": 28000}
]

var _pool: Array[WildlingNode] = []
var _active_nodes: Array[WildlingNode] = []
var _regions: Array[KingdomSpawnRegion] = []
var _spawn_timer: Timer

func _ready() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = spawn_interval_sec
	_spawn_timer.autostart = true
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)

# Initialize spawn layouts
func initialize_spawning(regions: Array[KingdomSpawnRegion], random_seed: int, map_center: Vector2) -> void:
	seed(random_seed)
	_regions = regions
	center_position = map_center
	
	_warm_pool(100)
	
	# Dynamically modify max_active_spawns of regions depending on proximity to center
	# (Fulfilling: Density increases toward center)
	for region in _regions:
		if region.region_type != "Wildling":
			continue
			
		var distance = region.global_position.distance_to(center_position)
		# Higher density factor near center (min 1.0, max 2.5 multiplier for spawn density)
		var proximity_factor = 1.0 + (1.5 * (1.0 - clampf(distance / max_map_radius, 0.0, 1.0)))
		region.max_active_spawns = clampi(int(region.max_active_spawns * proximity_factor), 3, 35)
		
		# Initial spawns
		var initial_spawn_count = clampi(int(region.max_active_spawns * 0.5), 1, region.max_active_spawns)
		for i in range(initial_spawn_count):
			spawn_wildling_in_region(region)

func _warm_pool(size: int) -> void:
	if not wildling_node_scene:
		push_error("WildlingSpawnManager: WildlingNode scene is NOT assigned!")
		return
		
	for i in range(size):
		var node = wildling_node_scene.instantiate() as WildlingNode
		node.visible = false
		node.clicked.connect(_on_node_clicked)
		add_child(node)
		_pool.append(node)

func _get_pooled_node() -> WildlingNode:
	for node in _pool:
		if not node.visible:
			node.visible = true
			return node
			
	var node = wildling_node_scene.instantiate() as WildlingNode
	node.clicked.connect(_on_node_clicked)
	add_child(node)
	_pool.append(node)
	node.visible = true
	return node

# Recycles wildlings back to the cache
func recycle_node(node: WildlingNode) -> void:
	if _active_nodes.has(node):
		_active_nodes.erase(node)
	node.visible = false
	node.global_position = Vector2(-99999, -99999)

func spawn_wildling_in_region(region: KingdomSpawnRegion) -> void:
	if not region.can_spawn_more():
		return
		
	# Select level based on region bounds, skewed by proximity to center (higher levels near core)
	var distance = region.global_position.distance_to(center_position)
	var proximity_factor = 1.0 - clampf(distance / max_map_radius, 0.0, 1.0)
	
	# Compute actual levels skewed by region configuration and map position
	var delta_level = region.max_level - region.min_level
	var target_lvl = region.min_level + int(delta_level * proximity_factor) + randi_range(-2, 2)
	target_lvl = clampi(target_lvl, 1, 30)
	
	# Determine species profiles
	var species_profile = SPECIES_LEVEL_RANGES[0]
	for profile in SPECIES_LEVEL_RANGES:
		if target_lvl >= profile["min_level"] and target_lvl <= profile["max_level"]:
			species_profile = profile
			break
			
	var species_name = species_profile["species"]
	var base_power = species_profile["power_factor"]
	var power = int(base_power * target_lvl * randf_range(0.9, 1.1))
	
	# Fetch correct texture maps
	var tex: Texture2D = wolf_texture
	var card_tex: Texture2D = wolf_card
	
	match species_name:
		"Wolf":
			tex = wolf_texture
			card_tex = wolf_card
		"Bear":
			tex = bear_texture
			card_tex = bear_card
		"Spider":
			tex = spider_texture
			card_tex = spider_card
		"Boar":
			tex = boar_texture
			card_tex = boar_card
		"Troll":
			tex = troll_texture
			card_tex = troll_card
		"Dragon":
			tex = dragon_texture
			card_tex = dragon_card
			
	var spawn_pos = region.get_random_spawn_point()
	
	var node = _get_pooled_node()
	node.global_position = spawn_pos
	node.setup_node(target_lvl, species_name, power, tex, card_tex)
	_active_nodes.append(node)
	region.register_spawn(node)

func _on_node_clicked(node: WildlingNode) -> void:
	wildling_node_clicked.emit(node)

func _on_spawn_timer_timeout() -> void:
	# Add new spawns periodically
	for region in _regions:
		if region.region_type == "Wildling" and region.can_spawn_more():
			# Dynamic chance based on distance and region weights
			var distance = region.global_position.distance_to(center_position)
			var density_boost = 1.0 - (0.5 * (distance / max_map_radius))
			if randf() <= region.spawn_weight * density_boost * 0.5:
				spawn_wildling_in_region(region)
