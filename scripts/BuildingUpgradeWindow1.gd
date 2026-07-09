extends Control

# Crownspire Building Upgrade Window (AAA Mobile strategy compliant)
# Implements white marble layout, gold trim, sapphire blue and purple crystal accents, with full database queries.

const BONUS_ROW_SCENE = preload("res://UI/building_upgrade/BonusRow.tscn")
const REQUIREMENT_ROW_SCENE = preload("res://UI/building_upgrade/RequirementRow.tscn")

@export var building_id: String = "citadel" # Set at runtime when opening

# Node references
@onready var animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer")
@onready var background_dim: ColorRect = $BackgroundDim
@onready var popup_container: PanelContainer = $PopupContainer

# Window Frame components
@onready var building_image: TextureRect = get_node_or_null("%BuildingImage")
@onready var building_name_label: Label = %BuildingNameLabel
@onready var current_level_label: Label = %CurrentLevelLabel
@onready var level_arrow: Label = %LevelArrow
@onready var next_level_label: Label = %NextLevelLabel
@onready var header_power_gain_label: Label = get_node_or_null("%HeaderPowerGainLabel")

# Containers
@onready var bonus_container: VBoxContainer = %BonusContainer
@onready var requirements_container: VBoxContainer = %RequirementsContainer

# Buttons
@onready var finish_button: Button = %FinishButton
@onready var upgrade_button: Button = %UpgradeButton
@onready var close_button: TextureButton = %CloseButton

# Notification/Celebration
@onready var celebration_panel: PanelContainer = %CelebrationPanel
@onready var celebration_title: Label = %CelebrationTitle
@onready var celebration_desc: Label = %CelebrationDesc
@onready var celebration_close_btn: Button = %CelebrationCloseBtn

# Cache state
var building_data: Dictionary = {}
var missing_resources_crystal_cost: int = 0

# Fallback player resources if UIManager autoload is not present
var _local_resources = {
	"food": 500000,
	"wood": 600000,
	"stone": 350000,
	"iron": 150000,
	"gold": 100000,
	"royal_crystals": 2500
}

# Fallback local dictionary of loaded building data
var _local_buildings_cache: Array = []
var _ui_manager: Node = null

# Safe runtime resolution of UIManager autoload node
func _get_ui_manager() -> Node:
	if _ui_manager == null:
		_ui_manager = get_node_or_null("/root/UIManager")
		if _ui_manager == null:
			_ui_manager = get_node_or_null("/root/UiManager")
		if _ui_manager == null:
			_ui_manager = get_node_or_null("/root/ui_manager")
	return _ui_manager

func _ready() -> void:
	# Hide celebration overlay by default
	if celebration_panel:
		celebration_panel.visible = false
		celebration_close_btn.pressed.connect(_on_celebration_close_pressed)

	# Connect core buttons
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)
	if upgrade_button:
		upgrade_button.pressed.connect(_on_upgrade_button_pressed)
	if finish_button:
		finish_button.pressed.connect(_on_finish_button_pressed)

	# Initial load
	load_building_data()

	# Connect global signal to refresh UI on currency changes safely
	var ui = _get_ui_manager()
	if ui and ui.has_signal("currency_changed"):
		ui.currency_changed.connect(_on_currency_changed)

func _on_currency_changed(_currency_id: String, _new_amount: float) -> void:
	# Refresh current check status when player receives wood/stone/gold
	refresh_requirements_and_buttons()

