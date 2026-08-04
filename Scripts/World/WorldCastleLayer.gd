extends Node2D

## Spawns and refreshes real kingdom player castles on the world map.
## Local player uses PlayerCastleMarker; others appear under OtherPlayerCastles.
## Castle tap → PlayerCastlePopup. Nameplate tap → PlayerProfileScreen.

const WorldGestureUtil = preload("res://scripts/World/WorldGesture.gd")

const CASTLE_TEXTURE_PATH := "res://assets/Buildings/Castle/main_castle.png"
const MAP_SIZE := Vector2(8192, 8192)
const EDGE_MARGIN := 900.0
## Comfortable mobile hit target in marker-local space (sprite ~0.15 scale).
const LOCAL_HIT_SIZE := Vector2(140, 140)
const OTHER_HIT_SIZE := Vector2(120, 120)
## Wide enough for future "[TAG] Name" + level badge; height stays compact.
const NAMEPLATE_SIZE := Vector2(150, 34)
## Nameplate vertical center within visible castle height (lower ~15–25% band).
const NAMEPLATE_ANCHOR_Y: float = 0.82
const _OPAQUE_ALPHA: int = 16

var _opaque_uv_rect: Rect2 = Rect2() ## cached opaque UV rect in texture pixels (0..size)
var _opaque_uv_ready: bool = false

var _other_root: Node2D
var _castle_texture: Texture2D
var _refreshing: bool = false
var _reserved_positions: Array[Vector2] = []
var _kingdom_id: String = ""


func _ready() -> void:
	name = "WorldCastleLayer"
	z_index = 25
	_other_root = Node2D.new()
	_other_root.name = "OtherPlayerCastles"
	add_child(_other_root)
	if ResourceLoader.exists(CASTLE_TEXTURE_PATH):
		_castle_texture = load(CASTLE_TEXTURE_PATH) as Texture2D
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.physics_object_picking = true
	call_deferred("refresh_castles")
	call_deferred("_wire_local_castle_input")
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

	_kingdom_id = str(result.get("kingdom_id", ""))
	var self_id: String = ""
	if ab.has_method("get_profile"):
		self_id = str(ab.get_profile().get("user_id", ""))
		if _kingdom_id == "":
			_kingdom_id = str(ab.get_profile().get("kingdom_id", ""))
	var nc: Node = get_node_or_null("/root/NakamaConnection")
	if self_id == "" and nc != null and nc.has_method("get_user_id"):
		self_id = str(nc.get_user_id())

	var self_entry: Dictionary = result.get("self", {}) if typeof(result.get("self")) == TYPE_DICTIONARY else {}
	var sx: float = float(self_entry.get("world_x", 4096))
	var sy: float = float(self_entry.get("world_y", 4096))
	_place_local_castle(Vector2(sx, sy), self_id, self_entry)
	_reserved_positions.append(Vector2(sx, sy))

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

	print("[WorldCastle] refreshed others=%d reserved=%d local_path=%s" % [
		_other_root.get_child_count(),
		_reserved_positions.size(),
		str(_player_castle_marker().get_path()) if _player_castle_marker() != null else "missing",
	])


func _apply_local_fallback_only() -> void:
	var marker: Node2D = _player_castle_marker()
	if marker != null:
		_reserved_positions.append(marker.global_position)
	_wire_local_castle_input()


func _map_root() -> Node:
	var p: Node = get_parent()
	if p != null and p.get_node_or_null("PlayerCastleMarker") != null:
		return p
	var marker: Node = get_tree().root.find_child("PlayerCastleMarker", true, false) if get_tree() != null else null
	if marker != null:
		return marker.get_parent()
	return p


func _player_castle_marker() -> Node2D:
	var root: Node = _map_root()
	if root != null:
		var m: Node2D = root.get_node_or_null("PlayerCastleMarker") as Node2D
		if m != null:
			return m
	if get_tree() != null:
		return get_tree().root.find_child("PlayerCastleMarker", true, false) as Node2D
	return null


