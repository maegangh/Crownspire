extends Control

# Crownspire Academy Research Window (AAA Mobile Portrait compliant)
# Fully ports the AcademyResearchScene.tsx React prototype into a high-fidelity Godot 4.6 scene.

const RESEARCH_NODE_SCENE = preload("res://scenes/ResearchNode.tscn")

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
	
	# Load current states from UIManager
	_load_persistent_state()
	
	# Setup Connection drawing callback
	if connection_layer:
		connection_layer.draw.connect(_draw_connections)
	
	# Initial rendering
	_update_resources_display()
	change_category("Economy")
	
	# Connect Global currency updates
	var ui = _get_ui_manager()
	if ui and ui.has_signal("currency_changed"):
		ui.currency_changed.connect(_on_global_currency_changed)

func _process(delta: float) -> void:
	_tick_active_research(delta)

# Tick active research queue progress
func _tick_active_research(delta: float) -> void:
	var active = get_active_job()
	if active.is_empty():
		if active_project_box: active_project_box.visible = false
		if active_project_empty_lbl: active_project_empty_lbl.visible = true
		return
		
	if active_project_box: active_project_box.visible = true
	if active_project_empty_lbl: active_project_empty_lbl.visible = false
	
	# Tick countdown
	active["time_remaining"] = maxf(0.0, active["time_remaining"] - delta)
	save_persistent_state()
	
	# UI displays
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
		
	# Check for completion
	if active["time_remaining"] <= 0.0:
		_complete_research_job()

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
	if not academy.is_empty():
		if not academy.has("research_levels"):
			academy["research_levels"] = {}
		if not academy.has("active_research"):
			academy["active_research"] = {}
		if not academy.has("research_queue"):
			academy["research_queue"] = []
	else:
		push_warning("[Crownspire AcademyResearch] Academy building object not found in UIManager. Using local state.")

func save_persistent_state() -> void:
	var ui = _get_ui_manager()
	if ui and ui.has_method("save_player_state"):
		ui.call("save_player_state")

func _get_academy_building_ref() -> Dictionary:
	var ui = _get_ui_manager()
	if ui and ui.has_method("get_building"):
		return ui.call("get_building", "academy")
	return {}

func get_research_levels() -> Dictionary:
	var academy = _get_academy_building_ref()
	if not academy.is_empty():
		return academy["research_levels"]
	return _local_research_levels

func get_active_job() -> Dictionary:
	var academy = _get_academy_building_ref()
	if not academy.is_empty():
		return academy["active_research"]
	return _local_active_research

func set_active_job(job: Dictionary) -> void:
	var academy = _get_academy_building_ref()
	if not academy.is_empty():
		academy["active_research"] = job
	else:
		_local_active_research = job
	save_persistent_state()

func get_queue() -> Array:
	var academy = _get_academy_building_ref()
	if not academy.is_empty():
		return academy["research_queue"]
	return _local_research_queue

func set_queue(q: Array) -> void:
	var academy = _get_academy_building_ref()
	if not academy.is_empty():
		academy["research_queue"] = q
	else:
		_local_research_queue = q
	save_persistent_state()

func get_resource(res_type: String) -> int:
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

# Speedup options config
func _setup_speedup_buttons() -> void:
	for child in speedup_container.get_children():
		child.queue_free()
		
	var speedups = [
		{"label": "1m Focus", "seconds": 60},
		{"label": "5m Scroll", "seconds": 300},
		{"label": "15m Tome", "seconds": 900},
		{"label": "1h Decree", "seconds": 3600}
	]
	
	for s in speedups:
		var btn = Button.new()
		btn.text = "-%dm %s" % [int(s["seconds"]/60), s["label"]]
		btn.add_theme_font_size_override("font_size", 9)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(func(): apply_speedup(s["seconds"]))
		speedup_container.add_child(btn)

