extends Control

## Hospital healing screen — wounded by type/tier, one healing queue.
## Runtime: GameHUD/ScreenRoot/HospitalScreen

const COL_INK := Color(0.93, 0.88, 0.76, 1.0)
const COL_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COL_GOLD := Color(0.86, 0.70, 0.32, 1.0)
const COL_OK := Color(0.55, 0.82, 0.58, 1.0)
const COL_WARN := Color(1.0, 0.58, 0.40, 1.0)
const COL_PANEL := Color(0.10, 0.08, 0.13, 0.96)
const COL_CARD := Color(0.14, 0.11, 0.17, 0.94)
const COL_BORDER := Color(0.58, 0.46, 0.28, 0.90)

const FALLBACK_TOP_INSET: float = 180.0
const FALLBACK_BOTTOM_INSET: float = 190.0
const SIDE_INSET: float = 14.0
const UI_LAYOUT_VERSION: int = 1

## Selection: { infantry:{tier:qty}, ... }
var _selected: Dictionary = {"infantry": {}, "marksmen": {}, "cavalry": {}}
var _built_layout_version: int = -1
var _top_inset: float = FALLBACK_TOP_INSET
var _bottom_inset: float = FALLBACK_BOTTOM_INSET
var _refresh_accum: float = 0.0
var _row_fingerprint: String = ""

var _dim: ColorRect
var _window: PanelContainer
var _capacity_label: Label
var _job_block: VBoxContainer
var _job_title: Label
var _job_detail: Label
var _job_time: Label
var _empty_label: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _selected_label: Label
var _time_label: Label
var _cost_label: Label
var _status_label: Label
var _heal_button: Button

## kind|tier -> amount Label
var _amount_labels: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_layout()
	if has_node("/root/HealingState") and not HealingState.healing_jobs_changed.is_connected(_on_healing_changed):
		HealingState.healing_jobs_changed.connect(_on_healing_changed)
	if has_node("/root/TroopState") and not TroopState.training_updated.is_connected(_on_healing_changed):
		TroopState.training_updated.connect(_on_healing_changed)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_accum += delta
	if _refresh_accum < 0.35:
		return
	_refresh_accum = 0.0
	_refresh_job_timer_only()
	_refresh_summary_labels()


func on_open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_selected = {"infantry": {}, "marksmen": {}, "cavalry": {}}
	_row_fingerprint = ""
	_ensure_layout()
	_rebuild_rows()
	_refresh_all()


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_healing_changed(_a = null, _b = null) -> void:
	if not visible:
		return
	_rebuild_rows()
	_refresh_all()


func _close() -> void:
	if has_node("/root/UIManager"):
		UIManager.close_current_screen()
	else:
		on_close()


# --- Layout -------------------------------------------------------------------