func _place_local_castle(pos: Vector2, self_id: String, self_entry: Dictionary) -> void:
	var marker: Node2D = _player_castle_marker()
	if marker == null:
		push_warning("[WorldCastle] PlayerCastleMarker missing — cannot place local castle")
		return
	marker.global_position = _clamp_map(pos)
	marker.visible = true
	marker.z_index = 20
	marker.set_meta("user_id", self_id)
	var backend_profile: Dictionary = {}

	var ab: Node = get_node_or_null("/root/AllianceBackend")
	if ab != null and ab.has_method("get_profile"):
		backend_profile = ab.get_profile()

	var display_name := str(backend_profile.get("display_name", self_entry.get("display_name", ""))).strip_edges()
	var alliance_tag := str(backend_profile.get("alliance_tag", self_entry.get("alliance_tag", ""))).strip_edges()

	marker.set_meta("display_name", display_name)
	marker.set_meta("alliance_tag", alliance_tag)
	marker.set_meta("world_x", marker.global_position.x)
	marker.set_meta("world_y", marker.global_position.y)
	marker.set_meta("is_player_castle", true)
	marker.set_meta("is_self_castle", true)
	_ensure_local_nameplate(marker)
	_wire_local_castle_input()


func _ensure_local_nameplate(marker: Node2D) -> void:
	var tag := str(marker.get_meta("alliance_tag", "")).strip_edges()
	var display := ""

	var ab: Node = get_node_or_null("/root/AllianceBackend")
	if ab != null and ab.has_method("get_profile"):
		var profile: Dictionary = ab.get_profile()
		display = str(profile.get("display_name", "")).strip_edges()

	if display == "":
		display = str(marker.get_meta("display_name", "")).strip_edges()

	if display == "":
		display = "Player"
	var plate_text := "[%s] %s" % [tag, display] if tag != "" else display
	var sprite: Sprite2D = marker.get_node_or_null("PlayerCastleSprite") as Sprite2D
	if sprite == null:
		sprite = marker.get_node_or_null("Sprite") as Sprite2D
	var plate_host: Control = marker.get_node_or_null("Nameplate") as Control
	if plate_host == null:
		plate_host = _make_nameplate_host()
		marker.add_child(plate_host)
	var name_btn: Button = plate_host.get_node_or_null("NameplateButton") as Button
	if name_btn == null:
		name_btn = _make_nameplate_button()
		name_btn.pressed.connect(_on_local_nameplate_pressed)
		plate_host.add_child(name_btn)
	name_btn.text = plate_text
	_position_nameplate(plate_host, sprite, marker)


func _on_local_nameplate_pressed() -> void:
	var marker: Node2D = _player_castle_marker()
	var uid: String = str(marker.get_meta("user_id", "")) if marker != null else ""
	print("[WorldCastle] nameplate tap owner=%s → profile" % uid)
	_open_profile(uid)


func _wire_local_castle_input() -> void:
	var marker: Node2D = _player_castle_marker()
	if marker == null:
		push_warning("[WorldCastle] wire skipped — PlayerCastleMarker not found (layer parent=%s)" % str(get_parent().get_path() if get_parent() else "?"))
		return
	var area: Area2D = marker.get_node_or_null("ClickArea") as Area2D
	if area == null:
		area = Area2D.new()
		area.name = "ClickArea"
		marker.add_child(area)
	area.input_pickable = true
	area.monitoring = true
	area.monitorable = true
	var shape: CollisionShape2D = area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null:
		shape = CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		area.add_child(shape)
	var rect := RectangleShape2D.new()
	rect.size = LOCAL_HIT_SIZE
	shape.shape = rect
	shape.disabled = false
	if not area.input_event.is_connected(_on_local_castle_input):
		area.input_event.connect(_on_local_castle_input)
	print("[WorldCastle] wired local ClickArea path=%s hit=%s pickable=%s" % [
		str(area.get_path()), str(LOCAL_HIT_SIZE), str(area.input_pickable),
	])


