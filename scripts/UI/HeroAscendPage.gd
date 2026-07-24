extends Control

const PROGRESS_TEXTURES: Array[String] = [
	"res://assets/ui/hero_ascension/asc_progress_0.png",
	"res://assets/ui/hero_ascension/asc_progress_1.png",
	"res://assets/ui/hero_ascension/asc_progress_2.png",
	"res://assets/ui/hero_ascension/asc_progress_3.png",
	"res://assets/ui/hero_ascension/asc_progress_4.png",
	"res://assets/ui/hero_ascension/asc_progress_5.png",
]

const SHARD_ICON_PATH: String = "res://assets/ui/hero_ascension/hero_shard_icon.png"

var hero_data: Dictionary = {}

@onready var back_button: BaseButton = $BackButton
@onready var hero_portrait: TextureRect = $HeroPortrait
@onready var hero_name: Label = $HeroName
@onready var hero_title: Label = $HeroTitle
@onready var ascend_button: BaseButton = $AscendButton
@onready var progress_image: TextureRect = $StarProgress/ProgressImage
@onready var shard_icon: TextureRect = $ShardCounter/ShardIcon
@onready var shard_count_label: Label = $ShardCounter/ShardCountLabel
@onready var power_value_label: Label = $PowerValueLabel
@onready var stars_container: HBoxContainer = $Stars


func _ready() -> void:
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

	if ascend_button:
		ascend_button.pressed.connect(_on_ascend_pressed)


func setup(new_hero_data: Dictionary) -> void:
	hero_data = new_hero_data.duplicate(true)
	_refresh_from_state()


func _refresh_from_state() -> void:
	var hero_id: String = str(hero_data.get("id", ""))

	if hero_id.is_empty():
		return

	var progress: Dictionary = HeroState.get_hero_progress(hero_id)

	hero_data["level"] = int(progress.get("level", 1))
	hero_data["starLevel"] = int(progress.get("starLevel", 5))
	hero_data["starProgress"] = int(progress.get("starProgress", 0))

	refresh()


func refresh() -> void:
	var hero_id: String = str(hero_data.get("id", ""))
	var name: String = str(hero_data.get("name", "Hero"))
	var title: String = _get_short_title(hero_data)
	var level: int = int(hero_data.get("level", 1))
	var star_level: int = int(hero_data.get("starLevel", 5))
	var star_progress: int = int(hero_data.get("starProgress", 0))
	var shards: int = HeroState.get_hero_shards(hero_id)
	var cost: int = HeroState.get_star_upgrade_cost(star_level)

	if hero_name:
		hero_name.text = name

	if hero_title:
		hero_title.text = title

	if shard_count_label:
		shard_count_label.text = "%d / %d" % [shards, cost]

	if power_value_label:
		var stats: Dictionary = _calculate_stats(hero_data)
		power_value_label.text = _format_number(int(stats.get("power", 0)))

	_update_portrait()
	_update_shard_icon()
	_update_progress_image(star_progress)
	_update_stars(star_level)
	_update_rewards(level, star_level, star_progress)

	if ascend_button:
		ascend_button.disabled = shards < cost or star_level >= 12


func _update_portrait() -> void:
	if hero_portrait == null:
		return

	var path: String = _resolve_portrait_path(hero_data)

	if not path.is_empty() and ResourceLoader.exists(path):
		var loaded: Resource = load(path)
		if loaded is Texture2D:
			hero_portrait.texture = loaded


func _update_shard_icon() -> void:
	if shard_icon == null:
		return

	var path: String = _resolve_portrait_path(hero_data)

	if not path.is_empty() and ResourceLoader.exists(path):
		var loaded: Resource = load(path)
		if loaded is Texture2D:
			shard_icon.texture = loaded
			return

	if ResourceLoader.exists(SHARD_ICON_PATH):
		var fallback: Resource = load(SHARD_ICON_PATH)
		if fallback is Texture2D:
			shard_icon.texture = fallback

func _update_progress_image(star_progress: int) -> void:
	if progress_image == null:
		return

	var safe_progress: int = clamp(star_progress, 0, 5)
	var path: String = PROGRESS_TEXTURES[safe_progress]

	if ResourceLoader.exists(path):
		var loaded: Resource = load(path)
		if loaded is Texture2D:
			progress_image.texture = loaded


func _update_stars(star_level: int) -> void:
	if stars_container == null:
		return

	for child in stars_container.get_children():
		if child is CanvasItem:
			child.visible = false

	var stars_to_show: int = star_level
	var use_big_stars: bool = false

	if star_level >= 6:
		use_big_stars = true
		stars_to_show = star_level - 5

	for i in range(min(stars_to_show, stars_container.get_child_count())):
		var star: TextureRect = stars_container.get_child(i) as TextureRect

		if star == null:
			continue

		star.visible = true

		if use_big_stars:
			star.scale = Vector2(1.5, 1.5)
			star.modulate = Color(1, 1, 1, 1)
		else:
			star.scale = Vector2(1, 1)
			star.modulate = Color(1, 0.82, 0.25, 1)


