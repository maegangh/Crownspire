extends Control

const BONUS_ROW_SCENE = preload("res://UI/building_upgrade/BonusRow.tscn")
const REQUIREMENT_ROW_SCENE = preload("res://UI/building_upgrade/RequirementRow.tscn")

@export var building_id: String = "castle"

@onready var animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer")
@onready var background_dim: ColorRect = $BackgroundDim
@onready var popup_container: PanelContainer = $PopupContainer

@onready var building_image: TextureRect = get_node_or_null("%BuildingImage")
@onready var building_name_label: Label = %BuildingNameLabel
@onready var current_level_label: Label = %CurrentLevelLabel
@onready var level_arrow: Label = %LevelArrow
@onready var next_level_label: Label = %NextLevelLabel
@onready var header_power_gain_label: Label = get_node_or_null("%HeaderPowerGainLabel")

@onready var bonus_container: VBoxContainer = %BonusContainer
@onready var requirements_container: VBoxContainer = %RequirementsContainer

@onready var finish_button: Button = %FinishButton
@onready var upgrade_button: Button = %UpgradeButton
@onready var close_button: TextureButton = %CloseButton

@onready var celebration_panel: PanelContainer = %CelebrationPanel
@onready var celebration_title: Label = %CelebrationTitle
@onready var celebration_desc: Label = %CelebrationDesc
@onready var celebration_close_btn: Button = %CelebrationCloseBtn

var building_data: Dictionary = {}
var missing_resources_crystal_cost: int = 0

var _local_resources := {
	"food": 500000,
	"wood": 600000,
	"stone": 350000,
	"iron": 150000,
	"gold": 100000,
	"royal_crystals": 2500
}

var _local_buildings_cache: Dictionary = {}
var _ui_manager: Node = null


func _ready() -> void:
	call_deferred("hide")

	if celebration_panel:
		celebration_panel.visible = false
		if celebration_close_btn:
			celebration_close_btn.pressed.connect(_on_celebration_close_pressed)

	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)
	if upgrade_button:
		upgrade_button.pressed.connect(_on_upgrade_button_pressed)
	if finish_button:
		finish_button.pressed.connect(_on_finish_button_pressed)

	load_building_data()

	var ui = _get_ui_manager()
	if ui and ui.has_signal("currency_changed"):
		ui.currency_changed.connect(_on_currency_changed)


func open_for_building(building_reference: Variant) -> void:
	var requested_id := ""
	

	if building_reference is String or building_reference is StringName:
		requested_id = str(building_reference)

	elif building_reference is Node:
		var node := building_reference as Node
		var node_building_id = node.get("building_id")

		if node_building_id != null and not str(node_building_id).is_empty():
			requested_id = str(node_building_id)
		else:
			requested_id = node.name.to_snake_case()

	requested_id = _normalize_building_id(requested_id)

	if requested_id.is_empty():
		push_error("[Crownspire UpgradeWindow] Could not determine building ID.")
		return

	building_id = requested_id
	GameState.popup_open = true

	load_building_data()

	if building_data.is_empty():
		GameState.popup_open = false
		return

	visible = true
	move_to_front()

func _normalize_building_id(raw_id: String) -> String:
	var normalized := raw_id.strip_edges().to_lower().replace(" ", "_")

	var aliases := {
		"citadel": "castle",
		"crystal_citadel": "castle",
		"citadel_of_emerald_spires": "castle",

		"lumbermill": "lumber_mill",
		"lumber_yard": "lumber_mill",
		"lumberyard": "lumber_mill",

		"stone_quarry": "quarry",

		"ironmine": "iron_mine",

		"research_center": "academy",
		"research_building": "academy",

		"medical_tent": "hospital",
		"infirmary": "hospital",

		"trade_post": "trading_post",


	}

	return str(aliases.get(normalized, normalized))
	

func _get_ui_manager() -> Node:
	if _ui_manager == null:
		_ui_manager = get_node_or_null("/root/UIManager")
		if _ui_manager == null:
			_ui_manager = get_node_or_null("/root/UiManager")
		if _ui_manager == null:
			_ui_manager = get_node_or_null("/root/ui_manager")
	return _ui_manager


func _on_currency_changed(_currency_id: String, _new_amount: float) -> void:
	refresh_requirements_and_buttons()


