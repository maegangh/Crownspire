extends Node2D

## Spawns and refreshes real kingdom player castles on the world map.
## Local player uses PlayerCastleMarker; others appear under OtherPlayerCastles.
## Does not invent fake castles — only Nakama kingdom registry entries.

const CASTLE_TEXTURE_PATH := "res://assets/Buildings/Castle/main_castle.png"
const MAP_SIZE := Vector2(8192, 8192)
const EDGE_MARGIN := 900.0

var _other_root: Node2D
var _castle_texture: Texture2D
var _refreshing: bool = false
var _reserved_positions: Array[Vector2] = []


func _ready() -> void:
	name = "WorldCastleLayer"
	z_index = 25
	_other_root = Node2D.new()
	_other_root.name = "OtherPlayerCastles"
	add_child(_other_root)
	if ResourceLoader.exists(CASTLE_TEXTURE_PATH):
		_castle_texture = load(CASTLE_TEXTURE_PATH) as Texture2D
	call_deferred("refresh_castles")
	if has_node("/root/NakamaConnection"):
		var nc: Node = get_node("/root/NakamaConnection")
		if nc.has_signal("authenticated") and not nc.authenticated.is_connected(_on_auth):
			nc.authenticated.connect(_on_auth)
		if nc.has_signal("socket_connected") and not nc.socket_connected.is_connected(_on_socket):
			nc.socket_connected.connect(_on_socket)
	if has_node("/root/AllianceBackend"):
		var ab: Node = get_node("/root/AllianceBackend")
		if ab.has_signal("profile_changed") and not ab.profile_changed.is_connected(_on_profile):
			ab.profile_changed.connect(_on_profile)


func _on_auth(_session: Variant = null) -> void:
	refresh_castles()


func _on_socket() -> void:
	refresh_castles()


func _on_profile(_profile: Dictionary = {}) -> void:
	refresh_castles()


func get_reserved_castle_positions() -> Array[Vector2]:
	return _reserved_positions.duplicate()


func refresh_castles() -> void:
	if _refreshing:
		return
	_refreshing = true
	await _refresh_async()
	_refreshing = false


func _refresh_async() -> void:
	_reserved_positions.clear()
	var ab: Node = get_node_or_null("/root/AllianceBackend")
	if ab == null or not ab.has_method("list_kingdom_castles"):
		_apply_local_fallback_only()
		return
	var result: Dictionary = await ab.list_kingdom_castles()
	if not bool(result.get("ok", false)):
		_apply_local_fallback_only()
		return

	var self_id: String = ""
	if ab.has_method("get_profile"):
		self_id = str(ab.get_profile().get("user_id", ""))
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if self_id == "" and nc != null and nc.has_method("get_user_id"):
		self_id = str(nc.get_user_id())

	var self_entry: Dictionary = result.get("self", {}) if typeof(result.get("self")) == TYPE_DICTIONARY else {}
	var sx: float = float(self_entry.get("world_x", 4096))
	var sy: float = float(self_entry.get("world_y", 4096))
	_place_local_castle(Vector2(sx, sy))
	_reserved_positions.append(Vector2(sx, sy))

	# Clear previous other castles only (never delete PlayerCastleMarker).
	while _other_root.get_child_count() > 0:
		var ch: Node = _other_root.get_child(0)
		_other_root.remove_child(ch)
		ch.free()

	var castles: Array = result.get("castles", [])
	for entry_v in castles:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var uid: String = str(entry.get("user_id", ""))
		if uid == "" or uid == self_id:
			continue
		var pos := Vector2(float(entry.get("world_x", 0)), float(entry.get("world_y", 0)))
		pos = _clamp_map(pos)
		_reserved_positions.append(pos)
		_spawn_other_castle(entry, pos)

	print("[WorldCastle] refreshed others=%d reserved=%d" % [
		_other_root.get_child_count(),
		_reserved_positions.size(),
	])


func _apply_local_fallback_only() -> void:
	var marker: Node2D = get_parent().get_node_or_null("PlayerCastleMarker") as Node2D if get_parent() else null
	if marker != null:
		_reserved_positions.append(marker.global_position)


func _place_local_castle(pos: Vector2) -> void:
	var marker: Node2D = get_parent().get_node_or_null("PlayerCastleMarker") as Node2D if get_parent() else null
	if marker == null:
		return
	marker.global_position = _clamp_map(pos)
	marker.visible = true
	marker.z_index = 20


func _spawn_other_castle(entry: Dictionary, pos: Vector2) -> void:
	var node := Node2D.new()
	node.name = "Castle_%s" % str(entry.get("user_id", "")).substr(0, 8)
	node.position = pos
	node.z_index = 18
	node.set_meta("user_id", str(entry.get("user_id", "")))
	node.set_meta("display_name", str(entry.get("display_name", "Lord")))
	node.set_meta("is_player_castle", true)
	_other_root.add_child(node)

	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.scale = Vector2(0.13, 0.13)
	if _castle_texture != null:
		sprite.texture = _castle_texture
	else:
		# Fallback diamond if art missing — still visible.
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.35, 0.45, 0.75, 1.0))
		sprite.texture = ImageTexture.create_from_image(img)
	node.add_child(sprite)

	var tag := str(entry.get("alliance_tag", "")).strip_edges()
	var label := Label.new()
	label.text = "[%s] %s" % [tag, str(entry.get("display_name", "Lord"))] if tag != "" else str(entry.get("display_name", "Lord"))
	label.position = Vector2(-70, -90)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75, 1.0))
	node.add_child(label)

	var area := Area2D.new()
	area.name = "ClickArea"
	node.add_child(area)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(80, 80)
	shape.shape = rect
	area.add_child(shape)
	area.input_event.connect(func(_viewport, event, _shape_idx):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_open_profile(str(entry.get("user_id", "")))
		elif event is InputEventScreenTouch and event.pressed:
			_open_profile(str(entry.get("user_id", "")))
	)


func _open_profile(user_id: String) -> void:
	if user_id == "":
		return
	var hud := get_tree().root.find_child("GameHUD", true, false)
	if hud != null and hud.has_method("open_player_profile"):
		hud.call("open_player_profile", user_id)


func _clamp_map(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, EDGE_MARGIN, MAP_SIZE.x - EDGE_MARGIN),
		clampf(pos.y, EDGE_MARGIN, MAP_SIZE.y - EDGE_MARGIN)
	)
