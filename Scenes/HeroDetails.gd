extends "res://Scenes/UI/HeroDetailsPanel.gd"

enum Tab {
	OVERVIEW,
	STATS,
	SKILLS,
	GEAR,
	TROOP_SKILLS,
}

const HEROES_JSON_PATH := "res://data/heroes.json"
const PORTRAIT_KEYS_FULL := ["fullbodyPath", "fullbody", "portraitPath", "portrait", "portrait_path"]

const RARITY_TEXTURES := {
	"Mythic": "res://images/HeroCard/mythic43.png",
	"Legendary": "res://images/HeroCard/Legendary.png",
	"Epic": "res://images/HeroCard/Epic.png",
	"Rare": "res://images/HeroCard/Rare.png",
	"Common": "res://images/HeroCard/Common.png",
}

const TROOP_TEXTURES := {
	"infantry": "res://assets/Buttons/infantry.png",
	"marksmen": "res://assets/Buttons/marksman.png",
	"cavalry": "res://assets/Buttons/cavalry.png",
}

var _hero_roster: Array = []
var _hero_index: int = 0
var _current_tab: Tab = Tab.OVERVIEW
var _ascend_page: Control

@onready var _rarity_badge: TextureRect = $Mythic
@onready var _role_icon: TextureRect = $RoleIcon

var _hero_name_label: Label
var _hero_title_label: Label
var _power_value_label: Label
var _stars_container: HBoxContainer
var _hero_xp_label: Label

var _left_arrow: TextureButton
var _right_arrow: TextureButton
var _overview_button: TextureButton
var _stats_button: TextureButton
var _skills_button: TextureButton
var _gear_button: TextureButton
var _troop_skills_button: TextureButton

var _overview_page: Control
var _stats_page: Control
var _skills_page: Control
var _gear_page: Control
var _troop_skill_page: Control

var _overview_list: VBoxContainer
var _stats_list: VBoxContainer
var _skills_page_list: VBoxContainer
var _gear_list: VBoxContainer
var _troop_skills_list: VBoxContainer

var _back_button: BaseButton
var _level_up_button: TextureButton
var _ascend_button: TextureButton


func _ready() -> void:
	_configure_input_handling()
	_bind_full_details_layout()
	_load_hero_roster()

	# TEMP TESTING ONLY. Remove later.
	HeroState.add_hero_shards("maegan", 5000)

	_build_tab_page_content()
	_configure_tab_page_input()
	_connect_full_details_signals()

	if _hero_roster.is_empty():
		push_warning("HeroDetails: no heroes loaded from heroes.json.")
		return

	if _ascend_page:
		_ascend_page.visible = false

	_show_tab(Tab.OVERVIEW)
	visible = false


func _configure_input_handling() -> void:
	if size.x < 100.0 or size.y < 100.0:
		size = Vector2(720, 1280)

	mouse_filter = Control.MOUSE_FILTER_PASS

	for node_name in [
		"Background",
		"LargePortrait",
		"RoleIcon",
		"Mythic",
		"HeroNameLabel",
		"HeroTitleLabel",
		"PowerLabel",
		"Label",
		"LevelLabel",
		"HeroXPLabel",
	]:
		_set_mouse_filter_ignore(get_node_or_null(node_name))

	var tab_buttons: Control = get_node_or_null("TabButtons") as Control
	if tab_buttons:
		tab_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab_buttons.z_index = 20

	for node_name in [
		"TabButtons/StatsButton",
		"TabButtons/SkillsButton",
		"TabButtons/GearButton",
		"TabButtons/TroopSkillButton",
		"TabButtons/OverviewButton",
		"LeftHeroArrow",
		"RightHeroArrow",
		"LevelUpButton",
		"AscendButton",
		"BackButton",
	]:
		var item: Control = get_node_or_null(node_name) as Control
		if item:
			item.mouse_filter = Control.MOUSE_FILTER_STOP
			item.z_index = 20


func _configure_tab_page_input() -> void:
	for page in [_overview_page, _stats_page, _skills_page, _gear_page, _troop_skill_page]:
		if page == null:
			continue
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.z_index = 0
		for child in page.get_children():
			_set_mouse_filter_ignore(child)


