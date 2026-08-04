extends Camera2D

@export var map_size: Vector2 = Vector2(8192, 8192)
@export var zoom_min: float = 0.35
@export var zoom_max: float = 2.5
@export var zoom_step: float = 0.12

const WorldGestureUtil = preload("res://scripts/World/WorldGesture.gd")

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
	# Required for Area2D castle/resource/lair taps (City camera already enables this).
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.physics_object_picking = true

	# Wait until the castle and world have finished loading.
	# City↔World change_scene can free this node mid-await; never touch get_tree() blindly.
	await _await_process_frames(2)
	if not is_inside_tree():
		return
	if player_castle == null or not is_instance_valid(player_castle):
		return

	global_position = player_castle.global_position
	_clamp_camera()

	print("Castle position: ", player_castle.global_position)
	print("Camera position: ", global_position)


## Await N process frames safely. Aborts if this camera leaves the SceneTree
## (common during rapid KingdomMap ↔ City scene switches).
func _await_process_frames(count: int) -> void:
	for _i in range(maxi(0, count)):
		if not is_inside_tree():
			return
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
			# Feed WorldGesture for resource-tile tap-vs-drag (does not change pan feel).
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					WorldGestureUtil.begin_press(event.position)
				else:
					# Let Area2D ClickArea consume release-as-tap first; clear leftovers after.
					call_deferred("_clear_world_gesture_if_still_pressing")
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_apply_zoom(zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_apply_zoom(-zoom_step)

	elif event is InputEventScreenTouch:
		if event.pressed:
			dragging = true
			WorldGestureUtil.begin_press(event.position)
		else:
			dragging = false
			call_deferred("_clear_world_gesture_if_still_pressing")

	elif event is InputEventMouseMotion and dragging:
		WorldGestureUtil.note_motion_relative(event.relative)
		global_position -= event.relative / zoom.x
		_clamp_camera()

	elif event is InputEventScreenDrag and dragging:
		WorldGestureUtil.note_motion_relative(event.relative)
		global_position -= event.relative / zoom.x
		_clamp_camera()


func _clear_world_gesture_if_still_pressing() -> void:
	if WorldGestureUtil.pressing:
		WorldGestureUtil.end_press()


## Center camera on a world position without changing zoom / pan feel / bounds rules.
func focus_world_position(world_pos: Vector2) -> void:
	if not is_inside_tree():
		return
	global_position = world_pos
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