func _ensure_layout() -> void:
	_resolve_insets()
	if _built_layout_version == UI_LAYOUT_VERSION and _window != null and is_instance_valid(_window):
		_apply_window_margins()
		return
	for child: Node in get_children():
		child.queue_free()
	_amount_labels.clear()
	_built_layout_version = UI_LAYOUT_VERSION

	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.03, 0.05, 0.62)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_window = PanelContainer.new()
	_window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, COL_BORDER, 14, 2))
	add_child(_window)
	_apply_window_margins()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_window.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "HOSPITAL"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COL_GOLD)
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(48, 48)
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	_capacity_label = Label.new()
	_capacity_label.add_theme_font_size_override("font_size", 16)
	_capacity_label.add_theme_color_override("font_color", COL_INK)
	root.add_child(_capacity_label)

	_job_block = VBoxContainer.new()
	_job_block.add_theme_constant_override("separation", 2)
	root.add_child(_job_block)
	_job_title = Label.new()
	_job_title.text = "HEALING"
	_job_title.add_theme_font_size_override("font_size", 18)
	_job_title.add_theme_color_override("font_color", COL_GOLD)
	_job_block.add_child(_job_title)
	_job_detail = Label.new()
	_job_detail.add_theme_font_size_override("font_size", 15)
	_job_detail.add_theme_color_override("font_color", COL_INK)
	_job_block.add_child(_job_detail)
	_job_time = Label.new()
	_job_time.add_theme_font_size_override("font_size", 20)
	_job_time.add_theme_color_override("font_color", COL_OK)
	_job_block.add_child(_job_time)

	var wounded_h := Label.new()
	wounded_h.text = "Wounded Troops"
	wounded_h.add_theme_font_size_override("font_size", 18)
	wounded_h.add_theme_color_override("font_color", COL_GOLD)
	root.add_child(wounded_h)

	_empty_label = Label.new()
	_empty_label.text = "No wounded troops."
	_empty_label.add_theme_font_size_override("font_size", 16)
	_empty_label.add_theme_color_override("font_color", COL_MUTED)
	root.add_child(_empty_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 280)
	root.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)

	var select_row := HBoxContainer.new()
	select_row.add_theme_constant_override("separation", 8)
	root.add_child(select_row)
	var all_btn := Button.new()
	all_btn.text = "SELECT ALL"
	all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_btn.pressed.connect(_select_all)
	select_row.add_child(all_btn)
	var clear_btn := Button.new()
	clear_btn.text = "CLEAR"
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_btn.pressed.connect(_clear_selection)
	select_row.add_child(clear_btn)

	_selected_label = Label.new()
	_selected_label.add_theme_font_size_override("font_size", 16)
	_selected_label.add_theme_color_override("font_color", COL_INK)
	root.add_child(_selected_label)
	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 16)
	_time_label.add_theme_color_override("font_color", COL_INK)
	root.add_child(_time_label)
	_cost_label = Label.new()
	_cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cost_label.add_theme_font_size_override("font_size", 15)
	_cost_label.add_theme_color_override("font_color", COL_MUTED)
	root.add_child(_cost_label)

	_heal_button = Button.new()
	_heal_button.text = "HEAL"
	_heal_button.custom_minimum_size = Vector2(0, 56)
	_heal_button.add_theme_font_size_override("font_size", 22)
	_heal_button.pressed.connect(_on_heal_pressed)
	root.add_child(_heal_button)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", COL_WARN)
	root.add_child(_status_label)


func _resolve_insets() -> void:
	_top_inset = FALLBACK_TOP_INSET
	_bottom_inset = FALLBACK_BOTTOM_INSET
	var hud: Node = get_tree().root.find_child("GameHUD", true, false)
	if hud == null:
		return
	var chrome: Control = hud.get_node_or_null("Control") as Control
	if chrome == null:
		return
	var top_bar: Control = chrome.get_node_or_null("TopBarTexture") as Control
	var bottom_bar: Control = chrome.get_node_or_null("BottomBarTexture") as Control
	if top_bar != null:
		_top_inset = maxf(FALLBACK_TOP_INSET, top_bar.size.y + 12.0)
	if bottom_bar != null:
		_bottom_inset = maxf(FALLBACK_BOTTOM_INSET, bottom_bar.size.y + 12.0)


func _apply_window_margins() -> void:
	if _window == null:
		return
	_window.offset_left = SIDE_INSET
	_window.offset_right = -SIDE_INSET
	_window.offset_top = _top_inset
	_window.offset_bottom = -_bottom_inset


# --- Rows ---------------------------------------------------------------------

func _wounded_fingerprint() -> String:
	if not has_node("/root/TroopState"):
		return "none"
	var w: Dictionary = TroopState.get_wounded_by_tiers()
	return JSON.stringify(w)


func _rebuild_rows() -> void:
	var fp: String = _wounded_fingerprint()
	if fp == _row_fingerprint and _list != null and _list.get_child_count() > 0:
		_clamp_selection_to_wounded()
		_sync_amount_labels()
		return
	_row_fingerprint = fp
	_amount_labels.clear()
	if _list == null:
		return
	for child: Node in _list.get_children():
		child.queue_free()

	if not has_node("/root/TroopState"):
		_empty_label.visible = true
		return

	var wounded: Dictionary = TroopState.get_wounded_by_tiers()
	var any: bool = false
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = wounded.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY or by_tier.is_empty():
			continue
		var tiers: Array = by_tier.keys()
		tiers.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
		if tiers.is_empty():
			continue
		any = true
		var section := Label.new()
		section.text = kind.to_upper()
		section.add_theme_font_size_override("font_size", 16)
		section.add_theme_color_override("font_color", COL_GOLD)
		_list.add_child(section)
		for tk: Variant in tiers:
			var tier: int = int(tk)
			var have: int = int(by_tier[tk])
			if have <= 0:
				continue
			_list.add_child(_make_tier_row(kind, tier, have))

	_empty_label.visible = not any
	_clamp_selection_to_wounded()


