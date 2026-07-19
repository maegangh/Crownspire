extends Control

const HERO_SKILLS_JSON_PATHS := [
	"res://Data/hero_skills.json",
	"res://data/hero_skills.json",
]

const PORTRAIT_KEYS := ["portraitPath", "portrait", "portrait_path"]
const HEROES_JSON_PATHS := [
	"res://data/heroes.json",
	"res://Data/heroes.json",
]

const RARITY_STAR_COUNTS := {
	"Common": 1,
	"Rare": 2,
	"Epic": 3,
	"Legendary": 4,
	"Mythic": 5,
}

static var _placeholder_texture: Texture2D
static var _cached_skills: Array = []

var portrait: TextureRect
var hero_name: Label
var role_label: Label
var rarity_label: Label
var level_label: Label
var power_label: Label
var skills_list: VBoxContainer
var close_button: Button

var _large_portrait: TextureRect


func _ready() -> void:
	_bind_panel_layout()
	visible = false

	if close_button and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
		return

	_bind_panel_layout()
	visible = false
	if close_button:
		close_button.pressed.connect(_on_close_pressed)


func _bind_panel_layout() -> void:
	portrait = get_node_or_null("LargePortrait") as TextureRect
	hero_name = get_node_or_null("HeroNameLabel") as Label
	role_label = get_node_or_null("HeroTitleLabel") as Label
	rarity_label = get_node_or_null("AscensionLabel") as Label
	level_label = get_node_or_null("LevelLabel") as Label
	power_label = get_node_or_null("PowerLabel") as Label
	close_button = get_node_or_null("BackButton") as Button

	skills_list = get_node_or_null("Pages/SkillsPage/Skills") as VBoxContainer

func show_hero_by_id(hero_id: String) -> void:
	var hero_data := _get_hero_template_by_id(hero_id)

	if hero_data.is_empty():
		push_error("HeroDetailsPanel: Hero not found: " + hero_id)
		return

	# Preserve the exact ID clicked.
	hero_data = hero_data.duplicate(true)
	hero_data["id"] = hero_id

	show_hero(hero_data)

func show_hero(hero_data: Dictionary) -> void:
	var hero_id := str(hero_data.get("id", ""))
	var view_data := build_hero_view_data(hero_id, hero_data)

	if hero_name:
		hero_name.text = str(view_data.get("name", "Unknown"))

	if role_label:
		role_label.text = str(view_data.get("role", "Unknown"))

	if rarity_label:
		rarity_label.text = str(view_data.get("rarity", "Unknown"))

	if level_label:
		var level := int(view_data.get("level", 1))
		var ascension := int(view_data.get("ascension", 0))
		level_label.text = "Level: %d  +%d" % [level, ascension]

	if power_label:
		power_label.text = "Power: %s" % str(_calculate_power(view_data))

	var portrait_path := _resolve_path(view_data, PORTRAIT_KEYS)
	if portrait_path.is_empty():
		portrait_path = _default_portrait_path(view_data)
	_set_texture(portrait, portrait_path)

	_populate_skills(hero_id)
	visible = true


func build_hero_view_data(hero_id: String, fallback: Dictionary = {}) -> Dictionary:
	var template := _get_hero_template_by_id(hero_id)
	if template.is_empty() and not fallback.is_empty():
		template = fallback.duplicate(true)

	if template.is_empty():
		return fallback.duplicate(true) if not fallback.is_empty() else {}

	var hero := template.duplicate(true)
	var progression := _get_hero_progression(hero_id)
	hero["level"] = progression["level"]
	hero["ascension"] = progression["ascension"]
	return hero


func _get_hero_template_by_id(hero_id: String) -> Dictionary:
	if hero_id.is_empty():
		return {}

	var wanted_id := hero_id.strip_edges().to_lower()

	for path in HEROES_JSON_PATHS:
		if not FileAccess.file_exists(path):
			continue

		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue

		var parsed = JSON.parse_string(file.get_as_text())

		if parsed is not Array:
			continue

		for hero_entry in parsed:
			if hero_entry is not Dictionary:
				continue

			var entry_id := str(hero_entry.get("id", "")).strip_edges().to_lower()

			if entry_id == wanted_id:
				var matched_hero: Dictionary = hero_entry.duplicate(true)

				print(
					"HeroDetails matched ID: ",
					matched_hero.get("id", ""),
					" | Name: ",
					matched_hero.get("name", "")
				)

				return matched_hero

	push_error("HeroDetailsPanel: No hero matched ID: " + hero_id)
	return {}

func _load_hero_templates() -> Array:
	var source = DataManager.get_all_heroes() if DataManager.has_method("get_all_heroes") else []
	if source is Array and not source.is_empty():
		return source

	for path in HEROES_JSON_PATHS:
		if not FileAccess.file_exists(path):
			continue

		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue

		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Array:
			return parsed

	return []


