# ==============================================================================
#                 CROWNSPIRE KINGDOM 001 - PRODUCTION WORLD IMPORTER
# ==============================================================================
# Godot 4.x Production Map Loader and Renderer for kingdom001.json
# File Location: res://Scripts/WorldImporter.gd
#
# Handled elements:
# 1. Loads data dynamically from res://Data/kingdom001.json
# 2. Automatically instantiates map nodes into the Scene hierarchy
# 3. Scales tiles to Godot 2D coordinates: world_pos = tile_coords * tile_size
# 4. Spawns beautiful procedural placeholders using vector polygons and colors
# 5. Connects interactive UI checkboxes for runtime visibility layer filtering
# ==============================================================================

extends Node2D

# Tile settings retrieved dynamically from kingdom001.json
var tile_size: int = 16
var map_width: int = 800
var map_height: int = 800

# References to hierarchical Node2D layers
@onready var rivers_container: Node2D = $Terrain/Rivers
@onready var forests_container: Node2D = $Terrain/Forests
@onready var mountains_container: Node2D = $Terrain/Mountains
@onready var plains_container: Node2D = $Terrain/Plains
@onready var fog_edges_container: Node2D = $Terrain/FogEdges

@onready var roads_container: Node2D = $Roads
@onready var resource_regions_container: Node2D = $ResourceRegions
@onready var gates_container: Node2D = $Gates
@onready var royal_keep_container: Node2D = $RoyalKeep
@onready var grand_landmarks_container: Node2D = $GrandLandmarks
@onready var conquest_keeps_container: Node2D = $ConquestKeeps
@onready var watch_keeps_container: Node2D = $WatchKeeps
@onready var alliance_beasts_container: Node2D = $AllianceBeasts
@onready var alliance_hqs_container: Node2D = $AllianceHQs
@onready var buildable_regions_container: Node2D = $BuildableRegions

# Debug nodes
var debug_labels: Array[Label] = []

func _ready() -> void:
	print("[WorldImporter] Initializing production scene build...")
	
	# Load JSON Database
	var data = _load_database_file("res://Data/kingdom001.json")
	if data.is_empty():
		push_error("[WorldImporter] Fatal error: Could not load crownspire database.")
		return
		
	# Parse Scale Metadata
	_parse_world_scale(data)
	
	# Load and Spawn Layers sequentially
	_build_terrain(data.get("terrain", {}))
	_build_roads(data.get("roads", []))
	_build_buildable_regions(data.get("buildable_regions", []))
	_build_gates(data.get("gates", []))
	_build_royal_keep(data.get("royal_keep", {}))
	_build_grand_landmarks(data.get("grand_landmarks", []))
	_build_landmarks(data.get("landmarks", [])) # Standalone landmarks
	_build_keeps(data.get("conquest_keeps", []), data.get("watch_keeps", []))
	_build_beasts(data.get("alliance_beasts", []))
	_build_resources(data.get("resource_regions", []))
	
	# Initialize HUD Control Toggles
	_setup_hud_toggles()
	
	print("[WorldImporter] Map successfully instantiated. Ready to explore!")


# ==============================================================================
# 1. DATABASE LOADER
# ==============================================================================

func _load_database_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[WorldImporter] Database file not found at: " + path)
		return {}
		
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	
	var data = JSON.parse_string(content)
	if data == null:
		push_error("[WorldImporter] Invalid JSON syntax in database file.")
		return {}
		
	return data


func _parse_world_scale(data: Dictionary) -> void:
	if data.has("kingdom"):
		var meta = data["kingdom"]
		tile_size = int(meta.get("tile_size", 16))
		map_width = int(meta.get("width", 800))
		map_height = int(meta.get("height", 800))
		print("[WorldImporter] Active Realm: ", meta.get("name", "Crownspire"))
		print("[WorldImporter] Matrix dimensions: ", map_width, "x", map_height, " tiles @ ", tile_size, "px per tile.")


# ==============================================================================
# 2. SCENE GENERATORS
# ==============================================================================

