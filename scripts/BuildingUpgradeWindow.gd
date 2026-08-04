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
var speedup_button: Button = null

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
var _building_name_to_id: Dictionary = {}
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
	_ensure_speedup_button()

	load_building_data()

	var ui = _get_ui_manager()
	if ui and ui.has_signal("currency_changed"):
		ui.currency_changed.connect(_on_currency_changed)

	if has_node("/root/ConstructionState"):
		if not ConstructionState.construction_jobs_changed.is_connected(_on_construction_jobs_changed):
			ConstructionState.construction_jobs_changed.connect(_on_construction_jobs_changed)
		if not ConstructionState.construction_completed.is_connected(_on_construction_completed):
			ConstructionState.construction_completed.connect(_on_construction_completed)


func _process(_delta: float) -> void:
	if visible and has_node("/root/ConstructionState"):
		if ConstructionState.is_building_upgrading(building_id) or not ConstructionState.has_free_construction_queue():
			refresh_requirements_and_buttons()


func _on_construction_jobs_changed() -> void:
	if visible:
		refresh_requirements_and_buttons()


func _on_construction_completed(completed_id: String, _new_level: int) -> void:
	if visible and (completed_id == building_id or true):
		load_building_data()
		_notify_city_buildings()


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
	var job: Dictionary = {}
	if has_node("/root/ConstructionState"):
		job = ConstructionState.get_job_for(building_id)

	if not job.is_empty():
		var from_lv: int = int(job.get("from_level", lvl))
		var to_lv: int = int(job.get("target_level", lvl + 1))
		current_level_label.text = "Lv. %d" % from_lv
		next_level_label.text = "Lv. %d" % to_lv
		if level_arrow:
			level_arrow.text = "UPGRADING"
	else:
		current_level_label.text = "Lv. %d" % lvl
		if lvl >= max_lvl:
			next_level_label.text = "MAX"
		else:
			next_level_label.text = "Lv. %d" % (lvl + 1)
		if level_arrow:
			level_arrow.text = "→"

	if building_image:
		var art_path := "res://assets/buildings/%s.png" % building_id
		if ResourceLoader.exists(art_path):
			building_image.texture = load(art_path)

	_populate_bonuses(lvl, max_lvl)
	_populate_requirements(lvl, max_lvl)
	refresh_requirements_and_buttons()


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

	var target_level: int = mini(lvl + 1, max_lvl)
	if _normalize_building_id(building_id) != "castle":
		_add_castle_cap_prerequisite_row(target_level)

	var building_prereqs: Array = building_data.get("prerequisites", [])
	for prereq_entry: Variant in building_prereqs:
		var parsed: Dictionary = _parse_prerequisite_entry(prereq_entry)
		if bool(parsed.get("ok", false)) and str(parsed.get("building_id", "")) == "castle":
			continue
		_add_building_prerequisite_row(prereq_entry)

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

	# Both sides use the same formatter on absolute units (affordability uses these ints).
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


func _add_castle_cap_prerequisite_row(required_castle_level: int) -> void:
	var have_lvl: int = _get_prerequisite_building_level("castle")
	var is_met: bool = have_lvl >= required_castle_level
	var missing_str := ""
	if not is_met:
		missing_str = "Lv. %d" % required_castle_level

	var row = REQUIREMENT_ROW_SCENE.instantiate()
	requirements_container.add_child(row)
	row.setup(
		"Citadel Keep",
		"res://assets/ui/icons/hud_power.png",
		"Lv. %d" % have_lvl,
		"Lv. %d" % required_castle_level,
		missing_str,
		is_met,
		""
	)