func _get_hero_progression(hero_id: String) -> Dictionary:
	var level := 1
	var ascension := 0

	if hero_id.is_empty():
		return {"level": level, "ascension": ascension}

	for recruited in HeroState.recruited_heroes:
		if str(recruited.get("id", "")) != hero_id:
			continue

		level = max(1, int(recruited.get("level", 1)))
		ascension = max(0, int(recruited.get("ascension", 0)))
		break

	return {"level": level, "ascension": ascension}


func get_rarity_star_count(rarity: String) -> int:
	if not RARITY_STAR_COUNTS.has(rarity):
		push_warning("HeroDetailsPanel: unknown rarity '%s' for star count." % rarity)
		return 0
	return int(RARITY_STAR_COUNTS[rarity])


func _on_close_pressed() -> void:
	visible = false


func _populate_skills(hero_id: String) -> void:
	if skills_list == null:
		return

	for child in skills_list.get_children():
		child.queue_free()

	if hero_id.is_empty():
		push_warning("HeroDetailsPanel: cannot load skills without hero id.")
		return

	var skills := _get_skills_for_hero(hero_id)
	if skills.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No skills listed."
		skills_list.add_child(empty_label)
		return

	for skill in skills:
		var skill_label := Label.new()
		var skill_name := str(skill.get("skillName", "Unknown Skill"))
		var skill_type := str(skill.get("skillType", ""))
		var description := str(skill.get("description", ""))
		skill_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		skill_label.text = "%s (%s)\n%s" % [skill_name, skill_type, description]
		skills_list.add_child(skill_label)


func _get_skills_for_hero(hero_id: String) -> Array:
	var all_skills := _load_hero_skills()
	var results: Array = []

	for skill in all_skills:
		if str(skill.get("heroId", "")) == hero_id:
			results.append(skill)

	return results


func _load_hero_skills() -> Array:
	if not _cached_skills.is_empty():
		return _cached_skills

	var json_text := _read_json_file(HERO_SKILLS_JSON_PATHS)
	if json_text.is_empty():
		return []

	var parsed = JSON.parse_string(json_text)
	if parsed == null:
		push_error("HeroDetailsPanel: failed to parse hero_skills.json.")
		return []

	if typeof(parsed) != TYPE_ARRAY:
		push_error("HeroDetailsPanel: hero_skills.json root must be an array.")
		return []

	_cached_skills = parsed
	return _cached_skills


func _calculate_power(hero_data: Dictionary) -> int:
	var stats := _calculate_stats(hero_data)
	return int(stats.get("power", 0))


func _calculate_stats(hero_data: Dictionary) -> Dictionary:
	var level := int(hero_data.get("level", 1))
	var ascension := int(hero_data.get("ascension", 0))
	var asc_key := "ascension%d" % ascension
	var asc_data: Dictionary = hero_data.get(asc_key, {})

	var level_factor := 1.0 + ((level - 1) * 0.25)
	var attack := int(
		float(hero_data.get("baseAttack", 0))
		* level_factor
		* float(asc_data.get("attackMultiplier", 1.0))
	)
	var defense := int(
		float(hero_data.get("baseDefense", 0))
		* level_factor
		* float(asc_data.get("defenseMultiplier", 1.0))
	)
	var health := int(
		float(hero_data.get("baseHealth", 0))
		* level_factor
		* float(asc_data.get("healthMultiplier", 1.0))
	)
	var leadership := int(
		float(hero_data.get("leadership", 0))
		* level_factor
		* float(asc_data.get("leadershipMultiplier", 1.0))
	)

	var power := int((attack + defense) * 12 + (health * 0.5) + leadership)
	return {
		"attack": attack,
		"defense": defense,
		"health": health,
		"leadership": leadership,
		"power": power,
	}


func _read_json_file(paths: Array) -> String:
	for path in paths:
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				push_error("HeroDetailsPanel: could not open '%s'." % path)
				continue
			return file.get_as_text()

	push_error("HeroDetailsPanel: hero_skills.json not found.")
	return ""


func _resolve_path(hero_data: Dictionary, keys: Array) -> String:
	for key in keys:
		if hero_data.has(key):
			return str(hero_data.get(key, ""))
	return ""


func _default_portrait_path(hero_data: Dictionary) -> String:
	var hero_name_value := str(hero_data.get("name", ""))
	if hero_name_value.is_empty():
		return ""
	return "res://Art/Heroes/%s/portrait.png" % hero_name_value


func _set_texture(target: TextureRect, path: String) -> void:
	if target == null:
		return

	if path.is_empty():
		target.texture = _get_placeholder_texture()
		return

	if not ResourceLoader.exists(path):
		push_warning("HeroDetailsPanel: texture not found at '%s'." % path)
		target.texture = _get_placeholder_texture()
		return

	var loaded := load(path)
	if loaded is Texture2D:
		target.texture = loaded
	else:
		push_warning("HeroDetailsPanel: resource at '%s' is not a Texture2D." % path)
		target.texture = _get_placeholder_texture()


func _get_placeholder_texture() -> Texture2D:
	if _placeholder_texture == null:
		var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
		image.fill(Color(0.22, 0.22, 0.28))
		_placeholder_texture = ImageTexture.create_from_image(image)
	return _placeholder_texture
