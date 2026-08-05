extends Camera2D

## City camera: pan + canonical building TAP dispatch.
##
## Architecture (single owner for activation):
## - CityGesture classifies press/move/release (relative motion, threshold 24px).
## - On TAP release, this camera physics-queries Areas under the pointer and calls
##   the building's existing activate_* methods (ResourceManager / Castle).
## - Area2D input_event is NOT required for activation (GUI Controls often block it).
## - Pan still uses the same gesture; buildings do not open after a drag.
## - Pan/zoom are clamped so the city background always fills the viewport.

const CityGestureUtil = preload("res://scripts/City/CityGesture.gd")
const BuildingNameplateUtil = preload("res://scripts/City/BuildingNameplate.gd")

@export var ui_manager: Node

var zoom_speed := 0.1
var min_zoom := 0.5
var max_zoom := 2.5

var drag_speed := 1.8
var _panning := false
var _debug_taps: bool = false
## World-space point captured at press (fallback if mouse warp/query drifts).
var _press_world_pos: Vector2 = Vector2.ZERO

## City artwork world rect (computed from Background sprite).
var _bounds_min: Vector2 = Vector2.ZERO
var _bounds_max: Vector2 = Vector2(1154, 1154)
var _bounds_ready: bool = false

## Pinch zoom state (Android).
var _pinch_active: bool = false
var _pinch_start_dist: float = 0.0
var _pinch_start_zoom: float = 1.0
var _touch_positions: Dictionary = {}


func _ready() -> void:
	zoom = Vector2(1.6, 1.6)
	CityGestureUtil.reset()
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.physics_object_picking = true
		# Secondary safeguard: avoid gray void if anything slips past clamp.
		RenderingServer.set_default_clear_color(Color(0.12, 0.16, 0.22, 1.0))
	call_deferred("_refresh_city_bounds")
	call_deferred("_clear_stale_modal_flags")
	call_deferred("_attach_orphan_building_nameplates")
	_debug_taps = OS.get_environment("CROWNSPIR_CITY_TAP_DEBUG") == "1"


func _attach_orphan_building_nameplates() -> void:
	var buildings: Node = get_parent().get_node_or_null("Buildings") if get_parent() else null
	BuildingNameplateUtil.attach_missing_under_buildings_root(buildings)


func _refresh_city_bounds() -> void:
	var bg: Sprite2D = null
	if get_parent() != null:
		bg = get_parent().get_node_or_null("Background") as Sprite2D
	if bg == null or bg.texture == null:
		_bounds_ready = false
		return
	var tex_size: Vector2 = bg.texture.get_size() * bg.scale.abs()
	var half: Vector2 = tex_size * 0.5
	_bounds_min = bg.global_position - half
	_bounds_max = bg.global_position + half
	_bounds_ready = true
	_enforce_min_zoom_for_bounds()
	_clamp_camera()


func _clear_stale_modal_flags() -> void:
	if not has_node("/root/GameState"):
		return
	var hud: Node = get_parent().get_node_or_null("GameHUD") if get_parent() else null
	var screen_open: bool = false
	if hud != null:
		var mgr: Node = hud.get_node_or_null("UIManager")
		if mgr != null and mgr.has_method("is_screen_open"):
			screen_open = bool(mgr.is_screen_open())
	if not screen_open:
		GameState.popup_open = false


func _input(event: InputEvent) -> void:
	if _is_blocked():
		if CityGestureUtil.pressing and _is_pointer_release(event):
			CityGestureUtil.end_press()
			_panning = false
		_pinch_active = false
		return

	if _handle_pinch(event):
		get_viewport().set_input_as_handled()
		return

	var probe_pos: Vector2 = _event_screen_pos(event)
	var gui_blocks_new_gesture: bool = _pointer_over_blocking_gui(probe_pos)
	if gui_blocks_new_gesture and not CityGestureUtil.pressing:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_press(event.pressed, (event as InputEventMouseButton).position)
		return

	if event is InputEventScreenTouch and event.index == 0 and not _pinch_active:
		_handle_press(event.pressed, (event as InputEventScreenTouch).position)
		return

	if not CityGestureUtil.pressing or _pinch_active:
		return

	if event is InputEventMouseMotion:
		_handle_motion((event as InputEventMouseMotion).relative)
		return
	if event is InputEventScreenDrag and event.index == 0:
		_handle_motion((event as InputEventScreenDrag).relative)


