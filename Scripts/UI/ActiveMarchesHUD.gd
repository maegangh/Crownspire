extends Control

## World Map active-march status panel. Display-only over MarchState.active_marches.
## Root/decorative: MOUSE_FILTER_IGNORE. Cards: STOP (tap focuses map camera).

const CARD_WIDTH := 210.0
const CARD_PAD := 8.0
const COL_BG := Color(0.07, 0.08, 0.12, 0.88)
const COL_HEADER := Color(0.92, 0.88, 0.72, 1.0)
const COL_STATUS := Color(0.98, 0.90, 0.55, 1.0)
const COL_BODY := Color(0.86, 0.84, 0.78, 1.0)
const COL_TIMER := Color(0.55, 0.92, 0.72, 1.0)
const COL_IDLE := Color(0.62, 0.62, 0.66, 1.0)
const COL_BORDER := Color(1, 1, 1, 0.14)

var _usage_label: Label
var _empty_label: Label
var _list: VBoxContainer
var _cards: Dictionary = {} # march_id -> card dict


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = 8.0
	offset_top = 210.0
	offset_right = CARD_WIDTH + 16.0
	offset_bottom = 210.0 + 420.0
	z_index = 40
	_build_ui()
	_connect_signals()
	_reconcile_cards()
	_refresh_all_text()


func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_all_text()


func _exit_tree() -> void:
	if has_node("/root/MarchState") and MarchState.marches_changed.is_connected(_on_marches_changed):
		MarchState.marches_changed.disconnect(_on_marches_changed)


func _build_ui() -> void:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	_usage_label = Label.new()
	_usage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_usage_label.add_theme_font_size_override("font_size", 18)
	_usage_label.add_theme_color_override("font_color", COL_HEADER)
	col.add_child(_usage_label)

	_empty_label = Label.new()
	_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_label.text = "No active marches"
	_empty_label.add_theme_font_size_override("font_size", 15)
	_empty_label.add_theme_color_override("font_color", COL_IDLE)
	col.add_child(_empty_label)

	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", 8)
	col.add_child(_list)


func _connect_signals() -> void:
	if has_node("/root/MarchState") and not MarchState.marches_changed.is_connected(_on_marches_changed):
		MarchState.marches_changed.connect(_on_marches_changed)


func _on_marches_changed() -> void:
	_reconcile_cards()
	_refresh_all_text()


func _reconcile_cards() -> void:
	if not has_node("/root/MarchState"):
		return
	var live_ids: Dictionary = {}
	for march: Dictionary in MarchState.get_active_marches():
		var status: String = str(march.get("status", ""))
		if status not in [
			MarchState.STATUS_MARCHING,
			MarchState.STATUS_GATHERING,
			MarchState.STATUS_RETURNING,
			MarchState.STATUS_IN_COMBAT,
		]:
			continue
		var mid: String = str(march.get("march_id", ""))
		if mid == "":
			continue
		live_ids[mid] = true
		if not _cards.has(mid):
			var card: Dictionary = _make_card(mid)
			_cards[mid] = card
			_list.add_child(card["panel"])

	var stale: Array[String] = []
	for mid2: Variant in _cards.keys():
		if not live_ids.has(str(mid2)):
			stale.append(str(mid2))
	for sid: String in stale:
		var old: Dictionary = _cards[sid]
		var panel: Node = old.get("panel") as Node
		_cards.erase(sid)
		if panel != null and is_instance_valid(panel):
			panel.queue_free()


