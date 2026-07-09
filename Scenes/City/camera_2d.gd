extends Camera2D

@export var ui_manager: Node

var zoom_speed := 0.1
var min_zoom := 0.5
var max_zoom := 2.5

var drag_speed := 1.8
var dragging := false

func _ready():
	zoom = Vector2(1.6, 1.6)

func _unhandled_input(event):
	if GameState.ui_blocking_input:
		return

	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom += Vector2(zoom_speed, zoom_speed)

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom -= Vector2(zoom_speed, zoom_speed)

		zoom.x = clamp(zoom.x, min_zoom, max_zoom)
		zoom.y = clamp(zoom.y, min_zoom, max_zoom)

	elif event is InputEventMouseMotion and dragging:
		position -= event.relative * drag_speed / zoom.x
