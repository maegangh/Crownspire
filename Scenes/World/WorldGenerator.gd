extends Node2D

@export_category("World Settings")
@export var world_size := Vector2(8192, 8192)
@export var edge_margin := 450.0
@export var castle_safe_radius := 900.0
@export var generation_seed := 12345

@export_category("Amounts")
@export var lake_count := 6
@export var mountain_count := 18
@export var forest_count := 35

@export var rock_count := 30

const LAKE_SCENES: Array[PackedScene] = [
	preload("res://Scenes/Terrain/Water/LakeLarge.tscn"),
	preload("res://Scenes/Terrain/Water/LakeSmall.tscn")
]

const MOUNTAIN_SCENES: Array[PackedScene] = [
	preload("res://Scenes/Terrain/Mountain/MountainCluster.tscn")
]

const FOREST_SCENES: Array[PackedScene] = [
	preload("res://Scenes/Terrain/Forest/ForestCluster01.tscn"),
	preload("res://Scenes/Terrain/Forest/ForestCluster02.tscn"),
	preload("res://Scenes/Terrain/Forest/ForestCluster03.tscn"),
	preload("res://Scenes/Terrain/Forest/ForestCluster04.tscn"),
	preload("res://Scenes/Terrain/Forest/ForestCluster05.tscn")
]

const ROCK_SCENES: Array[PackedScene] = [
	preload("res://Scenes/Terrain/Rocks/RockCluster01.tscn"),
	preload("res://Scenes/Terrain/Rocks/RockCluster02.tscn"),
	preload("res://Scenes/Terrain/Rocks/RockCluster03.tscn"),
	preload("res://Scenes/Terrain/Rocks/RockyHillCluster01.tscn")
]

@onready var lakes_container: Node2D = $"../Terrain/Lakes"
@onready var mountains_container: Node2D = $"../Terrain/Mountains"
@onready var forests_container: Node2D = $"../Terrain/Forests"
@onready var player_castle: Node2D = $"../PlayerCastleMarker"
@onready var rocks_container: Node2D = $"../Terrain/Rocks"

var rng := RandomNumberGenerator.new()
var occupied_areas: Array[Dictionary] = []


func _ready() -> void:
	rng.seed = generation_seed
	generate_world()


func generate_world() -> void:
	clear_generated_environment()

	# Protect the player's castle.
	reserve_area(player_castle.global_position, castle_safe_radius)

	spawn_random_scenes(
		LAKE_SCENES,
		lakes_container,
		lake_count,
		Vector2(0.12, 0.12),
		Vector2(0.20, 0.20),
		700.0
	)

	spawn_random_scenes(
		MOUNTAIN_SCENES,
		mountains_container,
		mountain_count,
		Vector2(0.12, 0.12),
		Vector2(0.20, 0.20),
		550.0
	)

	spawn_random_scenes(
		FOREST_SCENES,
		forests_container,
		forest_count,
		Vector2(0.10, 0.10),
		Vector2(0.17, 0.17),
		425.0
	)

	spawn_random_scenes(
		ROCK_SCENES,
		rocks_container,
		rock_count,
		Vector2(0.10, 0.10),
		Vector2(0.16, 0.16),
		250.0
	)

func spawn_random_scenes(
	scene_library: Array[PackedScene],
	container: Node2D,
	amount: int,
	min_scale: Vector2,
	max_scale: Vector2,
	placement_radius: float
) -> void:
	if scene_library.is_empty():
		return

	for index in amount:
		var spawn_position := find_valid_position(placement_radius)

		if spawn_position == Vector2.INF:
			push_warning(
				"Could not find a valid position for object number %d." % index
			)
			continue

		var packed_scene := scene_library[
			rng.randi_range(0, scene_library.size() - 1)
		]

		var instance := packed_scene.instantiate() as Node2D

		if instance == null:
			continue

		container.add_child(instance)
		instance.global_position = spawn_position

		var scale_value := rng.randf_range(min_scale.x, max_scale.x)
		instance.scale = Vector2.ONE * scale_value
		instance.rotation = deg_to_rad(rng.randf_range(-12.0, 12.0))
		instance.set_meta("generated_environment", true)

		reserve_area(spawn_position, placement_radius)
		

func find_valid_position(required_radius: float) -> Vector2:
	const MAX_ATTEMPTS := 250

	for attempt in MAX_ATTEMPTS:
		var candidate := Vector2(
			rng.randf_range(
				edge_margin + required_radius,
				world_size.x - edge_margin - required_radius
			),
			rng.randf_range(
				edge_margin + required_radius,
				world_size.y - edge_margin - required_radius
			)
		)

		if is_area_available(candidate, required_radius):
			return candidate

	return Vector2.INF


func reserve_area(area_position: Vector2, area_radius: float) -> void:
	occupied_areas.append({
		"position": area_position,
		"radius": area_radius
	})


func is_area_available(candidate: Vector2, candidate_radius: float) -> bool:
	for area in occupied_areas:
		var required_distance: float = candidate_radius + float(area["radius"])
		var existing_position: Vector2 = area["position"]

		if candidate.distance_to(existing_position) < required_distance:
			return false

	return true
	
func clear_generated_environment() -> void:
	occupied_areas.clear()

	for container in [
		lakes_container,
		mountains_container,
		forests_container,
		rocks_container
	]:
		for child in container.get_children():
			if child.has_meta("generated_environment"):
				child.queue_free()