func _on_local_castle_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var marker: Node2D = _player_castle_marker()
	var uid: String = str(marker.get_meta("user_id", "")) if marker != null else ""
	if event is InputEventScreenTouch:
		if event.pressed:
			print("[WorldCastle] press owner=%s" % uid)
			WorldGestureUtil.begin_press(event.position)
		elif WorldGestureUtil.consume_release_as_tap():
			print("[WorldCastle] release owner=%s" % uid)
			print("[WorldCastle] tap accepted")
			_open_local_castle_popup()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			print("[WorldCastle] press owner=%s" % uid)
			WorldGestureUtil.begin_press(event.position)
		elif WorldGestureUtil.consume_release_as_tap():
			print("[WorldCastle] release owner=%s" % uid)
			print("[WorldCastle] tap accepted")
			_open_local_castle_popup()


func _open_local_castle_popup() -> void:
	var marker: Node2D = _player_castle_marker()
	if marker == null:
		return
	var ab: Node = get_node_or_null("/root/AllianceBackend")
	var profile: Dictionary = ab.get_profile() if ab != null and ab.has_method("get_profile") else {}
	var payload := {
		"user_id": str(marker.get_meta("user_id", profile.get("user_id", ""))),
		"display_name": str(profile.get("display_name", marker.get_meta("display_name", "Player"))),
		"alliance_tag": str(profile.get("alliance_tag", marker.get_meta("alliance_tag", ""))),
		"alliance_name": str(profile.get("alliance_name", "")),
		"kingdom_id": str(profile.get("kingdom_id", _kingdom_id)),
		"world_x": float(marker.global_position.x),
		"world_y": float(marker.global_position.y),
		"power": int(profile.get("power", 0)),
		"citadel_level": int(profile.get("citadel_level", 1)),
		"avatar_id": str(profile.get("avatar_id", "avatar_01")),
	}
	_open_castle_popup(payload)


func _spawn_other_castle(entry: Dictionary, pos: Vector2) -> void:
	var uid: String = str(entry.get("user_id", ""))
	var node := Node2D.new()
	node.name = "Castle_%s" % uid.substr(0, 8)
	node.position = pos
	node.z_index = 18
	node.set_meta("user_id", uid)
	node.set_meta("display_name", str(entry.get("display_name", "Lord")))
	node.set_meta("is_player_castle", true)
	_other_root.add_child(node)

	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.scale = Vector2(0.13, 0.13)
	if _castle_texture != null:
		sprite.texture = _castle_texture
	else:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.35, 0.45, 0.75, 1.0))
		sprite.texture = ImageTexture.create_from_image(img)
	node.add_child(sprite)

	var tag := str(entry.get("alliance_tag", "")).strip_edges()
	var display := str(entry.get("display_name", "")).strip_edges()
	if display == "":
		display = "Player"
	var plate_text := "[%s] %s" % [tag, display] if tag != "" else display

	var castle_payload := {
		"user_id": uid,
		"display_name": display,
		"alliance_tag": tag,
		"alliance_name": str(entry.get("alliance_name", "")),
		"kingdom_id": _kingdom_id,
		"world_x": pos.x,
		"world_y": pos.y,
		"power": int(entry.get("power", 0)),
		"citadel_level": int(entry.get("citadel_level", 1)),
		"avatar_id": str(entry.get("avatar_id", "avatar_01")),
	}

	var plate_host := _make_nameplate_host()
	node.add_child(plate_host)
	var name_btn := _make_nameplate_button()
	name_btn.text = plate_text
	name_btn.pressed.connect(func():
		print("[WorldCastle] nameplate tap owner=%s → profile" % uid)
		_open_profile(uid)
	)
	plate_host.add_child(name_btn)
	_position_nameplate(plate_host, sprite, node)

	var area := Area2D.new()
	area.name = "ClickArea"
	area.input_pickable = true
	area.monitoring = true
	node.add_child(area)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = OTHER_HIT_SIZE
	shape.shape = rect
	shape.disabled = false
	area.add_child(shape)
	area.input_event.connect(func(_viewport, event, _shape_idx):
		if event is InputEventScreenTouch:
			if event.pressed:
				print("[WorldCastle] press owner=%s" % uid)
				WorldGestureUtil.begin_press(event.position)
			elif WorldGestureUtil.consume_release_as_tap():
				print("[WorldCastle] release owner=%s" % uid)
				print("[WorldCastle] tap accepted")
				_open_castle_popup(castle_payload)
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				print("[WorldCastle] press owner=%s" % uid)
				WorldGestureUtil.begin_press(event.position)
			elif WorldGestureUtil.consume_release_as_tap():
				print("[WorldCastle] release owner=%s" % uid)
				print("[WorldCastle] tap accepted")
				_open_castle_popup(castle_payload)
	)