func load_building_data() -> void:
	building_data = _get_local_building(building_id)

	if building_data.is_empty():
		push_error(
			"[Crownspire UpgradeWindow] Building data not found for ID: "
			+ building_id
		)
		return

	building_name_label.text = str(
		building_data.get("name", "Royal Structure")
	).to_upper()

	var lvl := int(building_data.get("level", 1))
	var max_lvl := int(building_data.get("max_level", 40))

	current_level_label.text = "Lv. %d" % lvl

	if lvl >= max_lvl:
		next_level_label.text = "MAX"
	else:
		next_level_label.text = "Lv. %d" % (lvl + 1)

	if building_image:
		var art_path := "res://assets/buildings/%s.png" % building_id

		if ResourceLoader.exists(art_path):
			building_image.texture = load(art_path)

	_populate_bonuses(lvl, max_lvl)
	_populate_requirements(lvl, max_lvl)


func _populate_bonuses(lvl: int, max_lvl: int) -> void:
	for child in bonus_container.get_children():
		child.queue_free()

	if lvl >= max_lvl:
		var max_lbl := Label.new()
		max_lbl.text = "Maximum Level attained."
		max_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		max_lbl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		bonus_container.add_child(max_lbl)
		return

	var power_gain := int(building_data.get("power_per_level", 100) * (1.0 + lvl * 0.1))


	var power_bonus = BONUS_ROW_SCENE.instantiate()
	bonus_container.add_child(power_bonus)

	var current_power := int(building_data.get("base_power", 1000)) + int(building_data.get("power_per_level", 100)) * lvl
	var next_power := current_power + power_gain

	power_bonus.setup(
		"Kingdom Power",
		"res://assets/ui/icons/hud_power.png",
		_format_with_commas(current_power),
		_format_with_commas(next_power),
		_format_with_commas(power_gain)
	)

	var stat_name := "Unique Benefit"
	var stat_icon_path := "res://assets/ui/icons/category_featured.png"

	match building_id:
		"citadel", "castle":
			stat_name = "Hospital Capacity"
		"farm":
			stat_name = "Food Production"
			stat_icon_path = "res://assets/ui/icons/res_food.png"
		"lumber_mill":
			stat_name = "Wood Production"
			stat_icon_path = "res://assets/ui/icons/res_wood.png"
		"quarry":
			stat_name = "Stone Production"
			stat_icon_path = "res://assets/ui/icons/res_stone.png"
		"iron_mine":
			stat_name = "Iron Production"
			stat_icon_path = "res://assets/ui/icons/res_iron.png"
		"academy":
			stat_name = "Research Speed"
		"hospital":
			stat_name = "Healing Capacity"
		"embassy":
			stat_name = "Reinforcement Capacity"
		"trading_post":
			stat_name = "Trading Bonus"
		"infantry_barracks":
			stat_name = "Infantry Training Capacity"

		"cavalry_stable":
			stat_name = "Cavalry Training Capacity"

		"marksmen_camp":
			stat_name = "Marksmen Training Capacity"

	var current_spec_bonus = building_data.get("current_bonus", "")
	var next_spec_bonus = building_data.get("next_bonus", "")

	if current_spec_bonus == "" or next_spec_bonus == "":
		match building_id:
			"citadel", "castle":
				current_spec_bonus = "%s Troops" % _format_with_commas(5000 + lvl * 1500)
				next_spec_bonus = "%s Troops" % _format_with_commas(5000 + (lvl + 1) * 1500)
			"farm":
				current_spec_bonus = "%s / Hour" % _format_amount(1500 + lvl * 500)
				next_spec_bonus = "%s / Hour" % _format_amount(1500 + (lvl + 1) * 500)
			"lumber_mill":
				current_spec_bonus = "%s / Hour" % _format_amount(1200 + lvl * 400)
				next_spec_bonus = "%s / Hour" % _format_amount(1200 + (lvl + 1) * 400)
			"quarry":
				current_spec_bonus = "%s / Hour" % _format_amount(800 + lvl * 300)
				next_spec_bonus = "%s / Hour" % _format_amount(800 + (lvl + 1) * 300)
			"iron_mine":
				current_spec_bonus = "%s / Hour" % _format_amount(400 + lvl * 150)
				next_spec_bonus = "%s / Hour" % _format_amount(400 + (lvl + 1) * 150)
			_:
				current_spec_bonus = "Lv. %d" % lvl
				next_spec_bonus = "Lv. %d" % (lvl + 1)

	if current_spec_bonus != "":
		var spec_bonus = BONUS_ROW_SCENE.instantiate()
		bonus_container.add_child(spec_bonus)
		spec_bonus.setup(
			stat_name,
			stat_icon_path,
			str(current_spec_bonus),
			str(next_spec_bonus),
			""
		)


