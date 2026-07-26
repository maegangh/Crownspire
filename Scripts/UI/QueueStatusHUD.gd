extends Control
class_name QueueStatusHUD

## Compact right-side City queue status.
## Reads ConstructionState / ResearchState / TroopState / HealingState.
## Does not own timers or queue rules. Root + decorative children use MOUSE_FILTER_IGNORE;
## only the queue cards receive taps.

const CARD_WIDTH := 168.0
const CARD_PAD := 8.0
const COL_BG := Color(0.07, 0.08, 0.12, 0.82)
const COL_HEADER := Color(0.92, 0.88, 0.72, 1.0)
const COL_BODY := Color(0.86, 0.84, 0.78, 1.0)
const COL_TIMER := Color(0.55, 0.92, 0.72, 1.0)
const COL_IDLE := Color(0.62, 0.62, 0.66, 1.0)
const COL_PULSE := Color(1.0, 0.72, 0.28, 1.0)

var _vbox: VBoxContainer
var _construction: Dictionary = {}
var _research: Dictionary = {}
var _training: Dictionary = {}
var _healing: Dictionary = {}

var _building_names: Dictionary = {}
var _research_names: Dictionary = {}

var _pulse_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_LEFT_WIDE)
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	offset_left = 8.0
	offset_right = CARD_WIDTH + 10.0
	# Slightly higher start so four compact cards fit above the nav.
	offset_top = 196.0
	offset_bottom = -150.0
	z_index = 40

	_load_name_caches()
	_build_ui()
	_connect_signals()
	_rebuild_all_job_rows()
	_refresh_headers()
	_refresh_timers()


func _process(_delta: float) -> void:
	_refresh_timers()


func pulse_queue(kind: String) -> void:
	var card: Dictionary = {}
	match kind.strip_edges().to_lower():
		"construction", "build", "upgrade":
			card = _construction
		"research":
			card = _research
		"training", "train", "troop":
			card = _training
		"healing", "heal", "hospital":
			card = _healing
		_:
			return
	var panel: PanelContainer = card.get("panel") as PanelContainer
	if panel == null:
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	panel.modulate = COL_PULSE
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(panel, "modulate", Color.WHITE, 0.55)


# --- Setup --------------------------------------------------------------------

func _build_ui() -> void:
	_vbox = VBoxContainer.new()
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_vbox.anchor_bottom = 0.0
	_vbox.offset_bottom = 0.0
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 8)
	add_child(_vbox)

	_construction = _make_card("Construction", "_on_construction_pressed")
	_research = _make_card("Research", "_on_research_pressed")
	_training = _make_card("Training", "_on_training_pressed")
	_healing = _make_card("Healing", "_on_healing_pressed")
	_vbox.add_child(_construction["panel"])
	_vbox.add_child(_research["panel"])
	_vbox.add_child(_training["panel"])
	_vbox.add_child(_healing["panel"])