func _build_terrain(terrain: Dictionary) -> void:
	# --- A. Rivers (Blue Curves) ---
	for r in terrain.get("rivers", []):
		var line = Line2D.new()
		line.name = r.get("name", "River")
		line.default_color = Color(0.1, 0.45, 0.85, 0.8) # Vibrant Blue
		line.width = 5.5
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		
		for p in r.get("points", []):
			line.add_point(_tile_to_pixel(Vector2(p["x"], p["y"])))
		rivers_container.add_child(line)
		
		if line.get_point_count() > 0:
			_spawn_label(line.get_point_position(0), r.get("name", "River"), Color(0.4, 0.7, 1.0))

	# --- B. Forests (Green Clusters with Asset Mapping) ---
	for f in terrain.get("forests", []):
		var center = _tile_to_pixel(Vector2(f["coords"]["x"], f["coords"]["y"]))
		var radius_px = float(f.get("radius", 14)) * tile_size
		var asset_key = f.get("asset_key", "forest_cluster")
		
		var fallback = Node2D.new()
		fallback.name = f.get("name", "ForestFallback")
		
		# Forest background canopy
		var canopy = Polygon2D.new()
		canopy.name = "Canopy"
		canopy.color = Color(0.08, 0.38, 0.18, 0.4) # Soft pine green overlay
		
		var pts = PackedVector2Array()
		var segments = 16
		for i in range(segments):
			var a = i * TAU / segments
			pts.append(Vector2(cos(a), sin(a)) * radius_px)
		canopy.polygon = pts
		fallback.add_child(canopy)
		
		# Individual Trees (Green Cones)
		var count = int(f.get("radius", 10) / 2.0) + 4
		for t in range(count):
			var r_dist = randf_range(0.0, radius_px * 0.85)
			var r_angle = randf_range(0.0, TAU)
			var tree_center = Vector2(cos(r_angle), sin(r_angle)) * r_dist
			
			var tree = Polygon2D.new()
			tree.color = Color(0.12, 0.48, 0.22, 0.9)
			tree.polygon = PackedVector2Array([
				tree_center + Vector2(0, -9),
				tree_center + Vector2(5, 3),
				tree_center + Vector2(-5, 3)
			])
			fallback.add_child(tree)
			
		var forest_node = _create_world_element(asset_key, fallback)
		forest_node.position = center
		forests_container.add_child(forest_node)
		
		_spawn_label(center, f.get("name"), Color(0.5, 0.85, 0.6))

	# --- C. Mountains (Gray Ridges with Asset Mapping) ---
	for m in terrain.get("mountain_ridges", []):
		var pos = _tile_to_pixel(Vector2(m["coords"]["x"], m["coords"]["y"]))
		var w = float(m.get("width", 20)) * tile_size
		var h = float(m.get("height", 15)) * tile_size
		var asset_key = m.get("asset_key", "mountain_peak")
		
		var fallback = Node2D.new()
		fallback.name = m.get("name", "MountainFallback")
		
		# Mountain Ridge Base
		var peak = Polygon2D.new()
		peak.name = "Peak"
		peak.color = Color(0.32, 0.33, 0.36, 0.85) # Slate mountain gray
		peak.polygon = PackedVector2Array([
			Vector2(0, -h / 2.0),
			Vector2(w / 2.0, h / 2.0),
			Vector2(-w / 2.0, h / 2.0)
		])
		fallback.add_child(peak)
		
		# Snowy peaks
		var snow = Polygon2D.new()
		snow.color = Color(0.92, 0.95, 0.98, 1.0) # Snowcap white
		snow.polygon = PackedVector2Array([
			Vector2(0, -h / 2.0),
			Vector2(w / 8.0, -h / 6.0),
			Vector2(-w / 8.0, -h / 6.0)
		])
		fallback.add_child(snow)
		
		var mountain_node = _create_world_element(asset_key, fallback)
		mountain_node.position = pos
		mountains_container.add_child(mountain_node)
		
		_spawn_label(pos, m.get("name"), Color(0.7, 0.75, 0.8))

	# --- D. Fog Edges (Fog Overlays with Asset Mapping) ---
	for fog in terrain.get("fog_edges", []):
		var pos = _tile_to_pixel(Vector2(fog["coords"]["x"], fog["coords"]["y"]))
		var w = float(fog.get("width", 100)) * tile_size
		var h = float(fog.get("height", 100)) * tile_size
		var asset_key = fog.get("asset_key", "fog_edge")
		
		var fallback = Node2D.new()
		fallback.name = fog.get("name", "FogFallback")
		
		var overlay = ColorRect.new()
		overlay.name = "FogRect"
		overlay.color = Color(0.08, 0.09, 0.12, 0.55) # Realm mist boundary
		overlay.size = Vector2(w, h)
		overlay.position = -Vector2(w/2, h/2)
		fallback.add_child(overlay)
		
		var fog_node = _create_world_element(asset_key, fallback)
		fog_node.position = pos
		fog_edges_container.add_child(fog_node)

	# --- E. Plains/General Background Artwork Backdrop ---
	var backdrop_fallback = Node2D.new()
	var backdrop_node = _create_world_element("terrain_backdrop", backdrop_fallback)
	if backdrop_node != backdrop_fallback:
		backdrop_node.position = Vector2(6400, 6400)
		plains_container.add_child(backdrop_node)
	else:
		backdrop_fallback.queue_free()


