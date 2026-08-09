extends Control

# Crownspire Academy Research Window (AAA Mobile Portrait compliant)
# Fully ports the AcademyResearchScene.tsx React prototype into a high-fidelity Godot 4.6 scene.

const RESEARCH_NODE_SCENE = preload("res://Scenes/ResearchNode.tscn")

# Node References
@onready var dark_overlay: ColorRect = $DarkOverlay
@onready var main_panel: PanelContainer = $MainPanel

# Resources Bar
@onready var food_label: Label = %FoodLabel
@onready var wood_label: Label = %WoodLabel
@onready var stone_label: Label = %StoneLabel
@onready var iron_label: Label = %IronLabel
@onready var valor_label: Label = %ValorLabel

# Tab Buttons
@onready var btn_economy: Button = %BtnEconomy
@onready var btn_military: Button = %BtnMilitary
@onready var btn_development: Button = %BtnDevelopment
@onready var btn_alliance: Button = %BtnAlliance
@onready var btn_hero: Button = %BtnHero

# Zoom controls
@onready var btn_zoom_out: Button = %BtnZoomOut
@onready var btn_zoom_reset: Button = %BtnZoomReset
@onready var btn_zoom_in: Button = %BtnZoomIn

# Canvas Area
@onready var scroll_container: ScrollContainer = %ResearchScrollContainer
@onready var zoom_wrapper: Control = %ZoomWrapper
@onready var connection_layer: Control = %ConnectionLayer
@onready var nodes_container: Control = %NodesContainer

# Details Sidebar
@onready var inspect_panel: VBoxContainer = %InspectPanel
@onready var empty_inspect_lbl: Label = %EmptyInspectLabel

# Active Labs Panel
@onready var active_labs_box: VBoxContainer = %ActiveLabsBox
@onready var active_project_box: PanelContainer = %ActiveProjectBox
@onready var active_project_title: Label = %ActiveProjectTitle
@onready var active_project_desc: Label = %ActiveProjectDesc
@onready var active_project_timer: Label = %ActiveProjectTimer
@onready var active_progress_bar: ProgressBar = %ActiveProgressBar
@onready var btn_instant_valor: Button = %BtnInstantValor
@onready var btn_cancel_active: Button = %BtnCancelActive
@onready var speedup_container: GridContainer = %SpeedupContainer
@onready var active_project_empty_lbl: Label = %ActiveProjectEmptyLabel

# Queue List
@onready var queue_label: Label = %QueueLabel
@onready var queue_list: VBoxContainer = %QueueList

# Detailed Card Info
@onready var card_panel: PanelContainer = %CardPanel
@onready var card_title: Label = %CardTitle
@onready var card_description: Label = %CardDescription
@onready var active_bonus_lbl: Label = %ActiveBonusLabel
@onready var next_bonus_lbl: Label = %NextBonusLabel

# Requirements & Costs
@onready var reqs_box: VBoxContainer = %ReqsBox
@onready var cost_food_lbl: Label = %CostFoodLabel
@onready var cost_wood_lbl: Label = %CostWoodLabel
@onready var cost_stone_lbl: Label = %CostStoneLabel
@onready var cost_iron_lbl: Label = %CostIronLabel
@onready var cost_valor_lbl: Label = %CostValorLabel
@onready var research_time_lbl: Label = %ResearchTimeLabel

# Core Upgrade Buttons
@onready var btn_start_research: Button = %BtnStartResearch
@onready var btn_close: Button = %BtnClose
@onready var academy_level_badge: Label = %AcademyLevelBadge

# State variables
var database: Array = []
var active_category: String = "Economy"
var selected_node_id: String = ""
var zoom_level: float = 1.0
var canvas_dimensions: Vector2 = Vector2(1200, 600)

## Mobile navigation: HOME → CATEGORY → DETAIL
enum MobilePage { HOME, CATEGORY, DETAIL }
const MOBILE_CATEGORIES: Array[Dictionary] = [
	{"id": "economy", "title": "ECONOMY", "subtitle": "Production & yields"},
	{"id": "military", "title": "MILITARY", "subtitle": "Troops & combat"},
	{"id": "development", "title": "DEVELOPMENT", "subtitle": "City growth"},
	{"id": "hero", "title": "HERO", "subtitle": "Hero power"},
	{"id": "alliance", "title": "ALLIANCE", "subtitle": "Shared strength"},
]

var _mobile_page: MobilePage = MobilePage.HOME
var _mobile_shell: Control
var _mobile_home: Control
var _mobile_category: Control
var _mobile_detail: Control
var _mobile_title: Label
var _mobile_back_btn: Button
var _mobile_home_grid: GridContainer
var _mobile_tech_list: VBoxContainer
var _mobile_detail_body: VBoxContainer
var _mobile_active_banner: Label
var _mobile_built: bool = false
## Live "In progress — Ns remaining" label on mobile detail (updated each tick).
var _mobile_detail_progress_label: Label = null
var _mobile_detail_speedup_btn: Button = null

# Local fallbacks for offline testing or missing UIManager state
var _local_research_levels: Dictionary = {}
var _local_active_research: Dictionary = {} # Contains: research_id, level, time_remaining, total_duration
var _local_research_queue: Array = [] # List of jobs

var _local_resources = {
	"food": 500000,
	"wood": 450000,
	"stone": 250000,
	"iron": 120000,
	"valor": 15000
}

var _ui_manager: Node = null

func _get_ui_manager() -> Node:
	if _ui_manager == null:
		_ui_manager = get_node_or_null("/root/UIManager")
		if _ui_manager == null:
			_ui_manager = get_node_or_null("/root/UiManager")
		if _ui_manager == null:
			_ui_manager = get_node_or_null("/root/ui_manager")
	return _ui_manager

func _ready() -> void:
	# Resilient DB Loading
	_load_database()
	
	# Connect Category Tab triggers
	if btn_economy: btn_economy.pressed.connect(func(): change_category("Economy"))
	if btn_military: btn_military.pressed.connect(func(): change_category("Military"))
	if btn_development: btn_development.pressed.connect(func(): change_category("Development"))
	if btn_alliance: btn_alliance.pressed.connect(func(): change_category("Alliance"))
	if btn_hero: btn_hero.pressed.connect(func(): change_category("Hero"))
	
	# Connect zoom buttons
	if btn_zoom_out: btn_zoom_out.pressed.connect(func(): change_zoom(-0.1))
	if btn_zoom_reset: btn_zoom_reset.pressed.connect(func(): reset_zoom())
	if btn_zoom_in: btn_zoom_in.pressed.connect(func(): change_zoom(0.1))
	
	# Details panel controls
	if btn_start_research: btn_start_research.pressed.connect(_on_start_research_pressed)
	if btn_cancel_active: btn_cancel_active.pressed.connect(func(): cancel_research_job("active"))
	if btn_instant_valor: btn_instant_valor.pressed.connect(_on_instant_valor_pressed)
	if btn_close: btn_close.pressed.connect(_on_close_pressed)
	
	# Setup Speedup cards
	_setup_speedup_buttons()
	
	# Load / migrate into canonical ResearchState
	_load_persistent_state()
	
	# Setup Connection drawing callback
	if connection_layer:
		connection_layer.draw.connect(_draw_connections)
	
	# Initial rendering — mobile shell (hide dense desktop split layout).
	_update_resources_display()
	_setup_mobile_shell()
	_mobile_show_home()
	
	# Connect Global currency updates
	var ui = _get_ui_manager()
	if ui and ui.has_signal("currency_changed"):
		ui.currency_changed.connect(_on_global_currency_changed)

	if has_node("/root/ResearchState"):
		if not ResearchState.research_jobs_changed.is_connected(_on_research_state_jobs_changed):
			ResearchState.research_jobs_changed.connect(_on_research_state_jobs_changed)
		if not ResearchState.research_completed.is_connected(_on_research_state_completed):
			ResearchState.research_completed.connect(_on_research_state_completed)


## Open from City Research Hall (Academy) tap. Reuses this existing window.
func open_research() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 200
	if dark_overlay != null:
		dark_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		dark_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dark_overlay.color = Color(0.02, 0.03, 0.05, 0.72)
	_apply_portrait_window_layout()
	if has_node("/root/GameState"):
		GameState.popup_open = true
	move_to_front()
	_update_resources_display()
	_load_persistent_state()
	if academy_level_badge:
		academy_level_badge.text = "Hall Lv %d" % _get_canonical_academy_level()
	_setup_mobile_shell()
	_mobile_show_home()


## Fit MainPanel inside 720×1280 with HUD-safe margins (portrait).
func _apply_portrait_window_layout() -> void:
	if main_panel == null:
		return
	var view: Vector2 = get_viewport_rect().size
	if view.x < 1.0 or view.y < 1.0:
		view = Vector2(720, 1280)
	var top_safe: float = 96.0
	var bottom_safe: float = 196.0
	var side: float = 10.0
	main_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_panel.anchor_left = 0.0
	main_panel.anchor_top = 0.0
	main_panel.anchor_right = 1.0
	main_panel.anchor_bottom = 1.0
	main_panel.offset_left = side
	main_panel.offset_top = top_safe
	main_panel.offset_right = -side
	main_panel.offset_bottom = -bottom_safe
	main_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	main_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

func _process(_delta: float) -> void:
	# ResearchState owns timers; window only mirrors UI.
	_sync_active_research_ui()


func _on_research_state_jobs_changed() -> void:
	_sync_active_research_ui()
	if visible and _mobile_built:
		call_deferred("_deferred_mobile_refresh_after_job_change")


func _on_research_state_completed(research_id: String, lvl: int) -> void:
	var ui = _get_ui_manager()
	if ui:
		if ui.has_signal("technology_researched"):
			ui.technology_researched.emit(research_id, lvl)
		if "power" in ui:
			ui.power += 800 * lvl
	var node_def = _find_node_in_db(research_id)
	var node_name = node_def.get("name", research_id)
	_trigger_log_message("Unveiled research breakthrough! '%s' Level %d is complete." % [node_name, lvl])
	_rebuild_tech_tree()
	if visible and _mobile_built:
		call_deferred("_deferred_mobile_refresh_after_job_change")


