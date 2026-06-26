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

@onready var _rarity_badge: TextureRect = $Mythic
@onready var _role_icon: TextureRect = $RoleIcon

var _hero_name_label: Label
var _hero_title_label: Label
var _power_value_label: Label
var _stars_container: HBoxContainer
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

var _stats_list: VBoxContainer
var _skills_page_list: VBoxContainer
var _gear_list: VBoxContainer
var _troop_skills_list: VBoxContainer
var _overview_list: VBoxContainer


func _ready() -> void:
	_configure_input_handling()
	_bind_full_details_layout()
	_load_hero_roster()
	_build_tab_page_content()
	_configure_tab_page_input()
	_connect_full_details_signals()

	if _hero_roster.is_empty():
		push_warning("HeroDetails: no heroes loaded from heroes.json.")
		return

	_show_tab(Tab.OVERVIEW)
	_display_hero_at_index(0)


func _configure_input_handling() -> void:
	# Root was 0px wide in the scene, which breaks reliable hit-testing.
	if size.x < 100.0 or size.y < 100.0:
		size = Vector2(720, 1280)

	# Scene root must not ignore input or child controls fail to receive clicks.
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
	]:
		_set_mouse_filter_ignore(get_node_or_null(node_name))

	if _stars_container == null:
		_stars_container = get_node_or_null("Stars") as HBoxContainer
	if _stars_container:
		_stars_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for star in _stars_container.get_children():
			_set_mouse_filter_ignore(star)

	var tab_buttons := get_node_or_null("TabButtons") as Control
	if tab_buttons:
		# Container spans far beyond the tab art; only the buttons should stop clicks.
		tab_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab_buttons.z_index = 20

	for node_name in [
		"TabButtons/StatsButton",
		"TabButtons/SkillsButton",
		"TabButtons/GearButton",
		"TabButtons/ToopSkillButton",
		"TabButtons/OverviewButton",
		"LeftHeroArrow",
		"RightHeroArrow",
		"LevelUpButton",
		"AscendButton",
		"BackButton",
	]:
		var item := get_node_or_null(node_name) as Control
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
	_large_portrait = get_node_or_null("LargePortrait") as TextureRect
	_hero_name_label = get_node_or_null("HeroNameLabel") as Label
	_hero_title_label = get_node_or_null("HeroTitleLabel") as Label
	power_label = get_node_or_null("PowerLabel") as Label
	_power_value_label = get_node_or_null("Label") as Label
	_stars_container = get_node_or_null("Stars") as HBoxContainer
	level_label = get_node_or_null("LevelLabel") as Label
	_left_arrow = get_node_or_null("LeftHeroArrow") as TextureButton
	_right_arrow = get_node_or_null("RightHeroArrow") as TextureButton

	var tab_buttons := get_node_or_null("TabButtons")
	if tab_buttons:
		_overview_button = tab_buttons.get_node_or_null("OverviewButton") as TextureButton
		_stats_button = tab_buttons.get_node_or_null("StatsButton") as TextureButton
		_skills_button = tab_buttons.get_node_or_null("SkillsButton") as TextureButton
		_gear_button = tab_buttons.get_node_or_null("GearButton") as TextureButton
		_troop_skills_button = tab_buttons.get_node_or_null("ToopSkillButton") as TextureButton

	_overview_page = get_node_or_null("OverviewPage") as Control
	_stats_page = get_node_or_null("StatsPage") as Control
	_skills_page = get_node_or_null("SkillsPage") as Control
	_gear_page = get_node_or_null("GearPage") as Control
	_troop_skill_page = get_node_or_null("TroopSkillPage") as Control


func _connect_full_details_signals() -> void:
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

	var existing := page.get_node_or_null(list_name) as VBoxContainer
	if existing:
		return existing

	var scroll := ScrollContainer.new()
	scroll.name = "%sScroll" % list_name
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 0
	scroll.offset_top = 0
	scroll.offset_right = 0
	scroll.offset_bottom = 0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = list_name
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(list)
	return list