func _build_roads(roads: Array) -> void:
	for r in roads:
		var line = Line2D.new()
		line.name = r.get("name", "Road")
		
		var is_highway = r.get("road_type", "Province") == "Imperial"
		# Gold lines for Imperial Highways, greyish slate for local routes
		line.default_color = Color(0.92, 0.65, 0.15, 0.8) if is_highway else Color(0.48, 0.52, 0.6, 0.5)
		line.width = 4.5 if is_highway else 2.5
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		
		for p in r.get("points", []):
			line.add_point(_tile_to_pixel(Vector2(p["x"], p["y"])))
		roads_container.add_child(line)


func _build_buildable_regions(regions: Array) -> void:
	for r in regions:
		var area = Polygon2D.new()
		area.name = r.get("name")
		# Transparent green overlay as requested
		area.color = Color(0.12, 0.65, 0.22, 0.11)
		
		var pts = PackedVector2Array()
		for pt in r.get("polygon", []):
			pts.append(_tile_to_pixel(Vector2(pt["x"], pt["y"])))
		area.polygon = pts
		buildable_regions_container.add_child(area)
		
		# Outline
		var boundary = Line2D.new()
		boundary.points = pts
		boundary.add_point(pts[0])
		boundary.default_color = Color(0.15, 0.72, 0.3, 0.38)
		boundary.width = 2.0
		buildable_regions_container.add_child(boundary)
		
		var center = Vector2.ZERO
		for p in pts:
			center += p
		center /= pts.size()
		
		var label_text = "%s\nSettle Zone (Capacity: %d bases)" % [r.get("name"), r.get("recommended_capacity", 100)]
		_spawn_label(center, label_text, Color(0.4, 0.85, 0.5))


func _build_gates(gates: Array) -> void:
	for g in gates:
		var pos = _tile_to_pixel(Vector2(g["coords"]["x"], g["coords"]["y"]))
		var size = 30.0
		var asset_key = g.get("asset_key", "gate_fortress_sp")
		
		var fallback = Node2D.new()
		fallback.name = g.get("name", "GateFallback")
		
		# Gates represented as sturdy fortress wall segments
		var gate = Polygon2D.new()
		gate.name = "GateWall"
		gate.color = Color(0.42, 0.46, 0.55, 1.0)
		gate.polygon = PackedVector2Array([
			Vector2(-size/2, -size/2),
			Vector2(size/2, -size/2),
			Vector2(size/2, size/2),
			Vector2(-size/2, size/2)
		])
		fallback.add_child(gate)
		
		# Portal archway slot
		var arch = ColorRect.new()
		arch.color = Color(0.05, 0.05, 0.08, 1.0)
		arch.size = Vector2(8, 14)
		arch.position = -Vector2(4, 7)
		fallback.add_child(arch)
		
		var gate_node = _create_world_element(asset_key, fallback)
		gate_node.position = pos
		gates_container.add_child(gate_node)
		
		_spawn_label(pos, "Fort Gate: " + g.get("name"), Color(0.8, 0.85, 0.9))


