extends Control

## Event Center + Royal Ascension detail (portrait).
## Runtime: GameHUD/ScreenRoot/EventsScreen

const COL_INK := Color(0.93, 0.88, 0.76, 1.0)
const COL_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COL_GOLD := Color(0.86, 0.70, 0.32, 1.0)
const COL_OK := Color(0.55, 0.82, 0.58, 1.0)
const COL_WARN := Color(1.0, 0.58, 0.40, 1.0)
const COL_PANEL := Color(0.10, 0.12, 0.18, 0.96)
const COL_CARD := Color(0.12, 0.16, 0.24, 0.94)
const COL_BORDER := Color(0.58, 0.46, 0.28, 0.90)
const COL_SAPPHIRE := Color(0.18, 0.32, 0.52, 1.0)

const TOP_SAFE: float = 168.0
const BOTTOM_SAFE: float = 188.0

var _mode: String = "center" # center | detail
var _detail_event_id: String = "royal_ascension"
var _built: bool = false
var _shell: VBoxContainer
var _title_label: Label
var _content: VBoxContainer
var _timer_label: Label
var _score_label: Label
var _status_label: Label
var _refresh_accum: float = 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if has_node("/root/EventState"):
		if not EventState.event_changed.is_connected(_on_event_changed):
			EventState.event_changed.connect(_on_event_changed)
		if not EventState.milestone_claimed.is_connected(_on_milestone_claimed):
			EventState.milestone_claimed.connect(_on_milestone_claimed)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_accum += delta
	if _refresh_accum < 0.4:
		return
	_refresh_accum = 0.0
	_refresh_timers_only()


func on_open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_mode = "center"
	_rebuild_content()


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode = "center"


func _on_event_changed() -> void:
	if visible:
		_rebuild_content()


func _on_milestone_claimed(_eid: String, _th: int) -> void:
	if visible:
		_status_label.text = "Milestone claimed."
		_status_label.add_theme_color_override("font_color", COL_OK)
		_rebuild_content()