# Tick active research queue progress (UI mirror only)
func _sync_active_research_ui() -> void:
	var active = get_active_job()
	if active.is_empty():
		if active_project_box: active_project_box.visible = false
		if active_project_empty_lbl: active_project_empty_lbl.visible = true
		_sync_speedup_button_state()
		if visible and _mobile_page == MobilePage.HOME and _mobile_active_banner != null:
			var used: int = 0
			if has_node("/root/ResearchState"):
				used = ResearchState.get_used_research_queues()
			if used > 0:
				_mobile_active_banner.text = "Research queues in use: %d / %d" % [
					used,
					ResearchState.get_research_queue_limit() if has_node("/root/ResearchState") else 1,
				]
			else:
				_mobile_active_banner.text = "No active research"
		return
		
	if active_project_box: active_project_box.visible = true
	if active_project_empty_lbl: active_project_empty_lbl.visible = false
	
	var node_def = _find_node_in_db(active.get("research_id", ""))
	var node_name = node_def.get("name", "Technology")
	
	if active_project_title:
		active_project_title.text = "%s Level %d" % [node_name, active["level"]]
		
	if active_project_timer:
		active_project_timer.text = format_duration(active["time_remaining"])
		
	if active_progress_bar:
		var total = float(active.get("total_duration", 10.0))
		var rem = float(active.get("time_remaining", 0.0))
		var progress = ((total - rem) / total) * 100.0
		active_progress_bar.value = clampf(progress, 0.0, 100.0)
		
	if btn_instant_valor:
		var valor_cost = int(active["time_remaining"] * 1.5)
		btn_instant_valor.text = "INSTANT (%d VALOR)" % valor_cost

	_sync_speedup_button_state()

	if visible and _mobile_built:
		if _mobile_page == MobilePage.HOME and _mobile_active_banner != null:
			_mobile_active_banner.text = "Researching: %s  ·  %s" % [
				node_name,
				format_duration(float(active.get("time_remaining", 0.0))),
			]
		_sync_mobile_detail_active_job_ui(active)

# Load database securely
func _load_database() -> void:
	var loaded := false
	var ui = _get_ui_manager()
	if ui and ui.has_method("load_json_file"):
		database = ui.call("load_json_file", "res://data/research.json")
		if database.size() > 0:
			loaded = true
			
	if not loaded:
		# Manual direct fallback loading
		if FileAccess.file_exists("res://data/research.json"):
			var file = FileAccess.open("res://data/research.json", FileAccess.READ)
			if file:
				var content = file.get_as_text()
				var json = JSON.new()
				var error = json.parse(content)
				if error == OK:
					var parsed = json.data
					if parsed is Array:
						database = parsed
						loaded = true
				else:
					print("[Crownspire AcademyResearch] JSON Parse Error: ", json.get_error_message(), " at line ", json.get_error_line())
				
	if database.size() > 0:
		print("[Crownspire AcademyResearch] Loaded %d research nodes." % database.size())
	else:
		push_error("[Crownspire AcademyResearch] Failed to load research.json. Injecting basic database.")
		database = _get_hardcoded_database()
		print("[Crownspire AcademyResearch] Loaded %d research nodes." % database.size())

func _load_persistent_state() -> void:
	var academy = _get_academy_building_ref()
	var active: Dictionary = {}
	var queue: Array = []
	var levels: Dictionary = {}
	if not academy.is_empty():
		if not academy.has("research_levels"):
			academy["research_levels"] = {}
		if not academy.has("active_research"):
			academy["active_research"] = {}
		if not academy.has("research_queue"):
			academy["research_queue"] = []
		active = academy.get("active_research", {})
		queue = academy.get("research_queue", [])
		levels = academy.get("research_levels", {})
	else:
		active = _local_active_research
		queue = _local_research_queue
		levels = _local_research_levels

	if has_node("/root/ResearchState"):
		ResearchState.import_legacy_jobs(active, queue, levels)
		# Clear ephemeral window locals so UI cannot fork a second job set.
		_local_active_research = {}
		_local_research_queue = []
		if not levels.is_empty():
			_local_research_levels = ResearchState.research_levels.duplicate(true)

func save_persistent_state() -> void:
	if has_node("/root/ResearchState"):
		ResearchState.save_research_state()
	var ui = _get_ui_manager()
	if ui and ui.has_method("save_player_state"):
		ui.call("save_player_state")

func _get_academy_building_ref() -> Dictionary:
	var ui = _get_ui_manager()
	if ui and ui.has_method("get_building"):
		return ui.call("get_building", "academy")
	return {}


## Phase 0B2-B: Academy completed building level from ConstructionState authority only.
func _get_canonical_academy_level() -> int:
	if has_node("/root/ConstructionState") and ConstructionState.has_method("get_canonical_building_level"):
		return maxi(1, int(ConstructionState.get_canonical_building_level("academy")))
	return 1

func get_research_levels() -> Dictionary:
	if has_node("/root/ResearchState"):
		return ResearchState.research_levels
	var academy = _get_academy_building_ref()
	if not academy.is_empty():
		return academy["research_levels"]
	return _local_research_levels

func get_active_job() -> Dictionary:
	if has_node("/root/ResearchState"):
		return ResearchState.get_primary_job()
	var academy = _get_academy_building_ref()
	if not academy.is_empty():
		return academy["active_research"]
	return _local_active_research

func set_active_job(job: Dictionary) -> void:
	# Legacy setter — route through ResearchState when available.
	if has_node("/root/ResearchState"):
		if job.is_empty():
			ResearchState.cancel_primary_research()
		else:
			ResearchState.try_start_research(job)
		return
	var academy = _get_academy_building_ref()
	if not academy.is_empty():
		academy["active_research"] = job
	else:
		_local_active_research = job
	save_persistent_state()

func get_queue() -> Array:
	if has_node("/root/ResearchState"):
		return ResearchState.get_waiting_jobs()
	var academy = _get_academy_building_ref()
	if not academy.is_empty():
		return academy["research_queue"]
	return _local_research_queue

func set_queue(q: Array) -> void:
	# Waiting queue beyond active slots is no longer used for free players.
	# Keep setter as no-op when ResearchState owns jobs (migration preserves excess in active_jobs).
	if has_node("/root/ResearchState"):
		return
	var academy = _get_academy_building_ref()
	if not academy.is_empty():
		academy["research_queue"] = q
	else:
		_local_research_queue = q
	save_persistent_state()

func get_resource(res_type: String) -> int:
	# Food/Wood/Stone/Iron are owned by GameState (same wallet as Top HUD).
	match res_type:
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
		if res_type == "valor":
			if "valor" in ui:
				return int(ui.get("valor"))
			else:
				return int(ui.get("royal_crystals"))
		elif res_type in ui:
			return int(ui.get(res_type))
	return int(_local_resources.get(res_type, 0))

func add_resource(res_type: String, amount: int) -> void:
	match res_type:
		"food":
			GameState.food = maxi(0, int(GameState.food) + amount)
			GameState.save_resources()
			GameState.resources_changed.emit()
			_update_resources_display()
			return
		"wood":
			GameState.wood = maxi(0, int(GameState.wood) + amount)
			GameState.save_resources()
			GameState.resources_changed.emit()
			_update_resources_display()
			return
		"stone":
			GameState.stone = maxi(0, int(GameState.stone) + amount)
			GameState.save_resources()
			GameState.resources_changed.emit()
			_update_resources_display()
			return
		"iron":
			GameState.iron = maxi(0, int(GameState.iron) + amount)
			GameState.save_resources()
			GameState.resources_changed.emit()
			_update_resources_display()
			return
	var ui = _get_ui_manager()
	if ui:
		if res_type == "valor":
			if "valor" in ui:
				ui.set("valor", max(0, int(ui.get("valor")) + amount))
			else:
				ui.set("royal_crystals", max(0, int(ui.get("royal_crystals")) + amount))
		elif res_type in ui:
			ui.set(res_type, max(0, int(ui.get(res_type)) + amount))
	else:
		_local_resources[res_type] = max(0, int(_local_resources.get(res_type, 0)) + amount)
	_update_resources_display()

# Shared Speed Up entry (Bag items via SpeedupService — not fake local timers).
func _setup_speedup_buttons() -> void:
	if speedup_container == null:
		return
	for child in speedup_container.get_children():
		child.queue_free()
	var btn := Button.new()
	btn.name = "SpeedUpButton"
	btn.text = "SPEED UP"
	btn.custom_minimum_size = Vector2(0, 48)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 16)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_on_shared_speedup_pressed)
	_style_research_speedup_button(btn, true)
	speedup_container.add_child(btn)
	_sync_speedup_button_state()


func _style_research_speedup_button(btn: Button, active: bool) -> void:
	if btn == null:
		return
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	var pressed := StyleBoxFlat.new()
	var disabled := StyleBoxFlat.new()
	for sb: StyleBoxFlat in [normal, hover, pressed, disabled]:
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(0)
		sb.border_width_bottom = 3
	if active:
		normal.bg_color = Color(0.13, 0.26, 0.46, 1)
		normal.border_color = Color(0.08, 0.18, 0.32, 1)
		hover.bg_color = Color(0.18, 0.35, 0.6, 1)
		hover.border_color = Color(0.1, 0.23, 0.42, 1)
		pressed.bg_color = Color(0.10, 0.20, 0.38, 1)
		pressed.border_color = Color(0.06, 0.14, 0.28, 1)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	else:
		normal.bg_color = Color(0.55, 0.58, 0.62, 1)
		normal.border_color = Color(0.42, 0.45, 0.48, 1)
		hover = normal
		pressed = normal
		btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, 1))
	disabled.bg_color = Color(0.70, 0.73, 0.76, 1)
	disabled.border_color = Color(0.55, 0.58, 0.61, 1)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)