# Load specific building ID and render bonuses & requirements
func load_building_data() -> void:
	var ui = _get_ui_manager()
	if ui and ui.has_method("get_building"):
		building_data = ui.call("get_building", building_id)
	else:
		building_data = _get_local_building(building_id)

	if building_data.is_empty():
		push_error("[Crownspire UpgradeWindow] Building data not found for ID: " + building_id)
		return

	# Update Window Header
	if building_name_label:
		building_name_label.text = building_data.get("name", "Royal Structure").to_upper()
	
	var lvl = int(building_data.get("level", 1))
	var max_lvl = int(building_data.get("max_level", 30))

	if current_level_label:
		current_level_label.text = "Lv.%d" % lvl
	if next_level_label:
		if lvl >= max_lvl:
			next_level_label.text = "MAX"
		else:
			next_level_label.text = "Lv.%d" % (lvl + 1)

	# Dynamic Building Artwork Loading
	if building_image:
		# Premium non-baked artwork path selection
		var art_path = "res://assets/buildings/%s.png" % building_id
		if ResourceLoader.exists(art_path):
			building_image.texture = load(art_path)
		else:
			# elegant fallback structure outline image or empty placeholder representation
			pass

	# Populate Upgrade Bonuses
	_populate_bonuses(lvl, max_lvl)

	# Populate Requirements list
	_populate_requirements(lvl, max_lvl)

# Populate statistical bonus rows
func _populate_bonuses(lvl: int, max_lvl: int) -> void:
	# Clear previous entries
	for child in bonus_container.get_children():
		child.queue_free()

	if lvl >= max_lvl:
		# Show a beautiful max level label
		var max_lbl = Label.new()
		max_lbl.text = "This structure has reached supreme completion. Maximum Level attained."
		max_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		max_lbl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		bonus_container.add_child(max_lbl)
		return

	# 1. Power Increase Bonus (Core AAA strategy feature)
	var power_gain = int(building_data.get("power_per_level", 100) * (1.0 + lvl * 0.1))
	if header_power_gain_label:
		header_power_gain_label.text = "+" + _format_with_commas(power_gain) + " Power"

	var power_bonus = BONUS_ROW_SCENE.instantiate()
	bonus_container.add_child(power_bonus)
	var current_power = int(building_data.get("base_power", 1000)) + int(building_data.get("power_per_level", 100)) * lvl
	var next_power = current_power + power_gain
	power_bonus.setup(
		"Kingdom Might Power", 
		"res://assets/ui/icons/hud_power.png", 
		str(current_power), 
		str(next_power), 
		str(power_gain)
	)

	# 2. Building Unique Special Production / Capacity Bonus
	var current_spec_bonus = building_data.get("current_bonus", "")
	var next_spec_bonus = building_data.get("next_bonus", "")
	if current_spec_bonus != "" and next_spec_bonus != "":
		var spec_bonus = BONUS_ROW_SCENE.instantiate()
		bonus_container.add_child(spec_bonus)
		spec_bonus.setup(
			"Structural Yield Benefit", 
			"res://assets/ui/icons/category_featured.png", 
			current_spec_bonus, 
			next_spec_bonus, 
			""
		)

