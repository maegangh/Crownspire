extends Node

## Small shared helper for Crownspire mobile scroll UX.
## - Hides scrollbar thumbs while keeping ScrollContainer scroll working
## - Desktop mouse-drag mirrors finger swipe
## - Tap-vs-swipe guard so buttons/cards don't fire after a drag
##
## Prefer: preload("res://Scripts/UI/MobileScroll.gd").ensure(...)
## class_name is also declared for editor convenience after project scan.

class_name MobileScroll

const DRAG_THRESHOLD_PX: float = 14.0
const WHEEL_STEP_PX: int = 48

var scroll: ScrollContainer
var enabled: bool = true

var _drag_tracking: bool = false
var _drag_moved: bool = false
var _drag_start: Vector2 = Vector2.ZERO


static func configure(scroll_container: ScrollContainer) -> void:
	if scroll_container == null:
		return
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll_container.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll_container.scroll_deadzone = int(DRAG_THRESHOLD_PX)


## Parent a MobileScroll under host (or reuse one) bound to the given ScrollContainer.
static func ensure(host: Node, scroll_container: ScrollContainer, node_name: String = "MobileScroll") -> Node:
	if host == null or scroll_container == null:
		return null
	var existing: Node = host.get_node_or_null(node_name)
	if existing == null:
		existing = (load("res://Scripts/UI/MobileScroll.gd") as GDScript).new()
		existing.name = node_name
		host.add_child(existing)
	if existing.has_method("bind"):
		existing.call("bind", scroll_container)
	return existing


func bind(scroll_container: ScrollContainer) -> void:
	scroll = scroll_container
	configure(scroll)


func set_enabled(is_enabled: bool) -> void:
	enabled = is_enabled
	if not enabled:
		_drag_tracking = false
		_drag_moved = false


func was_drag() -> bool:
	return _drag_moved


## Wire tap action that is suppressed after a scroll gesture.
func wire_tap(control: Control, action: Callable) -> void:
	if control == null or not action.is_valid():
		return
	if control is BaseButton:
		var btn := control as BaseButton
		btn.pressed.connect(func() -> void:
			if _drag_moved:
				return
			action.call()
		)
	else:
		control.mouse_filter = Control.MOUSE_FILTER_STOP
		control.gui_input.connect(func(event: InputEvent) -> void:
			if _is_pointer_release(event) and not _drag_moved:
				action.call()
		)


func _is_pointer_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	return false


func _is_over_scroll(screen_pos: Vector2) -> bool:
	if scroll == null or not scroll.is_visible_in_tree():
		return false
	return scroll.get_global_rect().has_point(screen_pos)


func _clear_drag_moved_flag() -> void:
	_drag_moved = false


func _apply_drag(relative: Vector2) -> void:
	if scroll == null:
		return
	scroll.scroll_vertical = int(scroll.scroll_vertical - relative.y)


func _input(event: InputEvent) -> void:
	if not enabled or scroll == null:
		return

	if event is InputEventMouseButton:
		var wheel := event as InputEventMouseButton
		if wheel.pressed and _is_over_scroll(wheel.position):
			if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
				scroll.scroll_vertical = int(scroll.scroll_vertical - WHEEL_STEP_PX)
				get_viewport().set_input_as_handled()
				return
			if wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				scroll.scroll_vertical = int(scroll.scroll_vertical + WHEEL_STEP_PX)
				get_viewport().set_input_as_handled()
				return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _is_over_scroll(touch.position):
				_drag_tracking = true
				_drag_moved = false
				_drag_start = touch.position
		else:
			_drag_tracking = false
			call_deferred("_clear_drag_moved_flag")
		return

	if event is InputEventScreenDrag and _drag_tracking:
		var drag := event as InputEventScreenDrag
		if not _drag_moved and _drag_start.distance_to(drag.position) >= DRAG_THRESHOLD_PX:
			_drag_moved = true
		if _drag_moved:
			_apply_drag(drag.relative)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if _is_over_scroll(mb.position):
				_drag_tracking = true
				_drag_moved = false
				_drag_start = mb.position
		else:
			_drag_tracking = false
			call_deferred("_clear_drag_moved_flag")
		return

	if event is InputEventMouseMotion and _drag_tracking:
		var motion := event as InputEventMouseMotion
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			return
		if not _drag_moved and _drag_start.distance_to(motion.position) >= DRAG_THRESHOLD_PX:
			_drag_moved = true
		if _drag_moved:
			_apply_drag(motion.relative)
			get_viewport().set_input_as_handled()