func _sync_speedup_button_state() -> void:
	if speedup_container == null:
		return
	var btn: Button = speedup_container.get_node_or_null("SpeedUpButton") as Button
	if btn == null:
		return
	var active: Dictionary = get_active_job()
	var rem: float = float(active.get("time_remaining", 0.0))
	var can_speedup: bool = not active.is_empty() and rem > 0.0
	btn.visible = not active.is_empty()
	btn.disabled = not can_speedup
	_style_research_speedup_button(btn, can_speedup)


func _on_shared_speedup_pressed() -> void:
	var active: Dictionary = get_active_job()
	if active.is_empty():
		return
	if not has_node("/root/SpeedupService"):
		return
	var rid: String = str(active.get("research_id", ""))
	SpeedupService.open_speedup_popup(SpeedupService.CAT_RESEARCH, rid)


## Legacy entry point — routes through shared SpeedupService when possible.
func apply_speedup(seconds: float) -> void:
	var active = get_active_job()
	if active.is_empty():
		return
	if not has_node("/root/SpeedupService") or not has_node("/root/ResearchState"):
		_trigger_log_message("Speedup service unavailable.")
		return
	# Prefer owned research/universal bag items; do not invent free time.
	var rid: String = str(active.get("research_id", ""))
	var needed: int = int(ceil(seconds))
	var used_any: bool = false
	for row: Dictionary in SpeedupService.list_owned_eligible(SpeedupService.CAT_RESEARCH):
		var per: int = int(row.get("seconds", 0))
		if per <= 0:
			continue
		var result: Dictionary = SpeedupService.apply_speedup_item(
			SpeedupService.CAT_RESEARCH,
			rid,
			str(row.get("item_id", "")),
			1
		)
		if bool(result.get("ok", false)):
			used_any = true
			needed -= per
			if needed <= 0 or bool(result.get("completed", false)):
				break
	if used_any:
		_sync_active_research_ui()
		_sync_speedup_button_state()
	else:
		_trigger_log_message("No eligible research speedups in Bag.")

func _on_instant_valor_pressed() -> void:
	var active = get_active_job()
	if active.is_empty():
		return
		
	var cost = int(active["time_remaining"] * 1.5)
	var available_valor = get_resource("valor")
	
	if available_valor < cost:
		_trigger_log_message("Technical Alert: Insufficient Arcane Valor!", true)
		return
		
	# Subtract valor
	add_resource("valor", -cost)
	
	_trigger_log_message("Applied instant breaktrough using Arcane Valor.")
	# Complete instantly
	_complete_research_job()

func change_category(cat: String) -> void:
	active_category = cat
	_update_category_tabs_style()
	_rebuild_tech_tree()

func _update_category_tabs_style() -> void:
	var tabs = {
		"Economy": btn_economy,
		"Military": btn_military,
		"Development": btn_development,
		"Alliance": btn_alliance,
		"Hero": btn_hero
	}
	for t_key in tabs.keys():
		var btn = tabs[t_key]
		if not btn: continue
		if t_key == active_category:
			btn.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
			btn.add_theme_font_size_override("font_size", 12)
		else:
			btn.remove_theme_color_override("font_color")
			btn.remove_theme_font_size_override("font_size")

func _rebuild_tech_tree() -> void:
	# Clear old nodes
	for child in nodes_container.get_children():
		child.queue_free()
		
	# Get category nodes case-insensitively
	var category_nodes = []
	for node in database:
		if node.get("category", "").to_lower() == active_category.to_lower():
			category_nodes.append(node)
			
	# Layout calculation
	var node_positions = calculate_tree_layout(category_nodes)
	
	# Instantiate nodes
	var select_first_id = ""
	for node in category_nodes:
		var n_id = node.get("id", "")
		if select_first_id == "":
			select_first_id = n_id
			
		var pos = node_positions.get(n_id, Vector2.ZERO)
		
		# Compute node properties
		var level = get_research_levels().get(n_id, 0)
		var max_lvl = int(node.get("maxLevel", 10))
		var is_max = level >= max_lvl
		
		# Check unlock requirements
		var unlock_data = check_node_unlocked(node)
		var unlocked = unlock_data["unlocked"]
		
		# Check affordable
		var affordable = false
		if unlocked and not is_max:
			var cost_data = get_node_level_costs(node, level + 1)
			affordable = check_resources_affordable(cost_data)
			
		# Determine visual status
		var status = "unlocked"
		if not unlocked:
			status = "locked"
		elif is_max:
			status = "max"
		elif _is_researching_id(n_id):
			status = "researching"
		elif _is_queued(n_id):
			status = "queued"
		elif affordable:
			status = "ready"
			
		# Create Node
		var node_inst = RESEARCH_NODE_SCENE.instantiate()
		nodes_container.add_child(node_inst)
		
		node_inst.position = pos
		
		# Remap category for rendering case-sensitive fallback emojis in ResearchNode
		var node_copy = node.duplicate()
		var orig_cat = node_copy.get("category", "")
		var title_cat = orig_cat
		match orig_cat.to_lower():
			"economy": title_cat = "Economy"
			"military": title_cat = "Military"
			"development", "dev": title_cat = "Development"
			"alliance": title_cat = "Alliance"
			"hero": title_cat = "Hero"
		node_copy["category"] = title_cat
		
		node_inst.setup(node_copy, level, status, affordable)
		node_inst.selected.connect(_on_node_selected)
		
		# Load node texture if it exists
		var icon_rect = node_inst.get_node_or_null("%IconRect")
		if icon_rect:
			_apply_category_icon(icon_rect, title_cat)
			
		# Update highlight state if selected
		if n_id == selected_node_id:
			node_inst.set_selected(true)
			
	# Resize Canvas size dynamically to encompass all nodes cleanly
	_resize_scroll_canvas(node_positions)
	
	# Select default or preserve selected
	if selected_node_id == "" or not _is_node_in_current_category(selected_node_id):
		_on_node_selected(select_first_id)
	else:
		_on_node_selected(selected_node_id)
		
	# Redraw SVG Connections Layer
	if connection_layer:
		connection_layer.queue_redraw()

func _is_node_in_current_category(n_id: String) -> bool:
	var n = _find_node_in_db(n_id)
	return n.get("category", "").to_lower() == active_category.to_lower()

func _apply_category_icon(texture_rect: TextureRect, cat: String) -> void:
	var path = "res://assets/UI/icons/tech_%s.png" % cat.to_lower()
	if ResourceLoader.exists(path):
		texture_rect.texture = load(path)
	else:
		texture_rect.texture = PlaceholderTexture2D.new()
		match cat:
			"Economy": texture_rect.self_modulate = Color(0.1, 0.8, 0.4)
			"Military": texture_rect.self_modulate = Color(0.9, 0.1, 0.2)
			"Development": texture_rect.self_modulate = Color(0.9, 0.6, 0.1)
			"Alliance": texture_rect.self_modulate = Color(0.2, 0.5, 0.9)
			"Hero": texture_rect.self_modulate = Color(0.6, 0.2, 0.9)

# SVG Bezier lines drawing callback
func _draw_connections() -> void:
	if not connection_layer or database.size() == 0:
		return
		
	var category_nodes = []
	for node in database:
		if node.get("category", "").to_lower() == active_category.to_lower():
			category_nodes.append(node)
			
	var node_positions = calculate_tree_layout(category_nodes)
	var active_id = get_active_job().get("research_id", "")
	
	for node in category_nodes:
		var n_id = node.get("id", "")
		var pos = node_positions.get(n_id, Vector2.ZERO)
		if pos == Vector2.ZERO:
			continue
			
		# Check prerequisites to draw direct connections
		var prereqs = node.get("prerequisites", [])
		for req in prereqs:
			var req_id = req.get("researchId", "")
			var req_pos = node_positions.get(req_id, Vector2.ZERO)
			if req_pos == Vector2.ZERO:
				continue
				
			# Draw Bezier from parent's right to current node's left (250x90 dimensions)
			var p0 = req_pos + Vector2(250.0, 45.0) # Parent Node Right End
			var p3 = pos + Vector2(0.0, 45.0)       # Current Node Left End
			
			var cp1 = p0 + Vector2(100.0, 0.0)
			var cp2 = p3 - Vector2(100.0, 0.0)
			
			# Check connection status
			var req_level = get_research_levels().get(req_id, 0)
			var meets_req = req_level >= int(req.get("level", 1))
			
			var is_unlocked = check_node_unlocked(node)["unlocked"]
			var active_conn = meets_req and is_unlocked
			
			var color = Color(0.15, 0.18, 0.25, 0.4) # Locked Connection color
			var width = 2.0
			var dashed = true
			
			if active_conn:
				width = 3.0
				dashed = false
				if n_id == selected_node_id or req_id == selected_node_id:
					color = Color(1.0, 0.65, 0.0) # High-contrast yellow selected connection
					width = 4.0
				else:
					color = Color(0.1, 0.72, 0.44) # Safe Green connection
					
			_draw_bezier_curve(p0, cp1, cp2, p3, color, width, dashed)

func _draw_bezier_curve(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color: Color, width: float, dashed: bool = false) -> void:
	var points = PackedVector2Array()
	var steps = 24
	for i in range(steps + 1):
		var t = float(i) / steps
		var q0 = p0.lerp(p1, t)
		var q1 = p1.lerp(p2, t)
		var q2 = p2.lerp(p3, t)
		var r0 = q0.lerp(q1, t)
		var r1 = q1.lerp(q2, t)
		var p = r0.lerp(r1, t)
		points.append(p)
		
	if dashed:
		for j in range(0, points.size() - 1, 2):
			connection_layer.draw_line(points[j], points[j+1], color, width)
	else:
		connection_layer.draw_polyline(points, color, width, true)