func _populate_requirements(lvl: int, max_lvl: int) -> void:
	for child in requirements_container.get_children():
		child.queue_free()

	if lvl >= max_lvl:
		var empty_lbl := Label.new()
		empty_lbl.text = "No further requirements."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		requirements_container.add_child(empty_lbl)
		return

	var reqs = building_data.get("resources_required", {})

	var req_food := int(reqs.get("food", 0))
	var req_wood := int(reqs.get("wood", 0))
	var req_stone := int(reqs.get("stone", 0))
	var req_iron := int(reqs.get("iron", 0))


	missing_resources_crystal_cost = 0

	if req_food > 0:
		_add_resource_row("Food", "food", req_food, "res://assets/ui/icons/res_food.png")
	if req_wood > 0:
		_add_resource_row("Wood", "wood", req_wood, "res://assets/ui/icons/res_wood.png")
	if req_stone > 0:
		_add_resource_row("Stone", "stone", req_stone, "res://assets/ui/icons/res_stone.png")
	if req_iron > 0:
		_add_resource_row("Iron", "iron", req_iron, "res://assets/ui/icons/res_iron.png")

	refresh_requirements_and_buttons()


func _add_resource_row(display_name: String, resource_id: String, req_amount: int, icon_path: String) -> void:
	var row = REQUIREMENT_ROW_SCENE.instantiate()
	requirements_container.add_child(row)

	var current_amt := _get_player_resource(resource_id)
	var is_met := current_amt >= req_amount
	var missing_str := ""

	if not is_met:
		var missing := req_amount - current_amt
		missing_str = _format_amount(missing)

		var rate := 1000
		if resource_id == "stone":
			rate = 500
		elif resource_id == "iron":
			rate = 250

		var cost: int = int(max(1, int(ceil(float(missing) / float(rate)))))
		missing_resources_crystal_cost += cost

	row.setup(
		display_name,
		icon_path,
		_format_amount(current_amt),
		_format_amount(req_amount),
		missing_str,
		is_met,
		"Obtain"
	)

	if row.has_signal("action_pressed"):
		row.action_pressed.connect(func(): _on_obtain_pressed(resource_id))


func refresh_requirements_and_buttons() -> void:
	var lvl := int(building_data.get("level", 1))
	var max_lvl := int(building_data.get("max_level", 30))

	if lvl >= max_lvl:
		if finish_button:
			finish_button.disabled = true
		if upgrade_button:
			upgrade_button.disabled = true
		return

	var all_met := true
	var reqs = building_data.get("resources_required", {})

	for res_key in reqs.keys():
		var required_amount := int(reqs[res_key])

		if _get_player_resource(res_key) < required_amount:
			all_met = false
			break

	if upgrade_button:
		upgrade_button.disabled = not all_met

	if finish_button:
		if missing_resources_crystal_cost > 0:
			finish_button.text = "Finish Now (%d 💎)" % missing_resources_crystal_cost
		else:
			var base_speed_cost := int(float(building_data.get("upgrade_time_seconds", 300)) / 60.0)
			finish_button.text = "Finish Now (%d 💎)" % max(5, base_speed_cost)

func _get_player_resource(res_id: String) -> int:
	var ui = _get_ui_manager()
	if ui:
		var value = ui.get(res_id)
		if value != null:
			return int(value)

	return int(_local_resources.get(res_id, 0))


func _get_building_level(b_id: String) -> int:
	var ui = _get_ui_manager()
	var b := {}

	if ui and ui.has_method("get_building"):
		b = ui.call("get_building", b_id)
	else:
		b = _get_local_building(b_id)

	return int(b.get("level", 1))