func _load_hero_roster() -> void:
	var source = DataManager.get_all_heroes() if DataManager.has_method("get_all_heroes") else []
	if source is Array and not source.is_empty():
		_hero_roster = source.duplicate(true)
		return

	for path in [HEROES_JSON_PATH, "res://Data/heroes.json"]:
		if not FileAccess.file_exists(path):
			continue

		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_error("HeroDetails: could not open heroes.json.")
			continue

		var parsed = JSON.parse_string(file.get_as_text())
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
		_overview_page.visible = tab == Tab.OVERVIEW
	if _stats_page:
		_stats_page.visible = tab == Tab.STATS
	if _skills_page:
		_skills_page.visible = tab == Tab.SKILLS
	if _gear_page:
		_gear_page.visible = tab == Tab.GEAR
	if _troop_skill_page:
		_troop_skill_page.visible = tab == Tab.TROOP_SKILLS


func _display_hero_at_index(index: int) -> void:
	if index < 0 or index >= _hero_roster.size():
		return

	_hero_index = index
	var roster_entry: Dictionary = _hero_roster[index]
	var hero_id := str(roster_entry.get("id", ""))
	var hero_data := build_hero_view_data(hero_id, roster_entry)
	if hero_data.is_empty():
		push_warning("HeroDetails: could not resolve template for hero '%s'." % hero_id)
		return

	_refresh_header(hero_data)
	_refresh_tab_content(hero_data)


func _refresh_header(hero_data: Dictionary) -> void:
	var hero_id := str(hero_data.get("id", ""))
	var fields := _get_hero_json_fields(hero_id, hero_data)
	var display_name := str(fields.get("name", "Unknown"))
	var role := str(fields.get("role", "Unknown"))
	var rarity := str(fields.get("rarity", ""))
	var troop_type := str(fields.get("troopType", ""))
	var level := int(hero_data.get("level", 1))
	var ascension := int(hero_data.get("ascension", 0))
	var stats := _calculate_stats(hero_data)
	var power := int(stats.get("power", _calculate_power(hero_data)))

	if _hero_name_label:
		_hero_name_label.text = display_name
	if _hero_title_label:
		_hero_title_label.text = str(hero_data.get("lore", role))
	if level_label:
		level_label.text = "Lv. %d  +%d" % [level, ascension]
	if power_label:
		power_label.text = "Power:"
	if _power_value_label:
		_power_value_label.text = _format_number(power)

	_set_texture(_large_portrait, _resolve_portrait_path(hero_data))

	var rarity_path := _resolve_rarity_texture_path(rarity)
	var troop_path := _resolve_troop_texture_path(troop_type)
	_debug_log_hero_icons(fields, rarity_path, troop_path)
	_set_rarity_badge(rarity, rarity_path)
	_set_troop_icon(troop_path)
	_update_stars(ascension, get_rarity_star_count(rarity))

	# Keep compact panel bindings in sync when present.
	if hero_name:
		hero_name.text = display_name
	if role_label:
		role_label.text = "Role: %s" % role
	if rarity_label:
		rarity_label.text = "Rarity: %s" % rarity
	if portrait:
		_set_texture(portrait, _resolve_portrait_path(hero_data, true))


func _refresh_tab_content(hero_data: Dictionary) -> void:
	var hero_id := str(hero_data.get("id", ""))
	_populate_overview_page(hero_data)
	_populate_stats_page(hero_data)
	_populate_skills_page(hero_id)
	_populate_gear_page(hero_id)
	_populate_troop_skills_page(hero_data, hero_id)