func _make_tier_row(kind: String, tier: int, wounded_qty: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(COL_CARD, Color(1, 1, 1, 0.08), 8, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var info := Label.new()
	info.text = "T%d  %s wounded" % [tier, _format_number(wounded_qty)]
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", COL_INK)
	row.add_child(info)

	row.add_child(_qty_btn("-100", kind, tier, -100))
	row.add_child(_qty_btn("-", kind, tier, -1))

	var amt := Label.new()
	amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amt.custom_minimum_size = Vector2(52, 0)
	amt.add_theme_font_size_override("font_size", 16)
	amt.add_theme_color_override("font_color", COL_OK)
	amt.text = str(_get_selected(kind, tier))
	row.add_child(amt)
	_amount_labels["%s|%d" % [kind, tier]] = amt

	row.add_child(_qty_btn("+", kind, tier, 1))
	row.add_child(_qty_btn("+100", kind, tier, 100))
	return panel


func _qty_btn(text: String, kind: String, tier: int, delta: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(48 if text.length() <= 2 else 56, 40)
	btn.pressed.connect(func() -> void: _adjust_selected(kind, tier, delta))
	return btn


func _get_selected(kind: String, tier: int) -> int:
	var by_tier: Dictionary = _selected.get(kind, {}) as Dictionary
	return int(by_tier.get(tier, by_tier.get(str(tier), 0)))


func _set_selected(kind: String, tier: int, amount: int) -> void:
	var by_tier: Dictionary = (_selected.get(kind, {}) as Dictionary).duplicate(true)
	if amount <= 0:
		by_tier.erase(tier)
		by_tier.erase(str(tier))
	else:
		by_tier[tier] = amount
	_selected[kind] = by_tier


func _adjust_selected(kind: String, tier: int, delta: int) -> void:
	var have: int = 0
	if has_node("/root/TroopState"):
		have = TroopState.get_wounded_tier_count(_display(kind), tier)
	var next: int = clampi(_get_selected(kind, tier) + delta, 0, have)
	_set_selected(kind, tier, next)
	_sync_amount_labels()
	_refresh_summary_labels()
	_status_label.text = ""


func _clamp_selection_to_wounded() -> void:
	if not has_node("/root/TroopState"):
		return
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = (_selected.get(kind, {}) as Dictionary).duplicate(true)
		for tk: Variant in by_tier.keys():
			var tier: int = int(tk)
			var have: int = TroopState.get_wounded_tier_count(_display(kind), tier)
			_set_selected(kind, tier, clampi(int(by_tier[tk]), 0, have))


func _sync_amount_labels() -> void:
	for key: Variant in _amount_labels.keys():
		var parts: PackedStringArray = str(key).split("|")
		if parts.size() != 2:
			continue
		var lbl: Label = _amount_labels[key] as Label
		if lbl == null or not is_instance_valid(lbl):
			continue
		lbl.text = str(_get_selected(parts[0], int(parts[1])))


func _select_all() -> void:
	_selected = {"infantry": {}, "marksmen": {}, "cavalry": {}}
	if has_node("/root/TroopState"):
		var wounded: Dictionary = TroopState.get_wounded_by_tiers()
		for kind: String in ["infantry", "marksmen", "cavalry"]:
			var by_tier: Dictionary = wounded.get(kind, {}) as Dictionary
			if typeof(by_tier) != TYPE_DICTIONARY:
				continue
			var copy: Dictionary = {}
			for tk: Variant in by_tier.keys():
				var qty: int = int(by_tier[tk])
				if qty > 0:
					copy[int(tk)] = qty
			_selected[kind] = copy
	_sync_amount_labels()
	_refresh_summary_labels()
	_status_label.text = ""


func _clear_selection() -> void:
	_selected = {"infantry": {}, "marksmen": {}, "cavalry": {}}
	_sync_amount_labels()
	_refresh_summary_labels()
	_status_label.text = ""


# --- Refresh ------------------------------------------------------------------

func _refresh_all() -> void:
	_refresh_capacity()
	_refresh_job_block()
	_refresh_summary_labels()


func _refresh_capacity() -> void:
	var waiting: int = 0
	var healing: int = 0
	var cap: int = 1000
	var sanctuary: int = 0
	if has_node("/root/TroopState"):
		waiting = TroopState.get_wounded_count()
		cap = TroopState.get_hospital_capacity()
		sanctuary = TroopState.get_sanctuary_count()
	if has_node("/root/HealingState"):
		healing = HealingState.get_healing_occupancy()
		cap = HealingState.get_hospital_capacity()
	var used: int = waiting + healing
	_capacity_label.text = "Hospital: %s / %s\nSanctuary: %s recovering" % [
		_format_number(used),
		_format_number(cap),
		_format_number(sanctuary),
	]


func _refresh_job_block() -> void:
	if not has_node("/root/HealingState") or not HealingState.has_active_job():
		_job_block.visible = false
		return
	_job_block.visible = true
	var job: Dictionary = HealingState.get_active_job()
	_job_detail.text = "%s troops" % _format_number(int(job.get("total_quantity", 0)))
	_job_time.text = _format_mmss(float(job.get("time_remaining", 0.0)))


func _refresh_job_timer_only() -> void:
	if _job_block == null or not _job_block.visible:
		return
	if not has_node("/root/HealingState") or not HealingState.has_active_job():
		_refresh_job_block()
		_rebuild_rows()
		return
	_job_time.text = _format_mmss(HealingState.get_remaining_seconds())


func _refresh_summary_labels() -> void:
	var qty: int = 0
	var seconds: int = 0
	var cost: Dictionary = {"food": 0, "wood": 0, "stone": 0, "iron": 0}
	if has_node("/root/HealingState"):
		qty = HealingState.count_composition(_selected)
		seconds = HealingState.estimate_heal_seconds(_selected) if qty > 0 else 0
		cost = HealingState.estimate_heal_cost(_selected) if qty > 0 else cost
	_selected_label.text = "Selected: %s troops" % _format_number(qty)
	_time_label.text = "Healing Time: %s" % (_format_mmss(float(seconds)) if qty > 0 else "—")
	_cost_label.text = "Cost:\n%s" % _format_cost(cost)

	var queue_full: bool = has_node("/root/HealingState") and not HealingState.has_free_queue()
	_heal_button.disabled = qty <= 0 or queue_full
	if queue_full and qty > 0:
		_heal_button.text = "QUEUE FULL"
	else:
		_heal_button.text = "HEAL"


func _on_heal_pressed() -> void:
	_status_label.text = ""
	if not has_node("/root/HealingState"):
		_status_label.text = "HealingState missing."
		return
	var result: Dictionary = HealingState.start_healing(_selected)
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("reason", "Heal failed."))
		_status_label.add_theme_color_override("font_color", COL_WARN)
		return
	_status_label.text = "Healing started."
	_status_label.add_theme_color_override("font_color", COL_OK)
	_selected = {"infantry": {}, "marksmen": {}, "cavalry": {}}
	_row_fingerprint = ""
	_rebuild_rows()
	_refresh_all()


# --- Helpers ------------------------------------------------------------------

func _display(kind: String) -> String:
	match kind:
		"infantry":
			return "Infantry"
		"marksmen":
			return "Marksmen"
		"cavalry":
			return "Cavalry"
		_:
			return kind.capitalize()


func _format_number(value: int) -> String:
	var raw: String = str(maxi(0, value))
	var out: String = ""
	var count: int = 0
	for i: int in range(raw.length() - 1, -1, -1):
		out = raw[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


func _format_mmss(seconds: float) -> String:
	var s: int = maxi(0, int(ceil(seconds)))
	var m: int = int(s / 60)
	var r: int = s % 60
	if m >= 60:
		var h: int = int(m / 60)
		m = m % 60
		return "%d:%02d:%02d" % [h, m, r]
	return "%02d:%02d" % [m, r]


func _format_cost(cost: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: String in ["food", "wood", "stone", "iron"]:
		var n: int = int(cost.get(key, 0))
		if n > 0:
			parts.append("%s %s" % [key.capitalize(), _format_number(n)])
	if parts.is_empty():
		return "—"
	return "  ".join(parts)


func _panel_style(bg: Color, border: Color, radius: int, border_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border_w)
	s.border_color = border
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s
