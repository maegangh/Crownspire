# ==============================================================================
# Crownspire MMO - Kingdom Manager Script (Main World Map Coordinator)
# Godot 4.6 / GDScript 2.0 Central orchestrator for maps, events & campaign columns
# ==============================================================================

extends Node2D

@export_category("Core Game Balance")
@export var random_seed: int = 423851
@export var player_castle_position: Vector2 = Vector2(-800, 600) # Base starting coordinates
@export var royal_keep_position: Vector2 = Vector2.ZERO          # Map center focal coordinate

@export_category("Sub-Managers Paths")
@export var resource_spawner: ResourceSpawnManager
@export var wildling_spawner: WildlingSpawnManager
@export var march_manager: MarchManager

@export_category("Region Roots")
@export var resource_regions_root: Node2D
@export var wildling_regions_root: Node2D

# Event tracking
signal display_resource_panel(node: ResourceNode)
signal display_wildling_panel(node: WildlingNode)

var _all_regions: Array[KingdomSpawnRegion] = []
var _is_event_multiplier_active: bool = false
var _active_kingdom_id: int = 1

func _ready() -> void:
	print("[KingdomManager] Initializing Crownspire Realm Maps...")
	_gather_spawn_regions()
	_validate_and_link_subsystems()
	
	# Launch state initialization
	initialize_kingdom(_active_kingdom_id, random_seed)

# Gather collision-defined areas
func _gather_spawn_regions() -> void:
	_all_regions.clear()
	
	if resource_regions_root:
		for child in resource_regions_root.get_children():
			if child is KingdomSpawnRegion:
				_all_regions.append(child)
				
	if wildling_regions_root:
		for child in wildling_regions_root.get_children():
			if child is KingdomSpawnRegion:
				_all_regions.append(child)
				
	print("[KingdomManager] Total spawn zones registered: ", _all_regions.size())

# Secure reference hookups
func _validate_and_link_subsystems() -> void:
	if not resource_spawner:
		resource_spawner = get_node_or_null("ResourceSpawnManager") as ResourceSpawnManager
	if not wildling_spawner:
		wildling_spawner = get_node_or_null("WildlingSpawnManager") as WildlingSpawnManager
	if not march_manager:
		march_manager = get_node_or_null("MarchManager") as MarchManager
		
	if resource_spawner:
		resource_spawner.resource_node_clicked.connect(_on_resource_node_clicked)
	else:
		push_error("[KingdomManager] Fatal: ResourceSpawnManager reference is unassigned!")
		
	if wildling_spawner:
		wildling_spawner.wildling_node_clicked.connect(_on_wildling_node_clicked)
	else:
		push_error("[KingdomManager] Fatal: WildlingSpawnManager reference is unassigned!")
		
	if march_manager:
		march_manager.march_action_completed.connect(_on_march_action_completed)
	else:
		push_error("[KingdomManager] Fatal: MarchManager reference is unassigned!")

# Initiates a specific kingdom grid layout deterministically
func initialize_kingdom(kingdom_id: int, seed_value: int) -> void:
	_active_kingdom_id = kingdom_id
	var kingdom_seed = seed_value + (kingdom_id * 1000)
	
	print("[KingdomManager] Formatting Kingdom Guild Grid #", kingdom_id, " using seed: ", kingdom_seed)
	
	# Dispatch initialization triggers
	if resource_spawner:
		resource_spawner.initialize_spawning(_all_regions, kingdom_seed)
	if wildling_spawner:
		var radius = royal_keep_position.distance_to(player_castle_position) * 1.5
		wildling_spawner.initialize_spawning(_all_regions, kingdom_seed, royal_keep_position)

# Sends a standard gathering/war march column
func dispatch_march_to_node(target: Node2D) -> void:
	if not march_manager:
		push_error("[KingdomManager] MarchManager unavailable to send column.")
		return
		
	var speed = 350.0
	var action_time = 3.0
	
	if target is ResourceNode:
		# Faster movement for resource gatherers, longer collection time
		speed = 400.0
		action_time = 4.0
	elif target is WildlingNode:
		# Slower heavily armored war squads, instant battle resolution
		speed = 320.0
		action_time = 1.5
		
	march_manager.dispatch_march(player_castle_position, target, speed, action_time)

# ---------------------------------------------------------
# Event Handlers & Core Callbacks
# ---------------------------------------------------------

func _on_resource_node_clicked(node: ResourceNode) -> void:
	print("[KingdomManager] Input registered on resource: Lvl ", node.level, " ", node.resource_type, " with ", node.amount, " capacity.")
	display_resource_panel.emit(node)

func _on_wildling_node_clicked(node: WildlingNode) -> void:
	print("[KingdomManager] Input registered on monster: Lvl ", node.level, " Species: ", node.species, " Strength: ", node.power_rating, " CR")
	display_wildling_panel.emit(node)

func _on_march_action_completed(target: Node2D, success: bool) -> void:
	if not success:
		print("[KingdomManager] March action failed/recalled.")
		return
		
	if target is ResourceNode:
		var reward_multiplier = 1.5 if _is_event_multiplier_active else 1.0
		var collected = int(target.amount * reward_multiplier)
		print("[KingdomManager] Resource collected successfully! Earned: +", collected, " ", target.resource_type)
		# Recycle the node back to its pool
		if resource_spawner:
			resource_spawner.recycle_node(target)
			
	elif target is WildlingNode:
		print("[KingdomManager] Wildling vanquished! Species: ", target.species, " Level: ", target.level, ". Victory rewards dispatched to Vault!")
		# Recycle the wildling node
		if wildling_spawner:
			wildling_spawner.recycle_node(target)

# Supports Server/Event hooks for server-wide dynamic scaling
func activate_event_boost(active: bool) -> void:
	_is_event_multiplier_active = active
	print("[KingdomManager] Event resource harvesting multiplier toggled to: ", active)