func _build_royal_keep(royal: Dictionary) -> void:
	if royal.is_empty():
		return
		
	var pos = _tile_to_pixel(Vector2(royal["coords"]["x"], royal["coords"]["y"]))
	var asset_key = royal.get("asset_key", "royal_keep_castle")
	
	var fallback = Node2D.new()
	fallback.name = royal.get("name", "RoyalKeepFallback")
	
	# Large Gold Keep representation as requested
	var castle = Polygon2D.new()
	castle.name = "GoldCastle"
	castle.color = Color(0.92, 0.68, 0.12, 1.0) # Sparkling Gold
	
	# 16-sided Imperial Star Crest
	var pts = PackedVector2Array()
	var spikes = 16
	var outer_r = 45.0
	var inner_r = 26.0
	for i in range(spikes * 2):
		var a = i * PI / spikes
		var r = outer_r if i % 2 == 0 else inner_r
		pts.append(Vector2(cos(a), sin(a)) * r)
	castle.polygon = pts
	fallback.add_child(castle)
	
	# Inner Citadel Fortress
	var citadel = Polygon2D.new()
	citadel.color = Color(0.18, 0.12, 0.08, 1.0) # Obsidian Core
	citadel.polygon = PackedVector2Array([
		Vector2(-15, -15),
		Vector2(15, -15),
		Vector2(15, 15),
		Vector2(-15, 15)
	])
	fallback.add_child(citadel)
	
	# Golden Spire
	var spire = Polygon2D.new()
	spire.color = Color(0.92, 0.68, 0.12, 1.0)
	spire.polygon = PackedVector2Array([
		Vector2(0, -10),
		Vector2(6, 4),
		Vector2(-6, 4)
	])
	fallback.add_child(spire)
	
	var keep_node = _create_world_element(asset_key, fallback)
	keep_node.position = pos
	royal_keep_container.add_child(keep_node)
	
	var text = "👑 ROYAL CITADEL (SOVEREIGN CENTER) 👑\nGrid coords: (%d, %d)" % [royal["coords"]["x"], royal["coords"]["y"]]
	_spawn_label(pos, text, Color(1.0, 0.82, 0.0))


func _build_grand_landmarks(grand_landmarks: Array) -> void:
	for l in grand_landmarks:
		var pos = _tile_to_pixel(Vector2(l["coords"]["x"], l["coords"]["y"]))
		var asset_key = l.get("asset_key", "grand_landmark_fortress")
		
		var fallback = Node2D.new()
		fallback.name = l.get("name", "GrandLandmarkFallback")
		
		# Large Blue icons for Grand Landmarks as requested
		var structure = Polygon2D.new()
		structure.name = "Structure"
		structure.color = Color(0.18, 0.55, 0.95, 1.0) # Deep Sapphire Blue
		
		# 8-sided Diamond Star Shape
		var pts = PackedVector2Array()
		var points = 8
		var outer_r = 30.0
		var inner_r = 15.0
		for i in range(points * 2):
			var a = i * PI / points
			var r = outer_r if i % 2 == 0 else inner_r
			pts.append(Vector2(cos(a), sin(a)) * r)
		structure.polygon = pts
		fallback.add_child(structure)
		
		# Glowing blue center core
		var core = Polygon2D.new()
		core.color = Color(0.45, 0.8, 1.0, 1.0) # Cyan beacon glow
		core.polygon = PackedVector2Array([
			Vector2(0, -8),
			Vector2(8, 0),
			Vector2(0, 8),
			Vector2(-8, 0)
		])
		fallback.add_child(core)
		
		var landmark_node = _create_world_element(asset_key, fallback)
		landmark_node.position = pos
		grand_landmarks_container.add_child(landmark_node)
		
		var buffs_text = l.get("buffDescription", "")
		var label_str = "🔹 LANDMARK: %s\nBuffs: %s" % [l.get("name"), buffs_text]
		_spawn_label(pos, label_str, Color(0.3, 0.7, 1.0))