func _make_nameplate_host() -> Control:
	var plate_host := Control.new()
	plate_host.name = "Nameplate"
	plate_host.custom_minimum_size = NAMEPLATE_SIZE
	plate_host.size = NAMEPLATE_SIZE
	plate_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate_host.z_index = 6
	return plate_host


func _make_nameplate_button() -> Button:
	var name_btn := Button.new()
	name_btn.name = "NameplateButton"
	name_btn.flat = false
	name_btn.focus_mode = Control.FOCUS_NONE
	name_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	name_btn.add_theme_font_size_override("font_size", 14)
	name_btn.add_theme_color_override("font_color", Color(0.98, 0.94, 0.82, 1.0))
	name_btn.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.08, 0.92))
	name_btn.add_theme_constant_override("outline_size", 4)
	var plate_style := StyleBoxFlat.new()
	plate_style.bg_color = Color(0.02, 0.025, 0.06, 0.60)

	plate_style.corner_radius_top_left = 6
	plate_style.corner_radius_top_right = 6
	plate_style.corner_radius_bottom_left = 6
	plate_style.corner_radius_bottom_right = 6

	plate_style.content_margin_left = 8
	plate_style.content_margin_right = 8
	plate_style.content_margin_top = 3
	plate_style.content_margin_bottom = 3

	name_btn.add_theme_stylebox_override("normal", plate_style)
	name_btn.add_theme_stylebox_override("hover", plate_style)
	name_btn.add_theme_stylebox_override("pressed", plate_style)
	name_btn.add_theme_stylebox_override("focus", plate_style)
	return name_btn


## Place nameplate over the lower portion of the VISIBLE castle artwork.
## Uses opaque texture bounds when available so transparent padding is ignored.
func _position_nameplate(plate: Control, sprite: Sprite2D, parent: Node2D) -> void:
	if plate == null:
		return
	plate.custom_minimum_size = NAMEPLATE_SIZE
	plate.size = NAMEPLATE_SIZE
	var vis: Rect2 = _visible_castle_rect_parent_local(sprite, parent)
	var cx: float = vis.position.x + vis.size.x * 0.5
	var cy: float = vis.position.y + vis.size.y * NAMEPLATE_ANCHOR_Y
	plate.position = Vector2(cx - NAMEPLATE_SIZE.x * 0.5, cy - NAMEPLATE_SIZE.y * 0.5)
	plate.z_index = 6
	print("[WorldCastle] nameplate pos=%s vis=%s anchorY=%.2f" % [
		str(plate.position), str(vis), NAMEPLATE_ANCHOR_Y,
	])


func _visible_castle_rect_parent_local(sprite: Sprite2D, parent: Node2D) -> Rect2:
	## Fallback when sprite missing: centered box matching typical castle footprint.
	if sprite == null or parent == null:
		return Rect2(Vector2(-60, -70), Vector2(120, 120))
	var tex: Texture2D = sprite.texture
	var tex_size: Vector2 = tex.get_size() if tex != null else Vector2(128, 128)
	if tex_size.x < 1.0 or tex_size.y < 1.0:
		tex_size = Vector2(128, 128)
	var opaque_px: Rect2 = _opaque_texture_rect(tex)
	# Convert opaque pixel rect → sprite-local (unscaled), then apply sprite scale/offset.
	# Sprite2D default is centered on its position.
	var local_tl: Vector2
	var local_br: Vector2
	if sprite.centered:
		local_tl = opaque_px.position - tex_size * 0.5
		local_br = opaque_px.end - tex_size * 0.5
	else:
		local_tl = opaque_px.position
		local_br = opaque_px.end
	local_tl = local_tl * sprite.scale + sprite.offset * sprite.scale
	local_br = local_br * sprite.scale + sprite.offset * sprite.scale
	# Sprite is a child of parent — add sprite.position for parent-local space.
	var tl: Vector2 = sprite.position + Vector2(minf(local_tl.x, local_br.x), minf(local_tl.y, local_br.y))
	var br: Vector2 = sprite.position + Vector2(maxf(local_tl.x, local_br.x), maxf(local_tl.y, local_br.y))
	return Rect2(tl, br - tl)


