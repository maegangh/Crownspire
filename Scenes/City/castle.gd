extends Node2D

@export var building_id: String = "castle"
@export var level_label_path: NodePath
@export var click_area_path: NodePath

var _level_label: Label = null
var _click_area: Area2D = null


func _ready() -> void:
	add_to_group("city_buildings")

	_level_label = _find_level_label()
	_click_area = _find_click_area()

	if _click_area == null:
		push_warning(
			"[Castle] No Area2D click area was found. "
			+ "Set click_area_path in the Inspector."
		)
	elif not _click_area.input_event.is_connected(
		_on_click_area_input_event
	):
		_click_area.input_event.connect(
			_on_click_area_input_event
		)

	refresh_level_display()


func _on_click_area_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton

		if (
			mouse_event.button_index == MOUSE_BUTTON_LEFT
			and mouse_event.pressed
		):
			_open_upgrade_window()

	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch

		if touch_event.pressed:
			_open_upgrade_window()


func _open_upgrade_window() -> void:
	if GameState.popup_open:
		return

	var upgrade_window := get_node_or_null(
		"/root/BuildingUpgradeWindow"
	)

	if upgrade_window == null:
		upgrade_window = get_tree().root.find_child(
			"BuildingUpgradeWindow",
			true,
			false
		)

	if upgrade_window == null:
		push_error(
			"[Castle] BuildingUpgradeWindow was not found."
		)
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
	var save := ConfigFile.new()
	var load_error := save.load("user://buildings.cfg")

	if load_error != OK:
		return 1

	return int(
		save.get_value(
			building_id,
			"level",
			1
		)
	)


func _find_level_label() -> Label:
	if not level_label_path.is_empty():
		var selected_node := get_node_or_null(level_label_path)

		if selected_node is Label:
			return selected_node as Label

	var possible_names := [
		"LevelLabel",
		"BuildingLevelLabel",
		"LevelNumber",
		"Level"
	]

	for label_name in possible_names:
		var found := find_child(label_name, true, false)

		if found is Label:
			return found as Label

	return null


func _find_click_area() -> Area2D:
	if not click_area_path.is_empty():
		var selected_node := get_node_or_null(click_area_path)

		if selected_node is Area2D:
			return selected_node as Area2D

	var found := find_child(
		"Area2D",
		true,
		false
	)

	if found is Area2D:
		return found as Area2D

	for child in find_children("*", "Area2D", true, false):
		if child is Area2D:
			return child as Area2D

	return null
