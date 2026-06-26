extends Camera2D

var dragging := false

func _ready():
	enabled = true
	make_current()

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom *= Vector2(1.1, 1.1)

		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom *= Vector2(0.9, 0.9)

	if event is InputEventMouseMotion and dragging:
		position -= event.relative / zoom
