extends Node2D

## Castle — tap activation via City camera physics query (activate_building_tap).

const CityGestureUtil = preload("res://Scripts/City/CityGesture.gd")
const BuildingNameplateUtil = preload("res://Scripts/City/BuildingNameplate.gd")

@export var building_id: String = "castle"
@export var level_label_path: NodePath
@export var click_area_path: NodePath

var _level_label: Label = null
var _click_area: Area2D = null


func _ready() -> void:
	add_to_group("city_buildings")

	_level_label = _find_level_label()
	_click_area = _find_click_area()
	_ignore_decor_controls()

	if _click_area == null:
		push_warning(
			"[Castle] No Area2D click area was found. "
			+ "Set click_area_path in the Inspector."
		)
	else:
		_click_area.input_pickable = true
		if not _click_area.input_event.is_connected(_on_click_area_input_event):
			_click_area.input_event.connect(_on_click_area_input_event)

	refresh_level_display()
	call_deferred("_attach_building_nameplate")


func _attach_building_nameplate() -> void:
	BuildingNameplateUtil.attach_to(self)


func _ignore_decor_controls() -> void:
	_ignore_controls_recursive(self)


func _ignore_controls_recursive(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Control and not (child is BaseButton):
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		if child is Control or (child is Node2D and not (child is Area2D)):
			_ignore_controls_recursive(child)


func activate_building_tap() -> void:
	if GameState.popup_open or _is_main_screen_open():
		return
	if has_node("/root/GameEvents"):
		GameEvents.emit_building_selected(building_id)
	_open_upgrade_window()


func _on_click_area_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if GameState.popup_open or _is_main_screen_open():
		return
	# Backup if Area2D picking works; camera usually consumes first via CityGesture.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			CityGestureUtil.begin_press(CityGestureUtil.viewport_pointer_pos(get_viewport()))
		elif CityGestureUtil.consume_release_as_tap():
			activate_building_tap()
	elif event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			CityGestureUtil.begin_press((event as InputEventScreenTouch).position)
		elif CityGestureUtil.consume_release_as_tap():
			activate_building_tap()


func _is_main_screen_open() -> bool:
	var hud: Node = get_tree().current_scene.get_node_or_null("GameHUD")
	if hud == null:
		hud = get_tree().root.find_child("GameHUD", true, false)
	if hud == null:
		return false
	var mgr: Node = hud.get_node_or_null("UIManager")
	return mgr != null and mgr.has_method("is_screen_open") and bool(mgr.is_screen_open())


func _open_upgrade_window() -> void:
	if GameState.popup_open:
		return

	var upgrade_window := get_node_or_null("/root/BuildingUpgradeWindow")

	if upgrade_window == null:
		upgrade_window = get_tree().root.find_child(
			"BuildingUpgradeWindow",
			true,
			false
		)

	if upgrade_window == null:
		push_error("[Castle] BuildingUpgradeWindow was not found.")
		return

	if not upgrade_window.has_method("open_for_building"):
		push_error(
			"[Castle] BuildingUpgradeWindow has no "
			+ "open_for_building() method."
		)
		return

	upgrade_window.call("open_for_building", building_id)


func refresh_level_display() -> void:
	if _level_label == null or not is_instance_valid(_level_label):
		_level_label = _find_level_label()

	if _level_label == null:
		push_warning(
			"[Castle] No level Label was found. Set "
			+ "level_label_path in the Inspector."
		)
		return

	_level_label.text = str(_load_saved_level())


func _load_saved_level() -> int:
	# Phase 0B2-A: read completed castle level from ConstructionState authority only.
	var id_key: String = building_id.strip_edges()
	if id_key.is_empty():
		id_key = "castle"
	if has_node("/root/ConstructionState") and ConstructionState.has_method("get_canonical_building_level"):
		return maxi(1, int(ConstructionState.get_canonical_building_level(id_key)))
	return 1


func _find_level_label() -> Label:
	if not level_label_path.is_empty():
		var selected_node := get_node_or_null(level_label_path)
		if selected_node is Label:
			return selected_node as Label

	for label_name in ["LevelLabel", "BuildingLevelLabel", "LevelNumber", "Level"]:
		var found := find_child(label_name, true, false)
		if found is Label:
			return found as Label

	return null


func _find_click_area() -> Area2D:
	if not click_area_path.is_empty():
		var selected_node := get_node_or_null(click_area_path)
		if selected_node is Area2D:
			return selected_node as Area2D

	var found := find_child("Area2D", true, false)
	if found is Area2D:
		return found as Area2D

	for child in find_children("*", "Area2D", true, false):
		if child is Area2D:
			return child as Area2D

	return null