# Populate upgrade resource and prerequisite entries
func _populate_requirements(lvl: int, max_lvl: int) -> void:
	# Clear old items
	for child in requirements_container.get_children():
		child.queue_free()

	if lvl >= max_lvl:
		var empty_lbl = Label.new()
		empty_lbl.text = "Supreme status requires no further requirements."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		requirements_container.add_child(empty_lbl)
		return

	# Load resources required
	var reqs = building_data.get("resources_required", {})
	
	# Strategical incremental costs based on level
	var multiplier = 1.0 + lvl * 0.15
	var req_food = int(reqs.get("food", 0) * multiplier)
	var req_wood = int(reqs.get("wood", 0) * multiplier)
	var req_stone = int(reqs.get("stone", 0) * multiplier)
	var req_iron = int(reqs.get("iron", 0) * multiplier)

	# Reset crystal calculation
	missing_resources_crystal_cost = 0

	# Spawn requirement rows
	if req_food > 0:
		_add_resource_row("Food Provisions", "food", req_food, "res://assets/ui/icons/res_food.png")
	if req_wood > 0:
		_add_resource_row("Cured Timber Wood", "wood", req_wood, "res://assets/ui/icons/res_wood.png")
	if req_stone > 0:
		_add_resource_row("Obsidian Granite Stone", "stone", req_stone, "res://assets/ui/icons/res_stone.png")
	if req_iron > 0:
		_add_resource_row("Sovereign Iron Ore", "iron", req_iron, "res://assets/ui/icons/res_iron.png")

	# Add any prerequisite buildings
	# (Prereqs dynamically derived: Crystal Citadel lvl needs other resources level, e.g.)
	if building_id == "citadel" and lvl % 2 == 0:
		var target_farm_lvl = int(lvl / 2) + 2
		var actual_farm_lvl = _get_building_level("farm")
		var is_met = actual_farm_lvl >= target_farm_lvl
		
		var pre_row = REQUIREMENT_ROW_SCENE.instantiate()
		requirements_container.add_child(pre_row)
		pre_row.setup(
			"Imperial Wheatlands Lv. %d" % target_farm_lvl,
			"res://assets/ui/icons/category_featured.png",
			"Lv. %d" % actual_farm_lvl,
			"Lv. %d" % target_farm_lvl,
			"",
			is_met,
			"Focus"
		)
		pre_row.action_pressed.connect(func(): _jump_to_building("farm"))

	refresh_requirements_and_buttons()

# Quick helper to add resource rows with validation
func _add_resource_row(display_name: String, resource_id: String, req_amount: int, icon_path: String) -> void:
	var row = REQUIREMENT_ROW_SCENE.instantiate()
	requirements_container.add_child(row)

	var current_amt = _get_player_resource(resource_id)
	var is_met = current_amt >= req_amount
	var missing = 0
	var missing_str = ""
	
	if not is_met:
		missing = req_amount - current_amt
		missing_str = _format_amount(missing)
		# Calculate instant crystal replacement cost (AAA Strategy monetization mechanic)
		var rate = 1000
		if resource_id == "stone": rate = 500
		elif resource_id == "iron": rate = 250
		var cost = max(1, int(missing / rate))
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
	
	# Connect Go/Obtain button callback
	row.action_pressed.connect(func(): _on_obtain_pressed(resource_id))

# Refresh buttons based on updated economics
func refresh_requirements_and_buttons() -> void:
	var lvl = int(building_data.get("level", 1))
	var max_lvl = int(building_data.get("max_level", 30))
	if lvl >= max_lvl:
		if finish_button: finish_button.disabled = true
		if upgrade_button: upgrade_button.disabled = true
		return

	# Evaluate if all resource constraints are met
	var all_met = true
	var reqs = building_data.get("resources_required", {})
	var multiplier = 1.0 + lvl * 0.15
	
	for res_key in reqs.keys():
		var cost = int(reqs[res_key] * multiplier)
		if _get_player_resource(res_key) < cost:
			all_met = false
			break

	# Upgrade button matches availability
	if upgrade_button:
		upgrade_button.disabled = !all_met
		
	# Finish Button dynamically updates with missing resource crystal cost
	if finish_button:
		if missing_resources_crystal_cost > 0:
			finish_button.text = "Finish Now (%d 💎)" % missing_resources_crystal_cost
		else:
			# standard immediate time speedup
			var base_speed_cost = int(building_data.get("upgrade_time_seconds", 300) / 60)
			finish_button.text = "Finish Now (%d 💎)" % max(5, base_speed_cost)

# Format utility (e.g. 150000 -> 150K)
func _format_amount(amt: int) -> String:
	if amt >= 1000000:
		return "%.1fM" % (float(amt) / 1000000.0)
	elif amt >= 1000:
		return "%.1fK" % (float(amt) / 1000.0)
	return str(amt)

# Query actual database states safely
func _get_player_resource(res_id: String) -> int:
	var ui = _get_ui_manager()
	if ui and res_id in ui:
		return int(ui.get(res_id))
	return _local_resources.get(res_id, 0)

