extends Control

## Live Alliance Rally lobby — countdown, participants, Join / Launch Now / Cancel.

const MobileScrollUtil = preload("res://scripts/UI/MobileScroll.gd")

const TOP_SAFE := 188.0
const BOTTOM_SAFE := 200.0

const COL_INK := Color(0.18, 0.16, 0.22, 1.0)
const COL_MUTED := Color(0.42, 0.40, 0.48, 1.0)
const COL_GOLD := Color(0.78, 0.62, 0.22, 1.0)
const COL_GOLD_BRIGHT := Color(0.92, 0.76, 0.28, 1.0)
const COL_SAPPHIRE := Color(0.22, 0.42, 0.72, 1.0)
const COL_MARBLE := Color(0.94, 0.93, 0.90, 0.98)
const COL_PANEL := Color(0.96, 0.95, 0.92, 0.98)
const COL_CARD := Color(0.91, 0.90, 0.87, 0.96)
const COL_BORDER := Color(0.78, 0.62, 0.22, 0.95)
const COL_WARN := Color(0.72, 0.28, 0.22, 1.0)
const COL_OK := Color(0.22, 0.55, 0.36, 1.0)

var _rally: Dictionary = {}
var _title_label: Label
var _leader_label: Label
var _countdown_label: Label
var _troops_label: Label
var _power_label: Label
var _status_label: Label
var _participant_list: VBoxContainer
var _join_btn: Button
var _launch_btn: Button
var _leave_btn: Button
var _cancel_btn: Button
var _close_btn: Button
var _pulse_tween: Tween


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	if has_node("/root/RallyBackend"):
		if not RallyBackend.rally_updated.is_connected(_on_rally_signal):
			RallyBackend.rally_updated.connect(_on_rally_signal)
		if not RallyBackend.rallies_changed.is_connected(_on_rallies_changed):
			RallyBackend.rallies_changed.connect(_on_rallies_changed)
		if not RallyBackend.rally_launched.is_connected(_on_rally_launched):
			RallyBackend.rally_launched.connect(_on_rally_launched)
		if not RallyBackend.rally_cancelled.is_connected(_on_rally_cancelled):
			RallyBackend.rally_cancelled.connect(_on_rally_cancelled)
		if not RallyBackend.rally_completed.is_connected(_on_rally_completed):
			RallyBackend.rally_completed.connect(_on_rally_completed)


func _process(_delta: float) -> void:
	if visible and not _rally.is_empty():
		_refresh_countdown()


func on_open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 42
	_refresh()
	_play_open_anim()


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func open_for_rally(rally: Dictionary) -> void:
	_rally = rally.duplicate(true)
	_build_ui()
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("open_screen"):
		manager.open_screen("RallyLobbyScreen")
	else:
		on_open()


func _on_rally_signal(rally: Dictionary) -> void:
	if str(rally.get("rally_id", "")) == str(_rally.get("rally_id", "")):
		_rally = rally.duplicate(true)
		_refresh()


func _on_rallies_changed(rallies: Array) -> void:
	var rid: String = str(_rally.get("rally_id", ""))
	if rid == "":
		return
	for r in rallies:
		if typeof(r) == TYPE_DICTIONARY and str(r.get("rally_id", "")) == rid:
			_rally = r.duplicate(true)
			_refresh()
			return


func _on_rally_launched(rally: Dictionary) -> void:
	if str(rally.get("rally_id", "")) != str(_rally.get("rally_id", "")):
		return
	_rally = rally.duplicate(true)
	_refresh()
	_play_launch_anim()
	if _status_label != null:
		_status_label.text = "Rally launched — marches en route."
		_status_label.add_theme_color_override("font_color", COL_SAPPHIRE)


func _on_rally_cancelled(rally: Dictionary) -> void:
	if str(rally.get("rally_id", "")) != str(_rally.get("rally_id", "")):
		return
	_rally = rally.duplicate(true)
	_refresh()
	if _status_label != null:
		_status_label.text = "Rally cancelled. Troops returning."
		_status_label.add_theme_color_override("font_color", COL_WARN)


func _on_rally_completed(rally: Dictionary) -> void:
	if str(rally.get("rally_id", "")) != str(_rally.get("rally_id", "")):
		return
	_rally = rally.duplicate(true)
	_refresh()
	_open_report(rally)


