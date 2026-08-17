extends Object
class_name ModalOutsideDismiss

## Bind a full-rect dim so a press that begins and ends outside `panel` closes it.
## The dim must use MOUSE_FILTER_STOP so the tap never reaches city/world gameplay.

const META_PRESS := "_modal_outside_press"


static func bind(dim: Control, panel: Control, close_cb: Callable) -> void:
	if dim == null or not close_cb.is_valid():
		return
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_meta(META_PRESS, false)
	if dim.has_meta("_modal_outside_bound") and bool(dim.get_meta("_modal_outside_bound")):
		return
	dim.set_meta("_modal_outside_bound", true)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		_on_dim_gui_input(dim, panel, close_cb, event)
	)


static func _on_dim_gui_input(dim: Control, panel: Control, close_cb: Callable, event: InputEvent) -> void:
	if not _is_pointer_event(event):
		return
	var gp: Vector2 = _event_global(dim, event)
	var inside_panel: bool = panel != null and is_instance_valid(panel) and panel.get_global_rect().has_point(gp)
	if _is_press(event):
		dim.set_meta(META_PRESS, not inside_panel)
		dim.accept_event()
		return
	if _is_release(event):
		var began_outside: bool = bool(dim.get_meta(META_PRESS, false))
		dim.set_meta(META_PRESS, false)
		dim.accept_event()
		if began_outside and not inside_panel and close_cb.is_valid():
			close_cb.call()


static func _is_pointer_event(event: InputEvent) -> bool:
	return event is InputEventMouseButton or event is InputEventScreenTouch


static func _is_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false


static func _is_release(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return (not mb.pressed) and mb.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	return false


static func _event_global(dim: Control, event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).global_position
	if event is InputEventScreenTouch:
		return dim.get_global_transform_with_canvas() * (event as InputEventScreenTouch).position
	return Vector2.ZERO