func _build_landmarks(landmarks: Array) -> void:
	for l in landmarks:
		if l.get("id") == "landmark_royal_keep":
			continue
			
		var pos = _tile_to_pixel(Vector2(l["coords"]["x"], l["coords"]["y"]))
		var asset_key = l.get("asset_key", "grand_landmark_fortress")
		
		var fallback = Node2D.new()
		fallback.name = l.get("name", "MinorLandmarkFallback")
		
		# Minor Landmarks are simple blue square towers
		var tower = Polygon2D.new()
		tower.name = "Tower"
		tower.color = Color(0.2, 0.45, 0.85, 0.9)
		tower.polygon = PackedVector2Array([
			Vector2(-10, -10),
			Vector2(10, -10),
			Vector2(10, 10),
			Vector2(-10, 10)
		])
		fallback.add_child(tower)
		
		var landmark_node = _create_world_element(asset_key, fallback)
		landmark_node.position = pos
		grand_landmarks_container.add_child(landmark_node)
		_spawn_label(pos, l.get("name"), Color(0.4, 0.75, 1.0))


func _build_keeps(conquest: Array, watch: Array) -> void:
	# --- A. Conquest Keeps (Purple Keep Icons with Asset Mapping) ---
	for c in conquest:
		var pos = _tile_to_pixel(Vector2(c["coords"]["x"], c["coords"]["y"]))
		var is_major = c.get("tier", "minor") == "major"
		var size = 26.0 if is_major else 18.0
		var asset_key = c.get("asset_key", "conquest_keep_lvl2" if is_major else "conquest_keep_lvl1")
		
		var fallback = Node2D.new()
		fallback.name = c.get("name", "ConquestFallback")
		
		# Double-stacked fortress shape (Purple Keeps)
		var keep = Polygon2D.new()
		keep.name = "KeepBody"
		keep.color = Color(0.55, 0.18, 0.85, 1.0) if is_major else Color(0.42, 0.12, 0.70, 1.0)
		keep.polygon = PackedVector2Array([
			Vector2(-size/2, -size/2),
			Vector2(size/2, -size/2),
			Vector2(size/2, size/2),
			Vector2(-size/2, size/2)
		])
		fallback.add_child(keep)
		
		# Corner rampart spikes
		for offset in [Vector2(-size/2, -size/2), Vector2(size/2, -size/2)]:
			var spike = Polygon2D.new()
			spike.color = Color(0.22, 0.05, 0.45, 1.0)
			spike.polygon = PackedVector2Array([
				offset + Vector2(-3, 0),
				offset + Vector2(3, 0),
				offset + Vector2(0, -8)
			])
			fallback.add_child(spike)
			
		var keep_node = _create_world_element(asset_key, fallback)
		keep_node.position = pos
		conquest_keeps_container.add_child(keep_node)
			
		var desc = "🟣 %s\nTier: %s" % [c.get("name"), c.get("tier", "minor").to_upper()]
		_spawn_label(pos, desc, Color(0.75, 0.45, 1.0))

	# --- B. Watch Keeps (Gray Towers with Asset Mapping) ---
	for w in watch:
		var pos = _tile_to_pixel(Vector2(w["coords"]["x"], w["coords"]["y"]))
		var w_size = 11.0
		var asset_key = w.get("asset_key", "watch_keep_tower")
		
		var fallback = Node2D.new()
		fallback.name = w.get("name", "WatchKeepFallback")
		
		# Gray watchtowers as requested
		var tower = Polygon2D.new()
		tower.name = "Tower"
		tower.color = Color(0.45, 0.47, 0.52, 1.0) # Slate Grey
		tower.polygon = PackedVector2Array([
			Vector2(-w_size/2, -w_size/2),
			Vector2(w_size/2, -w_size/2),
			Vector2(w_size/2 * 0.7, w_size/2),
			Vector2(-w_size/2 * 0.7, w_size/2)
		])
		fallback.add_child(tower)
		
		# Watchtower roof spire
		var spire = Polygon2D.new()
		spire.color = Color(0.25, 0.27, 0.30, 1.0)
		spire.polygon = PackedVector2Array([
			Vector2(-w_size/2, -w_size/2),
			Vector2(w_size/2, -w_size/2),
			Vector2(0, -w_size/2 - 6)
		])
		fallback.add_child(spire)
		
		var tower_node = _create_world_element(asset_key, fallback)
		tower_node.position = pos
		watch_keeps_container.add_child(tower_node)
		
		_spawn_label(pos, "🗼 Tower: " + w.get("name"), Color(0.7, 0.72, 0.78))