func _build_ui() -> void:
	for child: Node in get_children():
		child.queue_free()
	_participant_list = null

	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.08, 0.12, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_top = TOP_SAFE
	dim.offset_bottom = -BOTTOM_SAFE
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var window := PanelContainer.new()
	window.name = "LobbyWindow"
	window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.offset_left = 12.0
	window.offset_top = TOP_SAFE
	window.offset_right = -12.0
	window.offset_bottom = -BOTTOM_SAFE
	window.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, COL_BORDER, 16, 2))
	add_child(window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	window.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	_title_label = Label.new()
	_title_label.text = "ALLIANCE RALLY"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 26)
	_title_label.add_theme_color_override("font_color", COL_GOLD)
	header.add_child(_title_label)

	_close_btn = _chrome_button("X", Vector2(64, 48))
	_close_btn.pressed.connect(_on_close)
	header.add_child(_close_btn)

	_leader_label = Label.new()
	_leader_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leader_label.add_theme_font_size_override("font_size", 18)
	_leader_label.add_theme_color_override("font_color", COL_INK)
	root.add_child(_leader_label)

	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 42)
	_countdown_label.add_theme_color_override("font_color", COL_SAPPHIRE)
	root.add_child(_countdown_label)

	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 24)
	root.add_child(stats)
	_troops_label = Label.new()
	_troops_label.add_theme_font_size_override("font_size", 18)
	_troops_label.add_theme_color_override("font_color", COL_INK)
	stats.add_child(_troops_label)
	_power_label = Label.new()
	_power_label.add_theme_font_size_override("font_size", 18)
	_power_label.add_theme_color_override("font_color", COL_GOLD)
	stats.add_child(_power_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	MobileScrollUtil.ensure(self, scroll, "MobileScrollRallyLobby")
	root.add_child(scroll)

	_participant_list = VBoxContainer.new()
	_participant_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_participant_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_participant_list)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", COL_MUTED)
	root.add_child(_status_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)

	_join_btn = _primary_button("JOIN RALLY")
	_join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_btn.pressed.connect(_on_join)
	actions.add_child(_join_btn)

	_launch_btn = _primary_button("LAUNCH NOW")
	_launch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_launch_btn.pressed.connect(_on_launch)
	actions.add_child(_launch_btn)

	var secondary := HBoxContainer.new()
	secondary.add_theme_constant_override("separation", 8)
	root.add_child(secondary)
	_leave_btn = _chrome_button("LEAVE", Vector2(0, 52))
	_leave_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_leave_btn.pressed.connect(_on_leave)
	secondary.add_child(_leave_btn)
	_cancel_btn = _chrome_button("CANCEL RALLY", Vector2(0, 52))
	_cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_btn.pressed.connect(_on_cancel)
	secondary.add_child(_cancel_btn)

	_refresh()


func _refresh() -> void:
	if _rally.is_empty():
		return
	var level: int = int(_rally.get("lair_level", 1))
	if _title_label != null:
		_title_label.text = "RALLY · LAIR Lv.%d" % level
	if _leader_label != null:
		_leader_label.text = "Leader: %s" % str(_rally.get("leader_display_name", "—"))
	if _troops_label != null:
		_troops_label.text = "Troops %d" % int(_rally.get("total_troops", 0))
	if _power_label != null:
		_power_label.text = "Power %s" % _format_power(int(_rally.get("total_power", 0)))
	_refresh_countdown()
	_rebuild_participants()
	_refresh_buttons()


func _refresh_countdown() -> void:
	if _countdown_label == null:
		return
	var status: String = str(_rally.get("status", ""))
	if status == "FORMING":
		var remain: int = int(_rally.get("remaining_seconds", 0))
		var launch_at: int = int(_rally.get("launch_at", 0))
		if launch_at > 0:
			remain = maxi(0, launch_at - int(Time.get_unix_time_from_system()))
		_countdown_label.text = "%02d:%02d" % [int(remain / 60), remain % 60]
		_countdown_label.add_theme_color_override("font_color", COL_SAPPHIRE if remain > 10 else COL_WARN)
	elif status == "LAUNCHED":
		_countdown_label.text = "LAUNCHED"
		_countdown_label.add_theme_color_override("font_color", COL_OK)
	elif status == "COMPLETED":
		_countdown_label.text = "COMPLETE"
	elif status == "CANCELLED":
		_countdown_label.text = "CANCELLED"
		_countdown_label.add_theme_color_override("font_color", COL_WARN)
	else:
		_countdown_label.text = status


func _rebuild_participants() -> void:
	if _participant_list == null:
		return
	for c in _participant_list.get_children():
		c.queue_free()
	var parts: Array = _rally.get("participants", [])
	var header := Label.new()
	header.text = "Participants (%d / %d)" % [parts.size(), int(_rally.get("max_participants", 10))]
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", COL_GOLD)
	_participant_list.add_child(header)
	for p in parts:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _panel_style(COL_CARD, Color(0.70, 0.78, 0.90, 0.8), 10, 1))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		row.add_child(hb)
		var name_l := Label.new()
		name_l.text = str(p.get("display_name", "Player"))
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.add_theme_color_override("font_color", COL_INK)
		name_l.add_theme_font_size_override("font_size", 16)
		hb.add_child(name_l)
		var troops := 0
		var tc: Dictionary = p.get("troop_counts", {}) as Dictionary
		troops = int(tc.get("infantry", 0)) + int(tc.get("marksmen", 0)) + int(tc.get("cavalry", 0))
		var meta := Label.new()
		meta.text = "%d · %s" % [troops, _format_power(int(p.get("power", 0)))]
		meta.add_theme_color_override("font_color", COL_MUTED)
		meta.add_theme_font_size_override("font_size", 14)
		hb.add_child(meta)
		_participant_list.add_child(row)