func _update_rewards(level: int, star_level: int, star_progress: int) -> void:
	var next_progress: int = star_progress + 1
	var next_star_level: int = star_level

	if next_progress >= 5:
		next_progress = 0
		next_star_level += 1

	var current_cap: int = HeroState.get_level_cap(star_level)
	var next_cap: int = HeroState.get_level_cap(next_star_level)

	var current_multiplier: float = HeroState.get_star_power_multiplier(star_level, star_progress)
	var next_multiplier: float = HeroState.get_star_power_multiplier(next_star_level, next_progress)

	var base_attack: float = float(hero_data.get("baseAttack", 0))
	var base_defense: float = float(hero_data.get("baseDefense", 0))
	var base_health: float = float(hero_data.get("baseHealth", 0))
	var level_factor: float = 1.0 + (float(level - 1) * 0.25)

	var attack_gain: int = int((base_attack * level_factor * next_multiplier) - (base_attack * level_factor * current_multiplier))
	var defense_gain: int = int((base_defense * level_factor * next_multiplier) - (base_defense * level_factor * current_multiplier))
	var health_gain: int = int((base_health * level_factor * next_multiplier) - (base_health * level_factor * current_multiplier))

	_set_label_text("Rewards/AttackLabel", "+%d Attack" % max(1, attack_gain))
	_set_label_text("Rewards/DefenseLabel", "+%d Defense" % max(1, defense_gain))
	_set_label_text("Rewards/HealthLabel", "+%d Health" % max(1, health_gain))
	_set_label_text("Rewards/LevelCapLabel", "Level Cap %d → %d" % [current_cap, next_cap])


func _set_label_text(path: String, text: String) -> void:
	var label: Label = get_node_or_null(path) as Label
	if label:
		label.text = text


func _calculate_stats(data: Dictionary) -> Dictionary:
	var level: int = int(data.get("level", 1))
	var star_level: int = int(data.get("starLevel", 5))
	var star_progress: int = int(data.get("starProgress", 0))

	var level_factor: float = 1.0 + (float(level - 1) * 0.25)
	var star_multiplier: float = HeroState.get_star_power_multiplier(star_level, star_progress)

	var attack: int = int(float(data.get("baseAttack", 0)) * level_factor * star_multiplier)
	var defense: int = int(float(data.get("baseDefense", 0)) * level_factor * star_multiplier)
	var health: int = int(float(data.get("baseHealth", 0)) * level_factor * star_multiplier)
	var leadership: int = int(float(data.get("leadership", 0)) * level_factor * star_multiplier)

	var power: int = int((attack + defense) * 12 + (health * 0.5) + leadership)

	return {
		"attack": attack,
		"defense": defense,
		"health": health,
		"leadership": leadership,
		"power": power,
	}


func _resolve_portrait_path(data: Dictionary) -> String:
	var hero_name_value: String = str(data.get("name", ""))
	if hero_name_value.is_empty():
		return ""

	var portrait_path: String = "res://Art/Heroes/%s/portrait.png" % hero_name_value

	if ResourceLoader.exists(portrait_path):
		return portrait_path

	return ""

func _get_short_title(data: Dictionary) -> String:
	if data.has("title"):
		var title: String = str(data.get("title", "")).strip_edges()
		if not title.is_empty():
			return title

	var lore: String = str(data.get("lore", "")).strip_edges()

	if lore.contains(","):
		return lore.split(",")[0]

	if lore.length() > 28:
		return str(data.get("role", ""))

	return lore


func _format_number(value: int) -> String:
	var text: String = str(value)

	if text.length() <= 3:
		return text

	var parts: PackedStringArray = []

	while text.length() > 3:
		parts.insert(0, text.substr(text.length() - 3, 3))
		text = text.substr(0, text.length() - 3)

	if not text.is_empty():
		parts.insert(0, text)

	return ",".join(parts)


func _on_ascend_pressed() -> void:
	var hero_id: String = str(hero_data.get("id", ""))

	if hero_id.is_empty():
		return

	var success: bool = HeroState.ascend_hero(hero_id)

	if success:
		_refresh_from_state()


func _on_back_pressed() -> void:
	visible = false

	var parent_node: Node = get_parent()

	if parent_node != null and parent_node.has_method("_set_main_details_visible"):
		parent_node.call("_set_main_details_visible", true)

	if parent_node != null and parent_node.has_method("_display_hero_at_index"):
		var hero_index: int = int(parent_node.get("_hero_index"))
		parent_node.call("_display_hero_at_index", hero_index)