func _add_building_prerequisite_row(prereq_entry: Variant) -> void:
	var parsed: Dictionary = _parse_prerequisite_entry(prereq_entry)
	var row = REQUIREMENT_ROW_SCENE.instantiate()
	requirements_container.add_child(row)

	if not bool(parsed.get("ok", false)):
		row.setup(
			"Building Requirement",
			"res://assets/ui/icons/category_featured.png",
			"—",
			str(parsed.get("display", "Invalid")),
			"Invalid",
			false,
			""
		)
		return

	var bid: String = str(parsed.get("building_id", ""))
	var need_lvl: int = int(parsed.get("required_level", 1))
	var have_lvl: int = _get_prerequisite_building_level(bid)
	var is_met: bool = have_lvl >= need_lvl
	var display_name: String = str(parsed.get("building_name", bid))
	var missing_str := ""
	if not is_met:
		missing_str = "Lv. %d" % need_lvl

	row.setup(
		display_name,
		"res://assets/ui/icons/category_featured.png",
		"Lv. %d" % have_lvl,
		"Lv. %d" % need_lvl,
		missing_str,
		is_met,
		""
	)


func refresh_requirements_and_buttons() -> void:
	var lvl := int(building_data.get("level", 1))
	var max_lvl := int(building_data.get("max_level", 30))

	if lvl >= max_lvl:
		if finish_button:
			finish_button.disabled = true
		if upgrade_button:
			upgrade_button.disabled = true
			upgrade_button.text = "MAX LEVEL"
		return

	var all_met := true
	var reqs = building_data.get("resources_required", {})

	for res_key in reqs.keys():
		var required_amount := int(reqs[res_key])
		if _get_player_resource(res_key) < required_amount:
			all_met = false
			break

	var prereq_gate: Dictionary = _evaluate_upgrade_prerequisites(
		building_id,
		lvl,
		building_data.get("prerequisites", [])
	)
	var prereqs_met: bool = bool(prereq_gate.get("ok", true))

	var this_upgrading := false
	var queue_full := false
	if has_node("/root/ConstructionState"):
		this_upgrading = ConstructionState.is_building_upgrading(building_id)
		queue_full = not ConstructionState.has_free_construction_queue() and not this_upgrading

	if upgrade_button:
		if this_upgrading:
			var job: Dictionary = ConstructionState.get_job_for(building_id)
			var rem: float = float(job.get("time_remaining", 0.0))
			upgrade_button.text = "Upgrading… %s" % _format_secs(rem)
			upgrade_button.disabled = true
		elif queue_full:
			upgrade_button.text = "Construction Queue Full"
			upgrade_button.disabled = true
		else:
			upgrade_button.text = "Upgrade"
			upgrade_button.disabled = not all_met or not prereqs_met

	if finish_button:
		if missing_resources_crystal_cost > 0:
			finish_button.text = "Finish Now (%d 💎)" % missing_resources_crystal_cost
		else:
			var base_speed_cost := int(float(building_data.get("upgrade_time_seconds", 300)) / 60.0)
			finish_button.text = "Finish Now (%d 💎)" % max(5, base_speed_cost)
		# Finish Now blocked when another building occupies the only queue slot.
		finish_button.disabled = (queue_full and not this_upgrading) or not prereqs_met

	if speedup_button:
		# Enabled whenever a real construction timer is running — even with 0 bag speedups.
		var rem: float = 0.0
		if this_upgrading and has_node("/root/ConstructionState"):
			rem = ConstructionState.get_remaining_seconds(building_id)
		var can_speedup: bool = this_upgrading and rem > 0.0
		speedup_button.visible = this_upgrading
		speedup_button.disabled = not can_speedup
		_apply_speedup_button_visuals(can_speedup)


func _ensure_speedup_button() -> void:
	if speedup_button != null and is_instance_valid(speedup_button):
		return
	var footer: Node = null
	if finish_button != null:
		footer = finish_button.get_parent()
	elif upgrade_button != null:
		footer = upgrade_button.get_parent()
	if footer == null:
		return
	speedup_button = Button.new()
	speedup_button.name = "SpeedUpButton"
	speedup_button.text = "SPEED UP"
	speedup_button.custom_minimum_size = Vector2(0, 48)
	speedup_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speedup_button.visible = false
	speedup_button.pressed.connect(_on_speedup_button_pressed)
	_apply_speedup_button_visuals(true)
	# Insert before Finish so SPEED UP is the primary action while upgrading.
	if finish_button != null and finish_button.get_index() >= 0:
		footer.add_child(speedup_button)
		footer.move_child(speedup_button, finish_button.get_index())
	else:
		footer.add_child(speedup_button)