func _make_card(title: String, press_method: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = COL_BG
	style.set_corner_radius_all(8)
	style.content_margin_left = CARD_PAD
	style.content_margin_right = CARD_PAD
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(1, 1, 1, 0.12)
	panel.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	var header := Label.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.text = title
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", COL_HEADER)
	header.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(header)

	var jobs_box := VBoxContainer.new()
	jobs_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jobs_box.add_theme_constant_override("separation", 2)
	col.add_child(jobs_box)

	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.modulate = Color(1, 1, 1, 0)
	btn.tooltip_text = title
	btn.pressed.connect(Callable(self, press_method))
	panel.add_child(btn)

	return {
		"panel": panel,
		"header": header,
		"jobs_box": jobs_box,
		"title": title,
		"kind": title.to_lower(),
		"job_rows": [], # Array of { target: Label, timer: Label, key: String }
		"fingerprint": "",
	}


func _connect_signals() -> void:
	if has_node("/root/ConstructionState"):
		var cs: Node = get_node("/root/ConstructionState")
		if not cs.construction_jobs_changed.is_connected(_on_jobs_changed):
			cs.construction_jobs_changed.connect(_on_jobs_changed)
		if not cs.construction_completed.is_connected(_on_construction_completed):
			cs.construction_completed.connect(_on_construction_completed)
	if has_node("/root/ResearchState"):
		var rs: Node = get_node("/root/ResearchState")
		if not rs.research_jobs_changed.is_connected(_on_jobs_changed):
			rs.research_jobs_changed.connect(_on_jobs_changed)
		if not rs.research_completed.is_connected(_on_research_completed):
			rs.research_completed.connect(_on_research_completed)
	if has_node("/root/TroopState"):
		var ts: Node = get_node("/root/TroopState")
		if not ts.training_updated.is_connected(_on_jobs_changed):
			ts.training_updated.connect(_on_jobs_changed)
	if has_node("/root/HealingState"):
		var hs: Node = get_node("/root/HealingState")
		if not hs.healing_jobs_changed.is_connected(_on_jobs_changed):
			hs.healing_jobs_changed.connect(_on_jobs_changed)
		if not hs.healing_completed.is_connected(_on_healing_completed):
			hs.healing_completed.connect(_on_healing_completed)


func _on_jobs_changed(_a = null, _b = null) -> void:
	_rebuild_all_job_rows()
	_refresh_headers()
	_refresh_timers()


func _on_construction_completed(_id: String, _lvl: int) -> void:
	_on_jobs_changed()


func _on_research_completed(_id: String, _lvl: int) -> void:
	_on_jobs_changed()


func _on_healing_completed(_id: String, _qty: int) -> void:
	_on_jobs_changed()


# --- Rebuild job rows only when identity changes ------------------------------

func _rebuild_all_job_rows() -> void:
	_sync_card_jobs(_construction, _collect_construction_jobs())
	_sync_card_jobs(_research, _collect_research_jobs())
	_sync_card_jobs(_training, _collect_training_jobs())
	_sync_card_jobs(_healing, _collect_healing_jobs())


func _sync_card_jobs(card: Dictionary, jobs: Array) -> void:
	var fp := _jobs_fingerprint(jobs)
	if str(card.get("fingerprint", "")) == fp:
		return
	card["fingerprint"] = fp

	var jobs_box: VBoxContainer = card["jobs_box"] as VBoxContainer
	for child in jobs_box.get_children():
		child.queue_free()
	card["job_rows"] = []

	if jobs.is_empty():
		var idle_row := _make_job_row_controls("Idle", "", true)
		jobs_box.add_child(idle_row["root"])
		(card["job_rows"] as Array).append(idle_row)
		return

	for job: Dictionary in jobs:
		var row := _make_job_row_controls(
			str(job.get("target", "")),
			str(job.get("key", "")),
			false
		)
		jobs_box.add_child(row["root"])
		(card["job_rows"] as Array).append(row)


func _make_job_row_controls(target_text: String, key: String, is_idle: bool) -> Dictionary:
	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 0)

	var target := Label.new()
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.text = target_text
	target.add_theme_font_size_override("font_size", 12)
	target.add_theme_color_override("font_color", COL_IDLE if is_idle else COL_BODY)
	target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target.clip_text = true
	root.add_child(target)

	var timer := Label.new()
	timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer.text = ""
	timer.visible = not is_idle
	timer.add_theme_font_size_override("font_size", 12)
	timer.add_theme_color_override("font_color", COL_TIMER)
	root.add_child(timer)

	return {"root": root, "target": target, "timer": timer, "key": key, "idle": is_idle}


func _jobs_fingerprint(jobs: Array) -> String:
	if jobs.is_empty():
		return "idle"
	var parts: PackedStringArray = PackedStringArray()
	for job: Dictionary in jobs:
		parts.append("%s|%s" % [str(job.get("key", "")), str(job.get("target", ""))])
	return "|".join(parts)


# --- Data collectors (canonical sources) --------------------------------------

func _collect_construction_jobs() -> Array:
	var out: Array = []
	if not has_node("/root/ConstructionState"):
		return out
	var jobs: Array = ConstructionState.get_active_construction_jobs()
	for raw in jobs:
		var job: Dictionary = raw as Dictionary
		var bid := str(job.get("building_id", ""))
		var target_lvl := int(job.get("target_level", 0))
		var name := _building_display_name(bid)
		out.append({
			"key": bid,
			"target": "%s → Lv. %d" % [name, target_lvl],
			"remaining": float(job.get("time_remaining", 0.0)),
		})
	return out


func _collect_research_jobs() -> Array:
	var out: Array = []
	if not has_node("/root/ResearchState"):
		return out
	var jobs: Array = ResearchState.get_active_research_jobs()
	for raw in jobs:
		var job: Dictionary = raw as Dictionary
		var rid := str(job.get("research_id", ""))
		var lvl := int(job.get("level", 1))
		var name := _research_display_name(rid)
		# Prefer "Name" or "Name II" style — append level when useful.
		var target := name
		if lvl > 1 and not name.ends_with(str(lvl)) and not name.contains(" " + _roman(lvl)):
			target = "%s %s" % [name, _roman(lvl)]
		out.append({
			"key": rid,
			"target": target,
			"remaining": float(job.get("time_remaining", 0.0)),
		})
	return out


