extends Node2D

## Alliance Lair world marker (Phase 5.4).
## Selectable on desktop/mobile via WorldGesture click area.
## Rally indicators driven by RallyBackend; HP/active by AllianceLairState.

const WildlingLairDatabase = preload("res://scripts/World/WildlingLairDatabase.gd")
const GROUP_NAME := "wildling_lairs"

@export var lair_id: String = ""
@export var lair_level: int = 1
@export var recommended_power: int = 0
@export var species: String = ""
@export var visual_variant: String = "beast"
@export var display_name: String = "Alliance Lair"
@export var creature_title: String = ""
@export var max_hp: int = 5000
@export var current_hp: int = 5000
@export var difficulty: String = "Normal"
@export var rally_required: bool = true
@export var active: bool = true

var _level_def: Dictionary = {}
var _rally_banner: Label = null
var _rally_countdown: Label = null
var _rally_meta: Label = null
var _hp_label: Label = null
var _inactive_label: Label = null
var _rally_launched: bool = false


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group("world_blockers")
	add_to_group("alliance_lairs")
	z_index = 110
	_apply_labels()
	if has_node("/root/AllianceLairState") and not AllianceLairState.lairs_changed.is_connected(_on_lairs_changed):
		AllianceLairState.lairs_changed.connect(_on_lairs_changed)


func setup_from_def(def: Dictionary, stable_id: String) -> void:
	_level_def = def.duplicate(true)
	lair_id = stable_id
	lair_level = int(def.get("level", 1))
	recommended_power = int(def.get("recommended_power", 0))
	species = str(def.get("species", "")).strip_edges().to_lower()
	visual_variant = str(def.get("visual_variant", "")).strip_edges().to_lower()
	if visual_variant.is_empty():
		visual_variant = WildlingLairDatabase.visual_variant_for_species(species)
	display_name = str(def.get("display_name", "Alliance Lair"))
	creature_title = WildlingLairDatabase.creature_title(def)
	max_hp = int(def.get("max_hp", 5000))
	current_hp = max_hp
	difficulty = str(def.get("difficulty", "Normal"))
	rally_required = bool(def.get("rally_required", true))
	active = true
	name = "AllianceLair_%s" % lair_id
	z_index = 110

	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		var tex: Texture2D = WildlingLairDatabase.get_texture_for_level_def(def)
		sprite.texture = tex
		sprite.modulate = Color.WHITE
		sprite.centered = true
		sprite.position = Vector2.ZERO
		
		# Keep Alliance Lairs proportional to castles and other world objects.
		var lair_scale: float = WildlingLairDatabase.WORLD_SPRITE_SCALE * 0.55
		sprite.scale = Vector2(lair_scale, lair_scale)
		

	var ring: Node = get_node_or_null("DenRing")
	if ring != null:
		ring.queue_free()
	var old_ring: Node = get_node_or_null("LairRing")
	if old_ring != null:
		old_ring.queue_free()

	_sync_click_exports()
	_apply_labels()
	_place_nameplates()
	_sync_click_shape()
	_ensure_hp_labels()
	_refresh_active_visual()


func apply_runtime_state(inst: Dictionary) -> void:
	if inst.is_empty():
		return
	active = bool(inst.get("active", true))
	max_hp = int(inst.get("max_hp", max_hp))
	current_hp = int(inst.get("current_hp", current_hp if active else 0))
	difficulty = str(inst.get("difficulty", difficulty))
	rally_required = bool(inst.get("rally_required", rally_required))
	recommended_power = int(inst.get("recommended_power", recommended_power))
	_refresh_active_visual()
	_apply_labels()


func get_level_def() -> Dictionary:
	if not _level_def.is_empty():
		return _level_def.duplicate(true)
	return WildlingLairDatabase.get_level_def(lair_level)


func get_search_position() -> Vector2:
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		return to_global(sprite.position)
	return global_position


func set_rally_indicator(active_rally: bool, remaining_sec: int, participant_count: int, joined: bool, launched: bool = false) -> void:
	_ensure_rally_labels()
	if _rally_banner == null:
		return
	_rally_launched = launched
	_rally_banner.visible = active_rally
	_rally_countdown.visible = active_rally
	_rally_meta.visible = active_rally
	if not active_rally:
		return
	_rally_banner.text = "⚔ RALLY"
	_rally_banner.add_theme_color_override("font_color", Color(0.92, 0.76, 0.28, 1.0))
	if launched or remaining_sec <= 0:
		_rally_countdown.text = "LAUNCHED"
		_rally_countdown.add_theme_color_override("font_color", Color(0.30, 0.72, 0.45, 1.0))
	else:
		_rally_countdown.text = "%02d:%02d" % [int(remaining_sec / 60), remaining_sec % 60]
		_rally_countdown.add_theme_color_override("font_color", Color(0.35, 0.55, 0.90, 1.0))
	var joined_mark: String = " ✓" if joined else ""
	_rally_meta.text = "%d joined%s" % [participant_count, joined_mark]
	_rally_meta.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95, 1.0) if joined else Color(0.75, 0.72, 0.68, 1.0))
	_place_rally_labels()