func _apply_speedup_button_visuals(active: bool) -> void:
	## Active = Crownspire sapphire/blue (same family as Upgrade). Disabled = muted gray.
	if speedup_button == null:
		return
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	var pressed := StyleBoxFlat.new()
	var disabled := StyleBoxFlat.new()
	for sb: StyleBoxFlat in [normal, hover, pressed, disabled]:
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		sb.set_corner_radius_all(6)
		sb.border_width_bottom = 3
	if active:
		normal.bg_color = Color(0.13, 0.26, 0.46, 1)
		normal.border_color = Color(0.08, 0.18, 0.32, 1)
		hover.bg_color = Color(0.18, 0.35, 0.6, 1)
		hover.border_color = Color(0.1, 0.23, 0.42, 1)
		pressed.bg_color = Color(0.10, 0.20, 0.38, 1)
		pressed.border_color = Color(0.06, 0.14, 0.28, 1)
		speedup_button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		speedup_button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		speedup_button.add_theme_color_override("font_pressed_color", Color(0.95, 0.95, 1, 1))
	else:
		normal.bg_color = Color(0.55, 0.58, 0.62, 1)
		normal.border_color = Color(0.42, 0.45, 0.48, 1)
		hover.bg_color = normal.bg_color
		hover.border_color = normal.border_color
		pressed.bg_color = normal.bg_color
		pressed.border_color = normal.border_color
		speedup_button.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, 1))
	disabled.bg_color = Color(0.70, 0.73, 0.76, 1)
	disabled.border_color = Color(0.55, 0.58, 0.61, 1)
	speedup_button.add_theme_stylebox_override("normal", normal)
	speedup_button.add_theme_stylebox_override("hover", hover)
	speedup_button.add_theme_stylebox_override("pressed", pressed)
	speedup_button.add_theme_stylebox_override("disabled", disabled)
	speedup_button.add_theme_color_override("font_disabled_color", Color(0.78, 0.80, 0.82, 1))


func _on_speedup_button_pressed() -> void:
	if not has_node("/root/SpeedupService"):
		return
	if not ConstructionState.is_building_upgrading(building_id):
		return
	# Always open — popup shows empty state + debug grants when bag has no speedups.
	SpeedupService.open_speedup_popup(SpeedupService.CAT_CONSTRUCTION, building_id)


func _format_secs(seconds: float) -> String:
	var s: int = maxi(0, int(ceil(seconds)))
	var m: int = s / 60
	var r: int = s % 60
	if m > 0:
		return "%dm %02ds" % [m, r]
	return "%ds" % r

func _get_player_resource(res_id: String) -> int:
	# Canonical Food/Wood/Stone/Iron live on GameState (same as Top HUD).
	match res_id:
		"food":
			return int(GameState.food)
		"wood":
			return int(GameState.wood)
		"stone":
			return int(GameState.stone)
		"iron":
			return int(GameState.iron)
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
	match resource_id:
		"food":
			GameState.add_food(mock_batch)
		"wood":
			GameState.add_wood(mock_batch)
		"stone":
			GameState.add_stone(mock_batch)
		"iron":
			GameState.add_iron(mock_batch)
		_:
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


func _pulse_construction_queue_hud() -> void:
	var hud: Node = get_tree().root.find_child("GameHUD", true, false)
	if hud != null and hud.has_method("pulse_queue_status"):
		hud.call("pulse_queue_status", "construction")


func _on_upgrade_button_pressed() -> void:
	# Timed start only — never apply target level here.
	var result := _start_timed_construction(building_id)

	if result.get("success", false):
		_show_celebration_overlay(
			"CONSTRUCTION STARTED",
			"%s remains Lv. %d while upgrading to Lv. %d.\nRemaining: %s" % [
				building_data.get("name", "Building"),
				int(result.get("from_level", 1)),
				int(result.get("target_level", 1)),
				_format_secs(float(result.get("duration", 0.0))),
			]
		)
		load_building_data()
	else:
		var err: String = str(result.get("error", "Unknown error"))
		push_warning("[Crownspire UpgradeWindow] Upgrade failed: " + err)
		if _is_prerequisite_failure_message(err):
			_show_celebration_overlay("REQUIREMENTS NOT MET", err)
		if upgrade_button and err == "Construction Queue Full":
			upgrade_button.text = "Construction Queue Full"
			upgrade_button.disabled = true
			_pulse_construction_queue_hud()
		if animation_player and animation_player.has_animation("error_shake"):
			animation_player.play("error_shake")