func _get_building_level(b_id: String) -> int:
	var b = {}
	var ui = _get_ui_manager()
	if ui and ui.has_method("get_building"):
		b = ui.call("get_building", b_id)
	else:
		b = _get_local_building(b_id)
	return int(b.get("level", 1))

# Handle individual requirement obtain flows
func _on_obtain_pressed(resource_id: String) -> void:
	# Show message about resource obtain channels
	var notification_msg = "Please harvest more %s or complete alliance campaigns to collect resources." % resource_id.capitalize()
	print("[Crownspire UI] Obtain clicked for: " + resource_id)
	
	# Sandbox help feature: grant player 50k of the resource so they can test upgrading!
	var mock_batch = 50000
	var ui = _get_ui_manager()
	if ui and resource_id in ui:
		ui.set(resource_id, int(ui.get(resource_id)) + mock_batch)
		if ui.has_method("show_toast"):
			ui.call("show_toast", "+50K %s Granted!" % resource_id.capitalize())
	else:
		_local_resources[resource_id] = _local_resources.get(resource_id, 0) + mock_batch
	
	# Update
	load_building_data()

func _jump_to_building(b_id: String) -> void:
	print("[Crownspire UI] Jumper focus request on building ID: " + b_id)
	# Switch current edit selection
	building_id = b_id
	load_building_data()

# Close upgrade window popup
func _on_close_button_pressed() -> void:
	if animation_player and animation_player.has_animation("close_fade"):
		animation_player.play("close_fade")
		await animation_player.animation_finished
	
	var ui = _get_ui_manager()
	if ui:
		if ui.has_method("close_popup"):
			ui.call("close_popup", self)
		elif ui.has_method("close_window"):
			ui.call("close_window", self)
	else:
		queue_free()

# Execute upgrade building standard flow
func _on_upgrade_button_pressed() -> void:
	var result = {}
	var ui = _get_ui_manager()
	if ui and ui.has_method("upgrade_building"):
		result = ui.call("upgrade_building", building_id)
	else:
		result = _local_upgrade_building(building_id)

	if result.get("success", false):
		_show_celebration_overlay(
			"STRUCTURE UPGRADED",
			"Congratulations, my Lord! Your %s has been upgraded to Level %d, expanding your empire's administrative scope and capacity." % [building_data.get("name", ""), int(building_data.get("level", 1)) + 1]
		)
		load_building_data()
	else:
		# error visual feedback
		if animation_player and animation_player.has_animation("error_shake"):
			animation_player.play("error_shake")

# Execute instant buy/finish upgrade via premium crystals
func _on_finish_button_pressed() -> void:
	var cost = missing_resources_crystal_cost
	if cost <= 0:
		# default time-based finish cost
		cost = max(5, int(building_data.get("upgrade_time_seconds", 300) / 60))

	var current_crystals = 0
	var ui = _get_ui_manager()
	if ui and "royal_crystals" in ui:
		current_crystals = int(ui.get("royal_crystals"))
	else:
		current_crystals = _local_resources.get("royal_crystals", 0)

	if current_crystals >= cost:
		# Deduct premium crystals
		if ui and "royal_crystals" in ui:
			ui.set("royal_crystals", current_crystals - cost)
		else:
			_local_resources["royal_crystals"] = current_crystals - cost
		
		# Give missing materials so the core engine can succeed
		var lvl = int(building_data.get("level", 1))
		var reqs = building_data.get("resources_required", {})
		var multiplier = 1.0 + lvl * 0.15
		
		for res_key in reqs.keys():
			var req_val = int(reqs[res_key] * multiplier)
			var current = _get_player_resource(res_key)
			if current < req_val:
				# credit the difference
				var diff = req_val - current
				if ui and res_key in ui:
					ui.set(res_key, int(ui.get(res_key)) + diff)
				else:
					_local_resources[res_key] = _local_resources.get(res_key, 0) + diff

		# Perform upgrade
		var result = {}
		if ui and ui.has_method("upgrade_building"):
			result = ui.call("upgrade_building", building_id)
		else:
			result = _local_upgrade_building(building_id)

		if result.get("success", false):
			_show_celebration_overlay(
				"IMMEDIATE UPGRADE COMPLETE",
				"Instant Crystal Construction finished! Your %s has immediately reached Level %d. The realm flourishes under your gold-rimmed wisdom." % [building_data.get("name", ""), int(building_data.get("level", 1)) + 1]
			)
			load_building_data()
	else:
		# insufficient premium currency shake animation
		if animation_player and animation_player.has_animation("error_shake"):
			animation_player.play("error_shake")