func _refresh_buttons() -> void:
	var uid := _local_user_id()
	var is_leader: bool = str(_rally.get("leader_user_id", "")) == uid and uid != ""
	var joined: bool = false
	for p in _rally.get("participants", []):
		if typeof(p) == TYPE_DICTIONARY and str(p.get("user_id", "")) == uid:
			joined = true
			break
	var forming: bool = str(_rally.get("status", "")) == "FORMING"
	if _join_btn != null:
		_join_btn.visible = forming and not joined
		_join_btn.disabled = not _join_btn.visible
	if _launch_btn != null:
		_launch_btn.visible = forming and is_leader
		_launch_btn.disabled = not _launch_btn.visible
	if _leave_btn != null:
		_leave_btn.visible = forming and joined and not is_leader
		_leave_btn.disabled = not _leave_btn.visible
	if _cancel_btn != null:
		_cancel_btn.visible = forming and is_leader
		_cancel_btn.disabled = not _cancel_btn.visible


func _on_join() -> void:
	var setup: Node = _find_setup()
	if setup != null and setup.has_method("open_to_join"):
		setup.call("open_to_join", _rally.duplicate(true))
	elif _status_label != null:
		_status_label.text = "Rally setup unavailable."


func _on_launch() -> void:
	if not has_node("/root/RallyBackend"):
		return
	_launch_btn.disabled = true
	if _status_label != null:
		_status_label.text = "Launching…"
	var result: Dictionary = await RallyBackend.launch_rally(str(_rally.get("rally_id", "")), false)
	if not bool(result.get("ok", false)):
		if _status_label != null:
			_status_label.text = str(result.get("error", "Launch failed"))
			_status_label.add_theme_color_override("font_color", COL_WARN)
		_refresh_buttons()
	else:
		_rally = result.get("rally", _rally)
		_refresh()
		_play_launch_anim()


func _on_leave() -> void:
	if not has_node("/root/RallyBackend"):
		return
	var rid: String = str(_rally.get("rally_id", ""))
	var result: Dictionary = await RallyBackend.leave_rally(rid)
	if bool(result.get("ok", false)) and has_node("/root/MarchState"):
		MarchState.refund_rally_reservation(rid)
	_on_close()


func _on_cancel() -> void:
	if not has_node("/root/RallyBackend"):
		return
	var result: Dictionary = await RallyBackend.cancel_rally(str(_rally.get("rally_id", "")))
	if not bool(result.get("ok", false)) and _status_label != null:
		_status_label.text = str(result.get("error", "Cancel failed"))
		_status_label.add_theme_color_override("font_color", COL_WARN)


func _on_close() -> void:
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	else:
		on_close()


func _open_report(rally: Dictionary) -> void:
	var report: Node = get_tree().root.find_child("RallyReportScreen", true, false)
	if report != null and report.has_method("open_for_rally"):
		report.call("open_for_rally", rally.duplicate(true))


func _find_setup() -> Node:
	var scene: Node = get_tree().current_scene
	if scene != null:
		var via: Node = scene.get_node_or_null("GameHUD/ScreenRoot/RallySetupScreen")
		if via != null:
			return via
	return get_tree().root.find_child("RallySetupScreen", true, false)


func _local_user_id() -> String:
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if nc != null and nc.has_method("get_user_id"):
		return str(nc.get_user_id())
	return ""


func _play_open_anim() -> void:
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.22)


func _play_launch_anim() -> void:
	if _countdown_label == null:
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_countdown_label, "scale", Vector2(1.15, 1.15), 0.15)
	_pulse_tween.tween_property(_countdown_label, "scale", Vector2.ONE, 0.2)


func _format_power(v: int) -> String:
	if v >= 1000000:
		return "%.1fM" % (float(v) / 1000000.0)
	if v >= 1000:
		return "%.1fK" % (float(v) / 1000.0)
	return str(v)


func _chrome_button(text: String, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", COL_INK)
	btn.add_theme_stylebox_override("normal", _panel_style(COL_MARBLE, COL_BORDER, 10, 2))
	return btn


func _primary_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 64)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(0.98, 0.96, 0.92, 1.0))
	btn.add_theme_stylebox_override("normal", _panel_style(COL_SAPPHIRE, COL_GOLD_BRIGHT, 12, 2))
	return btn


func _panel_style(bg: Color, border: Color, radius: int, border_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s