func _on_finish_button_pressed() -> void:
	# Finish must complete through ConstructionState only (no direct level += 1).
	if not has_node("/root/ConstructionState"):
		push_warning("[Crownspire UpgradeWindow] ConstructionState missing.")
		return

	# Case 1: active job for this building → finish it now (beta free instant complete).
	if ConstructionState.is_building_upgrading(building_id):
		var cost := missing_resources_crystal_cost
		if cost <= 0:
			cost = max(5, int(float(building_data.get("upgrade_time_seconds", 300)) / 60.0))
		if not _try_spend_crystals(cost):
			if animation_player and animation_player.has_animation("error_shake"):
				animation_player.play("error_shake")
			return
		var finished: Dictionary = ConstructionState.finish_construction_now(building_id)
		if bool(finished.get("ok", false)):
			_show_celebration_overlay(
				"IMMEDIATE UPGRADE COMPLETE",
				"%s has reached Level %d." % [
					building_data.get("name", "Building"),
					int(finished.get("new_level", 1))
				]
			)
			load_building_data()
			_notify_city_buildings()
		return

	# Case 2: no job — queue must be free, then start + immediately complete via CS.
	var gate: Dictionary = ConstructionState.can_start_construction(building_id)
	if not bool(gate.get("ok", false)):
		if upgrade_button:
			upgrade_button.text = "Construction Queue Full"
			upgrade_button.disabled = true
		if animation_player and animation_player.has_animation("error_shake"):
			animation_player.play("error_shake")
		return

	var cost2 := missing_resources_crystal_cost
	if cost2 <= 0:
		cost2 = max(5, int(float(building_data.get("upgrade_time_seconds", 300)) / 60.0))
	var crystals_before := _get_player_resource("royal_crystals")
	if not _try_spend_crystals(cost2):
		if animation_player and animation_player.has_animation("error_shake"):
			animation_player.play("error_shake")
		return

	var started: Dictionary = _start_timed_construction(building_id)
	if not started.get("success", false):
		_set_player_resource("royal_crystals", crystals_before)
		var start_err: String = str(started.get("error", ""))
		push_warning("[Crownspire UpgradeWindow] Finish start failed: " + start_err)
		if _is_prerequisite_failure_message(start_err):
			_show_celebration_overlay("REQUIREMENTS NOT MET", start_err)
		return

	var finished2: Dictionary = ConstructionState.finish_construction_now(building_id)
	if bool(finished2.get("ok", false)):
		_show_celebration_overlay(
			"IMMEDIATE UPGRADE COMPLETE",
			"%s has reached Level %d." % [
				building_data.get("name", "Building"),
				int(finished2.get("new_level", 1))
			]
		)
		load_building_data()
		_notify_city_buildings()
	else:
		_set_player_resource("royal_crystals", crystals_before)


func _try_spend_crystals(cost: int) -> bool:
	var current_crystals := _get_player_resource("royal_crystals")
	if current_crystals < cost:
		return false
	_set_player_resource("royal_crystals", current_crystals - cost)
	return true