func _calculate_node_depth(node_id: String, depth_map: Dictionary, category_ids: Dictionary) -> int:
	if depth_map.has(node_id):
		return depth_map[node_id]
		
	var node = _find_node_in_db(node_id)
	if node.is_empty():
		depth_map[node_id] = 0
		return 0
		
	var prereqs = []
	var node_prereqs = node.get("prerequisites", [])
	for req in node_prereqs:
		var r_id = req.get("researchId", "")
		if r_id != "" and category_ids.has(r_id):
			prereqs.append(r_id)
				
	if prereqs.size() == 0:
		depth_map[node_id] = 0
		return 0
		
	var max_depth = 0
	for p_id in prereqs:
		var d = _calculate_node_depth(p_id, depth_map, category_ids)
		if d > max_depth:
			max_depth = d
	depth_map[node_id] = max_depth + 1
	return max_depth + 1

# Algorithmic auto layout using prerequisites
func calculate_tree_layout(category_nodes: Array) -> Dictionary:
	var depth_map = {}
	var category_ids = {}
	for n in category_nodes:
		category_ids[n["id"]] = true
		
	for n in category_nodes:
		_calculate_node_depth(n["id"], depth_map, category_ids)
		
	# Organize into vertical columns (depth -> nodes)
	var columns = {}
	for n in category_nodes:
		var d = depth_map.get(n["id"], 0)
		if not columns.has(d):
			columns[d] = []
		columns[d].append(n["id"])
		
	# Assign non-overlapping Row Indices to align kids nicely
	var row_assignments = {} # node_id -> row_index (int)
	var col_keys = columns.keys()
	col_keys.sort()
	
	var col_occupied_rows = {} # col -> Dictionary of row_index -> bool
	for col in col_keys:
		col_occupied_rows[col] = {}
		
	for col in col_keys:
		var ids = columns[col]
		for node_id in ids:
			var node = _find_node_in_db(node_id)
			
			var parent_row = -1
			var node_prereqs = node.get("prerequisites", [])
			for req in node_prereqs:
				var r_id = req.get("researchId", "")
				if r_id != "" and row_assignments.has(r_id):
					parent_row = row_assignments[r_id]
					break
						
			var assigned_row = 0
			if parent_row != -1:
				if not col_occupied_rows[col].has(parent_row):
					assigned_row = parent_row
				else:
					var offset = 1
					while true:
						if not col_occupied_rows[col].has(parent_row + offset):
							assigned_row = parent_row + offset
							break
						if not col_occupied_rows[col].has(parent_row - offset):
							assigned_row = parent_row - offset
							break
						offset += 1
			else:
				var r = 0
				while col_occupied_rows[col].has(r):
					r += 1
				assigned_row = r
				
			row_assignments[node_id] = assigned_row
			col_occupied_rows[col][assigned_row] = true
			
	# Convert row indices to coordinates
	var positions = {}
	var col_spacing = 340.0
	var row_spacing = 140.0
	
	if row_assignments.size() > 0:
		var min_row = 999999
		var max_row = -999999
		for node_id in row_assignments:
			var row = row_assignments[node_id]
			if row < min_row: min_row = row
			if row > max_row: max_row = row
			
		# Bounding size calculations
		var tree_w = col_keys.size() * col_spacing
		var tree_h = (max_row - min_row + 1) * row_spacing
		
		# Retrieve scroll view size safely for dynamic centering
		var view_w = 800.0
		var view_h = 500.0
		if scroll_container:
			view_w = scroll_container.size.x if scroll_container.size.x > 100.0 else 800.0
			view_h = scroll_container.size.y if scroll_container.size.y > 100.0 else 500.0
			
		var offset_x = 40.0
		var offset_y = 40.0
		
		if view_w > tree_w:
			offset_x = (view_w - tree_w) / 2.0
		if view_h > tree_h:
			offset_y = (view_h - tree_h) / 2.0 - min_row * row_spacing
		else:
			offset_y = 40.0 - min_row * row_spacing
			
		for node_id in row_assignments:
			var col = depth_map[node_id]
			var row = row_assignments[node_id]
			positions[node_id] = Vector2(offset_x + col * col_spacing, offset_y + row * row_spacing)
			
	return positions

func _resize_scroll_canvas(positions: Dictionary) -> void:
	var view_w = 800.0
	var view_h = 500.0
	if scroll_container:
		view_w = scroll_container.size.x if scroll_container.size.x > 100.0 else 800.0
		view_h = scroll_container.size.y if scroll_container.size.y > 100.0 else 500.0
		
	var max_x = view_w
	var max_y = view_h
	
	for p_id in positions:
		var pos = positions[p_id]
		if pos.x + 250.0 > max_x: max_x = pos.x + 250.0
		if pos.y + 90.0 > max_y: max_y = pos.y + 90.0
		
	canvas_dimensions = Vector2(max_x + 80.0, max_y + 80.0)
	_update_zoom_scale()
	
	# Scroll view container viewport auto-centering if content overflows
	if scroll_container:
		scroll_container.call_deferred("set_h_scroll", int(max(0.0, (canvas_dimensions.x * zoom_level - view_w) / 2.0)))
		scroll_container.call_deferred("set_v_scroll", int(max(0.0, (canvas_dimensions.y * zoom_level - view_h) / 2.0)))

func change_zoom(amount: float) -> void:
	zoom_level = clampf(zoom_level + amount, 0.6, 1.5)
	_update_zoom_scale()

func reset_zoom() -> void:
	zoom_level = 1.0
	_update_zoom_scale()

func _update_zoom_scale() -> void:
	if zoom_wrapper:
		zoom_wrapper.scale = Vector2.ONE * zoom_level
		zoom_wrapper.custom_minimum_size = canvas_dimensions * zoom_level

# Triggered when selecting a node runestone
func _on_node_selected(node_id: String) -> void:
	if selected_node_id != "" and selected_node_id != node_id:
		for child in nodes_container.get_children():
			if child.get("research_id") == selected_node_id:
				child.set_selected(false)
				
	selected_node_id = node_id
	
	for child in nodes_container.get_children():
		if child.get("research_id") == selected_node_id:
			child.set_selected(true)
			
	if connection_layer:
		connection_layer.queue_redraw()
		
	_populate_inspect_card(node_id)

func _populate_inspect_card(node_id: String) -> void:
	var node = _find_node_in_db(node_id)
	if node.is_empty():
		if inspect_panel: inspect_panel.visible = false
		if empty_inspect_lbl: empty_inspect_lbl.visible = true
		return
		
	if inspect_panel: inspect_panel.visible = true
	if empty_inspect_lbl: empty_inspect_lbl.visible = false
	
	var level = get_research_levels().get(node_id, 0)
	var max_lvl = int(node.get("maxLevel", 10))
	var is_max = level >= max_lvl
	
	# Update Title & Description
	if card_title:
		card_title.text = node.get("name", "Technology")
	if card_description:
		card_description.text = '"' + node.get("description", "Ancient tech breakthrough.") + '"'
		
	# Current and next bonus levels
	if active_bonus_lbl:
		if level > 0:
			var lvl_data = _get_level_data(node, level)
			if not lvl_data.is_empty():
				var active_effects = lvl_data.get("effects", [])
				if active_effects.size() > 0:
					active_bonus_lbl.text = "Active:\n" + "\n".join(active_effects)
				else:
					active_bonus_lbl.text = "Active: No effects."
			else:
				active_bonus_lbl.text = "Active: No active bonuses yet."
		else:
			active_bonus_lbl.text = "Active: No active bonuses yet."
			
	if next_bonus_lbl:
		if is_max:
			next_bonus_lbl.text = "Max level achieved."
		else:
			var next_lvl_data = _get_level_data(node, level + 1)
			if not next_lvl_data.is_empty():
				var next_effects = next_lvl_data.get("effects", [])
				if next_effects.size() > 0:
					next_bonus_lbl.text = "Next:\n" + "\n".join(next_effects)
				else:
					next_bonus_lbl.text = "Next: Unlock next level."
			else:
				next_bonus_lbl.text = "Next: Unlock next tier bonuses."
			
	# Update requirements list
	_populate_requirements_ui(node, level)
	
	# Update costs UI
	var next_lvl = level + 1
	var cost_data = get_node_level_costs(node, next_lvl)
	
	_populate_costs_ui(cost_data, is_max)
	
	# Update Action Button
	_update_action_button_state(node, level, is_max, cost_data)

func _populate_requirements_ui(node: Dictionary, current_lvl: int) -> void:
	for child in reqs_box.get_children():
		child.queue_free()
		
	var next_lvl = current_lvl + 1
	var max_lvl = int(node.get("maxLevel", 10))
	
	if next_lvl > max_lvl:
		var lbl = Label.new()
		lbl.text = "✔ Ultimate tier unlocked!"
		lbl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		lbl.add_theme_font_size_override("font_size", 10)
		reqs_box.add_child(lbl)
		return
		
	var prereqs = node.get("prerequisites", [])
	if prereqs.size() == 0:
		var lbl = Label.new()
		lbl.text = "✔ No prerequisites required."
		lbl.add_theme_color_override("font_color", Color(0.1, 0.8, 0.4))
		lbl.add_theme_font_size_override("font_size", 10)
		reqs_box.add_child(lbl)
		return
		
	for req in prereqs:
		var req_id = req.get("researchId", "")
		var req_lvl = int(req.get("level", 1))
		
		# Self reference checks
		if req_id == "" or req_id == node.get("id"):
			continue
			
		var req_def = _find_node_in_db(req_id)
		if req_def.is_empty():
			continue
			
		var req_name = req_def.get("name", req_id)
		var active_lvl = get_research_levels().get(req_id, 0)
		var met = (active_lvl >= req_lvl) or (next_lvl > 1)
		
		var lbl = Label.new()
		lbl.text = "%s %s Level %d (Have %d)" % ["✔" if met else "❌", req_name, req_lvl, active_lvl]
		if met:
			lbl.add_theme_color_override("font_color", Color(0.1, 0.8, 0.4))
		else:
			lbl.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
		lbl.add_theme_font_size_override("font_size", 10)
		reqs_box.add_child(lbl)