func _build_beasts(beasts: Array) -> void:
	for b in beasts:
		var pos = _tile_to_pixel(Vector2(b["coords"]["x"], b["coords"]["y"]))
		var asset_key = b.get("asset_key", "beast_lair_spawn")
		
		var fallback = Node2D.new()
		fallback.name = b.get("name", "BeastFallback")
		
		# Red lair spiked icon as requested
		var lair = Polygon2D.new()
		lair.name = "Lair"
		lair.color = Color(0.85, 0.12, 0.12, 1.0) # Burning Crimson Red
		
		# Red star/spiked circle
		var pts = PackedVector2Array()
		var spikes = 8
		for i in range(spikes * 2):
			var a = i * PI / spikes
			var r = 16.0 if i % 2 == 0 else 9.0
			pts.append(Vector2(cos(a), sin(a)) * r)
		lair.polygon = pts
		fallback.add_child(lair)
		
		# Black skull centerpiece
		var center = Polygon2D.new()
		center.color = Color(0.08, 0.02, 0.02, 1.0)
		center.polygon = PackedVector2Array([
			Vector2(-4, -4),
			Vector2(4, -4),
			Vector2(3, 4),
			Vector2(-3, 4)
		])
		fallback.add_child(center)
		
		var beast_node = _create_world_element(asset_key, fallback)
		beast_node.position = pos
		alliance_beasts_container.add_child(beast_node)
		
		var text = "👹 BOSS: %s\nLevel %d\nDrops: %s" % [b.get("name"), int(b.get("level", 20)), b.get("reward", "Crest")]
		_spawn_label(pos, text, Color(1.0, 0.35, 0.35))