func _set_player_resource(res_id: String, amount: int) -> void:
	# Prefer GameState for basic resources so Top HUD stays in sync.
	match res_id:
		"food":
			GameState.food = maxi(0, amount)
			GameState.save_resources()
			GameState.resources_changed.emit()
			return
		"wood":
			GameState.wood = maxi(0, amount)
			GameState.save_resources()
			GameState.resources_changed.emit()
			return
		"stone":
			GameState.stone = maxi(0, amount)
			GameState.save_resources()
			GameState.resources_changed.emit()
			return
		"iron":
			GameState.iron = maxi(0, amount)
			GameState.save_resources()
			GameState.resources_changed.emit()
			return
	var ui := _get_ui_manager()
	if ui and ui.get(res_id) != null:
		ui.set(res_id, amount)
	else:
		_local_resources[res_id] = amount


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
	## Canonical compact formatter — same rules as GameHUD.format_number.
	## Uses absolute resource units from buildings.json / GameState (NOT implied-thousands).
	## Example: cost 68 → "68"; owned 46000 → "46.0K".
	var hud: Node = get_tree().root.find_child("GameHUD", true, false) if get_tree() else null
	if hud != null and hud.has_method("format_number"):
		return str(hud.call("format_number", amt))
	# Fallback mirrors GameHUD (incl. billions).
	if amt >= 1000000000:
		return "%.1fB" % (float(amt) / 1000000000.0)
	if amt >= 1000000:
		return "%.1fM" % (float(amt) / 1000000.0)
	if amt >= 1000:
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

func _ensure_building_name_map() -> void:
	if not _building_name_to_id.is_empty():
		return
	_ensure_buildings_cache_loaded()
	for raw_id: Variant in _local_buildings_cache.keys():
		var bid: String = str(raw_id)
		var template: Dictionary = _local_buildings_cache[bid] as Dictionary
		var display_name: String = str(template.get("name", "")).strip_edges().to_lower()
		if not display_name.is_empty():
			_building_name_to_id[display_name] = bid
	# Common prerequisite spellings from buildings.json.
	_building_name_to_id["citadel keep"] = "castle"
	_building_name_to_id["citadel"] = "castle"
	_building_name_to_id["wanderers farm"] = "farm"
	_building_name_to_id["timber woodmill"] = "lumber_mill"
	_building_name_to_id["slate quarry"] = "quarry"
	_building_name_to_id["deep iron shaft"] = "iron_mine"
	_building_name_to_id["vault warehouse"] = "warehouse"
	_building_name_to_id["research hall"] = "academy"
	_building_name_to_id["sacred hospital"] = "hospital"
	_building_name_to_id["imperial embassy"] = "embassy"
	_building_name_to_id["sentry watchtower"] = "watchtower"


func _ensure_buildings_cache_loaded() -> void:
	if not _local_buildings_cache.is_empty():
		return
	var path := "res://data/buildings.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_local_buildings_cache = parsed as Dictionary