func _populate_costs_ui(cost_data: Dictionary, is_max: bool) -> void:
	if is_max:
		cost_food_lbl.text = "0"
		cost_wood_lbl.text = "0"
		cost_stone_lbl.text = "0"
		cost_iron_lbl.text = "0"
		cost_valor_lbl.text = "0"
		research_time_lbl.text = "Research complete."
		
		# Reset colors
		cost_food_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		cost_wood_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		cost_stone_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		cost_iron_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		cost_valor_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		return
		
	var food_req = cost_data["food"]
	var wood_req = cost_data["wood"]
	var stone_req = cost_data["stone"]
	var iron_req = cost_data["iron"]
	var valor_req = cost_data["valor"]
	var duration = cost_data["duration"]
	
	# Format counts
	cost_food_lbl.text = format_num(food_req)
	cost_wood_lbl.text = format_num(wood_req)
	cost_stone_lbl.text = format_num(stone_req)
	cost_iron_lbl.text = format_num(iron_req)
	cost_valor_lbl.text = format_num(valor_req)
	research_time_lbl.text = "Duration: " + format_duration(duration)
	
	# Contrast color warning if affordable
	_color_cost_label(cost_food_lbl, get_resource("food") >= food_req)
	_color_cost_label(cost_wood_lbl, get_resource("wood") >= wood_req)
	_color_cost_label(cost_stone_lbl, get_resource("stone") >= stone_req)
	_color_cost_label(cost_iron_lbl, get_resource("iron") >= iron_req)
	_color_cost_label(cost_valor_lbl, get_resource("valor") >= valor_req)

func _color_cost_label(label: Label, sufficient: bool) -> void:
	if sufficient:
		label.add_theme_color_override("font_color", Color(0.1, 0.8, 0.4))
	else:
		label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))

func _update_action_button_state(node: Dictionary, level: int, is_max: bool, cost_data: Dictionary) -> void:
	if not btn_start_research: return
	
	btn_start_research.disabled = false
	btn_start_research.remove_theme_color_override("font_color")
	
	var is_researching_current = _is_researching_id(str(node.get("id", "")))
	var is_queued_current = _is_queued(str(node.get("id", "")))
	
	if is_max:
		btn_start_research.text = "MAX LEVEL REACHED"
		btn_start_research.disabled = true
	elif is_researching_current:
		btn_start_research.text = "ALREADY RESEARCHING..."
		btn_start_research.disabled = true
	elif is_queued_current:
		btn_start_research.text = "QUEUED FOR RESEARCH..."
		btn_start_research.disabled = true
	else:
		var unlocked = check_node_unlocked(node)["unlocked"]
		if not unlocked:
			btn_start_research.text = "LOCKED (PREREQUISITES)"
			btn_start_research.disabled = true
		else:
			var affordable = check_resources_affordable(cost_data)
			var queue_full := false
			if has_node("/root/ResearchState"):
				queue_full = not ResearchState.has_free_research_queue()
			else:
				queue_full = not get_active_job().is_empty()

			if queue_full:
				btn_start_research.text = "Research Queue Full"
				btn_start_research.disabled = true
			elif not affordable:
				btn_start_research.text = "INSUFFICIENT RESOURCES"
				btn_start_research.disabled = true
			else:
				btn_start_research.text = "START RESEARCH"

# Starts research into canonical ResearchState queue (limit enforced there).
func _on_start_research_pressed() -> void:
	var node = _find_node_in_db(selected_node_id)
	if node.is_empty():
		return
		
	var level = get_research_levels().get(selected_node_id, 0)
	var next_lvl = level + 1
	var cost_data = get_node_level_costs(node, next_lvl)
	
	# Verify prerequisites
	if not check_node_unlocked(node)["unlocked"]:
		return

	# Canonical queue gate — before spending resources.
	if has_node("/root/ResearchState"):
		var gate: Dictionary = ResearchState.can_start_research(selected_node_id)
		if not bool(gate.get("ok", false)):
			_trigger_log_message(str(gate.get("reason", "Research Queue Full")), true)
			_pulse_research_queue_hud()
			return
		
	# Verify costs
	if not check_resources_affordable(cost_data):
		_trigger_log_message("Technical Alert: Insufficient materials!", true)
		return
		
	# Subtract resource costs
	add_resource("food", -cost_data["food"])
	add_resource("wood", -cost_data["wood"])
	add_resource("stone", -cost_data["stone"])
	add_resource("iron", -cost_data["iron"])
	add_resource("valor", -cost_data["valor"])
	
	var duration = cost_data["duration"]
	
	var job = {
		"research_id": selected_node_id,
		"level": next_lvl,
		"time_remaining": float(duration),
		"total_duration": float(duration)
	}

	if has_node("/root/ResearchState"):
		var started: Dictionary = ResearchState.try_start_research(job)
		if not bool(started.get("ok", false)):
			# Refund if state rejected after deduct (should be rare).
			add_resource("food", cost_data["food"])
			add_resource("wood", cost_data["wood"])
			add_resource("stone", cost_data["stone"])
			add_resource("iron", cost_data["iron"])
			add_resource("valor", cost_data["valor"])
			_trigger_log_message(str(started.get("reason", "Research Queue Full")), true)
			_pulse_research_queue_hud()
			return
		_trigger_log_message("Begun active Scholar research: '%s' Level %d." % [node["name"], next_lvl])
	else:
		var active = get_active_job()
		if active.is_empty():
			set_active_job(job)
			_trigger_log_message("Begun active Scholar research: '%s' Level %d." % [node["name"], next_lvl])
		else:
			_trigger_log_message("Research Queue Full", true)
			_pulse_research_queue_hud()
			add_resource("food", cost_data["food"])
			add_resource("wood", cost_data["wood"])
			add_resource("stone", cost_data["stone"])
			add_resource("iron", cost_data["iron"])
			add_resource("valor", cost_data["valor"])
			return

	_rebuild_tech_tree()

func cancel_research_job(idx_or_active) -> void:
	var target_job = {}
	var refund_factor = 0.7 # refund 70% of costs

	if has_node("/root/ResearchState"):
		if idx_or_active is String and idx_or_active == "active":
			target_job = ResearchState.cancel_primary_research()
		elif idx_or_active is String:
			target_job = ResearchState.cancel_research(str(idx_or_active))
		else:
			var waiting: Array = ResearchState.get_waiting_jobs()
			var idx = int(idx_or_active)
			if idx >= 0 and idx < waiting.size():
				target_job = ResearchState.cancel_research(str((waiting[idx] as Dictionary).get("research_id", "")))
	elif idx_or_active is String and idx_or_active == "active":
		target_job = get_active_job()
		if target_job.is_empty():
			return
		var queue = get_queue()
		if queue.size() > 0:
			var next_job = queue.pop_front()
			set_active_job(next_job)
			set_queue(queue)
		else:
			set_active_job({})
		_update_queue_list_ui()
	else:
		var queue2 = get_queue()
		var idx2 = int(idx_or_active)
		if idx2 >= 0 and idx2 < queue2.size():
			target_job = queue2[idx2]
			queue2.remove_at(idx2)
			set_queue(queue2)
		_update_queue_list_ui()
			
	if not target_job.is_empty():
		var node = _find_node_in_db(target_job["research_id"])
		if not node.is_empty():
			var cost_data = get_node_level_costs(node, target_job["level"])
			add_resource("food", int(cost_data["food"] * refund_factor))
			add_resource("wood", int(cost_data["wood"] * refund_factor))
			add_resource("stone", int(cost_data["stone"] * refund_factor))
			add_resource("iron", int(cost_data["iron"] * refund_factor))
			add_resource("valor", int(cost_data["valor"] * refund_factor))
			_trigger_log_message("Cancelled research for '%s'. Refunded 70%% resources." % node["name"])
			
	_rebuild_tech_tree()

func _complete_research_job() -> void:
	# Completion is owned by ResearchState._complete_job → research_completed signal.
	pass

func _update_queue_list_ui() -> void:
	if not queue_list: return
	
	for child in queue_list.get_children():
		child.queue_free()
		
	var queue = get_queue()
	if queue.size() == 0:
		queue_label.text = "Waiting in queue (0/4)"
		return
		
	queue_label.text = "Waiting in queue (%d/4)" % queue.size()
	
	for i in range(queue.size()):
		var job = queue[i]
		var node = _find_node_in_db(job["research_id"])
		
		var panel = PanelContainer.new()
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 6)
		margin.add_theme_constant_override("margin_right", 6)
		margin.add_theme_constant_override("margin_top", 4)
		margin.add_theme_constant_override("margin_bottom", 4)
		
		var hbox = HBoxContainer.new()
		
		var label = Label.new()
		label.text = "%s Lvl %d (%s)" % [node.get("name", job["research_id"]), job["level"], format_duration(job["total_duration"])]
		label.add_theme_font_size_override("font_size", 9)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(label)
		
		var cancel_btn = Button.new()
		cancel_btn.text = "✕"
		cancel_btn.add_theme_font_size_override("font_size", 8)
		cancel_btn.pressed.connect(func(): cancel_research_job(i))
		cancel_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hbox.add_child(cancel_btn)
		
		margin.add_child(hbox)
		panel.add_child(margin)
		queue_list.add_child(panel)

func _get_level_data(node: Dictionary, lvl: int) -> Dictionary:
	var levels_list = node.get("levels", [])
	for lvl_entry in levels_list:
		if int(lvl_entry.get("level", 0)) == lvl:
			return lvl_entry
	return {}

