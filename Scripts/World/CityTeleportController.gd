extends Node2D

## Kingdom-map placement mode for targeted city teleport (teleport_advanced_compass).
## Opens from Bag → KingdomMap; green/red castle preview + bottom Teleport/Cancel.

const MapPlacementContractScript = preload("res://Scripts/World/MapPlacementContract.gd")
const WorldGestureUtil = preload("res://Scripts/World/WorldGesture.gd")

const CASTLE_TEX := "res://assets/Buildings/Castle/main_castle.png"
const PREVIEW_SCALE := Vector2(0.15, 0.15)
const PANEL_H: float = 148.0

signal placement_finished(success: bool)

var _active: bool = false
var _busy: bool = false
var _preview: Node2D = null
var _preview_sprite: Sprite2D = null
var _panel: PanelContainer = null
var _status: Label = null
var _teleport_btn: Button = null
var _cancel_btn: Button = null
var _proposed: Vector2 = Vector2.INF
var _proposed_valid: bool = false
var _reason: String = ""
var _layer_canvas: CanvasLayer = null
var _pending_request_id: String = ""


func is_placement_active() -> bool:
	return _active


func begin_placement() -> void:
	if _active:
		return
	_active = true
	_busy = false
	_pending_request_id = ""
	_proposed = Vector2.INF
	_proposed_valid = false
	_reason = "Tap the map to choose a new city location."
	_ensure_preview()
	_ensure_panel()
	_refresh_panel()
	set_process_unhandled_input(true)


func cancel_placement() -> void:
	_teardown(false)


func _teardown(success: bool) -> void:
	_active = false
	set_process_unhandled_input(false)
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	_preview_sprite = null
	if _layer_canvas != null and is_instance_valid(_layer_canvas):
		_layer_canvas.queue_free()
	_layer_canvas = null
	_panel = null
	placement_finished.emit(success)


func _ensure_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		return
	var map_root: Node = _map_root()
	if map_root == null:
		return
	_preview = Node2D.new()
	_preview.name = "CityTeleportPreview"
	_preview.z_index = 40
	map_root.add_child(_preview)
	_preview_sprite = Sprite2D.new()
	if ResourceLoader.exists(CASTLE_TEX):
		_preview_sprite.texture = load(CASTLE_TEX) as Texture2D
	_preview_sprite.scale = PREVIEW_SCALE
	_preview_sprite.modulate = Color(1, 1, 1, 0.55)
	_preview.add_child(_preview_sprite)
	_preview.visible = false


func _ensure_panel() -> void:
	if _layer_canvas != null and is_instance_valid(_layer_canvas):
		return
	_layer_canvas = CanvasLayer.new()
	_layer_canvas.layer = 80
	_layer_canvas.name = "CityTeleportUI"
	add_child(_layer_canvas)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_top = -PANEL_H - 16.0
	_panel.offset_bottom = -16.0
	_panel.offset_left = 12.0
	_panel.offset_right = -12.0
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.09, 0.07, 0.12, 0.96)
	st.border_color = Color(0.62, 0.50, 0.30, 0.95)
	st.set_border_width_all(2)
	st.set_corner_radius_all(12)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 12
	st.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", st)
	_layer_canvas.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)
	var title := Label.new()
	title.text = "Teleport City"
	title.add_theme_color_override("font_color", Color(0.86, 0.70, 0.32, 1))
	title.add_theme_font_size_override("font_size", 18)
	col.add_child(title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.93, 0.88, 0.76, 1))
	_status.add_theme_font_size_override("font_size", 13)
	col.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.custom_minimum_size = Vector2(0, 48)
	_cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_btn.focus_mode = Control.FOCUS_NONE
	_cancel_btn.pressed.connect(cancel_placement)
	row.add_child(_cancel_btn)
	_teleport_btn = Button.new()
	_teleport_btn.text = "Teleport"
	_teleport_btn.custom_minimum_size = Vector2(0, 48)
	_teleport_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_teleport_btn.focus_mode = Control.FOCUS_NONE
	_teleport_btn.pressed.connect(_on_confirm_pressed)
	row.add_child(_teleport_btn)


func _refresh_panel() -> void:
	if _status != null:
		_status.text = _reason
	if _teleport_btn != null:
		_teleport_btn.disabled = _busy or not _proposed_valid


func _map_root() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene: Node = tree.current_scene
	if scene != null and (scene.get_node_or_null("PlayerCastleMarker") != null or scene.name == "KingdomMap"):
		return scene
	return tree.root.find_child("KingdomMap", true, false)


func _camera() -> Camera2D:
	var root: Node = _map_root()
	if root == null:
		return null
	return root.get_node_or_null("Camera2D") as Camera2D