func apply_speedup(seconds: float) -> void:
	var active = get_active_job()
	if active.is_empty():
		return
		
	active["time_remaining"] = maxf(0.0, active["time_remaining"] - seconds)
	save_persistent_state()
	
	var node_def = _find_node_in_db(active.get("research_id", ""))
	var name_str = node_def.get("name", active["research_id"])
	
	_trigger_log_message("Applied research speedup: -%s to '%s'." % [format_duration(seconds), name_str])
	
	if active["time_remaining"] <= 0.0:
		_complete_research_job()

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
		elif get_active_job().get("research_id", "") == n_id:
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
	var path = "res://assets/ui/icons/tech_%s.png" % cat.to_lower()
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
	
	var is_researching_current = get_active_job().get("research_id", "") == node["id"]
	var is_queued_current = _is_queued(node["id"])
	
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
		# Check locks
		var unlocked = check_node_unlocked(node)["unlocked"]
		if not unlocked:
			btn_start_research.text = "LOCKED (PREREQUISITES)"
			btn_start_research.disabled = true
		else:
			# Check enough resource assets
			var affordable = check_resources_affordable(cost_data)
			var queue = get_queue()
			var is_active_busy = not get_active_job().is_empty()
			
			if is_active_busy and queue.size() >= 4:
				btn_start_research.text = "SCHOLAR LABS FULL (QUEUE 4/4)"
				btn_start_research.disabled = true
			elif not affordable:
				btn_start_research.text = "INSUFFICIENT RESOURCES"
				btn_start_research.disabled = true
			else:
				if is_active_busy:
					btn_start_research.text = "ADD TO RESEARCH QUEUE"
				else:
					btn_start_research.text = "START RESEARCH breakthrough"

# Starts active or queue research
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
	
	var active = get_active_job()
	if active.is_empty():
		set_active_job(job)
		_trigger_log_message("Begun active Scholar research: '%s' Level %d." % [node["name"], next_lvl])
	else:
		var queue = get_queue()
		queue.append(job)
		set_queue(queue)
		_trigger_log_message("Enqueued tech breakthrough: '%s' Level %d." % [node["name"], next_lvl])
		_update_queue_list_ui()
		
	# Reload tree and inspect card
	_rebuild_tech_tree()

func cancel_research_job(idx_or_active) -> void:
	var target_job = {}
	var refund_factor = 0.7 # refund 70% of costs
	
	if idx_or_active is String and idx_or_active == "active":
		target_job = get_active_job()
		if target_job.is_empty():
			return
			
		# Promote first queued item
		var queue = get_queue()
		if queue.size() > 0:
			var next_job = queue.pop_front()
			set_active_job(next_job)
			set_queue(queue)
		else:
			set_active_job({})
			
		_update_queue_list_ui()
	else:
		var queue = get_queue()
		var idx = int(idx_or_active)
		if idx >= 0 and idx < queue.size():
			target_job = queue[idx]
			queue.remove_at(idx)
			set_queue(queue)
		_update_queue_list_ui()
			
	if not target_job.is_empty():
		var node = _find_node_in_db(target_job["research_id"])
		if not node.is_empty():
			var cost_data = get_node_level_costs(node, target_job["level"])
			# Refund resources
			add_resource("food", int(cost_data["food"] * refund_factor))
			add_resource("wood", int(cost_data["wood"] * refund_factor))
			add_resource("stone", int(cost_data["stone"] * refund_factor))
			add_resource("iron", int(cost_data["iron"] * refund_factor))
			add_resource("valor", int(cost_data["valor"] * refund_factor))
			
			_trigger_log_message("Cancelled research for '%s'. Refunded 70%% resources." % node["name"])
			
	_rebuild_tech_tree()

func _complete_research_job() -> void:
	var active = get_active_job()
	if active.is_empty():
		return
		
	var n_id = active["research_id"]
	var lvl = active["level"]
	
	# Complete in research levels
	var levels = get_research_levels()
	levels[n_id] = lvl
	
	# Emit global trigger signals
	var ui = _get_ui_manager()
	if ui:
		if ui.has_signal("technology_researched"):
			ui.technology_researched.emit(n_id, lvl)
		# Power gain boost
		if "power" in ui:
			ui.power += 800 * lvl
			
	var node_def = _find_node_in_db(n_id)
	var node_name = node_def.get("name", n_id)
	_trigger_log_message("Unveiled research breakthrough! '%s' Level %d is complete." % [node_name, lvl])
	
	# Trigger reward claiming layout if possible
	if ui and ui.has_signal("reward_claimed"):
		var reward_list: Array[Dictionary] = [{
			"name": "Sovereign Research: %s Level %d" % [node_name, lvl],
			"quantity": 1,
			"rarity": 4
		}]
		ui.reward_claimed.emit(reward_list)
		
	# Promote queue
	var queue = get_queue()
	if queue.size() > 0:
		var next_job = queue.pop_front()
		set_active_job(next_job)
		set_queue(queue)
	else:
		set_active_job({})
		
	_update_queue_list_ui()
	_rebuild_tech_tree()
	save_persistent_state()

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

func _is_queued(n_id: String) -> bool:
	for job in get_queue():
		if job["research_id"] == n_id:
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
		var academy = _get_academy_building_ref()
		var lvl = int(academy.get("level", 15))
		academy_level_badge.text = "Sovereign Lvl %d" % lvl

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

func _on_close_pressed() -> void:
	visible = false
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