# Resource helper getters
func get_node_level_costs(node: Dictionary, lvl: int) -> Dictionary:
	var cost_data = {
		"food": 0,
		"wood": 0,
		"stone": 0,
		"iron": 0,
		"valor": 0,
		"duration": 60
	}
	
	if lvl <= 0: return cost_data
	
	var lvl_data = _get_level_data(node, lvl)
	if not lvl_data.is_empty():
		var costs = lvl_data.get("costs", {})
		cost_data["food"] = int(costs.get("food", 0))
		cost_data["wood"] = int(costs.get("wood", 0))
		cost_data["stone"] = int(costs.get("stone", 0))
		cost_data["iron"] = int(costs.get("iron", 0))
		cost_data["valor"] = int(costs.get("valor", 0))
		cost_data["duration"] = int(lvl_data.get("researchTimeSec", 60))
	
	# Compute discount from academic research levels
	var discount = get_resource_discount_modifier()
	cost_data["food"] = int(cost_data["food"] * discount)
	cost_data["wood"] = int(cost_data["wood"] * discount)
	cost_data["stone"] = int(cost_data["stone"] * discount)
	cost_data["iron"] = int(cost_data["iron"] * discount)
	
	# Reduce research time duration based on speed modifiers
	var speed_modifier = get_research_speed_modifier()
	cost_data["duration"] = int(maxf(5.0, float(cost_data["duration"]) / (1.0 + speed_modifier)))
	
	return cost_data

# Modifier calculate helpers
func get_resource_discount_modifier() -> float:
	var discount = 0.0
	var levels = get_research_levels()
	var discount_lvl = levels.get("dev_res_discount", 0)
	discount = discount_lvl * 0.03 # 3% per level
	return clampf(1.0 - discount, 0.1, 1.0) # Cap at 90% discount

func get_research_speed_modifier() -> float:
	var speed = 0.0
	var levels = get_research_levels()
	var speed_lvl = levels.get("dev_build_spd", 0) # speed modifier
	speed = speed_lvl * 0.05 # 5% per level
	return speed

func check_node_unlocked(node: Dictionary) -> Dictionary:
	var levels = get_research_levels()
	var next_lvl = levels.get(node["id"], 0) + 1
	var max_lvl = int(node.get("maxLevel", 10))
	
	if next_lvl > max_lvl:
		return {"unlocked": false, "reason": "Ultimate level achieved."}
		
	# For levels 2 through maxLevel, the technology remains available once level 1 has been unlocked
	if next_lvl > 1:
		return {"unlocked": true, "reason": ""}
		
	# Check prerequisites for Level 1
	var prereqs = node.get("prerequisites", [])
	for req in prereqs:
		var req_id = req.get("researchId", "")
		var req_lvl = int(req.get("level", 1))
		
		# Skip self prerequisite
		if req_id == "" or req_id == node["id"]:
			continue
			
		var req_node = _find_node_in_db(req_id)
		if req_node.is_empty():
			# Skip invalid or missing prerequisite IDs safely
			continue
			
		var current_lvl = levels.get(req_id, 0)
		if current_lvl < req_lvl:
			var req_name = req_node.get("name", req_id)
			return {"unlocked": false, "reason": "Requires %s Level %d." % [req_name, req_lvl]}
			
	return {"unlocked": true, "reason": ""}

func check_resources_affordable(cost_data: Dictionary) -> bool:
	if get_resource("food") < cost_data["food"]: return false
	if get_resource("wood") < cost_data["wood"]: return false
	if get_resource("stone") < cost_data["stone"]: return false
	if get_resource("iron") < cost_data["iron"]: return false
	if get_resource("valor") < cost_data["valor"]: return false
	return true

func _is_researching_id(n_id: String) -> bool:
	if has_node("/root/ResearchState"):
		return not ResearchState.get_job_for(n_id).is_empty()
	return get_active_job().get("research_id", "") == n_id


func _is_queued(n_id: String) -> bool:
	# Overflow / waiting jobs only (primary is "researching").
	for job in get_queue():
		if str(job.get("research_id", "")) == n_id:
			return true
	return false

func _find_node_in_db(n_id: String) -> Dictionary:
	for n in database:
		if n.get("id", "") == n_id:
			return n
	return {}

# UI sync helpers
func _update_resources_display() -> void:
	if food_label: food_label.text = format_num(get_resource("food"))
	if wood_label: wood_label.text = format_num(get_resource("wood"))
	if stone_label: stone_label.text = format_num(get_resource("stone"))
	if iron_label: iron_label.text = format_num(get_resource("iron"))
	if valor_label: valor_label.text = format_num(get_resource("valor"))
	
	if academy_level_badge:
		academy_level_badge.text = "Sovereign Lvl %d" % _get_canonical_academy_level()

func _on_global_currency_changed(_id: String, _val: float) -> void:
	_update_resources_display()
	if selected_node_id != "":
		_populate_inspect_card(selected_node_id)

# String utility helpers
func format_num(val: int) -> String:
	if val >= 1000000:
		return "%.2fM" % (float(val) / 1000000.0)
	elif val >= 1000:
		return "%.1fK" % (float(val) / 1000.0)
	return str(val)

func format_duration(seconds: float) -> String:
	var secs = int(seconds)
	var hrs = secs / 3600
	var mins = (secs % 3600) / 60
	var s = secs % 60
	
	if hrs > 0:
		return "%02dh %02dm %02ds" % [hrs, mins, s]
	elif mins > 0:
		return "%02dm %02ds" % [mins, s]
	return "%02ds" % s

func _trigger_log_message(msg: String, is_warn: bool = false) -> void:
	var ui = _get_ui_manager()
	if ui and ui.has_method("add_log"):
		ui.call("add_log", msg, "warning" if is_warn else "success")
	else:
		print("[%s] %s" % ["WARNING" if is_warn else "SUCCESS", msg])


func _pulse_research_queue_hud() -> void:
	var hud: Node = get_tree().root.find_child("GameHUD", true, false)
	if hud != null and hud.has_method("pulse_queue_status"):
		hud.call("pulse_queue_status", "research")


# =============================================================================
# MOBILE NAVIGATION (Category Home → Category List → Tech Detail)
# Reuses existing research logic; replaces dense desktop split layout.
# =============================================================================

func _setup_mobile_shell() -> void:
	if _mobile_built and _mobile_shell != null and is_instance_valid(_mobile_shell):
		return
	var vbox: VBoxContainer = get_node_or_null("MainPanel/VBox") as VBoxContainer
	if vbox == null:
		return

	# Hide legacy dense desktop chrome and ensure it cannot steal clicks.
	for path: String in [
		"MainPanel/VBox/CategoryTabs",
		"MainPanel/VBox/ZoomControls",
		"MainPanel/VBox/ContentArea",
	]:
		var legacy: CanvasItem = get_node_or_null(path) as CanvasItem
		if legacy != null:
			legacy.visible = false
			if legacy is Control:
				(legacy as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
				_set_mouse_filter_recursive(legacy, Control.MOUSE_FILTER_IGNORE)

	# Header title + back wiring.
	var title: Label = get_node_or_null("MainPanel/VBox/Header/Margin/HBox/TitleContainer/TitleRow/Title") as Label
	if title != null:
		_mobile_title = title
		_mobile_title.add_theme_font_size_override("font_size", 22)
		_mobile_title.text = "ACADEMY RESEARCH"
	var subtitle: CanvasItem = get_node_or_null("MainPanel/VBox/Header/Margin/HBox/TitleContainer/Subtitle") as CanvasItem
	if subtitle != null:
		subtitle.visible = false
	var header_row: HBoxContainer = get_node_or_null("MainPanel/VBox/Header/Margin/HBox") as HBoxContainer
	if header_row != null and _mobile_back_btn == null:
		_mobile_back_btn = Button.new()
		_mobile_back_btn.name = "MobileBackButton"
		_mobile_back_btn.text = "‹"
		_mobile_back_btn.custom_minimum_size = Vector2(56, 48)
		_mobile_back_btn.add_theme_font_size_override("font_size", 28)
		_mobile_back_btn.pressed.connect(_on_mobile_back_pressed)
		header_row.add_child(_mobile_back_btn)
		header_row.move_child(_mobile_back_btn, 0)

	_mobile_shell = Control.new()
	_mobile_shell.name = "MobileShell"
	_mobile_shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mobile_shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mobile_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_child(_mobile_shell)

	_mobile_home = _make_mobile_page("HomePage")
	_mobile_category = _make_mobile_page("CategoryPage")
	_mobile_detail = _make_mobile_page("DetailPage")
	_mobile_shell.add_child(_mobile_home)
	_mobile_shell.add_child(_mobile_category)
	_mobile_shell.add_child(_mobile_detail)

	# HOME
	var home_margin := MarginContainer.new()
	home_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home_margin.add_theme_constant_override("margin_left", 12)
	home_margin.add_theme_constant_override("margin_right", 12)
	home_margin.add_theme_constant_override("margin_top", 8)
	home_margin.add_theme_constant_override("margin_bottom", 8)
	_mobile_home.add_child(home_margin)
	var home_col := VBoxContainer.new()
	home_col.add_theme_constant_override("separation", 12)
	home_margin.add_child(home_col)
	_mobile_active_banner = Label.new()
	_mobile_active_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mobile_active_banner.add_theme_font_size_override("font_size", 15)
	_mobile_active_banner.add_theme_color_override("font_color", Color(0.86, 0.70, 0.32, 1.0))
	home_col.add_child(_mobile_active_banner)
	var hint := Label.new()
	hint.text = "Choose a research discipline"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.72, 0.68, 0.58, 1.0))
	home_col.add_child(hint)
	var home_scroll := ScrollContainer.new()
	home_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	home_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	home_col.add_child(home_scroll)
	_mobile_home_grid = GridContainer.new()
	_mobile_home_grid.columns = 2
	_mobile_home_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mobile_home_grid.add_theme_constant_override("h_separation", 10)
	_mobile_home_grid.add_theme_constant_override("v_separation", 10)
	home_scroll.add_child(_mobile_home_grid)

	# CATEGORY
	var cat_margin := MarginContainer.new()
	cat_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cat_margin.add_theme_constant_override("margin_left", 10)
	cat_margin.add_theme_constant_override("margin_right", 10)
	cat_margin.add_theme_constant_override("margin_top", 6)
	cat_margin.add_theme_constant_override("margin_bottom", 6)
	_mobile_category.add_child(cat_margin)
	var cat_scroll := ScrollContainer.new()
	cat_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cat_margin.add_child(cat_scroll)
	_mobile_tech_list = VBoxContainer.new()
	_mobile_tech_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mobile_tech_list.add_theme_constant_override("separation", 10)
	cat_scroll.add_child(_mobile_tech_list)

	# DETAIL
	var det_margin := MarginContainer.new()
	det_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	det_margin.add_theme_constant_override("margin_left", 12)
	det_margin.add_theme_constant_override("margin_right", 12)
	det_margin.add_theme_constant_override("margin_top", 6)
	det_margin.add_theme_constant_override("margin_bottom", 6)
	_mobile_detail.add_child(det_margin)
	var det_scroll := ScrollContainer.new()
	det_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	det_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	det_margin.add_child(det_scroll)
	_mobile_detail_body = VBoxContainer.new()
	_mobile_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mobile_detail_body.add_theme_constant_override("separation", 10)
	det_scroll.add_child(_mobile_detail_body)

	_mobile_built = true


