# ==============================================================================
# Crownspire MMO - Dynamic Spawn Area Region
# Godot 4.6 / GDScript 2.0 Reusable Area2D region-based bounding box/polygon validator
# ==============================================================================

class_name KingdomSpawnRegion
extends Area2D

@export_enum("Resource", "Wildling", "Buildable", "Restricted") var region_type: String = "Resource"
@export var allowed_spawn_types: Array[String] = [] # e.g. ["food", "wood", "stone", "iron", "crystal"]
@export var min_level: int = 1
@export var max_level: int = 7
@export var spawn_weight: float = 1.0
@export var max_active_spawns: int = 15

var active_spawns: Array[Node2D] = []

func _ready() -> void:
	# Ensure the collision area is set to monitor clicks or queries if needed
	monitoring = false
	monitorable = false
	add_to_group("spawn_regions")

# Returns if a new node can be spawned in this region
func can_spawn_more() -> bool:
	_cleanup_active_spawns()
	return active_spawns.size() < max_active_spawns

# Track a newly spawned object
func register_spawn(spawn_node: Node2D) -> void:
	if not active_spawns.has(spawn_node):
		active_spawns.append(spawn_node)

# Cleans up freed nodes from our tracker
func _cleanup_active_spawns() -> void:
	var valid_spawns: Array[Node2D] = []
	for node in active_spawns:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			valid_spawns.append(node)
	active_spawns = valid_spawns

# Picks a random, verified point inside the collision shape/polygon of this Area2D
func get_random_spawn_point() -> Vector2:
	var shape_nodes = find_children("", "CollisionShape2D")
	var polygon_nodes = find_children("", "CollisionPolygon2D")
	
	# Priority 1: Check Polygon Collision Shape
	for poly in polygon_nodes:
		if poly is CollisionPolygon2D:
			var points = poly.polygon
			if points.size() < 3:
				continue
				
			# Compute bounding box of polygon
			var min_x = points[0].x
			var max_x = points[0].x
			var min_y = points[0].y
			var max_y = points[0].y
			for pt in points:
				min_x = min(min_x, pt.x)
				max_x = max(max_x, pt.x)
				min_y = min(min_y, pt.y)
				max_y = max(max_y, pt.y)
				
			# Try up to 40 times to find a verified coordinate inside polygon boundaries
			for attempt in range(40):
				var test_pt = Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
				if Geometry2D.is_point_in_polygon(test_pt, points):
					return global_position + poly.position + test_pt
					
	# Priority 2: Check standard primitive Collision Shapes (Rectangles/Circles)
	for col in shape_nodes:
		if col is CollisionShape2D and col.shape:
			var shape = col.shape
			if shape is RectangleShape2D:
				var half_size = shape.size / 2.0
				var rx = randf_range(-half_size.x, half_size.x)
				var ry = randf_range(-half_size.y, half_size.y)
				return global_position + col.position + Vector2(rx, ry)
			elif shape is CircleShape2D:
				var r = shape.radius * sqrt(randf()) # Uniform radial distribution
				var angle = randf_range(0.0, TAU)
				return global_position + col.position + Vector2(cos(angle) * r, sin(angle) * r)

	# Fallback: Just return the global coordinate origin of the region
	return global_position