func _parse_prerequisite_entry(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_STRING:
		return {"ok": false, "display": "Invalid prerequisite", "error": "not_string"}
	var text: String = str(raw).strip_edges()
	if text.is_empty():
		return {"ok": false, "display": "Empty prerequisite", "error": "empty"}

	var re := RegEx.new()
	if re.compile("(?i)^(.+?)\\s+(?:lvl|level)\\.?\\s*(\\d+)\\s*$") != OK:
		return {"ok": false, "display": text, "error": "regex_failed"}
	var match: RegExMatch = re.search(text)
	if match == null:
		return {"ok": false, "display": text, "error": "unrecognized_format"}

	var name_part: String = match.get_string(1).strip_edges()
	var req_level: int = int(match.get_string(2))
	if req_level <= 0:
		return {"ok": false, "display": text, "error": "invalid_level"}

	var bid: String = _resolve_prerequisite_building_id(name_part)
	if bid.is_empty():
		return {"ok": false, "display": text, "error": "unknown_building"}

	return {
		"ok": true,
		"building_id": bid,
		"required_level": req_level,
		"building_name": name_part,
		"display": text,
	}


func _resolve_prerequisite_building_id(name_part: String) -> String:
	_ensure_building_name_map()
	var key: String = name_part.strip_edges().to_lower()
	if _building_name_to_id.has(key):
		return _normalize_building_id(str(_building_name_to_id[key]))
	var snake_guess: String = _normalize_building_id(key.replace(" ", "_"))
	if _local_buildings_cache.has(snake_guess):
		return snake_guess
	return ""


func _get_prerequisite_building_level(building_id: String) -> int:
	var bid: String = _normalize_building_id(building_id)
	if bid.is_empty():
		return 0
	if has_node("/root/ConstructionState") and ConstructionState.has_method("get_canonical_building_level"):
		return maxi(0, int(ConstructionState.get_canonical_building_level(bid)))
	return 0


func _evaluate_upgrade_prerequisites(
	building_id_for_cap: String,
	current_level: int,
	prereqs: Variant
) -> Dictionary:
	var json_gate: Dictionary = _evaluate_building_prerequisites(prereqs)
	if not bool(json_gate.get("ok", false)):
		return json_gate
	if _normalize_building_id(building_id_for_cap) == "castle":
		return json_gate

	var target_level: int = current_level + 1
	if has_node("/root/ConstructionState") and ConstructionState.has_method("check_castle_level_cap"):
		var cap: Dictionary = ConstructionState.check_castle_level_cap(
			building_id_for_cap,
			target_level
		)
		if not bool(cap.get("ok", false)):
			return {
				"ok": false,
				"unmet": [{
					"display": "Citadel Keep Lv. %d" % int(cap.get("required_castle_level", target_level)),
					"building_id": "castle",
					"have": int(cap.get("current_castle_level", 0)),
					"need": int(cap.get("required_castle_level", target_level)),
					"building_name": "Citadel Keep",
				}],
				"invalid": PackedStringArray(),
			}
	return {"ok": true, "unmet": [], "invalid": []}


func _evaluate_building_prerequisites(prereqs: Variant) -> Dictionary:
	if prereqs == null:
		return {"ok": true, "unmet": [], "invalid": []}
	if typeof(prereqs) != TYPE_ARRAY:
		return {
			"ok": false,
			"unmet": [],
			"invalid": ["Prerequisites must be a list."],
		}

	var unmet: Array = []
	var invalid: PackedStringArray = PackedStringArray()
	for entry: Variant in prereqs as Array:
		var parsed: Dictionary = _parse_prerequisite_entry(entry)
		if not bool(parsed.get("ok", false)):
			invalid.append(str(parsed.get("display", entry)))
			continue
		var bid: String = str(parsed.get("building_id", ""))
		var need: int = int(parsed.get("required_level", 1))
		var have: int = _get_prerequisite_building_level(bid)
		if have < need:
			unmet.append({
				"display": str(parsed.get("display", "")),
				"building_id": bid,
				"have": have,
				"need": need,
				"building_name": str(parsed.get("building_name", bid)),
			})

	return {
		"ok": unmet.is_empty() and invalid.is_empty(),
		"unmet": unmet,
		"invalid": invalid,
	}


func _format_prerequisite_failure(gate: Dictionary) -> String:
	var invalid: PackedStringArray = gate.get("invalid", PackedStringArray()) as PackedStringArray
	if not invalid.is_empty():
		return "Upgrade blocked: invalid prerequisite data (%s)." % ", ".join(invalid)

	var unmet: Array = gate.get("unmet", []) as Array
	if unmet.is_empty():
		return "Upgrade blocked: building requirements not met."

	var lines: PackedStringArray = PackedStringArray()
	for item: Variant in unmet:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item as Dictionary
		lines.append(
			"%s Lv. %d (current Lv. %d)" % [
				str(d.get("building_name", d.get("display", "Building"))),
				int(d.get("need", 1)),
				int(d.get("have", 0)),
			]
		)
	return "Requires:\n" + "\n".join(lines)


func _format_castle_cap_failure(cap: Dictionary) -> String:
	return "Requires:\nCitadel Keep Lv. %d (current Lv. %d)" % [
		int(cap.get("required_castle_level", 1)),
		int(cap.get("current_castle_level", 0)),
	]


func _is_prerequisite_failure_message(err: String) -> bool:
	return (
		err.begins_with("Requires:")
		or err.begins_with("Upgrade blocked:")
		or err.contains("Citadel Keep Lv.")
	)


func _load_saved_building_level(
	b_id: String,
	_display_name: String
) -> int:
	# Phase 0B2-A: canonical ConstructionState authority only.
	# Display-name / legacy cfg sections are never used as level authority.
	var id_key: String = _normalize_building_id(b_id)
	if id_key.is_empty():
		return 1
	if has_node("/root/ConstructionState") and ConstructionState.has_method("get_canonical_building_level"):
		return maxi(1, int(ConstructionState.get_canonical_building_level(id_key)))
	return 1

func _local_upgrade_building(b_id: String) -> Dictionary:
	# Legacy name — starts a TIMED job only. Level applies on ConstructionState completion.
	return _start_timed_construction(b_id)


## Deduct resources once and start a timed ConstructionState job.
## NEVER writes the target building level here.
func _start_timed_construction(b_id: String) -> Dictionary:
	if not has_node("/root/ConstructionState"):
		return {"success": false, "error": "ConstructionState missing"}

	var b := _get_local_building(b_id)
	if b.is_empty():
		return {"success": false, "error": "Building not found"}

	var lvl := int(b.get("level", 1))
	var max_lvl := int(b.get("max_level", 40))
	if lvl >= max_lvl:
		return {"success": false, "error": "Max level reached"}

	if ConstructionState.is_building_upgrading(b_id):
		return {"success": false, "error": "Already upgrading."}

	var gate: Dictionary = ConstructionState.can_start_construction(b_id)
	if not bool(gate.get("ok", false)):
		return {"success": false, "error": str(gate.get("reason", "Construction Queue Full"))}

	var prereq_gate: Dictionary = _evaluate_upgrade_prerequisites(
		b_id,
		lvl,
		b.get("prerequisites", [])
	)
	if not bool(prereq_gate.get("ok", false)):
		return {
			"success": false,
			"error": _format_prerequisite_failure(prereq_gate),
		}

	var target_level := lvl + 1
	if has_node("/root/ConstructionState"):
		var cap: Dictionary = ConstructionState.check_castle_level_cap(b_id, target_level)
		if not bool(cap.get("ok", false)):
			return {
				"success": false,
				"error": _format_castle_cap_failure(cap),
			}

	var reqs: Dictionary = b.get("resources_required", {})
	var food_cost := int(reqs.get("food", 0))
	var wood_cost := int(reqs.get("wood", 0))
	var stone_cost := int(reqs.get("stone", 0))
	var iron_cost := int(reqs.get("iron", 0))
	for res_key in reqs.keys():
		var resource_id := str(res_key)
		var required_amount := int(reqs[res_key])
		if _get_player_resource(resource_id) < required_amount:
			return {"success": false, "error": "Not enough %s" % resource_id.capitalize()}

	# Deduct resources exactly once at start via canonical GameState wallet.
	if not GameState.spend_resources(food_cost, wood_cost, stone_cost, iron_cost):
		return {"success": false, "error": "Not enough resources"}

	# Non-basic costs (e.g. valor) still spend through crystal/UIManager wallet.
	var extra_spent: Dictionary = {}
	for res_key in reqs.keys():
		var resource_id := str(res_key)
		if resource_id in ["food", "wood", "stone", "iron"]:
			continue
		var required_amount := int(reqs[res_key])
		if required_amount <= 0:
			continue
		_set_player_resource(resource_id, _get_player_resource(resource_id) - required_amount)
		extra_spent[resource_id] = required_amount

	var duration: float = float(b.get("upgrade_time_seconds", building_data.get("upgrade_time_seconds", 300)))
	if duration <= 0.0:
		duration = 30.0

	var started: Dictionary = ConstructionState.start_construction(b_id, lvl, target_level, duration)
	if not bool(started.get("ok", false)):
		# Refund on reject (queue full / race).
		if food_cost > 0:
			GameState.add_food(food_cost)
		if wood_cost > 0:
			GameState.add_wood(wood_cost)
		if stone_cost > 0:
			GameState.add_stone(stone_cost)
		if iron_cost > 0:
			GameState.add_iron(iron_cost)
		for rid3 in extra_spent.keys():
			_set_player_resource(str(rid3), _get_player_resource(str(rid3)) + int(extra_spent[rid3]))
		return {"success": false, "error": str(started.get("reason", "Construction Queue Full"))}

	return {
		"success": true,
		"from_level": lvl,
		"target_level": target_level,
		"duration": duration,
	}