func _make_mobile_page(page_name: String) -> Control:
	var page := Control.new()
	page.name = page_name
	page.visible = false
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return page


func _set_mobile_page_visible(page: Control, is_on: bool) -> void:
	if page == null:
		return
	page.visible = is_on
	page.mouse_filter = Control.MOUSE_FILTER_STOP if is_on else Control.MOUSE_FILTER_IGNORE


func _set_mouse_filter_recursive(node: Node, filter: Control.MouseFilter) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child: Node in node.get_children():
		_set_mouse_filter_recursive(child, filter)


func _mobile_show_home() -> void:
	_setup_mobile_shell()
	_mobile_page = MobilePage.HOME
	_set_mobile_page_visible(_mobile_home, true)
	_set_mobile_page_visible(_mobile_category, false)
	_set_mobile_page_visible(_mobile_detail, false)
	if _mobile_back_btn:
		_mobile_back_btn.visible = false
	if _mobile_title:
		_mobile_title.text = "ACADEMY RESEARCH"
	_refresh_mobile_home()


func _mobile_show_category(cat_id: String) -> void:
	_setup_mobile_shell()
	active_category = _canon_category_title(cat_id)
	_mobile_page = MobilePage.CATEGORY
	_set_mobile_page_visible(_mobile_home, false)
	_set_mobile_page_visible(_mobile_category, true)
	_set_mobile_page_visible(_mobile_detail, false)
	if _mobile_back_btn:
		_mobile_back_btn.visible = true
	if _mobile_title:
		_mobile_title.text = active_category.to_upper()
	_refresh_mobile_category_list()


func _mobile_show_detail(tech_id: String) -> void:
	_setup_mobile_shell()
	selected_node_id = tech_id
	_mobile_page = MobilePage.DETAIL
	_set_mobile_page_visible(_mobile_home, false)
	_set_mobile_page_visible(_mobile_category, false)
	_set_mobile_page_visible(_mobile_detail, true)
	if _mobile_back_btn:
		_mobile_back_btn.visible = true
	var node: Dictionary = _find_node_in_db(tech_id)
	if _mobile_title:
		_mobile_title.text = str(node.get("name", "Technology"))
	_refresh_mobile_detail()


func _on_mobile_back_pressed() -> void:
	match _mobile_page:
		MobilePage.DETAIL:
			_mobile_show_category(active_category)
		MobilePage.CATEGORY:
			_mobile_show_home()
		_:
			_mobile_show_home()


func _canon_category_title(raw: String) -> String:
	match raw.strip_edges().to_lower():
		"economy":
			return "Economy"
		"military":
			return "Military"
		"development", "dev":
			return "Development"
		"alliance":
			return "Alliance"
		"hero":
			return "Hero"
		_:
			return raw.capitalize()


func _category_progress_pct(cat_id: String) -> float:
	var total: int = 0
	var have: int = 0
	var levels: Dictionary = get_research_levels()
	for node: Variant in database:
		if typeof(node) != TYPE_DICTIONARY:
			continue
		if str((node as Dictionary).get("category", "")).to_lower() != cat_id.to_lower():
			continue
		var max_lvl: int = maxi(1, int((node as Dictionary).get("maxLevel", 1)))
		total += max_lvl
		have += clampi(int(levels.get(str((node as Dictionary).get("id", "")), 0)), 0, max_lvl)
	if total <= 0:
		return 0.0
	return 100.0 * float(have) / float(total)


func _clear_mobile_children(container: Node) -> void:
	if container == null:
		return
	# queue_free only — never free() during/after button signals.
	while container.get_child_count() > 0:
		var c: Node = container.get_child(0)
		container.remove_child(c)
		c.queue_free()


func _refresh_mobile_home() -> void:
	if _mobile_home_grid == null:
		return
	_clear_mobile_children(_mobile_home_grid)

	var active: Dictionary = get_active_job()
	if _mobile_active_banner != null:
		if active.is_empty():
			_mobile_active_banner.text = "No active research"
		else:
			var n: Dictionary = _find_node_in_db(str(active.get("research_id", "")))
			_mobile_active_banner.text = "Researching: %s  ·  %s" % [
				str(n.get("name", "Technology")),
				format_duration(float(active.get("time_remaining", 0.0))),
			]

	for entry: Dictionary in MOBILE_CATEGORIES:
		var cat_id: String = str(entry.get("id", ""))
		var pct: float = _category_progress_pct(cat_id)
		var card := Button.new()
		card.custom_minimum_size = Vector2(300, 148)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.text = ""
		card.add_theme_stylebox_override("normal", _mobile_card_style(Color(0.12, 0.10, 0.18, 1.0)))
		card.add_theme_stylebox_override("hover", _mobile_card_style(Color(0.18, 0.14, 0.24, 1.0)))
		card.add_theme_stylebox_override("pressed", _mobile_card_style(Color(0.22, 0.16, 0.10, 1.0)))
		card.clip_contents = true

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 12
		row.offset_right = -12
		row.offset_top = 12
		row.offset_bottom = -12
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(56, 56)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_category_icon(icon, _canon_category_title(cat_id))
		row.add_child(icon)

		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 4)
		row.add_child(col)

		var title_l := Label.new()
		title_l.text = str(entry.get("title", ""))
		title_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_l.add_theme_font_size_override("font_size", 20)
		title_l.add_theme_color_override("font_color", Color(0.95, 0.84, 0.40, 1.0))
		title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(title_l)

		var sub_l := Label.new()
		sub_l.text = str(entry.get("subtitle", ""))
		sub_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub_l.add_theme_font_size_override("font_size", 14)
		sub_l.add_theme_color_override("font_color", Color(0.72, 0.68, 0.58, 1.0))
		sub_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(sub_l)

		var pct_l := Label.new()
		pct_l.text = "%d%%" % int(round(pct))
		pct_l.add_theme_font_size_override("font_size", 22)
		pct_l.add_theme_color_override("font_color", Color(0.78, 0.88, 1.0, 1.0))
		pct_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(pct_l)

		var captured: String = cat_id
		card.pressed.connect(func() -> void: _mobile_show_category(captured))
		_mobile_home_grid.add_child(card)


func _mobile_card_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = Color(0.72, 0.58, 0.28, 0.85)
	s.set_border_width_all(2)
	s.set_corner_radius_all(14)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s


func _refresh_mobile_category_list() -> void:
	if _mobile_tech_list == null:
		return
	_clear_mobile_children(_mobile_tech_list)

	var cat_key: String = active_category.to_lower()
	for node: Variant in database:
		if typeof(node) != TYPE_DICTIONARY:
			continue
		var def: Dictionary = node as Dictionary
		if str(def.get("category", "")).to_lower() != cat_key:
			continue
		var n_id: String = str(def.get("id", ""))
		var level: int = int(get_research_levels().get(n_id, 0))
		var max_lvl: int = maxi(1, int(def.get("maxLevel", 1)))
		var unlock_data: Dictionary = check_node_unlocked(def)
		var unlocked: bool = bool(unlock_data.get("unlocked", false))
		var status: String = "Available"
		if not unlocked:
			status = "Locked"
		elif level >= max_lvl:
			status = "Completed"
		elif _is_researching_id(n_id):
			status = "Researching"
		elif _is_queued(n_id):
			status = "Queued"

		var row := Button.new()
		row.custom_minimum_size = Vector2(0, 96)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.text = "%s\nLv %d / %d   ·   %s" % [str(def.get("name", n_id)), level, max_lvl, status]
		row.add_theme_font_size_override("font_size", 18)
		row.add_theme_color_override("font_color", Color(0.93, 0.88, 0.76, 1.0))
		row.add_theme_stylebox_override("normal", _mobile_card_style(Color(0.10, 0.09, 0.15, 1.0)))
		row.add_theme_stylebox_override("hover", _mobile_card_style(Color(0.16, 0.13, 0.22, 1.0)))
		var captured_id: String = n_id
		row.pressed.connect(func() -> void: _mobile_show_detail(captured_id))
		_mobile_tech_list.add_child(row)