func _build_resources(regions: Array) -> void:
	for r in regions:
		var poly_pts = r.get("polygon", [])
		if poly_pts.size() < 3:
			continue
			
		var res_type = r.get("resourceType", "Lumber")
		var tier = int(r.get("tier", 1))
		
		# Get Palette
		var base_color = Color(0.08, 0.72, 0.42) # Lumber (Green)
		if res_type == "Quarry":
			base_color = Color(0.48, 0.44, 0.42) # Stone (Grey)
		elif res_type == "Iron":
			base_color = Color(0.95, 0.48, 0.08) # Iron (Orange)
		elif res_type == "Farming":
			base_color = Color(0.92, 0.68, 0.05) # Wheat (Gold)
			
		# Semi-transparent colored polygons as requested
		var region_poly = Polygon2D.new()
		region_poly.name = r.get("name")
		region_poly.color = Color(base_color.r, base_color.g, base_color.b, 0.06)
		
		var godot_pts = PackedVector2Array()
		for pt in poly_pts:
			godot_pts.append(_tile_to_pixel(Vector2(pt["x"], pt["y"])))
		region_poly.polygon = godot_pts
		resource_regions_container.add_child(region_poly)
		
		# Dashed region border line
		var border = Line2D.new()
		border.points = godot_pts
		border.add_point(godot_pts[0])
		border.default_color = Color(base_color.r, base_color.g, base_color.b, 0.28)
		border.width = 1.2
		resource_regions_container.add_child(border)
		
		# Center node icon
		var center_pos = _tile_to_pixel(Vector2(r["coords"]["x"], r["coords"]["y"]))
		var core_dot = Polygon2D.new()
		core_dot.color = base_color
		var dot_pts = PackedVector2Array()
		for d in range(6):
			var a = d * TAU / 6
			dot_pts.append(center_pos + Vector2(cos(a), sin(a)) * 5.5)
		core_dot.polygon = dot_pts
		resource_regions_container.add_child(core_dot)
		
		# Spawning nodes inside the boundary box
		var spawn_count = tier * 5
		var min_x = 99999.0; var max_x = -99999.0
		var min_y = 99999.0; var max_y = -99999.0
		for pt in godot_pts:
			if pt.x < min_x: min_x = pt.x
			if pt.x > max_x: max_x = pt.x
			if pt.y < min_y: min_y = pt.y
			if pt.y > max_y: max_y = pt.y
			
		var nodes_spawned = 0
		var max_attempts = spawn_count * 10
		var attempts = 0
		
		while nodes_spawned < spawn_count and attempts < max_attempts:
			attempts += 1
			var test_pos = Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
			
			if Geometry2D.is_point_in_polygon(test_pos, godot_pts):
				if test_pos.distance_to(center_pos) < 10.0:
					continue
					
				var res_node_fallback = Node2D.new()
				res_node_fallback.name = "ResNodeFallback"
				
				var res_vector = Polygon2D.new()
				res_vector.color = Color(base_color.r * 1.15, base_color.g * 1.15, base_color.b * 1.15, 0.9)
				
				# Unique shapes for each resource
				var shape_pts = PackedVector2Array()
				if res_type == "Lumber": # Leaf diamond
					shape_pts = PackedVector2Array([Vector2(0, -4), Vector2(3.5, 0), Vector2(0, 4), Vector2(-3.5, 0)])
				elif res_type == "Quarry": # Octagonal rock
					shape_pts = PackedVector2Array([Vector2(-2, -3), Vector2(2, -3), Vector2(4, 0), Vector2(2, 3), Vector2(-2, 3), Vector2(-4, 0)])
				elif res_type == "Iron": # Spiked Ore
					shape_pts = PackedVector2Array([Vector2(0, -5), Vector2(3.5, 3), Vector2(-3.5, 3)])
				else: # Crop square
					shape_pts = PackedVector2Array([Vector2(-3, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-3, 3)])
					
				res_vector.polygon = shape_pts
				res_node_fallback.add_child(res_vector)
				
				var node_asset_key = "resource_node_" + res_type
				var res_node = _create_world_element(node_asset_key, res_node_fallback)
				res_node.position = test_pos
				resource_regions_container.add_child(res_node)
				nodes_spawned += 1
				
		var desc = "%s\n%s (Tier %d)\nSpawned: %d nodes" % [r.get("name"), res_type, tier, nodes_spawned]
		_spawn_label(center_pos, desc, base_color.lightened(0.2))


# ==============================================================================
# 3. UTILITIES & COORDINATE MAPPERS
# ==============================================================================

# Core Asset Factory: Dynamically loads production scenes (.tscn) or sprites (.png)
# and falls back gracefully to vector polygons if they aren't created yet.
func _create_world_element(asset_key: String, fallback_node: Node2D) -> Node2D:
	# 1. Look for a compiled PackedScene (.tscn) inside production folders
	var scene_paths = [
		"res://Scenes/World/Sprites/" + asset_key + ".tscn",
		"res://Scenes/Sprites/" + asset_key + ".tscn",
		"res://Assets/Sprites/" + asset_key + ".tscn",
		"res://Assets/" + asset_key + ".tscn"
	]
	
	for path in scene_paths:
		if ResourceLoader.exists(path):
			var loaded_scene = load(path)
			if loaded_scene:
				var inst = loaded_scene.instantiate()
				if inst is Node2D:
					print("[WorldImporter] Instantiated custom production scene for ", asset_key, " from: ", path)
					fallback_node.queue_free()
					return inst

	# 2. Look for an imported 2D Texture (.png / .svg) in asset structures
	var texture_paths = [
		"res://Assets/World/" + asset_key + ".png",
		"res://Assets/Terrain/" + asset_key + ".png",
		"res://Assets/Objectives/" + asset_key + ".png",
		"res://Assets/" + asset_key + ".png",
		"res://Textures/" + asset_key + ".png",
		"res://Sprites/" + asset_key + ".png"
	]
	
	for path in texture_paths:
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex is Texture2D:
				var sprite = Sprite2D.new()
				sprite.texture = tex
				sprite.name = asset_key + "_Sprite"
				print("[WorldImporter] Loaded production texture for ", asset_key, " from: ", path)
				fallback_node.queue_free()
				return sprite

	# 3. Fallback to vector elements if artwork is not yet present
	return fallback_node


