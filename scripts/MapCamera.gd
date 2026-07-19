extends Camera2D

@export var map_size: Vector2 = Vector2(8192, 8192)
@export var zoom_min: float = 0.35
@export var zoom_max: float = 2.5
@export var zoom_step: float = 0.12

var dragging: bool = false

@onready var player_castle: Node2D = $"../PlayerCastleMarker"

func _ready() -> void:
	map_size = Vector2(8192, 8192)

	limit_left = 0
	limit_top = 0
	limit_right = int(map_size.x)
	limit_bottom = int(map_size.y)
	limit_smoothed = false

	zoom = Vector2(1.5, 1.5)
	make_current()

	# Wait until the castle and world have finished loading.
	await get_tree().process_frame
	await get_tree().process_frame

	global_position = player_castle.global_position
	_clamp_camera()

	print("Castle position: ", player_castle.global_position)
	print("Camera position: ", global_position)
	
	

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_apply_zoom(zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_apply_zoom(-zoom_step)

	elif event is InputEventMouseMotion and dragging:
		global_position -= event.relative / zoom.x
		_clamp_camera()

func _apply_zoom(amount: float) -> void:
	var new_zoom: float = clampf(zoom.x + amount, zoom_min, zoom_max)
	zoom = Vector2(new_zoom, new_zoom)
	_clamp_camera()

func _clamp_camera() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var half_view: Vector2 = (viewport_size * 0.5) / zoom.x

	var min_x: float = half_view.x
	var max_x: float = map_size.x - half_view.x
	var min_y: float = half_view.y
	var max_y: float = map_size.y - half_view.y

	if min_x > max_x:
		global_position.x = map_size.x / 2.0
	else:
		global_position.x = clampf(global_position.x, min_x, max_x)

	if min_y > max_y:
		global_position.y = map_size.y / 2.0
	else:
		global_position.y = clampf(global_position.y, min_y, max_y)