func _populate_overview_page(hero_data: Dictionary) -> void:
	_clear_list(_overview_list)
	if _overview_list == null:
		return

	_add_info_label(_overview_list, "Role: %s" % str(hero_data.get("role", "Unknown")))
	_add_info_label(_overview_list, "Rarity: %s" % str(hero_data.get("rarity", "Unknown")))
	_add_info_label(_overview_list, "Troop: %s" % str(hero_data.get("troopType", "none")))
	_add_info_label(
		_overview_list,
		"Level: %d  Ascension: +%d" % [
			int(hero_data.get("level", 1)),
			int(hero_data.get("ascension", 0)),
		]
	)

	var active_skills: Array = hero_data.get("activeSkills", [])
	if active_skills.is_empty():
		_add_info_label(_overview_list, "Active Ability: None")
	else:
		var ability = active_skills[0]
		_add_info_label(
			_overview_list,
			"Active Ability: %s" % str(ability.get("name", "None"))
		)


func _populate_stats_page(hero_data: Dictionary) -> void:
	_clear_list(_stats_list)
	if _stats_list == null:
		return

	var stats := _calculate_stats(hero_data)
	_add_info_label(_stats_list, "Attack: %d" % int(stats.get("attack", 0)))
	_add_info_label(_stats_list, "Defense: %d" % int(stats.get("defense", 0)))
	_add_info_label(_stats_list, "Health: %d" % int(stats.get("health", 0)))
	_add_info_label(_stats_list, "Leadership: %d" % int(stats.get("leadership", 0)))
	_add_info_label(_stats_list, "Power: %s" % _format_number(int(stats.get("power", 0))))
	_add_info_label(_stats_list, "Troop Type: %s" % str(hero_data.get("troopType", "none")))


func _populate_skills_page(hero_id: String) -> void:
	_clear_list(_skills_page_list)
	if _skills_page_list == null:
		return

	var skills := _get_skills_for_hero(hero_id)
	if skills.is_empty():
		_add_info_label(_skills_page_list, "No skills listed.")
		return

	for skill in skills:
		var skill_name := str(skill.get("skillName", "Unknown Skill"))
		var skill_type := str(skill.get("skillType", ""))
		var description := str(skill.get("description", ""))
		_add_info_label(_skills_page_list, "%s (%s)" % [skill_name, skill_type], true)
		_add_info_label(_skills_page_list, description, true)


func _populate_gear_page(hero_id: String) -> void:
	_clear_list(_gear_list)
	if _gear_list == null:
		return

	_add_info_label(_gear_list, "Gear slots are not loaded in this screen yet.")
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
			if not bonus is Dictionary:
				continue
			_add_info_label(
				_troop_skills_list,
				"%s: +%.0f%%" % [
					str(bonus.get("stat", "Bonus")),
					float(bonus.get("value", 0.0)) * 100.0,
				]
			)

	for skill in _get_skills_for_hero(hero_id):
		var scaling: Dictionary = skill.get("powerScaling", {})
		var stat_name := str(scaling.get("stat", ""))
		if stat_name.is_empty():
			continue
		if not _is_troop_related_stat(stat_name):
			continue
		_add_info_label(
			_troop_skills_list,
			"%s - %s" % [str(skill.get("skillName", "Skill")), stat_name]
		)


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


func _resolve_portrait_path(hero_data: Dictionary, prefer_portrait: bool = false) -> String:
	var keys := PORTRAIT_KEYS if prefer_portrait else PORTRAIT_KEYS_FULL
	var resolved := _resolve_path(hero_data, keys)
	if not resolved.is_empty():
		return resolved

	var hero_name_value := str(hero_data.get("name", ""))
	if hero_name_value.is_empty():
		return ""

	var portrait_path := "res://Art/Heroes/%s/portrait.png" % hero_name_value
	if prefer_portrait:
		return portrait_path

	var fullbody_path := "res://Art/Heroes/%s/fullbody.png" % hero_name_value
	if ResourceLoader.exists(fullbody_path):
		return fullbody_path
	if ResourceLoader.exists(portrait_path):
		return portrait_path
	return fullbody_path


func _get_hero_json_fields(hero_id: String, fallback: Dictionary) -> Dictionary:
	var template := _get_hero_template_by_id(hero_id)
	if template.is_empty():
		template = fallback

	return {
		"id": str(template.get("id", hero_id)),
		"name": str(template.get("name", "Unknown")),
		"rarity": str(template.get("rarity", "")).strip_edges(),
		"troopType": str(template.get("troopType", "")).strip_edges(),
		"role": str(template.get("role", "")).strip_edges(),
	}