func _opaque_texture_rect(tex: Texture2D) -> Rect2:
	if tex == null:
		return Rect2(Vector2.ZERO, Vector2(128, 128))
	if _opaque_uv_ready and _castle_texture == tex:
		return _opaque_uv_rect
	var img: Image = tex.get_image()
	var full := Rect2(Vector2.ZERO, tex.get_size())
	if img == null:
		_opaque_uv_rect = full
		_opaque_uv_ready = true
		return _opaque_uv_rect
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w < 1 or h < 1:
		_opaque_uv_rect = full
		_opaque_uv_ready = true
		return _opaque_uv_rect
	var min_x: int = w
	var min_y: int = h
	var max_x: int = -1
	var max_y: int = -1
	# Step sample — castle art is large; every 2px is enough for nameplate placement.
	var step: int = 2
	for y in range(0, h, step):
		for x in range(0, w, step):
			if img.get_pixel(x, y).a8 > _OPAQUE_ALPHA:
				if x < min_x:
					min_x = x
				if y < min_y:
					min_y = y
				if x > max_x:
					max_x = x
				if y > max_y:
					max_y = y
	if max_x < min_x or max_y < min_y:
		_opaque_uv_rect = full
	else:
		_opaque_uv_rect = Rect2(
			Vector2(min_x, min_y),
			Vector2(max_x - min_x + 1, max_y - min_y + 1)
		)
	_opaque_uv_ready = true
	return _opaque_uv_rect


func _open_castle_popup(payload: Dictionary) -> void:
	print("[WorldCastle] opening PlayerCastlePopup owner=%s" % str(payload.get("user_id", "")))
	var popup: Control = _ensure_castle_popup()
	if popup != null and popup.has_method("open_for_castle"):
		popup.call("open_for_castle", payload)
		print("[PlayerCastlePopup] opened owner=%s" % str(payload.get("user_id", "")))
	else:
		push_error("[WorldCastle] PlayerCastlePopup missing open_for_castle")


func _open_profile(user_id: String) -> void:
	if user_id == "":
		return
	print("[CastlePopup] profile requested user=%s" % user_id)
	var hud := get_tree().root.find_child("GameHUD", true, false)
	if hud != null and hud.has_method("open_player_profile"):
		hud.call("open_player_profile", user_id)


func _ensure_castle_popup() -> Control:
	var hud: Node = get_tree().get_first_node_in_group("game_hud") if get_tree() != null else null
	if hud == null:
		hud = get_tree().root.find_child("GameHUD", true, false)
	if hud == null:
		return null
	if hud.has_method("ensure_player_castle_popup"):
		return hud.call("ensure_player_castle_popup") as Control
	var host: Control = hud.get_node_or_null("Control") as Control
	if host == null:
		return null
	var existing: Control = host.get_node_or_null("PlayerCastlePopup") as Control
	if existing != null:
		return existing
	var popup := Control.new()
	popup.name = "PlayerCastlePopup"
	popup.set_script(load("res://scripts/UI/PlayerCastlePopup.gd"))
	host.add_child(popup)
	return popup


func _clamp_map(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, EDGE_MARGIN, MAP_SIZE.x - EDGE_MARGIN),
		clampf(pos.y, EDGE_MARGIN, MAP_SIZE.y - EDGE_MARGIN)
	)
