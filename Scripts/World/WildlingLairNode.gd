extends Node2D

## World Wildling Lair marker (presentation only).
## Distinct from WildlingNode. No combat / no MarchState coupling.

const WildlingLairDatabase = preload("res://scripts/World/WildlingLairDatabase.gd")
const GROUP_NAME := "wildling_lairs"

@export var lair_id: String = ""
@export var lair_level: int = 1
@export var recommended_power: int = 0
@export var species: String = ""
@export var visual_variant: String = "beast"
@export var display_name: String = "Wildling Lair"
@export var creature_title: String = ""

var _level_def: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group("world_blockers")
	# Below marches (250+) and search markers (280); above normal Wildlings (100).
	z_index = 110
	_apply_labels()


func setup_from_def(def: Dictionary, stable_id: String) -> void:
	_level_def = def.duplicate(true)
	lair_id = stable_id
	lair_level = int(def.get("level", 1))
	recommended_power = int(def.get("recommended_power", 0))
	species = str(def.get("species", "")).strip_edges().to_lower()
	visual_variant = str(def.get("visual_variant", "")).strip_edges().to_lower()
	if visual_variant.is_empty():
		visual_variant = WildlingLairDatabase.visual_variant_for_species(species)
	display_name = str(def.get("display_name", "Wildling Lair"))
	creature_title = WildlingLairDatabase.creature_title(def)
	name = "WildlingLair_%s" % lair_id
	z_index = 110

	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		var tex: Texture2D = WildlingLairDatabase.get_texture_for_level_def(def)
		sprite.texture = tex
		sprite.modulate = Color.WHITE
		sprite.centered = true
		sprite.position = Vector2.ZERO
		sprite.scale = Vector2(
			WildlingLairDatabase.WORLD_SPRITE_SCALE,
			WildlingLairDatabase.WORLD_SPRITE_SCALE
		)

	# Remove temporary den ring if present from older scenes.
	var ring: Node = get_node_or_null("DenRing")
	if ring != null:
		ring.queue_free()
	var old_ring: Node = get_node_or_null("LairRing")
	if old_ring != null:
		old_ring.queue_free()

	var click: Node = get_node_or_null("ClickArea")
	if click != null:
		if "lair_id" in click:
			click.set("lair_id", lair_id)
		if "lair_level" in click:
			click.set("lair_level", lair_level)
		if "recommended_power" in click:
			click.set("recommended_power", recommended_power)
		if "species" in click:
			click.set("species", species)
		if "visual_variant" in click:
			click.set("visual_variant", visual_variant)
		if click is Area2D:
			(click as Area2D).input_pickable = true
			(click as Area2D).monitoring = true

	_apply_labels()
	_place_nameplates()
	_sync_click_shape()


func get_level_def() -> Dictionary:
	if not _level_def.is_empty():
		return _level_def.duplicate(true)
	return WildlingLairDatabase.get_level_def(lair_level)


func get_search_position() -> Vector2:
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		return to_global(sprite.position)
	return global_position


func _apply_labels() -> void:
	var title: Label = get_node_or_null("TitleLabel") as Label
	if title != null:
		title.text = "WILDLING LAIR"
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var level_label: Label = get_node_or_null("LevelLabel") as Label
	if level_label != null:
		level_label.text = "Lv.%d" % lair_level
		level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _place_nameplates() -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	var half_h: float = 160.0
	if sprite != null and sprite.texture != null:
		half_h = (sprite.texture.get_size().y * sprite.scale.y) * 0.5
	var title: Label = get_node_or_null("TitleLabel") as Label
	if title != null:
		title.position = Vector2(-110.0, -half_h - 36.0)
		title.size = Vector2(220.0, 28.0)
	var level_label: Label = get_node_or_null("LevelLabel") as Label
	if level_label != null:
		level_label.position = Vector2(-70.0, half_h + 4.0)
		level_label.size = Vector2(140.0, 28.0)


func _sync_click_shape() -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	var click: Area2D = get_node_or_null("ClickArea") as Area2D
	if sprite == null or click == null:
		return
	var shape_node: CollisionShape2D = click.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		shape_node = CollisionShape2D.new()
		shape_node.name = "CollisionShape2D"
		click.add_child(shape_node)
	var rect := RectangleShape2D.new()
	if sprite.texture != null:
		rect.size = sprite.texture.get_size() * sprite.scale.abs()
	else:
		rect.size = Vector2(220, 220)
	# Pad so nameplate region remains tappable near the art.
	rect.size += Vector2(36, 80)
	shape_node.shape = rect
	shape_node.position = sprite.position + Vector2(0, -12)
	shape_node.disabled = false
	shape_node.visible = false
