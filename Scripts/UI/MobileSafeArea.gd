extends Object
class_name MobileSafeArea

## Viewport-space display safe-area margins (status bar / cutout / home indicator).
## Uses DisplayServer.get_display_safe_area() scaled through canvas_items stretch.

static var _test_margins: Dictionary = {} ## {left, top, right, bottom} or empty


static func set_test_margins(left: float, top: float, right: float, bottom: float) -> void:
	_test_margins = {
		"left": left,
		"top": top,
		"right": right,
		"bottom": bottom,
	}


static func clear_test_margins() -> void:
	_test_margins.clear()


static func margins(control: Control = null) -> Dictionary:
	if not _test_margins.is_empty():
		return _test_margins.duplicate()
	var out := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var win: Vector2i = DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return out
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var vp_size: Vector2 = Vector2(win)
	if control != null:
		vp_size = control.get_viewport_rect().size
	elif Engine.get_main_loop() is SceneTree:
		var tree := Engine.get_main_loop() as SceneTree
		if tree.root != null:
			vp_size = tree.root.get_visible_rect().size
	if vp_size.x < 1.0 or vp_size.y < 1.0:
		return out
	var sx: float = vp_size.x / float(win.x)
	var sy: float = vp_size.y / float(win.y)
	out["left"] = maxf(0.0, float(safe.position.x) * sx)
	out["top"] = maxf(0.0, float(safe.position.y) * sy)
	out["right"] = maxf(0.0, float(win.x - safe.end.x) * sx)
	out["bottom"] = maxf(0.0, float(win.y - safe.end.y) * sy)
	return out


static func top(control: Control = null) -> float:
	return float(margins(control).get("top", 0.0))


static func bottom(control: Control = null) -> float:
	return float(margins(control).get("bottom", 0.0))


static func max_top(control: Control, fallback: float) -> float:
	return maxf(fallback, top(control) + 8.0)


static func max_bottom(control: Control, fallback: float) -> float:
	return maxf(fallback, bottom(control) + 8.0)