func _collect_training_jobs() -> Array:
	var out: Array = []
	if not has_node("/root/TroopState"):
		return out
	for troop_type: String in ["Infantry", "Marksmen", "Cavalry"]:
		if not TroopState.is_training_active(troop_type) and not TroopState.is_training_ready(troop_type):
			continue
		var amount: int = TroopState.get_training_amount(troop_type)
		var tier: int = TroopState.get_job_target_tier(troop_type)
		var job_type: String = TroopState.get_job_type(troop_type)
		var label := "%s T%d ×%d" % [troop_type, tier, amount]
		if job_type == "promote":
			var src: int = TroopState.get_job_source_tier(troop_type)
			label = "%s T%d→T%d ×%d" % [troop_type, src, tier, amount]
		var remaining: float = 0.0
		if TroopState.is_training_ready(troop_type):
			label += " Ready"
			remaining = 0.0
		else:
			remaining = TroopState.get_training_time_left(troop_type)
		out.append({
			"key": troop_type,
			"target": label,
			"remaining": remaining,
		})
	return out


func _collect_healing_jobs() -> Array:
	var out: Array = []
	if not has_node("/root/HealingState") or not HealingState.has_active_job():
		return out
	var job: Dictionary = HealingState.get_active_job()
	out.append({
		"key": str(job.get("job_id", "heal")),
		"target": "%s troops" % _format_amount(int(job.get("total_quantity", 0))),
		"remaining": float(job.get("time_remaining", 0.0)),
	})
	return out


func _refresh_headers() -> void:
	if has_node("/root/ConstructionState"):
		var used: int = ConstructionState.get_used_construction_queues()
		var limit: int = ConstructionState.get_construction_queue_limit()
		(_construction["header"] as Label).text = "Construction %d/%d" % [used, limit]
	else:
		(_construction["header"] as Label).text = "Construction"

	if has_node("/root/ResearchState"):
		var used_r: int = ResearchState.get_used_research_queues()
		var limit_r: int = ResearchState.get_research_queue_limit()
		(_research["header"] as Label).text = "Research %d/%d" % [used_r, limit_r]
	else:
		(_research["header"] as Label).text = "Research"

	var train_count := _collect_training_jobs().size()
	if train_count <= 0:
		(_training["header"] as Label).text = "Training"
	else:
		(_training["header"] as Label).text = "Training %d" % train_count

	if has_node("/root/HealingState"):
		var used_h: int = HealingState.get_used_queues()
		var limit_h: int = HealingState.get_queue_limit()
		(_healing["header"] as Label).text = "Healing %d/%d" % [used_h, limit_h]
	else:
		(_healing["header"] as Label).text = "Healing"


func _refresh_timers() -> void:
	_update_card_timers(_construction, _collect_construction_jobs())
	_update_card_timers(_research, _collect_research_jobs())
	_update_card_timers(_training, _collect_training_jobs())
	_update_card_timers(_healing, _collect_healing_jobs())


func _update_card_timers(card: Dictionary, jobs: Array) -> void:
	# If job identity drifted (e.g. completed mid-frame), rebuild once.
	var fp := _jobs_fingerprint(jobs)
	if str(card.get("fingerprint", "")) != fp:
		_sync_card_jobs(card, jobs)
		_refresh_headers()

	var rows: Array = card.get("job_rows", []) as Array
	if jobs.is_empty():
		return
	for i: int in range(mini(rows.size(), jobs.size())):
		var row: Dictionary = rows[i] as Dictionary
		if bool(row.get("idle", false)):
			continue
		var rem: float = float((jobs[i] as Dictionary).get("remaining", 0.0))
		# Prefer live remaining from state for construction/research keys.
		var key := str(row.get("key", ""))
		var kind := str(card.get("kind", ""))
		if kind == "construction" and has_node("/root/ConstructionState") and key != "":
			rem = ConstructionState.get_remaining_seconds(key)
		elif kind == "research" and has_node("/root/ResearchState") and key != "":
			var job: Dictionary = ResearchState.get_job_for(key)
			rem = float(job.get("time_remaining", rem))
		elif kind == "training" and has_node("/root/TroopState") and key != "":
			if TroopState.is_training_ready(key):
				(row["timer"] as Label).text = "Collect"
				continue
			rem = TroopState.get_training_time_left(key)
		elif kind == "healing" and has_node("/root/HealingState"):
			rem = HealingState.get_remaining_seconds()
		(row["timer"] as Label).text = _format_mmss(rem)


