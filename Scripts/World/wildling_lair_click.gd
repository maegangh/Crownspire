extends Area2D

## Alliance Lair click area — TAP opens Lair popup; drag still pans MapCamera.
## Uses WorldGesture (same contract as resource tiles). Do not use press-to-open.

const WorldGestureUtil = preload("res://Scripts/World/WorldGesture.gd")

@export var lair_id: String = ""
@export var lair_level: int = 1
@export var recommended_power: int = 0
@export var species: String = ""
@export var visual_variant: String = "beast"

var lair_node: Node2D


func _ready() -> void:
	input_pickable = true
	monitoring = true
	monitorable = true
	lair_node = get_parent() as Node2D


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	# Do not mark handled on press — MapCamera must still receive drag-start.
	if event is InputEventScreenTouch:
		if event.pressed:
			WorldGestureUtil.begin_press(event.position)
		elif WorldGestureUtil.consume_release_as_tap():
			_open_panel()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			WorldGestureUtil.begin_press(event.position)
		elif WorldGestureUtil.consume_release_as_tap():
			_open_panel()


func _open_panel() -> void:
	if _is_city_teleport_placement_active():
		return
	var panel: Node = _find_lair_panel()
	if panel == null:
		push_error("[AllianceLair] WildlingLairPanel not found under HUD/")
		return
	if not panel.has_method("open_for_lair"):
		push_error("[AllianceLair] WildlingLairPanel missing open_for_lair()")
		return
	var node: Node2D = lair_node if lair_node != null else get_parent() as Node2D
	var payload: Dictionary = {}
	var lid: String = lair_id
	if node != null and "lair_id" in node:
		lid = str(node.get("lair_id"))
	if has_node("/root/AllianceLairState") and lid != "":
		payload = AllianceLairState.build_ui_payload(lid)
	if payload.is_empty():
		payload = {
			"lair_id": lid,
			"lair_level": lair_level,
			"recommended_power": recommended_power,
			"species": species,
			"visual_variant": visual_variant,
			"world_position": {
				"x": node.global_position.x if node != null else 0.0,
				"y": node.global_position.y if node != null else 0.0,
			},
			"target_type": "wildling_lair",
			"target_id": lid,
		}
		if node != null and node.has_method("get_level_def"):
			payload["level_def"] = node.call("get_level_def")
		if node != null and "display_name" in node:
			payload["display_name"] = str(node.get("display_name"))
		if node != null and "creature_title" in node:
			payload["creature_title"] = str(node.get("creature_title"))
	panel.call("open_for_lair", payload, node)
	if has_node("/root/GameEvents"):
		var wid: String = lid.strip_edges()
		if wid.is_empty():
			wid = "lair_%s_L%d" % [species.strip_edges().to_lower(), lair_level]
		GameEvents.emit_wildling_selected(wid)


func _is_city_teleport_placement_active() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var ctrl: Node = tree.root.find_child("CityTeleportController", true, false)
	return ctrl != null and ctrl.has_method("is_placement_active") and bool(ctrl.call("is_placement_active"))


func _find_lair_panel() -> Node:
	var scene: Node = get_tree().current_scene
	if scene != null:
		var panel: Node = scene.get_node_or_null("HUD/WildlingLairPanel")
		if panel != null:
			return panel
	return get_tree().root.find_child("WildlingLairPanel", true, false)