func _set_mouse_filter_ignore(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in node.get_children():
			if child is Control:
				_set_mouse_filter_ignore(child)


func _bind_full_details_layout() -> void:
	_back_button = get_node_or_null("BackButton") as BaseButton
	_level_up_button = get_node_or_null("LevelUpButton") as TextureButton
	_ascend_button = get_node_or_null("AscendButton") as TextureButton

	_large_portrait = get_node_or_null("LargePortrait") as TextureRect
	_hero_name_label = get_node_or_null("HeroNameLabel") as Label
	_hero_title_label = get_node_or_null("HeroTitleLabel") as Label
	power_label = get_node_or_null("PowerLabel") as Label
	_power_value_label = get_node_or_null("Label") as Label
	level_label = get_node_or_null("LevelLabel") as Label
	_hero_xp_label = get_node_or_null("HeroXPLabel") as Label
	_stars_container = get_node_or_null("Stars") as HBoxContainer

	_left_arrow = get_node_or_null("LeftHeroArrow") as TextureButton
	_right_arrow = get_node_or_null("RightHeroArrow") as TextureButton

	_ascend_page = get_node_or_null("HeroAscendPage") as Control

	var tab_buttons: Node = get_node_or_null("TabButtons")
	if tab_buttons:
		_overview_button = tab_buttons.get_node_or_null("OverviewButton") as TextureButton
		_stats_button = tab_buttons.get_node_or_null("StatsButton") as TextureButton
		_skills_button = tab_buttons.get_node_or_null("SkillsButton") as TextureButton
		_gear_button = tab_buttons.get_node_or_null("GearButton") as TextureButton
		_troop_skills_button = tab_buttons.get_node_or_null("TroopSkillButton") as TextureButton

	_overview_page = get_node_or_null("Pages/OverviewPage") as Control
	_stats_page = get_node_or_null("Pages/StatsPage") as Control
	_skills_page = get_node_or_null("Pages/SkillsPage") as Control
	_gear_page = get_node_or_null("Pages/GearPage") as Control
	_troop_skill_page = get_node_or_null("Pages/TroopSkillsPage") as Control


func _connect_full_details_signals() -> void:
	if _back_button:
		_back_button.pressed.connect(_on_back_pressed)
	if _level_up_button:
		_level_up_button.pressed.connect(_on_level_up_pressed)
	if _ascend_button:
		_ascend_button.pressed.connect(_on_ascend_pressed)
	if _left_arrow:
		_left_arrow.pressed.connect(_on_left_hero_arrow_pressed)
	if _right_arrow:
		_right_arrow.pressed.connect(_on_right_hero_arrow_pressed)
	if _overview_button:
		_overview_button.pressed.connect(_on_overview_tab_pressed)
	if _stats_button:
		_stats_button.pressed.connect(_on_stats_tab_pressed)
	if _skills_button:
		_skills_button.pressed.connect(_on_skills_tab_pressed)
	if _gear_button:
		_gear_button.pressed.connect(_on_gear_tab_pressed)
	if _troop_skills_button:
		_troop_skills_button.pressed.connect(_on_troop_skills_tab_pressed)


func _build_tab_page_content() -> void:
	_overview_list = _ensure_page_list(_overview_page, "OverviewList")
	_stats_list = _ensure_page_list(_stats_page, "StatsList")
	_skills_page_list = _ensure_page_list(_skills_page, "SkillsList")
	_gear_list = _ensure_page_list(_gear_page, "GearList")
	_troop_skills_list = _ensure_page_list(_troop_skill_page, "TroopSkillsList")


func _ensure_page_list(page: Control, list_name: String) -> VBoxContainer:
	if page == null:
		return null

	var existing: VBoxContainer = page.get_node_or_null(list_name) as VBoxContainer
	if existing:
		return existing

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "%sScroll" % list_name
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(scroll)

	var list: VBoxContainer = VBoxContainer.new()
	list.name = list_name
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(list)

	return list


func _load_hero_roster() -> void:
	for path in [HEROES_JSON_PATH, "res://Data/heroes.json"]:
		if not FileAccess.file_exists(path):
			continue

		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue

		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Array:
			_hero_roster = parsed
			return

	push_error("HeroDetails: heroes.json not found or invalid.")


func _on_left_hero_arrow_pressed() -> void:
	if _hero_roster.is_empty():
		return

	_hero_index = (_hero_index - 1 + _hero_roster.size()) % _hero_roster.size()
	_display_hero_at_index(_hero_index)


func _on_right_hero_arrow_pressed() -> void:
	if _hero_roster.is_empty():
		return

	_hero_index = (_hero_index + 1) % _hero_roster.size()
	_display_hero_at_index(_hero_index)


func _on_overview_tab_pressed() -> void:
	_show_tab(Tab.OVERVIEW)


func _on_stats_tab_pressed() -> void:
	_show_tab(Tab.STATS)


func _on_skills_tab_pressed() -> void:
	_show_tab(Tab.SKILLS)


func _on_gear_tab_pressed() -> void:
	_show_tab(Tab.GEAR)


func _on_troop_skills_tab_pressed() -> void:
	_show_tab(Tab.TROOP_SKILLS)


func _show_tab(tab: Tab) -> void:
	_current_tab = tab

	if _overview_page:
		_overview_page.visible = false
	if _stats_page:
		_stats_page.visible = false
	if _skills_page:
		_skills_page.visible = false
	if _gear_page:
		_gear_page.visible = false
	if _troop_skill_page:
		_troop_skill_page.visible = false

	match tab:
		Tab.OVERVIEW:
			if _overview_page:
				_overview_page.visible = true
		Tab.STATS:
			if _stats_page:
				_stats_page.visible = true
		Tab.SKILLS:
			if _skills_page:
				_skills_page.visible = true
		Tab.GEAR:
			if _gear_page:
				_gear_page.visible = true
		Tab.TROOP_SKILLS:
			if _troop_skill_page:
				_troop_skill_page.visible = true

func show_hero_by_id(hero_id: String) -> void:
	if hero_id.is_empty():
		push_error("HeroDetails: Cannot display an empty hero ID.")
		return

	var wanted_id := hero_id.strip_edges().to_lower()

	for index in range(_hero_roster.size()):
		var roster_entry = _hero_roster[index]

		if roster_entry is not Dictionary:
			continue

		var entry_id := str(roster_entry.get("id", "")).strip_edges().to_lower()

		if entry_id == wanted_id:
			_hero_index = index
			_show_tab(Tab.OVERVIEW)
			_display_hero_at_index(index)
			visible = true

			print(
				"HeroDetails displaying ID: ",
				entry_id,
				" | Index: ",
				index
			)
			return

	push_error("HeroDetails: Hero ID not found in roster: " + hero_id)
	
func _display_hero_at_index(index: int) -> void:
	if index < 0 or index >= _hero_roster.size():
		return

	_hero_index = index

	var roster_entry: Dictionary = _hero_roster[index]
	var hero_id: String = str(roster_entry.get("id", ""))
	var hero_data: Dictionary = build_hero_view_data(hero_id, roster_entry)

	if hero_data.is_empty():
		return

	var progress: Dictionary = HeroState.get_or_create_hero(hero_id)
	hero_data["level"] = int(progress.get("level", 1))
	hero_data["starLevel"] = int(progress.get("starLevel", 5))
	hero_data["starProgress"] = int(progress.get("starProgress", 0))

	_refresh_header(hero_data)
	_refresh_tab_content(hero_data)


func _refresh_header(hero_data: Dictionary) -> void:
	var hero_id: String = str(hero_data.get("id", ""))
	var fields: Dictionary = _get_hero_json_fields(hero_id, hero_data)

	var display_name: String = str(fields.get("name", "Unknown"))
	var role: String = str(fields.get("role", "Unknown"))
	var rarity: String = str(fields.get("rarity", ""))
	var troop_type: String = str(fields.get("troopType", ""))

	var level: int = int(hero_data.get("level", 1))
	var star_level: int = int(hero_data.get("starLevel", get_rarity_star_count(rarity)))
	var max_level: int = HeroState.get_level_cap(star_level)

	var stats: Dictionary = _calculate_stats(hero_data)
	var power: int = int(stats.get("power", 0))

	if _hero_xp_label:
		_hero_xp_label.text = "Hero XP: %d" % HeroState.get_hero_xp()

	if _hero_name_label:
		_hero_name_label.text = display_name

	if _hero_title_label:
		_hero_title_label.text = _get_short_title(hero_data, role)

	if level_label:
		if level >= max_level:
			level_label.text = "Lv. %d MAX" % level
		else:
			level_label.text = "Lv. %d" % level

	if power_label:
		power_label.text = "Power:"

	if _power_value_label:
		_power_value_label.text = _format_number(power)

	_set_texture(_large_portrait, _resolve_portrait_path(hero_data))
	_set_rarity_badge(rarity, _resolve_rarity_texture_path(rarity))
	_set_troop_icon(_resolve_troop_texture_path(troop_type))
	_update_stars(star_level)

	if hero_name:
		hero_name.text = display_name
	if role_label:
		role_label.text = "Role: %s" % role
	if rarity_label:
		rarity_label.text = "Rarity: %s" % rarity
	if portrait:
		_set_texture(portrait, _resolve_portrait_path(hero_data, true))


func _refresh_tab_content(hero_data: Dictionary) -> void:
	var hero_id: String = str(hero_data.get("id", ""))

	_populate_overview_page(hero_data)
	_populate_stats_page(hero_data)
	_populate_skills_page(hero_id)
	_populate_gear_page(hero_id)
	_populate_troop_skills_page(hero_data, hero_id)


func _populate_overview_page(hero_data: Dictionary) -> void:
	_clear_list(_overview_list)

	if _overview_list == null:
		return

	var rarity: String = str(hero_data.get("rarity", "Unknown"))
	var troop: String = str(hero_data.get("troopType", "none"))
	var role: String = str(hero_data.get("role", "Unknown"))
	var level: int = int(hero_data.get("level", 1))
	var star_level: int = int(hero_data.get("starLevel", get_rarity_star_count(rarity)))
	var max_level: int = HeroState.get_level_cap(star_level)
	var star_progress: int = int(hero_data.get("starProgress", 0))

	_add_info_label(_overview_list, "Role: %s" % role)
	_add_info_label(_overview_list, "Rarity: %s" % rarity)
	_add_info_label(_overview_list, "Troop: %s" % troop)
	_add_info_label(_overview_list, "Level: %d / %d" % [level, max_level])
	_add_info_label(_overview_list, "Star Progress: %d / 5" % star_progress)

	var active_skills: Array = hero_data.get("activeSkills", [])
	if active_skills.is_empty():
		_add_info_label(_overview_list, "Signature Skill: None")
	else:
		var ability: Dictionary = active_skills[0]
		_add_info_label(_overview_list, "Signature Skill: %s" % str(ability.get("name", "None")))


func _populate_stats_page(hero_data: Dictionary) -> void:
	_clear_list(_stats_list)

	if _stats_list == null:
		return

	var stats: Dictionary = _calculate_stats(hero_data)

	_add_info_label(_stats_list, "Attack: %d" % int(stats.get("attack", 0)))
	_add_info_label(_stats_list, "Defense: %d" % int(stats.get("defense", 0)))
	_add_info_label(_stats_list, "Health: %d" % int(stats.get("health", 0)))
	_add_info_label(_stats_list, "Leadership: %d" % int(stats.get("leadership", 0)))
	_add_info_label(_stats_list, "Power: %s" % _format_number(int(stats.get("power", 0))))


func _populate_skills_page(hero_id: String) -> void:
	_clear_list(_skills_page_list)

	if _skills_page_list == null:
		return

	var skills: Array = _get_skills_for_hero(hero_id)

	if skills.is_empty():
		_add_info_label(_skills_page_list, "No skills listed.")
		return

	for skill in skills:
		var skill_name: String = str(skill.get("skillName", "Unknown Skill"))
		var skill_type: String = str(skill.get("skillType", ""))
		var description: String = str(skill.get("description", ""))

		_add_info_label(_skills_page_list, "%s (%s)" % [skill_name, skill_type], true)
		_add_info_label(_skills_page_list, description, true)


func _populate_gear_page(hero_id: String) -> void:
	_clear_list(_gear_list)

	if _gear_list == null:
		return

	_add_info_label(_gear_list, "Gear slots are not loaded yet.")
	_add_info_label(_gear_list, "Hero ID: %s" % hero_id)


func _populate_troop_skills_page(hero_data: Dictionary, hero_id: String) -> void:
	_clear_list(_troop_skills_list)

	if _troop_skills_list == null:
		return

	var passives: Array = hero_data.get("passiveBonuses", [])

	if passives.is_empty():
		_add_info_label(_troop_skills_list, "No troop passive bonuses listed.")
	else:
		for bonus in passives:
			if bonus is Dictionary:
				_add_info_label(
					_troop_skills_list,
					"%s: +%.0f%%" % [
						str(bonus.get("stat", "Bonus")),
						float(bonus.get("value", 0.0)) * 100.0,
					]
				)


func _calculate_stats(hero_data: Dictionary) -> Dictionary:
	var level: int = int(hero_data.get("level", 1))
	var star_level: int = int(hero_data.get("starLevel", 5))
	var star_progress: int = int(hero_data.get("starProgress", 0))

	var level_factor: float = 1.0 + (float(level - 1) * 0.25)
	var star_multiplier: float = HeroState.get_star_power_multiplier(star_level, star_progress)

	var attack: int = int(float(hero_data.get("baseAttack", 0)) * level_factor * star_multiplier)
	var defense: int = int(float(hero_data.get("baseDefense", 0)) * level_factor * star_multiplier)
	var health: int = int(float(hero_data.get("baseHealth", 0)) * level_factor * star_multiplier)
	var leadership: int = int(float(hero_data.get("leadership", 0)) * level_factor * star_multiplier)

	var power: int = int((attack + defense) * 12 + (health * 0.5) + leadership)

	return {
		"attack": attack,
		"defense": defense,
		"health": health,
		"leadership": leadership,
		"power": power,
	}


func _resolve_portrait_path(hero_data: Dictionary, prefer_portrait: bool = false) -> String:
	var keys: Array = PORTRAIT_KEYS if prefer_portrait else PORTRAIT_KEYS_FULL
	var resolved: String = _resolve_path(hero_data, keys)

	if not resolved.is_empty():
		return resolved

	var hero_name_value: String = str(hero_data.get("name", ""))
	if hero_name_value.is_empty():
		return ""

	var portrait_path: String = "res://Art/Heroes/%s/portrait.png" % hero_name_value
	var fullbody_path: String = "res://Art/Heroes/%s/fullbody.png" % hero_name_value

	if prefer_portrait:
		return portrait_path

	if ResourceLoader.exists(fullbody_path):
		return fullbody_path

	if ResourceLoader.exists(portrait_path):
		return portrait_path

	return fullbody_path


func _get_hero_json_fields(hero_id: String, fallback: Dictionary) -> Dictionary:
	var template: Dictionary = _get_hero_template_by_id(hero_id)

	if template.is_empty():
		template = fallback

	return {
		"id": str(template.get("id", hero_id)),
		"name": str(template.get("name", "Unknown")),
		"rarity": str(template.get("rarity", "")).strip_edges(),
		"troopType": str(template.get("troopType", "")).strip_edges(),
		"role": str(template.get("role", "")).strip_edges(),
	}


func _get_short_title(hero_data: Dictionary, fallback: String) -> String:
	if hero_data.has("title"):
		var title: String = str(hero_data.get("title", "")).strip_edges()
		if not title.is_empty():
			return title

	var lore: String = str(hero_data.get("lore", "")).strip_edges()

	if lore.contains(","):
		return lore.split(",")[0]

	if lore.length() > 28:
		return fallback

	return lore if not lore.is_empty() else fallback


func _clear_icon_rect(icon: TextureRect) -> void:
	if icon == null:
		return

	icon.texture = null
	icon.visible = false
	icon.modulate = Color(1, 1, 1, 1)


func _apply_icon_texture(icon: TextureRect, texture_path: String) -> bool:
	if icon == null:
		return false

	if texture_path.is_empty():
		return false

	if not ResourceLoader.exists(texture_path):
		return false

	var loaded: Resource = load(texture_path)

	if loaded is Texture2D:
		icon.texture = loaded
		icon.visible = true
		icon.modulate = Color(1, 1, 1, 1)
		return true

	return false


func _resolve_rarity_texture_path(rarity: String) -> String:
	var normalized: String = rarity.strip_edges()

	if normalized.is_empty():
		return ""

	if not RARITY_TEXTURES.has(normalized):
		return ""

	return RARITY_TEXTURES[normalized]


func _resolve_troop_texture_path(troop_type: String) -> String:
	var normalized: String = troop_type.to_lower().strip_edges()

	if normalized.is_empty() or normalized in ["none", "support"]:
		return ""

	if TROOP_TEXTURES.has(normalized):
		return TROOP_TEXTURES[normalized]

	if normalized == "marksman" and TROOP_TEXTURES.has("marksmen"):
		return TROOP_TEXTURES["marksmen"]

	return ""


func _set_troop_icon(texture_path: String) -> void:
	_clear_icon_rect(_role_icon)

	if texture_path.is_empty():
		return

	_apply_icon_texture(_role_icon, texture_path)


func _set_rarity_badge(_rarity: String, texture_path: String) -> void:
	_clear_icon_rect(_rarity_badge)

	if texture_path.is_empty():
		return

	_apply_icon_texture(_rarity_badge, texture_path)


func _update_stars(star_level: int) -> void:
	if _stars_container == null:
		return

	for child in _stars_container.get_children():
		child.visible = false

	var stars_to_show: int = star_level
	var use_big_stars: bool = false

	if star_level >= 6:
		use_big_stars = true
		stars_to_show = star_level - 5

	for i in range(min(stars_to_show, _stars_container.get_child_count())):
		var star: TextureRect = _stars_container.get_child(i) as TextureRect

		if star == null:
			continue

		star.visible = true

		if use_big_stars:
			star.scale = Vector2(1.5, 1.5)
			star.modulate = Color(1, 1, 1, 1)
		else:
			star.scale = Vector2(1, 1)
			star.modulate = Color(1, 0.82, 0.25, 1)


func _clear_list(list: VBoxContainer) -> void:
	if list == null:
		return

	for child in list.get_children():
		child.queue_free()


func _add_info_label(list: VBoxContainer, text: String, autowrap: bool = false) -> void:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if autowrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	list.add_child(label)


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


func _set_main_details_visible(is_visible: bool) -> void:
	for path in [
		"BackButton",
		"Pages",
		"TabButtons",
		"LevelUpButton",
		"AscendButton",
		"LeftHeroArrow",
		"RightHeroArrow",
	]:
		var node: CanvasItem = get_node_or_null(path) as CanvasItem
		if node:
			node.visible = is_visible

	if _ascend_page:
		_ascend_page.visible = not is_visible
		_ascend_page.mouse_filter = Control.MOUSE_FILTER_STOP if not is_visible else Control.MOUSE_FILTER_IGNORE

func _on_back_pressed() -> void:
	print("Back pressed")
	visible = false


func _on_level_up_pressed() -> void:
	if _hero_roster.is_empty():
		return

	var hero_data: Dictionary = _hero_roster[_hero_index]
	var hero_id: String = str(hero_data.get("id", ""))

	if hero_id.is_empty():
		return

	var success: bool = HeroState.level_up_hero(hero_id)

	if success:
		print(hero_id, " leveled up")
	else:
		print(hero_id, " did not level up")

	_display_hero_at_index(_hero_index)


func _on_ascend_pressed() -> void:
	if _hero_roster.is_empty():
		return

	if _ascend_page == null:
		print("ERROR: HeroAscendPage not found.")
		return

	if not _ascend_page.has_method("setup"):
		print("ERROR: HeroAscendPage has no setup() method.")
		return

	var roster_entry: Dictionary = _hero_roster[_hero_index]
	var hero_id: String = str(roster_entry.get("id", ""))

	var hero_data: Dictionary = build_hero_view_data(hero_id, roster_entry)
	var progress: Dictionary = HeroState.get_or_create_hero(hero_id)

	hero_data["level"] = int(progress.get("level", 1))
	hero_data["starLevel"] = int(progress.get("starLevel", 5))
	hero_data["starProgress"] = int(progress.get("starProgress", 0))

	_ascend_page.setup(hero_data)
	_ascend_page.visible = true
	_set_main_details_visible(false)