func _clear_icon_rect(icon: TextureRect) -> void:
	if icon == null:
		return
	icon.texture = null
	icon.visible = false
	icon.modulate = Color(1, 1, 1, 1)


func _apply_icon_texture(icon: TextureRect, texture_path: String) -> bool:
	if icon == null or texture_path.is_empty() or not ResourceLoader.exists(texture_path):
		return false

	var loaded := load(texture_path)
	if not loaded is Texture2D:
		return false

	icon.texture = loaded
	icon.visible = true
	icon.modulate = Color(1, 1, 1, 1)
	return true


func _resolve_rarity_texture_path(rarity: String) -> String:
	var normalized := rarity.strip_edges()
	if normalized.is_empty() or not RARITY_TEXTURES.has(normalized):
		return ""
	return RARITY_TEXTURES[normalized]


func _resolve_troop_texture_path(troop_type: String) -> String:
	var normalized := troop_type.to_lower().strip_edges()
	if normalized.is_empty() or normalized in ["none", "support"]:
		return ""

	if TROOP_TEXTURES.has(normalized):
		return TROOP_TEXTURES[normalized]

	# Accept singular alias used in some assets/data without defaulting to infantry.
	if normalized == "marksman" and TROOP_TEXTURES.has("marksmen"):
		return TROOP_TEXTURES["marksmen"]

	return ""


func _debug_log_hero_icons(
	fields: Dictionary,
	rarity_path: String,
	troop_path: String
) -> void:
	print(
		"HeroDetails icon bind: id=%s name=%s rarity=%s troopType=%s role=%s rarity_path=%s troop_path=%s"
		% [
			str(fields.get("id", "")),
			str(fields.get("name", "")),
			str(fields.get("rarity", "")),
			str(fields.get("troopType", "")),
			str(fields.get("role", "")),
			rarity_path if not rarity_path.is_empty() else "(hidden)",
			troop_path if not troop_path.is_empty() else "(hidden)",
		]
	)


func _set_troop_icon(texture_path: String) -> void:
	_clear_icon_rect(_role_icon)
	if texture_path.is_empty():
		return
	if not _apply_icon_texture(_role_icon, texture_path):
		push_warning("HeroDetails: troop icon not found at '%s'." % texture_path)


func _set_rarity_badge(_rarity: String, texture_path: String) -> void:
	_clear_icon_rect(_rarity_badge)
	if texture_path.is_empty():
		if not _rarity.is_empty():
			push_warning("HeroDetails: no rarity badge for '%s'." % _rarity)
		return
	if not _apply_icon_texture(_rarity_badge, texture_path):
		push_warning("HeroDetails: rarity badge not found at '%s'." % texture_path)


func _update_stars(ascension: int, star_count: int) -> void:
	if _stars_container == null:
		return

	var star_nodes: Array = _stars_container.get_children()
	for i in range(star_nodes.size()):
		var star := star_nodes[i] as CanvasItem
		if star == null:
			continue

		if i >= star_count:
			star.visible = false
			continue

		star.visible = true
		star.modulate = Color(1, 1, 1, 1)


func _clear_list(list: VBoxContainer) -> void:
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()


func _add_info_label(list: VBoxContainer, text: String, autowrap: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if autowrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(label)


func _format_number(value: int) -> String:
	var text := str(value)
	if text.length() <= 3:
		return text

	var parts: PackedStringArray = []
	while text.length() > 3:
		parts.insert(0, text.substr(text.length() - 3, 3))
		text = text.substr(0, text.length() - 3)
	if not text.is_empty():
		parts.insert(0, text)
	return ",".join(parts)


func _is_troop_related_stat(stat_name: String) -> bool:
	var lowered := stat_name.to_lower()
	return (
		"troop" in lowered
		or "infantry" in lowered
		or "cavalry" in lowered
		or "marksman" in lowered
		or "marksmen" in lowered
	)