# Vector Scale conversion: world_pixel = grid_coords * tile_size
func _tile_to_pixel(coords: Vector2) -> Vector2:
	return coords * tile_size


# Renders high-readability floating black labels for map coordinates and buffs
func _spawn_label(world_pos: Vector2, text: String, text_color: Color = Color.WHITE) -> void:
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# Solid slate background to stand out
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.04, 0.06, 0.88)
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.border_color = text_color.darkened(0.4)
	bg.set_corner_radius_all(3)
	bg.expand_margin_left = 4
	bg.expand_margin_right = 4
	bg.expand_margin_top = 2
	bg.expand_margin_bottom = 2
	label.add_theme_stylebox_override("normal", bg)
	
	# Small legible tactical font
	label.add_theme_color_override("font_color", text_color)
	label.add_theme_font_size_override("font_size", 9)
	
	# Grid Coordinate positioning
	label.position = world_pos - Vector2(100, 10)
	label.custom_minimum_size = Vector2(200, 20)
	label.clip_text = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	# Add to Scene hierarchy
	var labels_node = get_node_or_null("HUD/Labels")
	if labels_node:
		labels_node.add_child(label)
	else:
		add_child(label)
		
	debug_labels.append(label)


# ==============================================================================
# 4. RUNTIME USER INTERFACE TOGGLES
# ==============================================================================

func _setup_hud_toggles() -> void:
	var control_panel = get_node_or_null("HUD/ControlPanel")
	if not control_panel:
		return
		
	# Setup styling for HUD panel
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.10, 0.95) # Futuristic Space Navy
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.92, 0.65, 0.15, 0.85) # Golden sovereign trim
	sb.set_corner_radius_all(5)
	control_panel.add_theme_stylebox_override("panel", sb)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	control_panel.add_child(vbox)
	
	var space = Control.new()
	space.custom_minimum_size = Vector2(0, 2)
	vbox.add_child(space)
	
	# Title Header
	var title = Label.new()
	title.text = "👑 CROWNSPIRE WORLD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.92, 0.65, 0.15))
	vbox.add_child(title)
	
	var desc = Label.new()
	desc.text = "Strategic Layer Visibility"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 9)
	desc.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	vbox.add_child(desc)
	
	var div = ColorRect.new()
	div.color = Color(0.2, 0.25, 0.35, 0.4)
	div.custom_minimum_size = Vector2(0, 2)
	vbox.add_child(div)
	
	# Connect Checkboxes
	_add_checkbox_option(vbox, "🌳 Terrain Assets", true, func(v): $Terrain.visible = v)
	_add_checkbox_option(vbox, "🛣️ Highways & Roads", true, func(v): $Roads.visible = v)
	_add_checkbox_option(vbox, "💎 Resource Regions", true, func(v): $ResourceRegions.visible = v)
	_add_checkbox_option(vbox, "🏰 Faction Objectives", true, func(v): 
		$Gates.visible = v
		$RoyalKeep.visible = v
		$GrandLandmarks.visible = v
		$ConquestKeeps.visible = v
		$WatchKeeps.visible = v
		$AllianceBeasts.visible = v
	)
	_add_checkbox_option(vbox, "🟩 Buildable Settlement Rings", true, func(v): $BuildableRegions.visible = v)
	_add_checkbox_option(vbox, "🏷️ Map Labels", true, func(v): 
		var label_node = get_node_or_null("HUD/Labels")
		if label_node:
			label_node.visible = v
	)


func _add_checkbox_option(parent: VBoxContainer, text: String, default: bool, toggle_func: Callable) -> void:
	var cb = CheckBox.new()
	cb.text = text
	cb.button_pressed = default
	cb.add_theme_font_size_override("font_size", 11)
	cb.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(toggle_func)
	parent.add_child(cb)