func _unhandled_input(event: InputEvent) -> void:
	if not _active or _busy:
		return
	var screen := Vector2.INF
	var is_tap := false
	if event is InputEventScreenTouch and event.pressed:
		screen = event.position
		WorldGestureUtil.begin_press(screen)
		return
	if event is InputEventScreenTouch and not event.pressed:
		if WorldGestureUtil.consume_release_as_tap():
			screen = event.position
			is_tap = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			WorldGestureUtil.begin_press(event.position)
			return
		if WorldGestureUtil.consume_release_as_tap():
			screen = event.position
			is_tap = true
	if not is_tap or screen == Vector2.INF:
		return
	## Ignore taps on the bottom panel.
	if _panel != null and _panel.get_global_rect().has_point(screen):
		return
	var cam: Camera2D = _camera()
	if cam == null:
		return
	var world: Vector2
	if cam.has_method("screen_to_world"):
		world = cam.call("screen_to_world", screen)
	else:
		world = cam.get_screen_center_position() + (screen - cam.get_viewport_rect().size * 0.5) / cam.zoom.x
	_set_proposed(world)
	get_viewport().set_input_as_handled()


func _set_proposed(world: Vector2) -> void:
	_proposed = world
	var ab: Node = get_node_or_null("/root/AllianceBackend")
	var kid: String = "kingdom_dev_001"
	var self_id: String = ""
	var castles: Array = []
	if ab != null:
		if ab.has_method("get_profile"):
			var prof: Dictionary = ab.get_profile()
			kid = str(prof.get("kingdom_id", kid))
			self_id = str(prof.get("user_id", ""))
		if ab.has_method("get_cached_kingdom_castles"):
			castles = ab.call("get_cached_kingdom_castles")
	var check: Dictionary = MapPlacementContractScript.validate_castle_candidate(
		kid, world.x, world.y, castles, self_id
	)
	## Also block while local troops are out (server re-checks activity ledger).
	if has_node("/root/MarchState") and MarchState.has_method("has_blocking_deployments"):
		if MarchState.has_blocking_deployments():
			check = {"ok": false, "error": "Cannot teleport while troops are deployed."}
	_proposed_valid = bool(check.get("ok", false))
	_reason = str(check.get("error", "")) if not _proposed_valid else "Location looks clear. Confirm to teleport."
	if _preview != null:
		_preview.visible = true
		_preview.global_position = world
	if _preview_sprite != null:
		_preview_sprite.modulate = Color(0.35, 0.95, 0.45, 0.75) if _proposed_valid else Color(0.95, 0.28, 0.28, 0.75)
	_refresh_panel()


func _on_confirm_pressed() -> void:
	if _busy or not _proposed_valid or _proposed == Vector2.INF:
		return
	_busy = true
	_reason = "Teleporting…"
	_refresh_panel()
	if has_node("/root/MarchState") and MarchState.has_method("sync_troop_activity_to_server"):
		await MarchState.sync_troop_activity_to_server()
	var ab: Node = get_node_or_null("/root/AllianceBackend")
	if ab == null or not ab.has_method("city_teleport_relocate"):
		_busy = false
		_reason = "Teleport service unavailable."
		_refresh_panel()
		return
	if _pending_request_id == "":
		_pending_request_id = "tp_%s_%s" % [
			str(Time.get_unix_time_from_system()).replace(".", ""),
			str(randi()),
		]
	var result: Dictionary = await ab.city_teleport_relocate(_proposed.x, _proposed.y, _pending_request_id)
	if not bool(result.get("ok", false)):
		_busy = false
		_reason = str(result.get("error", "Teleport failed."))
		## Keep placement active when relocating the preview would help.
		_proposed_valid = false
		if _preview_sprite != null:
			_preview_sprite.modulate = Color(0.95, 0.28, 0.28, 0.75)
		_refresh_panel()
		return
	## Apply local marker + camera + bag mirror.
	var wx: float = float(result.get("world_x", _proposed.x))
	var wy: float = float(result.get("world_y", _proposed.y))
	var layer: Node = null
	var root: Node = _map_root()
	if root != null:
		layer = root.get_node_or_null("WorldCastleLayer")
	if layer != null and layer.has_method("apply_self_castle_position"):
		layer.call("apply_self_castle_position", Vector2(wx, wy))
	elif root != null:
		var marker: Node2D = root.get_node_or_null("PlayerCastleMarker") as Node2D
		if marker != null:
			marker.global_position = Vector2(wx, wy)
	if layer != null and layer.has_method("refresh_castles"):
		layer.call("refresh_castles")
	var cam: Camera2D = _camera()
	if cam != null and cam.has_method("focus_world_position"):
		cam.call("focus_world_position", Vector2(wx, wy))
	var bal: int = int(result.get("balance", -1))
	if bal >= 0 and has_node("/root/BagState") and BagState.has_method("set_item_count_authoritative"):
		BagState.set_item_count_authoritative("teleport_advanced_compass", bal)
	_pending_request_id = ""
	_teardown(true)