func _make_card(march_id: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	panel.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = COL_BG
	style.set_corner_radius_all(10)
	style.content_margin_left = CARD_PAD
	style.content_margin_right = CARD_PAD
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	style.set_border_width_all(1)
	style.border_color = COL_BORDER
	panel.add_theme_stylebox_override("panel", style)
	panel.gui_input.connect(_on_card_gui_input.bind(march_id))

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var status_l := Label.new()
	status_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_l.add_theme_font_size_override("font_size", 17)
	status_l.add_theme_color_override("font_color", COL_STATUS)
	vbox.add_child(status_l)

	var line1 := Label.new()
	line1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line1.add_theme_font_size_override("font_size", 14)
	line1.add_theme_color_override("font_color", COL_BODY)
	vbox.add_child(line1)

	var line2 := Label.new()
	line2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line2.add_theme_font_size_override("font_size", 13)
	line2.add_theme_color_override("font_color", COL_BODY)
	vbox.add_child(line2)

	var timer_l := Label.new()
	timer_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_l.add_theme_font_size_override("font_size", 18)
	timer_l.add_theme_color_override("font_color", COL_TIMER)
	vbox.add_child(timer_l)

	var recall_btn := Button.new()
	recall_btn.name = "RecallButton"
	recall_btn.text = "↩ RECALL"
	recall_btn.visible = false
	recall_btn.focus_mode = Control.FOCUS_NONE
	recall_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	recall_btn.custom_minimum_size = Vector2(0, 36)
	recall_btn.add_theme_font_size_override("font_size", 15)
	recall_btn.add_theme_color_override("font_color", Color(0.98, 0.92, 0.78, 1.0))
	var rstyle := StyleBoxFlat.new()
	rstyle.bg_color = Color(0.22, 0.14, 0.10, 0.95)
	rstyle.border_color = Color(0.85, 0.55, 0.28, 0.95)
	rstyle.set_border_width_all(1)
	rstyle.set_corner_radius_all(8)
	rstyle.content_margin_left = 8
	rstyle.content_margin_right = 8
	rstyle.content_margin_top = 6
	rstyle.content_margin_bottom = 6
	recall_btn.add_theme_stylebox_override("normal", rstyle)
	var rhover := rstyle.duplicate() as StyleBoxFlat
	rhover.bg_color = Color(0.32, 0.20, 0.12, 0.98)
	recall_btn.add_theme_stylebox_override("hover", rhover)
	recall_btn.pressed.connect(_on_recall_pressed.bind(march_id))
	vbox.add_child(recall_btn)

	return {
		"panel": panel,
		"status": status_l,
		"line1": line1,
		"line2": line2,
		"timer": timer_l,
		"recall": recall_btn,
		"march_id": march_id,
	}


func _on_recall_pressed(march_id: String) -> void:
	if not has_node("/root/MarchState"):
		return
	if not MarchState.has_method("recall_march"):
		return
	var result: Dictionary = MarchState.recall_march(march_id)
	if not bool(result.get("ok", false)):
		push_warning("[ActiveMarchesHUD] Recall failed: %s" % str(result.get("error", "")))



func _on_card_gui_input(event: InputEvent, march_id: String) -> void:
	var tapped := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		tapped = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tapped = (event as InputEventScreenTouch).pressed
	if not tapped:
		return
	if not has_node("/root/MarchState"):
		return
	var pos: Vector2 = MarchState.get_march_world_position(march_id)
	if pos == Vector2.ZERO:
		return
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var cam: Camera2D = scene.get_node_or_null("Camera2D") as Camera2D
	if cam != null and cam.has_method("focus_world_position"):
		cam.call("focus_world_position", pos)


func _refresh_all_text() -> void:
	if not has_node("/root/MarchState"):
		_usage_label.text = "Marches 0/0"
		_empty_label.visible = true
		return

	var active_count: int = MarchState.get_active_march_count()
	var max_slots: int = MarchState.MAX_ACTIVE_MARCHES
	_usage_label.text = "Marches %d/%d" % [active_count, max_slots]
	_empty_label.visible = active_count <= 0

	var now: int = int(Time.get_unix_time_from_system())
	for march: Dictionary in MarchState.get_active_marches():
		var mid: String = str(march.get("march_id", ""))
		if not _cards.has(mid):
			continue
		_update_card_text(_cards[mid], march, now)


func _update_card_text(card: Dictionary, march: Dictionary, now: int) -> void:
	var status: String = str(march.get("status", ""))
	var status_l: Label = card["status"]
	var line1: Label = card["line1"]
	var line2: Label = card["line2"]
	var timer_l: Label = card["timer"]
	var recall_btn: Button = card.get("recall") as Button

	var display_status: String = _status_label(status)
	status_l.text = display_status

	var mtype: String = str(march.get("march_type", ""))
	var lines: Dictionary = _content_lines(march, mtype, status)
	line1.text = str(lines.get("line1", ""))
	line2.text = str(lines.get("line2", ""))
	line2.visible = line2.text.strip_edges() != ""

	var remain: int = _remaining_seconds(march, status, now)
	if status == MarchState.STATUS_IN_COMBAT:
		timer_l.text = ""
		timer_l.visible = false
	else:
		timer_l.visible = true
		timer_l.text = _format_mmss(remain)

	if recall_btn != null:
		var can_recall: bool = (
			mtype == "gather"
			and (
				status == MarchState.STATUS_MARCHING
				or status == MarchState.STATUS_GATHERING
			)
		)
		recall_btn.visible = can_recall
		recall_btn.disabled = not can_recall


func _status_label(status: String) -> String:
	match status:
		MarchState.STATUS_MARCHING:
			return "MARCHING"
		MarchState.STATUS_GATHERING:
			return "GATHERING"
		MarchState.STATUS_RETURNING:
			return "RETURNING"
		MarchState.STATUS_IN_COMBAT:
			return "COMBAT"
		_:
			return status


func _content_lines(march: Dictionary, mtype: String, status: String) -> Dictionary:
	if mtype == "gather":
		return _gather_lines(march, status)
	if mtype == "join_rally" or bool(march.get("rally_banner", false)):
		return _rally_lines(march, status)
	return _wildling_lines(march, status)


func _rally_lines(march: Dictionary, status: String) -> Dictionary:
	var target: Dictionary = march.get("target_data", {}) as Dictionary
	if typeof(target) != TYPE_DICTIONARY:
		target = {}
	var level: int = int(target.get("level", 1))
	var title: String = "Lair Lv.%d" % level
	var banner: String = "⚔ RALLY"
	if bool(march.get("is_rally_leader", false)):
		banner = "⚔ RALLY LEADER"
	match status:
		MarchState.STATUS_MARCHING:
			return {"line1": "%s → %s" % [banner, title], "line2": "Alliance March"}
		MarchState.STATUS_IN_COMBAT:
			return {"line1": banner, "line2": "Lair Battle"}
		MarchState.STATUS_RETURNING:
			return {"line1": "Returning home", "line2": banner}
		_:
			return {"line1": banner, "line2": title}


func _gather_lines(march: Dictionary, status: String) -> Dictionary:
	var target: Dictionary = march.get("target_data", {}) as Dictionary
	if typeof(target) != TYPE_DICTIONARY:
		target = {}
	var display: String = str(target.get("display_name", "")).strip_edges()
	if display == "":
		display = _resource_display_name(str(march.get("resource_type", target.get("resource_type", ""))))
	var level: int = int(target.get("resource_level", target.get("level", 0)))
	var rtype: String = str(march.get("resource_type", target.get("resource_type", ""))).strip_edges().to_lower()
	var type_label: String = rtype.capitalize()
	var amount: int = int(march.get("gather_target_amount", 0))
	if status == MarchState.STATUS_RETURNING:
		amount = int(march.get("gathered_amount", amount))
	var capacity: int = int(march.get("cargo_capacity", 0))

	match status:
		MarchState.STATUS_MARCHING:
			return {
				"line1": "→ %s Lv.%d" % [display, level] if level > 0 else "→ %s" % display,
				"line2": type_label,
			}
		MarchState.STATUS_GATHERING:
			return {
				"line1": "%s Lv.%d" % [display, level] if level > 0 else display,
				"line2": "Gathering %s · Cap %s" % [_format_amount(amount), _format_amount(capacity)],
			}
		MarchState.STATUS_RETURNING:
			return {
				"line1": "%s × %s" % [type_label, _format_amount(amount)],
				"line2": display,
			}
		_:
			return {"line1": display, "line2": type_label}


func _wildling_lines(march: Dictionary, status: String) -> Dictionary:
	var target: Dictionary = march.get("target_data", {}) as Dictionary
	if typeof(target) != TYPE_DICTIONARY:
		target = {}
	var level: int = int(target.get("level", 1))
	var species: String = str(target.get("species", "Wildling")).capitalize()
	var title: String = "%s Lv.%d" % [species if species != "" else "Wildling", level]
	match status:
		MarchState.STATUS_MARCHING:
			return {"line1": "→ %s" % title, "line2": "Hunt"}
		MarchState.STATUS_IN_COMBAT:
			return {"line1": title, "line2": "In combat"}
		MarchState.STATUS_RETURNING:
			return {"line1": "Returning home", "line2": title}
		_:
			return {"line1": title, "line2": ""}


func _remaining_seconds(march: Dictionary, status: String, now: int) -> int:
	var end_unix: int = 0
	match status:
		MarchState.STATUS_MARCHING:
			end_unix = int(march.get("arrival_timestamp", 0))
		MarchState.STATUS_GATHERING:
			end_unix = int(march.get("gather_end_unix", 0))
		MarchState.STATUS_RETURNING:
			end_unix = int(march.get("return_arrival_timestamp", 0))
		_:
			return 0
	return maxi(0, end_unix - now)


func _resource_display_name(resource_type: String) -> String:
	match resource_type.strip_edges().to_lower():
		"food":
			return "Fertile Wheat Farm"
		"wood":
			return "Cedar Lumber Camp"
		"stone":
			return "Granite Stone Quarry"
		"iron":
			return "Magnetic Iron Lode"
		_:
			return resource_type.capitalize()


func _format_mmss(total_sec: int) -> String:
	var sec: int = maxi(0, total_sec)
	var m: int = int(sec / 60)
	var s: int = sec % 60
	return "%02d:%02d" % [m, s]


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
