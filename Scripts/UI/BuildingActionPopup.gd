extends Control

## Small HUD-space building action chooser.
## Parent under a CanvasLayer (GameHUD). Blocks City taps while open.
##
## Generic — callers pass title + action list. Examples:
##   Research Hall: [{id:research},{id:upgrade}]
##   Troop buildings: [{id:train},{id:upgrade}]
## Do not hardcode Academy-only labels here.

signal action_chosen(action_id: String)
signal closed

const NODE_NAME := "BuildingActionPopup"
const ModalOutsideDismiss := preload("res://Scripts/UI/ModalOutsideDismiss.gd")

var _title_label: Label
var _actions_col: VBoxContainer
var _dim: ColorRect
var _panel: PanelContainer


static func present(
	parent: Node,
	title: String,
	actions: Array,
	on_action: Callable = Callable(),
	on_closed: Callable = Callable()
) -> Control:
	if parent == null:
		return null
	var existing: Node = parent.get_node_or_null(NODE_NAME)
	if existing != null:
		existing.queue_free()

	var popup: Control = (load("res://Scripts/UI/BuildingActionPopup.gd") as GDScript).new()
	popup.name = NODE_NAME
	parent.add_child(popup)
	popup.call("setup", title, actions)
	var tree: SceneTree = parent.get_tree()
	if tree != null and tree.root.get_node_or_null("UiLayerStack") != null:
		popup.set_meta("ui_layer_id", "modal:BuildingActionPopup")
		UiLayerStack.push_layer("modal:BuildingActionPopup", popup.dismiss, UiLayerStack.KIND_MODAL)
	if on_action.is_valid():
		popup.connect("action_chosen", on_action)
	if on_closed.is_valid():
		popup.connect("closed", on_closed)
	return popup


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 250
	if has_node("/root/GameState"):
		GameState.popup_open = true


func setup(title: String, actions: Array) -> void:
	_ensure_ui()
	_title_label.text = title
	while _actions_col.get_child_count() > 0:
		var c: Node = _actions_col.get_child(0)
		_actions_col.remove_child(c)
		c.free()

	for entry: Variant in actions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry as Dictionary
		var action_id: String = str(d.get("id", ""))
		var label: String = str(d.get("label", action_id))
		if action_id.is_empty():
			continue
		var btn := Button.new()
		btn.text = label
		btn.custom_minimum_size = Vector2(0, 56)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 20)
		btn.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78, 1.0))
		btn.add_theme_stylebox_override("normal", _btn_style(Color(0.14, 0.12, 0.20, 1.0)))
		btn.add_theme_stylebox_override("hover", _btn_style(Color(0.20, 0.16, 0.28, 1.0)))
		btn.add_theme_stylebox_override("pressed", _btn_style(Color(0.26, 0.18, 0.10, 1.0)))
		var captured: String = action_id
		btn.pressed.connect(func() -> void: _choose(captured))
		_actions_col.add_child(btn)


func _ensure_ui() -> void:
	if _panel != null:
		return

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.03, 0.05, 0.55)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	ModalOutsideDismiss.bind(_dim, _panel, dismiss)
	add_child(_dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(320, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)

	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.84, 0.40, 1.0))
	_title_label.text = "Building"
	header.add_child(_title_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(44, 44)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(dismiss)
	header.add_child(close_btn)

	_actions_col = VBoxContainer.new()
	_actions_col.add_theme_constant_override("separation", 10)
	col.add_child(_actions_col)


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.06, 0.12, 0.98)
	s.border_color = Color(0.72, 0.58, 0.28, 0.90)
	s.set_border_width_all(2)
	s.set_corner_radius_all(16)
	return s


func _btn_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = Color(0.55, 0.44, 0.26, 0.75)
	s.set_border_width_all(1)
	s.set_corner_radius_all(12)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _choose(action_id: String) -> void:
	# Clear chooser ownership first. Destination screens/windows re-assert popup_open if needed.
	# Leaving this true after Defense/Train/etc. permanently blocked City building taps.
	_unregister_layer()
	if has_node("/root/GameState"):
		GameState.popup_open = false
	action_chosen.emit(action_id)
	queue_free()


func dismiss() -> void:
	_unregister_layer()
	if has_node("/root/GameState"):
		GameState.popup_open = false
	closed.emit()
	queue_free()


func _unregister_layer() -> void:
	if has_node("/root/UiLayerStack"):
		UiLayerStack.remove_layer("modal:BuildingActionPopup")