func _on_obtain_pressed(resource_id: String) -> void:
	print("[Crownspire UI] Obtain clicked for: " + resource_id)

	var mock_batch := 50000
	var ui = _get_ui_manager()

	if ui:
		var current = ui.get(resource_id)
		if current != null:
			ui.set(resource_id, int(current) + mock_batch)
			if ui.has_method("show_toast"):
				ui.call("show_toast", "+50K %s" % resource_id.capitalize())
	else:
		_local_resources[resource_id] = int(_local_resources.get(resource_id, 0)) + mock_batch

	load_building_data()


func _on_close_button_pressed() -> void:
	GameState.popup_open = false
	hide()


func _on_upgrade_button_pressed() -> void:
	var result := _local_upgrade_building(building_id)

	if result.get("success", false):
		var new_level := int(result.get("new_level", 1))

		_show_celebration_overlay(
			"STRUCTURE UPGRADED",
			"%s has reached Level %d." % [
				building_data.get("name", "Building"),
				new_level
			]
		)

		load_building_data()
		_notify_city_buildings()
	else:
		push_warning(
			"[Crownspire UpgradeWindow] Upgrade failed: "
			+ str(result.get("error", "Unknown error"))
		)

		if animation_player and animation_player.has_animation("error_shake"):
			animation_player.play("error_shake")


func _on_finish_button_pressed() -> void:
	var cost := missing_resources_crystal_cost

	if cost <= 0:
		cost = max(
			5,
			int(
				float(building_data.get("upgrade_time_seconds", 300))
				/ 60.0
			)
		)

	var ui := _get_ui_manager()
	var current_crystals := int(
		_local_resources.get("royal_crystals", 0)
	)

	if ui:
		var value = ui.get("royal_crystals")
		if value != null:
			current_crystals = int(value)

	if current_crystals < cost:
		if animation_player and animation_player.has_animation("error_shake"):
			animation_player.play("error_shake")
		return

	if ui and ui.get("royal_crystals") != null:
		ui.set("royal_crystals", current_crystals - cost)
	else:
		_local_resources["royal_crystals"] = current_crystals - cost

	var result := _local_upgrade_building(building_id)

	if result.get("success", false):
		_show_celebration_overlay(
			"IMMEDIATE UPGRADE COMPLETE",
			"%s has reached Level %d." % [
				building_data.get("name", "Building"),
				int(result.get("new_level", 1))
			]
		)

		load_building_data()
		_notify_city_buildings()
	else:
		# Refund crystals when the building upgrade itself fails.
		if ui and ui.get("royal_crystals") != null:
			ui.set("royal_crystals", current_crystals)
		else:
			_local_resources["royal_crystals"] = current_crystals

		push_warning(
			"[Crownspire UpgradeWindow] Immediate upgrade failed: "
			+ str(result.get("error", "Unknown error"))
		)

		if animation_player and animation_player.has_animation("error_shake"):
			animation_player.play("error_shake")


func _notify_city_buildings() -> void:
	get_tree().call_group(
		"city_buildings",
		"refresh_level_display"
	)


func _show_celebration_overlay(title: String, desc: String) -> void:
	if celebration_panel:
		celebration_title.text = title.to_upper()
		celebration_desc.text = desc
		celebration_panel.visible = true
		celebration_panel.modulate.a = 0.0

		var tw = create_tween()
		tw.tween_property(celebration_panel, "modulate:a", 1.0, 0.3)


func _on_celebration_close_pressed() -> void:
	if celebration_panel:
		var tw = create_tween()
		tw.tween_property(celebration_panel, "modulate:a", 0.0, 0.2)
		await tw.finished
		celebration_panel.visible = false


func _format_amount(amt: int) -> String:
	if amt >= 1000000:
		return "%.1fM" % (float(amt) / 1000000.0)
	elif amt >= 1000:
		return "%.1fK" % (float(amt) / 1000.0)
	return str(amt)


func _format_with_commas(value: int) -> String:
	var s := str(value)
	var result := ""
	var length := s.length()

	for i in range(length):
		if i > 0 and (length - i) % 3 == 0:
			result += ","
		result += s[i]

	return result


