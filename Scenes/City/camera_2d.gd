extends Camera2D

## City camera: pan + canonical building TAP dispatch.
##
## Architecture (single owner for activation):
## - CityGesture classifies press/move/release (relative motion, threshold 24px).
## - On TAP release, this camera physics-queries Areas under the pointer and calls
##   the building's existing activate_* methods (ResourceManager / Castle).
## - Area2D input_event is NOT required for activation (GUI Controls often block it).
## - Pan still uses the same gesture; buildings do not open after a drag.

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


func _ready() -> void:
	zoom = Vector2(1.6, 1.6)
	CityGestureUtil.reset()
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.physics_object_picking = true
	# Clear stuck modal flags from prior sessions / aborted UI closes.
	call_deferred("_clear_stale_modal_flags")
	# Cover intentional buildings without ResourceManager (PetDen, HallOfLegends).
	call_deferred("_attach_orphan_building_nameplates")
	_debug_taps = OS.get_environment("CROWNSPIR_CITY_TAP_DEBUG") == "1"


func _attach_orphan_building_nameplates() -> void:
	var buildings: Node = get_parent().get_node_or_null("Buildings") if get_parent() else null
	BuildingNameplateUtil.attach_missing_under_buildings_root(buildings)


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
		# Still clear a stale gesture so the next tap can begin.
		if CityGestureUtil.pressing and _is_pointer_release(event):
			CityGestureUtil.end_press()
			_panning = false
		return

	# While a City gesture is active, keep ownership until release even if the
	# pointer drifts over HUD chrome — otherwise press/release get desynced and
	# taps never fire.
	var gui_blocks_new_gesture: bool = _pointer_over_blocking_gui()
	if gui_blocks_new_gesture and not CityGestureUtil.pressing:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Prefer event.position — get_mouse_position() can disagree under stretch/headless.
		_handle_press(event.pressed, (event as InputEventMouseButton).position)
		return

	if event is InputEventScreenTouch and event.index == 0:
		_handle_press(event.pressed, (event as InputEventScreenTouch).position)
		return

	if not CityGestureUtil.pressing:
		return

	if event is InputEventMouseMotion:
		_handle_motion((event as InputEventMouseMotion).relative)
		return
	if event is InputEventScreenDrag and event.index == 0:
		_handle_motion((event as InputEventScreenDrag).relative)


func _unhandled_input(event: InputEvent) -> void:
	if _is_blocked():
		return
	# Zoom only here (never owned by buildings).
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom += Vector2(zoom_speed, zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom -= Vector2(zoom_speed, zoom_speed)
		zoom.x = clampf(zoom.x, min_zoom, max_zoom)
		zoom.y = clampf(zoom.y, min_zoom, max_zoom)


func _is_pointer_release(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		return true
	if event is InputEventScreenTouch and event.index == 0 and not event.pressed:
		return true
	return false


func _pointer_over_blocking_gui() -> bool:
	var vp: Viewport = get_viewport()
	if vp == null:
		return false
	var hovered: Control = vp.gui_get_hovered_control()
	if hovered == null:
		return false
	# Building level badges are Controls parented under Node2D buildings — must NOT block city taps.
	if _is_building_decor_control(hovered):
		return false
	# Any other Control (HUD buttons, screens, upgrade window) keeps ownership.
	return true


func _is_building_decor_control(ctrl: Control) -> bool:
	var n: Node = ctrl
	while n != null:
		if n.is_in_group("city_buildings"):
			return true
		if n is Node2D and (n.has_node("UpgradeArea") or n.has_node("ClickArea")):
			return true
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
			return true
	return false


func _viewport_to_world(screen_pos: Vector2) -> Vector2:
	var vp: Viewport = get_viewport()
	if vp == null:
		return global_position
	var vp_size: Vector2 = vp.get_visible_rect().size
	# Camera-centered conversion — avoids stretch/canvas transform mismatches.
	return get_screen_center_position() + (screen_pos - vp_size * 0.5) / zoom


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

	# TAP — activate building under pointer via physics query (does not need Area2D input_event).
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

	# Tap query uses the press world point (stable). Mouse APIs are a fallback only.
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

	# Prefer ClickArea (collect) when present AND ready; else UpgradeArea / Castle area.
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
		# Castle fallback
		host2.call("_open_upgrade_window")