# Show beautiful stylized completion overlay with gold text
func _show_celebration_overlay(title: String, desc: String) -> void:
	if celebration_panel:
		celebration_title.text = title.to_upper()
		celebration_desc.text = desc
		celebration_panel.visible = true
		
		# Play dynamic entrance animation
		celebration_panel.modulate.a = 0.0
		var tw = create_tween()
		tw.tween_property(celebration_panel, "modulate:a", 1.0, 0.3)

func _on_celebration_close_pressed() -> void:
	if celebration_panel:
		var tw = create_tween()
		tw.tween_property(celebration_panel, "modulate:a", 0.0, 0.2)
		await tw.finished
		celebration_panel.visible = false

# Fallback local dictionary builder
func _get_local_building(b_id: String) -> Dictionary:
	if _local_buildings_cache.is_empty():
		var path = "res://data/buildings.json"
		if FileAccess.file_exists(path):
			var file = FileAccess.open(path, FileAccess.READ)
			if file:
				var json = JSON.new()
				if json.parse(file.get_as_text()) == OK:
					var data = json.get_data()
					if data is Array:
						_local_buildings_cache = data
		if _local_buildings_cache.is_empty():
			# Ultra fallback
			_local_buildings_cache = [
				{
					"id": "citadel",
					"name": "Crystal Citadel",
					"level": 1,
					"max_level": 30,
					"base_power": 10000,
					"power_per_level": 2500,
					"resources_required": {"food": 50000, "wood": 60000, "stone": 30000, "iron": 10000},
					"upgrade_time_seconds": 300,
					"current_bonus": "Max Troop Tier: I",
					"next_bonus": "Max Troop Tier: II"
				},
				{
					"id": "farm",
					"name": "Imperial Wheatlands",
					"level": 1,
					"max_level": 30,
					"base_power": 1000,
					"power_per_level": 200,
					"resources_required": {"food": 10000, "wood": 15000, "stone": 5000},
					"upgrade_time_seconds": 120,
					"current_bonus": "1.5K Food / Hour",
					"next_bonus": "2.2K Food / Hour"
				}
			]
			
	for b in _local_buildings_cache:
		if b is Dictionary and b.get("id", "") == b_id:
			return b
	return {}

func _local_upgrade_building(b_id: String) -> Dictionary:
	var b = _get_local_building(b_id)
	if b.is_empty():
		return {"success": false, "error": "Building not found"}
		
	var lvl = int(b.get("level", 1))
	var max_lvl = int(b.get("max_level", 30))
	if lvl >= max_lvl:
		return {"success": false, "error": "Max level reached"}
		
	# Deduct resources
	var reqs = b.get("resources_required", {})
	var multiplier = 1.0 + lvl * 0.15
	for res_key in reqs.keys():
		var cost = int(reqs[res_key] * multiplier)
		_local_resources[res_key] = max(0, _local_resources.get(res_key, 0) - cost)
		
	# Increment level
	b["level"] = lvl + 1
	refresh_requirements_and_buttons()
	return {"success": true}

func _format_with_commas(value: int) -> String:
	var s = str(value)
	var result = ""
	var length = s.length()
	for i in range(length):
		if i > 0 and (length - i) % 3 == 0:
			result += ","
		result += s[i]
	return result