func _get_local_building(b_id: String) -> Dictionary:
	if _local_buildings_cache.is_empty():
		var path := "res://data/buildings.json"

		if not FileAccess.file_exists(path):
			push_error(
				"[Crownspire UpgradeWindow] Missing buildings.json at: "
				+ path
			)
			return {}

		var file := FileAccess.open(path, FileAccess.READ)

		if file == null:
			push_error(
				"[Crownspire UpgradeWindow] Could not open buildings.json."
			)
			return {}

		var parsed = JSON.parse_string(file.get_as_text())

		if parsed is not Dictionary:
			push_error(
				"[Crownspire UpgradeWindow] buildings.json must use a Dictionary root."
			)
			return {}

		_local_buildings_cache = parsed

	if not _local_buildings_cache.has(b_id):
		push_error(
			"[Crownspire UpgradeWindow] Unknown building ID: " + b_id
		)
		return {}

	var template: Dictionary = _local_buildings_cache[b_id]
	var levels: Dictionary = template.get("levels", {})

	if levels.is_empty():
		push_error(
			"[Crownspire UpgradeWindow] No levels found for: " + b_id
		)
		return {}

	var current_level := _load_saved_building_level(
		b_id,
		str(template.get("name", b_id))
	)

	var max_level := 1

	for level_key in levels.keys():
		max_level = max(max_level, int(str(level_key)))

	current_level = clampi(current_level, 1, max_level)

	var current_data: Dictionary = levels.get(str(current_level), {})
	var next_level: int = min(current_level + 1, max_level)
	var next_data: Dictionary = levels.get(str(next_level), current_data)

	return {
		"id": b_id,
		"name": str(template.get("name", b_id.capitalize())),
		"level": current_level,
		"max_level": max_level,

		"base_power": int(current_data.get("powerGained", 0)),
		"power_per_level": int(next_data.get("powerGained", 0)),

		"resources_required": next_data.get("costs", {}),
		"upgrade_time_seconds": int(
			next_data.get("buildTimeSec", 0)
		),

		"current_bonus": str(
			current_data.get("buildingEffect", "")
		),
		"next_bonus": str(
			next_data.get("buildingEffect", "")
		),

		"prerequisites": next_data.get("prerequisites", []),
		"description": str(next_data.get("description", ""))
	}

func _load_saved_building_level(
	b_id: String,
	display_name: String
) -> int:
	var save := ConfigFile.new()

	if save.load("user://buildings.cfg") != OK:
		return 1

	if save.has_section_key(b_id, "level"):
		return int(save.get_value(b_id, "level", 1))

	if save.has_section_key(display_name, "level"):
		return int(save.get_value(display_name, "level", 1))

	return 1

func _local_upgrade_building(b_id: String) -> Dictionary:
	var b := _get_local_building(b_id)

	if b.is_empty():
		return {
			"success": false,
			"error": "Building not found"
		}

	var lvl := int(b.get("level", 1))
	var max_lvl := int(b.get("max_level", 40))

	if lvl >= max_lvl:
		return {
			"success": false,
			"error": "Max level reached"
		}

	var reqs: Dictionary = b.get("resources_required", {})

	for res_key in reqs.keys():
		var resource_id := str(res_key)
		var required_amount := int(reqs[res_key])
		var current_amount := _get_player_resource(resource_id)

		if current_amount < required_amount:
			return {
				"success": false,
				"error": "Not enough %s" % resource_id.capitalize()
			}

	var ui := _get_ui_manager()

	for res_key in reqs.keys():
		var resource_id := str(res_key)
		var required_amount := int(reqs[res_key])
		var current_amount := _get_player_resource(resource_id)
		var remaining_amount := current_amount - required_amount

		if ui and ui.get(resource_id) != null:
			ui.set(resource_id, remaining_amount)
		else:
			_local_resources[resource_id] = remaining_amount

	var new_level := lvl + 1
	var save := ConfigFile.new()
	var save_path := "user://buildings.cfg"

	# Keep every other building already stored in the same file.
	var load_error := save.load(save_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return {
			"success": false,
			"error": "Could not open building save file"
		}

	save.set_value(b_id, "level", new_level)

	var save_error := save.save(save_path)
	if save_error != OK:
		return {
			"success": false,
			"error": "Could not save building level"
		}

	return {
		"success": true,
		"new_level": new_level
	}
