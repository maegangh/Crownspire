# ==============================================================================
# Crownspire MMO - Mobile Map Camera 2D
# Godot 4.6 / GDScript 2.0 Responsive Touch Drag, Pinch-to-Zoom & PC Testing Scroll
# ==============================================================================

class_name MapCamera2D
extends Camera2D

@export_category("Zoom Parameters")
@export var min_zoom: Vector2 = Vector2(0.35, 0.35) # Max zoomed out view
@export var max_zoom: Vector2 = Vector2(2.0, 2.0)   # Max zoomed in details
@export var zoom_speed: float = 0.08
@export var zoom_sensitivity: float = 0.01          # Pinch gesture sensitivity

@export_category("Bounds & Clamps")
@export var limit_left_coord: int = -4000
@export var limit_right_coord: int = 4000
@export var limit_top_coord: int = -4000
@export var limit_bottom_coord: int = 4000

@export_category("Interaction Settings")
@export var drag_speed_modifier: float = 1.0
@export var smoothing_enabled: bool = true
@export var smoothing_weight: float = 12.0

var _target_zoom: Vector2 = Vector2.ONE
var _target_position: Vector2 = Vector2.ZERO

# Touch state tracking
var _touches: Dictionary = {} # Stores positions by touch index
var _is_dragging: bool = false
var _initial_pinch_dist: float = 0.0
var _initial_zoom: Vector2 = Vector2.ONE

func _ready() -> void:
	# Set limit boundaries
	limit_left = limit_left_coord
	limit_right = limit_right_coord
	limit_top = limit_top_coord
	limit_bottom = limit_bottom_coord
	
	_target_zoom = zoom
	_target_position = position

func _physics_process(delta: float) -> void:
	# Smoothly interpolate position and zoom for visual fluidity
	if smoothing_enabled:
		zoom = zoom.lerp(_target_zoom, smoothing_weight * delta)
		position = position.lerp(_target_position, smoothing_weight * delta)
	else:
		zoom = _target_zoom
		position = _target_position

func _unhandled_input(event: InputEvent) -> void:
	# ---------------------------------------------------------
	# PC TESTING: Mouse drag / Middle mouse click drag support
	# ---------------------------------------------------------
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Zoom In
			_adjust_zoom(zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Zoom Out
			_adjust_zoom(-zoom_speed)

	elif event is InputEventMouseMotion and _is_dragging:
		# Calculate delta adjusted for current zoom level (so drag speed matches screen pixel moves)
		var drag_delta = -event.relative * (1.0 / zoom.x) * drag_speed_modifier
		_adjust_position(drag_delta)

	# ---------------------------------------------------------
	# MOBILE DEVICE: Touch Drag & Multi-Finger Pinch-to-Zoom
	# ---------------------------------------------------------
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
			
		if _touches.size() < 2:
			_initial_pinch_dist = 0.0
			
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		
		# Single Finger Drag (Panning the view)
		if _touches.size() == 1:
			var drag_delta = -event.relative * (1.0 / zoom.x) * drag_speed_modifier
			_adjust_position(drag_delta)
			
		# Two Fingers Pinch (Scaling zoom)
		elif _touches.size() == 2:
			var touch_keys = _touches.keys()
			var p1: Vector2 = _touches[touch_keys[0]]
			var p2: Vector2 = _touches[touch_keys[1]]
			var current_dist = p1.distance_to(p2)
			
			if _initial_pinch_dist == 0.0:
				_initial_pinch_dist = current_dist
				_initial_zoom = _target_zoom
			else:
				var zoom_delta_factor = (current_dist - _initial_pinch_dist) * zoom_sensitivity
				var final_z = _initial_zoom + Vector2(zoom_delta_factor, zoom_delta_factor)
				_target_zoom = final_z.clamp(min_zoom, max_zoom)

# Safely increase/decrease zoom coordinates
func _adjust_zoom(amount: float) -> void:
	_target_zoom = (_target_zoom + Vector2(amount, amount)).clamp(min_zoom, max_zoom)

# Translate coordinates and keep camera clamped within map borders
func _adjust_position(delta_vec: Vector2) -> void:
	_target_position += delta_vec
	
	# Compute half dimensions of viewport in game units to dynamically clamp camera boundaries
	var viewport_size = get_viewport().get_visible_rect().size
	var half_view_x = (viewport_size.x / 2.0) * (1.0 / zoom.x)
	var half_view_y = (viewport_size.y / 2.0) * (1.0 / zoom.y)
	
	# Clamp target coordinates accurately
	_target_position.x = clampf(_target_position.x, limit_left_coord + half_view_x, limit_right_coord - half_view_x)
	_target_position.y = clampf(_target_position.y, limit_top_coord + half_view_y, limit_bottom_coord - half_view_y)
