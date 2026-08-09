extends RefCounted

## Centralized City tap-vs-drag classification.
## Drag is detected from accumulated POINTER RELATIVE motion (not absolute event.position),
## because Area2D input_event positions are not reliably in the same space as Camera motion events.
##
## Preload: const CityGestureUtil = preload("res://Scripts/City/CityGesture.gd")

## Screen-pixel deadzone for 720×1280 portrait.
const DRAG_THRESHOLD_PX: float = 24.0

static var pressing: bool = false
static var dragged: bool = false
static var press_screen_pos: Vector2 = Vector2.ZERO
static var _accum_motion: float = 0.0


static func reset() -> void:
	pressing = false
	dragged = false
	press_screen_pos = Vector2.ZERO
	_accum_motion = 0.0


static func begin_press(screen_pos: Vector2) -> void:
	# Touch + emulated mouse can both fire; keep the first press origin.
	if pressing:
		return
	pressing = true
	dragged = false
	press_screen_pos = screen_pos
	_accum_motion = 0.0


## Prefer this — uses event.relative so Area2D/camera coordinate spaces cannot falsely trip drag.
static func note_motion_relative(relative: Vector2) -> bool:
	if not pressing:
		return false
	if dragged:
		return true
	_accum_motion += relative.length()
	if _accum_motion >= DRAG_THRESHOLD_PX:
		dragged = true
		return true
	return false


static func note_motion(screen_pos: Vector2) -> bool:
	## Fallback absolute check (viewport-space positions only).
	if not pressing:
		return false
	if dragged:
		return true
	if press_screen_pos.distance_to(screen_pos) >= DRAG_THRESHOLD_PX:
		dragged = true
		return true
	return false


static func end_press() -> bool:
	## Returns true if this gesture should count as a TAP (building may open).
	var was_tap: bool = pressing and not dragged
	pressing = false
	dragged = false
	_accum_motion = 0.0
	return was_tap


## Building release handler: true only for a stationary tap. Clears gesture state.
static func consume_release_as_tap() -> bool:
	return end_press()


static func is_drag_active() -> bool:
	return pressing and dragged


static func should_suppress_building_open() -> bool:
	return dragged


## Always prefer Viewport mouse position when a Viewport is available.
static func viewport_pointer_pos(viewport: Viewport) -> Vector2:
	if viewport == null:
		return Vector2.ZERO
	return viewport.get_mouse_position()


static func event_screen_pos(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	if event is InputEventMouseMotion:
		return (event as InputEventMouseMotion).position
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).position
	return Vector2.ZERO
