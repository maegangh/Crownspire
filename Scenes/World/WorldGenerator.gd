extends Node2D

@export_category("World Settings")
@export var world_size := Vector2(8192, 8192)
@export var edge_margin := 450.0
@export var castle_safe_radius := 900.0
## Legacy export kept for scene compatibility; shared terrain uses MapPlacementContract.
@export var generation_seed := 12345

@export_category("Amounts")
@export var lake_count := 6
@export var mountain_count := 18
@export var forest_count := 35
@export var rock_count := 30

const MapPlacementContractScript = preload("res://Scripts/World/MapPlacementContract.gd")

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

var occupied_areas: Array[Dictionary] = []


func _ready() -> void:
	generate_world()


func _kingdom_id() -> String:
	if has_node("/root/AllianceBackend") and AllianceBackend.has_method("get_profile"):
		var kid: String = str(AllianceBackend.get_profile().get("kingdom_id", "")).strip_edges()
		if kid != "":
			return kid
	if has_node("/root/AllianceLairState") and AllianceLairState.has_method("get_kingdom_id"):
		return str(AllianceLairState.get_kingdom_id())
	return "kingdom_dev_001"


func generate_world() -> void:
	clear_generated_environment()
	## Shared contract — lakes/mountains/forests/rocks are kingdom-deterministic and
	## independent of the local player's castle (server validates the same blockers).
	var blockers: Array = MapPlacementContractScript.compute_blockers(_kingdom_id())
	var lake_i := 0
	var mountain_i := 0
	var forest_i := 0
	var rock_i := 0
	for b in blockers:
		var kind: String = str(b.get("kind", ""))
		var pos := Vector2(float(b.get("x", 0.0)), float(b.get("y", 0.0)))
		match kind:
			"lake":
				_spawn_at(LAKE_SCENES, lakes_container, pos, lake_i, Vector2(0.12, 0.20))
				lake_i += 1
			"mountain":
				_spawn_at(MOUNTAIN_SCENES, mountains_container, pos, mountain_i, Vector2(0.12, 0.20))
				mountain_i += 1
			"forest":
				_spawn_at(FOREST_SCENES, forests_container, pos, forest_i, Vector2(0.10, 0.17))
				forest_i += 1
			"rock":
				_spawn_at(ROCK_SCENES, rocks_container, pos, rock_i, Vector2(0.10, 0.16))
				rock_i += 1
		reserve_area(pos, float(b.get("radius", 0.0)))


func _spawn_at(
	library: Array[PackedScene],
	container: Node2D,
	pos: Vector2,
	index: int,
	scale_range: Vector2
) -> void:
	if library.is_empty() or container == null:
		return
	var packed: PackedScene = library[index % library.size()]
	var instance := packed.instantiate() as Node2D
	if instance == null:
		return
	container.add_child(instance)
	instance.global_position = pos
	var t: float = float((index * 37) % 100) / 100.0
	var scale_value: float = lerpf(scale_range.x, scale_range.y, t)
	instance.scale = Vector2.ONE * scale_value
	instance.rotation = deg_to_rad(-12.0 + 24.0 * t)
	instance.set_meta("generated_environment", true)
	instance.set_meta("map_contract", MapPlacementContractScript.CONTRACT_ID)


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
		if container == null:
			continue
		for child in container.get_children():
			if child.has_meta("generated_environment"):
				child.queue_free()
