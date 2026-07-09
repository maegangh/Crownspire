extends Control

const BONUS_ROW_SCENE = preload("res://UI/building_upgrade/BonusRow.tscn")
const REQUIREMENT_ROW_SCENE = preload("res://UI/building_upgrade/RequirementRow.tscn")

@export var building_id: String = "citadel"

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

var _local_buildings_cache: Array = []
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


func open_for_building(new_building_id: String) -> void:
	building_id = new_building_id
	GameState.popup_open = true
	load_building_data()
	show()


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
	var ui = _get_ui_manager()

	if ui and ui.has_method("get_building"):
		building_data = ui.call("get_building", building_id)
	else:
		building_data = _get_local_building(building_id)

	if building_data.is_empty():
		push_error("[Crownspire UpgradeWindow] Building data not found for ID: " + building_id)
		return

	if building_name_label:
		building_name_label.text = building_data.get("name", "Royal Structure").to_upper()

	var lvl := int(building_data.get("level", 1))
	var max_lvl := int(building_data.get("max_level", 30))

	if current_level_label:
		current_level_label.text = "Lv. %d" % lvl

	if next_level_label:
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

	if header_power_gain_label:
		header_power_gain_label.text = "+" + _format_with_commas(power_gain) + " Kingdom Power"

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
		"barracks":
			stat_name = "Training Capacity"

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
	var multiplier := 1.0 + lvl * 0.15

	var req_food := int(reqs.get("food", 0) * multiplier)
	var req_wood := int(reqs.get("wood", 0) * multiplier)
	var req_stone := int(reqs.get("stone", 0) * multiplier)
	var req_iron := int(reqs.get("iron", 0) * multiplier)

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
	var multiplier := 1.0 + lvl * 0.15

	for res_key in reqs.keys():
		var cost := int(reqs[res_key] * multiplier)
		if _get_player_resource(res_key) < cost:
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
	var result := {}
	var ui = _get_ui_manager()

	if ui and ui.has_method("upgrade_building"):
		result = ui.call("upgrade_building", building_id)
	else:
		result = _local_upgrade_building(building_id)

	if result.get("success", false):
		_show_celebration_overlay(
			"STRUCTURE UPGRADED",
			"%s has reached Level %d." % [building_data.get("name", "Building"), int(building_data.get("level", 1)) + 1]
		)
		load_building_data()
	else:
		if animation_player and animation_player.has_animation("error_shake"):
			animation_player.play("error_shake")


func _on_finish_button_pressed() -> void:
	var cost := missing_resources_crystal_cost

	if cost <= 0:
		cost = max(5, int(float(building_data.get("upgrade_time_seconds", 300)) / 60.0))

	var ui = _get_ui_manager()
	var current_crystals := int(_local_resources.get("royal_crystals", 0))

	if ui:
		var value = ui.get("royal_crystals")
		if value != null:
			current_crystals = int(value)

	if current_crystals < cost:
		if animation_player and animation_player.has_animation("error_shake"):
			animation_player.play("error_shake")
		return

	if ui:
		ui.set("royal_crystals", current_crystals - cost)
	else:
		_local_resources["royal_crystals"] = current_crystals - cost

	var result := {}
	if ui and ui.has_method("upgrade_building"):
		result = ui.call("upgrade_building", building_id)
	else:
		result = _local_upgrade_building(building_id)

	if result.get("success", false):
		_show_celebration_overlay(
			"IMMEDIATE UPGRADE COMPLETE",
			"%s has immediately upgraded." % building_data.get("name", "Building")
		)
		load_building_data()


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

		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK:
					var data = json.get_data()
					if data is Array:
						_local_buildings_cache = data

		if _local_buildings_cache.is_empty():
			_local_buildings_cache = [
				{
					"id": "citadel",
					"name": "Crystal Citadel",
					"level": 1,
					"max_level": 30,
					"base_power": 10000,
					"power_per_level": 2500,
					"resources_required": {
						"food": 50000,
						"wood": 60000,
						"stone": 30000,
						"iron": 10000
					},
					"upgrade_time_seconds": 300,
					"current_bonus": "",
					"next_bonus": ""
				}
			]

	for b in _local_buildings_cache:
		if b is Dictionary and b.get("id", "") == b_id:
			return b

	return {}


func _local_upgrade_building(b_id: String) -> Dictionary:
	var b := _get_local_building(b_id)

	if b.is_empty():
		return {"success": false, "error": "Building not found"}

	var lvl := int(b.get("level", 1))
	var max_lvl := int(b.get("max_level", 30))

	if lvl >= max_lvl:
		return {"success": false, "error": "Max level reached"}

	var reqs = b.get("resources_required", {})
	var multiplier := 1.0 + lvl * 0.15

	for res_key in reqs.keys():
		var cost := int(reqs[res_key] * multiplier)
		_local_resources[res_key] = max(0, int(_local_resources.get(res_key, 0)) - cost)

	b["level"] = lvl + 1
	refresh_requirements_and_buttons()
	return {"success": true}