func _on_lairs_changed() -> void:
	if has_node("/root/AllianceLairState") and lair_id != "":
		apply_runtime_state(AllianceLairState.get_lair(lair_id))


func _sync_click_exports() -> void:
	var click: Node = get_node_or_null("ClickArea")
	if click == null:
		return
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
		(click as Area2D).input_pickable = active
		(click as Area2D).monitoring = true


func _apply_labels() -> void:
	var title: Label = get_node_or_null("TitleLabel") as Label
	if title != null:
		title.text = "ALLIANCE LAIR"
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var level_label: Label = get_node_or_null("LevelLabel") as Label
	if level_label != null:
		level_label.text = "Lv.%d" % lair_level
		level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_hp_labels()
	if _hp_label != null:
		if active:
			_hp_label.text = "HP %s / %s" % [
				WildlingLairDatabase.format_power(current_hp),
				WildlingLairDatabase.format_power(max_hp),
			]
			_hp_label.visible = true
		else:
			_hp_label.visible = false
	if _inactive_label != null:
		_inactive_label.visible = not active
		if not active:
			var remain := 0
			if has_node("/root/AllianceLairState"):
				var inst: Dictionary = AllianceLairState.get_lair(lair_id)
				remain = maxi(0, int(inst.get("respawn_at", 0)) - int(Time.get_unix_time_from_system()))
			_inactive_label.text = "DEFEATED" if remain <= 0 else "RESPAWN %02d:%02d" % [int(remain / 60), remain % 60]


func _refresh_active_visual() -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.modulate = Color(0.55, 0.55, 0.58, 0.72) if not active else Color.WHITE
	_sync_click_exports()
	visible = true


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
	_place_hp_labels(half_h)
	_place_rally_labels()


func _ensure_hp_labels() -> void:
	if _hp_label != null and is_instance_valid(_hp_label):
		return
	_hp_label = Label.new()
	_hp_label.name = "HpLabel"
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 13)
	_hp_label.add_theme_color_override("font_color", Color(0.55, 0.82, 0.95, 1.0))
	_hp_label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02, 1.0))
	_hp_label.add_theme_constant_override("outline_size", 4)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_label)
	_inactive_label = Label.new()
	_inactive_label.name = "InactiveLabel"
	_inactive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inactive_label.add_theme_font_size_override("font_size", 14)
	_inactive_label.add_theme_color_override("font_color", Color(0.95, 0.45, 0.40, 1.0))
	_inactive_label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02, 1.0))
	_inactive_label.add_theme_constant_override("outline_size", 4)
	_inactive_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inactive_label.visible = false
	add_child(_inactive_label)


func _place_hp_labels(half_h: float) -> void:
	if _hp_label != null:
		_hp_label.position = Vector2(-90.0, half_h + 28.0)
		_hp_label.size = Vector2(180.0, 22.0)
	if _inactive_label != null:
		_inactive_label.position = Vector2(-90.0, -half_h - 58.0)
		_inactive_label.size = Vector2(180.0, 24.0)


func _ensure_rally_labels() -> void:
	if _rally_banner != null and is_instance_valid(_rally_banner):
		return
	_rally_banner = Label.new()
	_rally_banner.name = "RallyBanner"
	_rally_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rally_banner.add_theme_font_size_override("font_size", 18)
	_rally_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rally_banner.visible = false
	add_child(_rally_banner)
	_rally_countdown = Label.new()
	_rally_countdown.name = "RallyCountdown"
	_rally_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rally_countdown.add_theme_font_size_override("font_size", 22)
	_rally_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rally_countdown.visible = false
	add_child(_rally_countdown)
	_rally_meta = Label.new()
	_rally_meta.name = "RallyMeta"
	_rally_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rally_meta.add_theme_font_size_override("font_size", 14)
	_rally_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rally_meta.visible = false
	add_child(_rally_meta)


func _place_rally_labels() -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	var half_h: float = 160.0
	if sprite != null and sprite.texture != null:
		half_h = (sprite.texture.get_size().y * sprite.scale.y) * 0.5
	if _rally_banner != null:
		_rally_banner.position = Vector2(-90.0, -half_h - 92.0)
		_rally_banner.size = Vector2(180.0, 24.0)
	if _rally_countdown != null:
		_rally_countdown.position = Vector2(-70.0, -half_h - 70.0)
		_rally_countdown.size = Vector2(140.0, 28.0)
	if _rally_meta != null:
		_rally_meta.position = Vector2(-80.0, -half_h - 46.0)
		_rally_meta.size = Vector2(160.0, 22.0)


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
	rect.size += Vector2(36, 80)
	shape_node.shape = rect
	shape_node.position = sprite.position + Vector2(0, -12)
	shape_node.disabled = false
	shape_node.visible = false