# --- Name helpers -------------------------------------------------------------

func _load_name_caches() -> void:
	_building_names.clear()
	if FileAccess.file_exists("res://data/buildings.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))
		if parsed is Dictionary:
			for bid in (parsed as Dictionary).keys():
				var entry: Dictionary = (parsed as Dictionary)[bid]
				if entry is Dictionary:
					_building_names[str(bid)] = str(entry.get("name", bid))

	_research_names.clear()
	if FileAccess.file_exists("res://data/research.json"):
		var rparsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/research.json"))
		if rparsed is Array:
			for entry in rparsed:
				if entry is Dictionary:
					_research_names[str(entry.get("id", ""))] = str(entry.get("name", entry.get("id", "")))


func _building_display_name(building_id: String) -> String:
	if _building_names.has(building_id):
		var full: String = str(_building_names[building_id])
		# Shorten long display names for the compact card.
		if full.begins_with("Wanderers "):
			return full.substr("Wanderers ".length())
		return full
	return building_id.capitalize().replace("_", " ")


func _research_display_name(research_id: String) -> String:
	if _research_names.has(research_id):
		return str(_research_names[research_id])
	return research_id.replace("_", " ").capitalize()


func _roman(n: int) -> String:
	match n:
		1: return "I"
		2: return "II"
		3: return "III"
		4: return "IV"
		5: return "V"
		_: return str(n)


func _format_mmss(seconds: float) -> String:
	var s: int = maxi(0, int(ceil(seconds)))
	var m: int = s / 60
	var r: int = s % 60
	if m >= 60:
		var h: int = m / 60
		m = m % 60
		return "%d:%02d:%02d" % [h, m, r]
	return "%d:%02d" % [m, r]


# --- Light tap routing (existing screens only) --------------------------------

func _on_construction_pressed() -> void:
	var jobs := _collect_construction_jobs()
	var bid := "farm"
	if not jobs.is_empty():
		bid = str((jobs[0] as Dictionary).get("key", "farm"))
	var hud := _game_hud()
	if hud == null:
		return
	var window: Node = hud.get_node_or_null("BuildingUpgradeWindow")
	if window != null and window.has_method("open_for_building"):
		window.call("open_for_building", bid)


func _on_research_pressed() -> void:
	var hud := _game_hud()
	if hud == null:
		return
	var research: Node = hud.get_node_or_null("AcademyResearchWindow")
	if research == null:
		var packed: PackedScene = load("res://Scenes/AcademyResearchWindow.tscn") as PackedScene
		if packed == null:
			return
		research = packed.instantiate()
		research.name = "AcademyResearchWindow"
		if research is Control:
			(research as Control).visible = false
			(research as Control).z_index = 200
		hud.add_child(research)
	if research.has_method("open_research"):
		research.call("open_research")


func _on_training_pressed() -> void:
	var jobs := _collect_training_jobs()
	var troop_type := "Infantry"
	if not jobs.is_empty():
		troop_type = str((jobs[0] as Dictionary).get("key", "Infantry"))
	var hud := _game_hud()
	if hud == null:
		return
	var manager: Node = hud.get_node_or_null("UIManager")
	var screen: Node = hud.get_node_or_null("ScreenRoot/TroopTrainingScreen")
	if screen != null and screen.has_method("open_for_building"):
		var building_id := ""
		if has_node("/root/TroopState"):
			building_id = TroopState.building_id_for_troop_type(troop_type)
		screen.call("open_for_building", troop_type, building_id, 1)
	if manager != null and manager.has_method("open_screen"):
		manager.call("open_screen", "TroopTrainingScreen")


func _on_healing_pressed() -> void:
	var hud := _game_hud()
	if hud == null:
		return
	var manager: Node = hud.get_node_or_null("UIManager")
	if manager != null and manager.has_method("open_screen"):
		manager.call("open_screen", "HospitalScreen")
		return
	var screen: Node = hud.get_node_or_null("ScreenRoot/HospitalScreen")
	if screen != null and screen.has_method("on_open"):
		screen.call("on_open")


func _format_amount(value: int) -> String:
	var raw: String = str(maxi(0, value))
	var out: String = ""
	var count: int = 0
	for i: int in range(raw.length() - 1, -1, -1):
		out = raw[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


func _game_hud() -> Node:
	var p: Node = get_parent()
	while p != null:
		if p.name == "GameHUD" or p.get_script() != null and str(p.get_script().resource_path).ends_with("GameHUD.gd"):
			return p
		p = p.get_parent()
	return get_tree().root.find_child("GameHUD", true, false)