func _build_ui() -> void:
	if _built:
		return
	_built = true
	for child: Node in get_children():
		remove_child(child)
		child.free()

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.08, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_top = TOP_SAFE
	dim.offset_bottom = -BOTTOM_SAFE
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var window := PanelContainer.new()
	window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.offset_left = 12.0
	window.offset_top = TOP_SAFE
	window.offset_right = -12.0
	window.offset_bottom = -BOTTOM_SAFE
	window.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, COL_BORDER, 16, 2))
	add_child(window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 10)
	window.add_child(margin)

	_shell = VBoxContainer.new()
	_shell.add_theme_constant_override("separation", 8)
	margin.add_child(_shell)

	var header := HBoxContainer.new()
	_shell.add_child(header)
	var back := Button.new()
	back.text = "← BACK"
	back.custom_minimum_size = Vector2(110, 44)
	back.pressed.connect(_on_back)
	header.add_child(back)

	_title_label = Label.new()
	_title_label.text = "EVENT CENTER"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", COL_GOLD)
	header.add_child(_title_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(110, 0)
	header.add_child(spacer)

	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_shell.add_child(_content)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", COL_MUTED)
	_shell.add_child(_status_label)


func _on_back() -> void:
	if _mode == "detail":
		_mode = "center"
		_rebuild_content()
		return
	var manager: Node = get_node_or_null("../../UIManager")
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	else:
		on_close()


func request_back() -> bool:
	if _mode == "detail":
		_on_back()
		return true
	return false


func _rebuild_content() -> void:
	while _content.get_child_count() > 0:
		var c: Node = _content.get_child(0)
		_content.remove_child(c)
		c.free()
	_timer_label = null
	_score_label = null
	if _mode == "detail":
		_title_label.text = "ROYAL ASCENSION"
		_build_detail()
	else:
		_title_label.text = "EVENT CENTER"
		_build_center()


func _build_center() -> void:
	var intro := Label.new()
	intro.text = "Strengthen your realm. Compete for the Crown's favor."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 14)
	intro.add_theme_color_override("font_color", COL_MUTED)
	_content.add_child(intro)

	if not has_node("/root/EventState"):
		_status_label.text = "EventState unavailable."
		return

	var snap: Dictionary = EventState.get_active_event()
	var status: String = EventState.get_event_status()
	var ended: bool = (
		status == EventState.STATUS_ENDED
		and EventState.get_current_event_id() == "royal_ascension"
	)
	var def: Dictionary = EventState.get_event_definition("royal_ascension")
	if def.is_empty():
		_status_label.text = "Royal Ascension definition missing."
		return

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(COL_CARD, COL_GOLD, 12, 1))
	_content.add_child(card)
	var cm := MarginContainer.new()
	cm.add_theme_constant_override("margin_left", 12)
	cm.add_theme_constant_override("margin_right", 12)
	cm.add_theme_constant_override("margin_top", 10)
	cm.add_theme_constant_override("margin_bottom", 10)
	card.add_child(cm)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	cm.add_child(col)

	var name_l := Label.new()
	name_l.text = str(def.get("name", "ROYAL ASCENSION"))
	name_l.add_theme_font_size_override("font_size", 22)
	name_l.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(name_l)

	var tag := Label.new()
	tag.text = str(def.get("tagline", ""))
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.add_theme_font_size_override("font_size", 14)
	tag.add_theme_color_override("font_color", COL_INK)
	col.add_child(tag)

	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 16)
	_timer_label.add_theme_color_override("font_color", COL_OK)
	col.add_child(_timer_label)

	var enter := Button.new()
	enter.text = "ENTER"
	enter.custom_minimum_size = Vector2(0, 52)
	enter.add_theme_font_size_override("font_size", 20)
	enter.pressed.connect(func() -> void:
		_mode = "detail"
		_detail_event_id = "royal_ascension"
		_rebuild_content()
	)
	col.add_child(enter)

	if snap.is_empty() and not ended:
		_timer_label.text = "NOT ACTIVE"
		_timer_label.add_theme_color_override("font_color", COL_WARN)
		_status_label.text = "Start Royal Ascension from debug controls (debug builds)."
	elif ended:
		_timer_label.text = "ENDED · Score %s" % _fmt(EventState.get_points("royal_ascension"))
		_status_label.text = "Event ended. Unclaimed milestones remain claimable."
	else:
		_timer_label.text = "ENDS IN  %s" % _fmt_hms(EventState.get_time_remaining())
		_status_label.text = "Your score: %s" % _fmt(EventState.get_points())

	if OS.is_debug_build():
		_content.add_child(_section("DEBUG"))
		var dbg := HBoxContainer.new()
		dbg.add_theme_constant_override("separation", 8)
		_content.add_child(dbg)
		dbg.add_child(_dbg_btn("START", func() -> void: EventState.debug_start_event("royal_ascension")))
		dbg.add_child(_dbg_btn("RESET", func() -> void: EventState.debug_reset_event()))
		dbg.add_child(_dbg_btn("+1000", func() -> void: EventState.debug_add_points(1000)))


func _build_detail() -> void:
	if not has_node("/root/EventState"):
		return
	var def: Dictionary = EventState.get_event_definition(_detail_event_id)
	var banner := PanelContainer.new()
	banner.custom_minimum_size = Vector2(0, 88)
	banner.add_theme_stylebox_override("panel", _panel_style(COL_SAPPHIRE, COL_GOLD, 12, 1))
	_content.add_child(banner)
	var bm := MarginContainer.new()
	bm.add_theme_constant_override("margin_left", 12)
	bm.add_theme_constant_override("margin_right", 12)
	bm.add_theme_constant_override("margin_top", 10)
	bm.add_theme_constant_override("margin_bottom", 10)
	banner.add_child(bm)
	var tag := Label.new()
	tag.text = str(def.get("tagline", ""))
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.add_theme_font_size_override("font_size", 15)
	tag.add_theme_color_override("font_color", COL_INK)
	bm.add_child(tag)

	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 18)
	_timer_label.add_theme_color_override("font_color", COL_OK)
	_content.add_child(_timer_label)

	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 26)
	_score_label.add_theme_color_override("font_color", COL_GOLD)
	_content.add_child(_score_label)

	_content.add_child(_section("MILESTONES"))
	var milestones: Array[Dictionary] = EventState.get_milestone_states(_detail_event_id)
	for m: Dictionary in milestones:
		_content.add_child(_make_milestone_row(m))

	_content.add_child(_section("HOW TO EARN"))
	var scoring: Dictionary = def.get("scoring", {}) as Dictionary
	for key: Variant in [
		"building_upgraded", "research_completed", "troop_training_completed",
		"wildling_defeated", "gathering_completed", "speedup_used",
	]:
		var rule: Variant = scoring.get(key, {})
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		var rd: Dictionary = rule as Dictionary
		var line := Label.new()
		var label: String = str(rd.get("label", key))
		var pts_txt: String = _score_rule_text(rd)
		line.text = "%-22s %s" % [label, pts_txt]
		line.add_theme_font_size_override("font_size", 13)
		line.add_theme_color_override("font_color", COL_MUTED)
		_content.add_child(line)

	_refresh_timers_only()
	_status_label.text = ""


