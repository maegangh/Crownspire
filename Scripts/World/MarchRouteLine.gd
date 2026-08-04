extends Node2D

## World-space dotted march route. Parent under KingdomMap/Marches.
## Does not consume map input.
## Node is anchored near the route so Camera2D culling does not drop off-origin draws.

const DOT_SPACING_WORLD: float = 26.0
const DOT_RADIUS_WORLD: float = 3.4

var from_world: Vector2 = Vector2.ZERO
var to_world: Vector2 = Vector2.ZERO
var route_color: Color = Color(0.28, 0.86, 0.42, 0.92)
var _last_zoom_x: float = -1.0


func _ready() -> void:
	z_as_relative = true
	# Never block map taps.
	if has_method("set_process_input"):
		set_process_input(false)


func configure(from: Vector2, to: Vector2, color: Color, anchor_world: Vector2 = Vector2.INF) -> void:
	from_world = from
	to_world = to
	route_color = color
	_anchor_near_route(anchor_world)
	queue_redraw()


func set_endpoints(from: Vector2, to: Vector2) -> void:
	from_world = from
	to_world = to
	_anchor_near_route(Vector2.INF)
	queue_redraw()


func set_route_color(color: Color) -> void:
	route_color = color
	queue_redraw()


func _anchor_near_route(anchor_world: Vector2) -> void:
	# Keep CanvasItem near visible geometry — drawing far from node origin is culled.
	if anchor_world != Vector2.INF and anchor_world.length_squared() > 0.01:
		global_position = anchor_world
	else:
		global_position = (from_world + to_world) * 0.5


func _process(_delta: float) -> void:
	var zoom_x: float = _camera_zoom_x()
	if absf(zoom_x - _last_zoom_x) > 0.001:
		_last_zoom_x = zoom_x
		queue_redraw()


func _camera_zoom_x() -> float:
	var cam: Camera2D = get_viewport().get_camera_2d() if get_viewport() != null else null
	if cam == null:
		return 1.0
	return maxf(0.35, cam.zoom.x)


func _draw() -> void:
	var a: Vector2 = to_local(from_world)
	var b: Vector2 = to_local(to_world)
	var delta: Vector2 = b - a
	var dist: float = delta.length()
	if dist < 4.0:
		return
	var dir: Vector2 = delta / dist
	var zoom_x: float = _camera_zoom_x()
	_last_zoom_x = zoom_x
	var scale_f: float = clampf(1.0 / zoom_x, 0.55, 2.4)
	var spacing: float = DOT_SPACING_WORLD * scale_f
	var radius: float = DOT_RADIUS_WORLD * scale_f
	var t: float = 0.0
	while t <= dist:
		draw_circle(a + dir * t, radius, route_color)
		t += spacing