func _unhandled_input(event: InputEvent) -> void:
	if _is_blocked():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_apply_zoom(zoom.x + zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_apply_zoom(zoom.x - zoom_speed)


func _handle_pinch(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			_touch_positions[st.index] = st.position
		else:
			_touch_positions.erase(st.index)
			if _touch_positions.size() < 2:
				_pinch_active = false
		return _touch_positions.size() >= 2

	if event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		_touch_positions[sd.index] = sd.position
		if _touch_positions.size() < 2:
			return false
		var keys: Array = _touch_positions.keys()
		var p0: Vector2 = _touch_positions[keys[0]]
		var p1: Vector2 = _touch_positions[keys[1]]
		var dist: float = p0.distance_to(p1)
		if dist < 8.0:
			return true
		if not _pinch_active:
			_pinch_active = true
			_pinch_start_dist = dist
			_pinch_start_zoom = zoom.x
			CityGestureUtil.end_press()
			_panning = false
			return true
		var factor: float = dist / maxf(_pinch_start_dist, 1.0)
		_apply_zoom(_pinch_start_zoom * factor)
		return true
	return false


func _apply_zoom(new_zoom: float) -> void:
	_enforce_min_zoom_for_bounds()
	var z: float = clampf(new_zoom, min_zoom, max_zoom)
	zoom = Vector2(z, z)
	_clamp_camera()


func _enforce_min_zoom_for_bounds() -> void:
	## At minimum zoom the background must still cover the viewport.
	if not _bounds_ready:
		return
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		return
	var world_size: Vector2 = _bounds_max - _bounds_min
	if world_size.x <= 1.0 or world_size.y <= 1.0:
		return
	var min_x: float = vp_size.x / world_size.x
	var min_y: float = vp_size.y / world_size.y
	var cover: float = maxf(min_x, min_y)
	min_zoom = maxf(0.35, cover)
	if zoom.x < min_zoom:
		zoom = Vector2(min_zoom, min_zoom)


func _clamp_camera() -> void:
	if not _bounds_ready:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var half_view: Vector2 = (viewport_size * 0.5) / zoom.x
	var min_x: float = _bounds_min.x + half_view.x
	var max_x: float = _bounds_max.x - half_view.x
	var min_y: float = _bounds_min.y + half_view.y
	var max_y: float = _bounds_max.y - half_view.y
	if min_x > max_x:
		global_position.x = (_bounds_min.x + _bounds_max.x) * 0.5
	else:
		global_position.x = clampf(global_position.x, min_x, max_x)
	if min_y > max_y:
		global_position.y = (_bounds_min.y + _bounds_max.y) * 0.5
	else:
		global_position.y = clampf(global_position.y, min_y, max_y)


func _is_pointer_release(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		return true
	if event is InputEventScreenTouch and event.index == 0 and not event.pressed:
		return true
	return false


func _event_screen_pos(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	if event is InputEventMouseMotion:
		return (event as InputEventMouseMotion).position
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).position
	var vp: Viewport = get_viewport()
	return vp.get_mouse_position() if vp != null else Vector2.ZERO


func _pointer_over_blocking_gui(screen_pos: Vector2 = Vector2.INF) -> bool:
	var vp: Viewport = get_viewport()
	if vp == null:
		return false
	var hovered: Control = vp.gui_get_hovered_control()
	if hovered == null:
		return false
	if _is_building_decor_control(hovered):
		return false
	var pos: Vector2 = screen_pos
	if pos == Vector2.INF:
		pos = vp.get_mouse_position()
	## Queue cards sit over the left/top city band; prefer collect when a ready
	## Collect ClickArea is under the pointer so Farm/resource taps still work.
	if _is_under_named_ancestor(hovered, "QueueStatusHUD") and _collect_ready_under_screen(pos):
		return false
	if _pointer_inside_tutorial_spotlight_hole(pos) and not _is_tutorial_interactive_chrome(hovered):
		return false
	return true


func _is_under_named_ancestor(ctrl: Control, node_name: String) -> bool:
	var n: Node = ctrl
	while n != null:
		if str(n.name) == node_name:
			return true
		n = n.get_parent()
	return false


func _collect_ready_under_screen(screen_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state if get_world_2d() != null else null
	if space == null:
		return false
	var world_pos: Vector2 = get_canvas_transform().affine_inverse() * screen_pos
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_pos
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 0xFFFFFFFF
	var hits: Array = space.intersect_point(query, 16)
	for hit: Variant in hits:
		if typeof(hit) != TYPE_DICTIONARY:
			continue
		var collider: Variant = hit.get("collider")
		if not (collider is Area2D):
			continue
		var area: Area2D = collider as Area2D
		if area.name != "ClickArea":
			continue
		var host: Node = area.get_parent()
		if host == null or not host.has_method("activate_collect_tap"):
			continue
		if "ready_to_collect" in host and not bool(host.get("ready_to_collect")):
			continue
		return true
	return false


func _is_building_decor_control(ctrl: Control) -> bool:
	var n: Node = ctrl
	while n != null:
		if n.is_in_group("city_buildings"):
			return true
		if n is Node2D and (n.has_node("UpgradeArea") or n.has_node("ClickArea")):
			return true
		n = n.get_parent()
	return false


func _pointer_inside_tutorial_spotlight_hole(screen_pos: Vector2) -> bool:
	var hud: Node = get_parent().get_node_or_null("GameHUD") if get_parent() else null
	if hud == null and get_tree() != null:
		hud = get_tree().root.find_child("GameHUD", true, false)
	if hud == null:
		return false
	var overlay: Node = hud.get_node_or_null("TutorialOverlay")
	if overlay == null or not (overlay is CanvasItem) or not (overlay as CanvasItem).visible:
		return false
	var hole: Control = overlay.find_child("HighlightHole", true, false) as Control
	if hole == null or not hole.visible or hole.size.x < 8.0 or hole.size.y < 8.0:
		return false
	return hole.get_global_rect().has_point(screen_pos)


func _is_tutorial_interactive_chrome(ctrl: Control) -> bool:
	var n: Node = ctrl
	while n != null:
		var nm: String = str(n.name)
		if nm in ["InstructionPanel", "SkipButton", "ContinueButton", "SkipConfirm"]:
			return true
		if nm == "TutorialOverlay":
			return false
		n = n.get_parent()
	return false


func _is_blocked() -> bool:
	if has_node("/root/GameState") and GameState.ui_blocking_input:
		return true
	if has_node("/root/GameState") and GameState.popup_open:
		return true
	var hud: Node = get_parent().get_node_or_null("GameHUD") if get_parent() else null
	if hud == null and get_tree() != null:
		hud = get_tree().root.find_child("GameHUD", true, false)
	if hud != null:
		var mgr: Node = hud.get_node_or_null("UIManager")
		if mgr != null and mgr.has_method("is_screen_open") and bool(mgr.is_screen_open()):
			var screen_name: String = ""
			if mgr.has_method("get_current_screen_name"):
				screen_name = str(mgr.call("get_current_screen_name"))
			var screen: CanvasItem = null
			if not screen_name.is_empty():
				screen = hud.get_node_or_null("ScreenRoot/" + screen_name) as CanvasItem
			if screen != null and not screen.visible:
				if mgr.has_method("close_current_screen"):
					mgr.call("close_current_screen")
				return false
			return true
	return false


func _viewport_to_world(screen_pos: Vector2) -> Vector2:
	var vp: Viewport = get_viewport()
	if vp == null:
		return global_position
	var vp_size: Vector2 = vp.get_visible_rect().size
	return get_screen_center_position() + (screen_pos - vp_size * 0.5) / zoom


## Soft framing helper for tutorials / UI focus. Does not change zoom or gesture thresholds.
func focus_world_position(world_pos: Vector2) -> void:
	global_position = world_pos
	_clamp_camera()


func _handle_press(is_pressed: bool, screen_pos: Vector2) -> void:
	if is_pressed:
		if not CityGestureUtil.pressing:
			CityGestureUtil.begin_press(screen_pos)
			_press_world_pos = _viewport_to_world(screen_pos)
		_panning = false
		if _debug_taps:
			print("[CityCamera] PRESS screen=", screen_pos, " world=", _press_world_pos)
		return

	var was_drag: bool = CityGestureUtil.dragged or _panning
	var was_pressing: bool = CityGestureUtil.pressing
	CityGestureUtil.end_press()
	if _panning:
		get_viewport().set_input_as_handled()
	_panning = false

	if not was_pressing:
		return
	if was_drag:
		if _debug_taps:
			print("[CityCamera] RELEASE as PAN — no building tap")
		return

	if _debug_taps:
		print("[CityCamera] RELEASE as TAP — dispatching building")
	_dispatch_building_tap()


func _handle_motion(relative: Vector2) -> void:
	if not CityGestureUtil.pressing:
		return
	CityGestureUtil.note_motion_relative(relative)
	if not CityGestureUtil.dragged:
		return
	_panning = true
	if relative != Vector2.ZERO:
		position -= relative * drag_speed / zoom.x
		_clamp_camera()
	get_viewport().set_input_as_handled()


func _dispatch_building_tap() -> void:
	if _is_blocked():
		return
	var world: World2D = get_world_2d()
	if world == null:
		return
	var space: PhysicsDirectSpaceState2D = world.direct_space_state
	if space == null:
		return

	var query_pos: Vector2 = _press_world_pos
	if query_pos == Vector2.ZERO:
		query_pos = get_global_mouse_position()

	var query := PhysicsPointQueryParameters2D.new()
	query.position = query_pos
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 0xFFFFFFFF

	var hits: Array = space.intersect_point(query, 32)
	if hits.is_empty():
		var mouse_world: Vector2 = get_global_mouse_position()
		if mouse_world != query_pos:
			query.position = mouse_world
			hits = space.intersect_point(query, 32)

	if _debug_taps:
		print("[CityCamera] tap hits=", hits.size(), " at ", query.position)

	var click_host: Node = null
	var upgrade_host: Node = null
	for hit: Variant in hits:
		if typeof(hit) != TYPE_DICTIONARY:
			continue
		var collider: Variant = hit.get("collider")
		if not (collider is Area2D):
			continue
		var area: Area2D = collider as Area2D
		var host: Node = area.get_parent()
		if host == null:
			continue
		if area.name == "ClickArea":
			click_host = host
		elif area.name == "UpgradeArea" or area.name == "Area2D":
			upgrade_host = host

	if click_host != null and click_host.has_method("activate_collect_tap"):
		var ready: bool = true
		if "ready_to_collect" in click_host:
			ready = bool(click_host.get("ready_to_collect"))
		if ready:
			if _debug_taps:
				print("[CityCamera] activate_collect_tap on ", click_host.name)
			click_host.call("activate_collect_tap")
			return

	var host2: Node = upgrade_host
	if host2 == null and click_host != null:
		host2 = click_host
	if host2 == null:
		if _debug_taps:
			print("[CityCamera] TAP missed — no building Area under pointer")
		return

	if host2.has_method("activate_building_tap"):
		if _debug_taps:
			print("[CityCamera] activate_building_tap on ", host2.name)
		host2.call("activate_building_tap")
	elif host2.has_method("_open_upgrade_window"):
		host2.call("_open_upgrade_window")