func _make_milestone_row(m: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var th: int = int(m.get("threshold", 0))
	var state: String = str(m.get("state", "LOCKED"))
	var left := Label.new()
	left.text = _fmt(th)
	left.custom_minimum_size = Vector2(90, 0)
	left.add_theme_font_size_override("font_size", 16)
	left.add_theme_color_override("font_color", COL_INK)
	row.add_child(left)

	if state == "CLAIMED":
		var done := Label.new()
		done.text = "✓ CLAIMED"
		done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		done.add_theme_font_size_override("font_size", 15)
		done.add_theme_color_override("font_color", COL_OK)
		row.add_child(done)
	elif state == "AVAILABLE":
		var claim := Button.new()
		claim.text = "CLAIM"
		claim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		claim.custom_minimum_size = Vector2(0, 40)
		claim.pressed.connect(func() -> void:
			var res: Dictionary = EventState.claim_milestone(th, _detail_event_id)
			if not bool(res.get("ok", false)):
				_status_label.text = str(res.get("error", "Claim failed."))
				_status_label.add_theme_color_override("font_color", COL_WARN)
		)
		row.add_child(claim)
	else:
		var locked := Label.new()
		locked.text = "LOCKED"
		locked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		locked.add_theme_font_size_override("font_size", 15)
		locked.add_theme_color_override("font_color", COL_MUTED)
		row.add_child(locked)
	return row


func _refresh_timers_only() -> void:
	if not has_node("/root/EventState"):
		return
	var status: String = EventState.get_event_status()
	var pts: int = EventState.get_points()
	if _score_label != null:
		_score_label.text = "YOUR SCORE\n%s" % _fmt(pts)
	if _timer_label == null:
		return
	if status == EventState.STATUS_ACTIVE:
		_timer_label.text = "ENDS IN  %s" % _fmt_hms(EventState.get_time_remaining())
		_timer_label.add_theme_color_override("font_color", COL_OK)
	elif status == EventState.STATUS_ENDED:
		_timer_label.text = "ENDED"
		_timer_label.add_theme_color_override("font_color", COL_WARN)
	else:
		_timer_label.text = "NOT ACTIVE"
		_timer_label.add_theme_color_override("font_color", COL_WARN)


func _score_rule_text(rule: Dictionary) -> String:
	if rule.has("points"):
		return "+%d" % int(rule.get("points", 0))
	if rule.has("points_per_100_troops"):
		return "+%d / 100 troops" % int(rule.get("points_per_100_troops", 0))
	if rule.has("points_per_1000_resources"):
		return "+%d / 1,000" % int(rule.get("points_per_1000_resources", 0))
	if rule.has("points_per_minute"):
		return "+%d / minute" % int(rule.get("points_per_minute", 0))
	return ""


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", COL_GOLD)
	return l


func _dbg_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(cb)
	return b


func _panel_style(bg: Color, border: Color, radius: float, border_w: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(int(border_w))
	s.set_corner_radius_all(int(radius))
	return s


func _fmt(value: int) -> String:
	var raw: String = str(maxi(0, value))
	var out: String = ""
	var count: int = 0
	for i: int in range(raw.length() - 1, -1, -1):
		out = raw[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


func _fmt_hms(total_sec: int) -> String:
	var sec: int = maxi(0, total_sec)
	var h: int = int(sec / 3600)
	var m: int = int((sec % 3600) / 60)
	var s: int = sec % 60
	return "%02d:%02d:%02d" % [h, m, s]
