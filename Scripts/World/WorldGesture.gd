extends RefCounted

## Minimal World Map tap-vs-drag classifier (resource tiles + Wildling Lairs).
## Same 24px relative-motion threshold idea as CityGesture, but World-scoped.
## Do NOT auto-apply to Wildlings without an explicit follow-up task.
##
## Preload: const WorldGestureUtil = preload("res://Scripts/World/WorldGesture.gd")

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
	if pressing:
		return
	pressing = true
	dragged = false
	press_screen_pos = screen_pos
	_accum_motion = 0.0


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


static func end_press() -> bool:
	## Returns true if this gesture should count as a TAP.
	var was_tap: bool = pressing and not dragged
	pressing = false
	dragged = false
	_accum_motion = 0.0
	return was_tap


static func consume_release_as_tap() -> bool:
	return end_press()


static func is_drag_active() -> bool:
	return pressing and dragged