func _refresh_mobile_detail() -> void:
	if _mobile_detail_body == null:
		return
	_mobile_detail_progress_label = null
	_mobile_detail_speedup_btn = null
	_clear_mobile_children(_mobile_detail_body)

	var node: Dictionary = _find_node_in_db(selected_node_id)
	if node.is_empty():
		_mobile_detail_body.add_child(_mobile_text("Technology not found.", 18, Color(1, 0.5, 0.4)))
		return

	var level: int = int(get_research_levels().get(selected_node_id, 0))
	var max_lvl: int = maxi(1, int(node.get("maxLevel", 1)))
	var is_max: bool = level >= max_lvl
	var unlock_data: Dictionary = check_node_unlocked(node)
	var unlocked: bool = bool(unlock_data.get("unlocked", false))
	var cost_data: Dictionary = get_node_level_costs(node, level + 1)
	var active: Dictionary = {}
	if has_node("/root/ResearchState"):
		active = ResearchState.get_job_for(selected_node_id)
	else:
		active = get_active_job()
		if str(active.get("research_id", "")) != selected_node_id:
			active = {}
	var is_researching: bool = not active.is_empty()

	_mobile_detail_body.add_child(_mobile_text(str(node.get("name", "Technology")), 26, Color(0.95, 0.84, 0.40)))
	_mobile_detail_body.add_child(_mobile_text("Level %d / %d" % [level, max_lvl], 18, Color(0.80, 0.76, 0.68)))
	_mobile_detail_body.add_child(_mobile_text(str(node.get("description", "")), 17, Color(0.90, 0.86, 0.78)))

	# Effects
	if level > 0:
		var cur: Dictionary = _get_level_data(node, level)
		var fx: Array = cur.get("effects", [])
		if fx.size() > 0:
			var fx_txt: PackedStringArray = PackedStringArray()
			for e: Variant in fx:
				fx_txt.append(str(e))
			_mobile_detail_body.add_child(_mobile_text("Current Effect\n" + "\n".join(fx_txt), 16, Color(0.55, 0.85, 0.60)))
	if not is_max:
		var nxt: Dictionary = _get_level_data(node, level + 1)
		var nfx: Array = nxt.get("effects", [])
		if nfx.size() > 0:
			var nfx_txt: PackedStringArray = PackedStringArray()
			for e2: Variant in nfx:
				nfx_txt.append(str(e2))
			_mobile_detail_body.add_child(_mobile_text("Next Effect\n" + "\n".join(nfx_txt), 16, Color(0.70, 0.78, 0.95)))

	# Prerequisites
	var prereq_lines: PackedStringArray = PackedStringArray()
	for req: Variant in node.get("prerequisites", []):
		if typeof(req) != TYPE_DICTIONARY:
			continue
		var req_id: String = str((req as Dictionary).get("researchId", ""))
		var req_lvl: int = int((req as Dictionary).get("level", 1))
		var req_def: Dictionary = _find_node_in_db(req_id)
		var have: int = int(get_research_levels().get(req_id, 0))
		var met: bool = have >= req_lvl or level >= 1
		prereq_lines.append("%s %s Lv.%d (have %d)" % ["✔" if met else "✖", str(req_def.get("name", req_id)), req_lvl, have])
	if prereq_lines.is_empty():
		prereq_lines.append("No prerequisites")
	_mobile_detail_body.add_child(_mobile_text("Prerequisites\n" + "\n".join(prereq_lines), 16, Color(0.85, 0.80, 0.70)))

	# Costs / time
	if is_max:
		_mobile_detail_body.add_child(_mobile_text("Maximum level reached.", 18, Color(0.86, 0.70, 0.32)))
	else:
		var cost_txt: String = "Food %d · Wood %d · Stone %d · Iron %d · Valor %d" % [
			int(cost_data.get("food", 0)),
			int(cost_data.get("wood", 0)),
			int(cost_data.get("stone", 0)),
			int(cost_data.get("iron", 0)),
			int(cost_data.get("valor", 0)),
		]
		_mobile_detail_body.add_child(_mobile_text("Cost\n" + cost_txt, 16, Color(0.80, 0.76, 0.68)))
		_mobile_detail_body.add_child(_mobile_text(
			"Duration  %s" % format_duration(float(cost_data.get("duration", 0))),
			16,
			Color(0.80, 0.76, 0.68)
		))

	if is_researching:
		_mobile_detail_progress_label = _mobile_text(
			"In progress — %s remaining" % format_duration(float(active.get("time_remaining", 0.0))),
			18,
			Color(0.55, 0.82, 0.95)
		)
		_mobile_detail_progress_label.name = "MobileActiveProgress"
		_mobile_detail_body.add_child(_mobile_detail_progress_label)

		# Portrait path: SPEED UP must live here (desktop SpeedupContainer is hidden).
		_mobile_detail_speedup_btn = Button.new()
		_mobile_detail_speedup_btn.name = "MobileSpeedUpButton"
		_mobile_detail_speedup_btn.text = "SPEED UP"
		_mobile_detail_speedup_btn.custom_minimum_size = Vector2(0, 56)
		_mobile_detail_speedup_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_mobile_detail_speedup_btn.add_theme_font_size_override("font_size", 20)
		_mobile_detail_speedup_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_mobile_detail_speedup_btn.pressed.connect(_on_shared_speedup_pressed)
		var rem_now: float = float(active.get("time_remaining", 0.0))
		var can_su: bool = rem_now > 0.0
		_mobile_detail_speedup_btn.disabled = not can_su
		_style_research_speedup_button(_mobile_detail_speedup_btn, can_su)
		_mobile_detail_body.add_child(_mobile_detail_speedup_btn)

		var cancel := Button.new()
		cancel.name = "MobileCancelResearchButton"
		cancel.text = "CANCEL RESEARCH"
		cancel.custom_minimum_size = Vector2(0, 52)
		cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cancel.add_theme_font_size_override("font_size", 17)
		_style_mobile_cancel_button(cancel)
		cancel.pressed.connect(func() -> void:
			cancel_research_job(selected_node_id)
			# Defer rebuild — Cancel button lives in _mobile_detail_body.
			call_deferred("_deferred_mobile_refresh_after_job_change")
		)
		_mobile_detail_body.add_child(cancel)
	elif not unlocked:
		var why: String = str(unlock_data.get("reason", "Locked"))
		_mobile_detail_body.add_child(_mobile_text("Locked\n%s" % why, 17, Color(1.0, 0.55, 0.45)))
	elif is_max:
		pass
	else:
		var start := Button.new()
		start.custom_minimum_size = Vector2(0, 64)
		start.add_theme_font_size_override("font_size", 20)
		var affordable: bool = check_resources_affordable(cost_data)
		var queue_full := false
		if has_node("/root/ResearchState"):
			queue_full = not ResearchState.has_free_research_queue()
		else:
			queue_full = not get_active_job().is_empty()
		if not affordable:
			start.text = "INSUFFICIENT RESOURCES"
			start.disabled = true
		elif queue_full:
			start.text = "Research Queue Full"
			start.disabled = true
		else:
			start.text = "START RESEARCH"
		start.pressed.connect(func() -> void:
			_on_start_research_pressed()
			# Defer rebuild — Start button is a child of _mobile_detail_body.
			call_deferred("_deferred_mobile_refresh_after_job_change")
		)
		_mobile_detail_body.add_child(start)


func _deferred_mobile_refresh_after_job_change() -> void:
	if not is_instance_valid(self) or not _mobile_built:
		return
	if _mobile_page == MobilePage.DETAIL:
		_refresh_mobile_detail()
	if _mobile_page == MobilePage.CATEGORY or _mobile_page == MobilePage.DETAIL:
		_refresh_mobile_category_list()
	_refresh_mobile_home()


func _sync_mobile_detail_active_job_ui(active: Dictionary) -> void:
	## Tick-only refresh for the live mobile detail progress line + SPEED UP state.
	if _mobile_page != MobilePage.DETAIL:
		return
	if _mobile_detail_progress_label != null and is_instance_valid(_mobile_detail_progress_label):
		if active.is_empty() or str(active.get("research_id", "")) != selected_node_id:
			# Job finished / switched — full rebuild handles idle/complete UI.
			return
		_mobile_detail_progress_label.text = "In progress — %s remaining" % format_duration(
			float(active.get("time_remaining", 0.0))
		)
	if _mobile_detail_speedup_btn != null and is_instance_valid(_mobile_detail_speedup_btn):
		var rem: float = float(active.get("time_remaining", 0.0)) if not active.is_empty() else 0.0
		var can_su: bool = not active.is_empty() and rem > 0.0
		_mobile_detail_speedup_btn.visible = not active.is_empty()
		# Enabled whenever a real timer is running — even with 0 bag speedups.
		_mobile_detail_speedup_btn.disabled = not can_su
		_style_research_speedup_button(_mobile_detail_speedup_btn, can_su)


func _style_mobile_cancel_button(btn: Button) -> void:
	if btn == null:
		return
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	var pressed := StyleBoxFlat.new()
	for sb: StyleBoxFlat in [normal, hover, pressed]:
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(1)
	normal.bg_color = Color(0.14, 0.12, 0.16, 1.0)
	normal.border_color = Color(0.40, 0.34, 0.30, 0.90)
	hover.bg_color = Color(0.20, 0.16, 0.20, 1.0)
	hover.border_color = Color(0.55, 0.45, 0.35, 0.95)
	pressed.bg_color = Color(0.10, 0.09, 0.12, 1.0)
	pressed.border_color = Color(0.30, 0.26, 0.24, 0.90)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(0.82, 0.76, 0.68, 1.0))


func _mobile_text(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _on_close_pressed() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if has_node("/root/GameState"):
		GameState.popup_open = false
	queue_free()

func _get_hardcoded_database() -> Array:
	return [
		{
			"id": "econ_food_prod_1",
			"name": "Citadel Irrigation I",
			"category": "economy",
			"description": "Ancient agrarian breakthroughs utilizing structured canal irrigation.",
			"maxLevel": 2,
			"prerequisites": [],
			"levels": [
				{
					"level": 1,
					"costs": {
						"food": 150,
						"wood": 100,
						"stone": 0,
						"iron": 0,
						"valor": 0
					},
					"researchTimeSec": 10,
					"effects": ["Food Production +5.0%"]
				},
				{
					"level": 2,
					"costs": {
						"food": 300,
						"wood": 200,
						"stone": 0,
						"iron": 0,
						"valor": 0
					},
					"researchTimeSec": 30,
					"effects": ["Food Production +10.0%"]
				}
			]
		}
	]
