extends RefCounted
class_name TutorialTargetResolver

## Centralized tutorial target resolution. Presentation only — never mutates gameplay.

const LOG_PREFIX := "[TUTORIAL UI]"


static func resolve(hud: Node, step: Dictionary) -> Dictionary:
	## Returns { ok, kind, control, node2d, rect, label }
	var empty: Dictionary = {
		"ok": false,
		"kind": "",
		"control": null,
		"node2d": null,
		"rect": Rect2(),
		"label": "",
	}
	if hud == null or step.is_empty():
		return empty
	var ttype: String = str(step.get("target_type", "")).strip_edges()
	var tid: String = str(step.get("target_id", "")).strip_edges()
	if ttype.is_empty() or tid.is_empty():
		return empty

	match ttype:
		"hud_control":
			return _resolve_hud_control(hud, tid)
		"city_building":
			return _resolve_city_building(hud, tid)
		"resource_collect_icon":
			return _resolve_resource_collect_icon(hud, tid)
		"screen_control":
			return _resolve_screen_control(hud, tid)
		"world_target":
			return _resolve_world_target(hud, tid)
		_:
			_log("Unknown target_type: %s" % ttype)
			return empty


static func rect_for_result(result: Dictionary, padding: float = 12.0) -> Rect2:
	if not bool(result.get("ok", false)):
		return Rect2()
	var control: Control = result.get("control") as Control
	if control != null and is_instance_valid(control):
		var gr: Rect2 = control.get_global_rect()
		return gr.grow(padding)
	# Collect-icon targets: keep hole centered on the visible icon, sized from ClickArea.
	if str(result.get("kind", "")) == "resource_collect_icon":
		var icon: Sprite2D = result.get("collect_icon") as Sprite2D
		var click: Area2D = result.get("click_area") as Area2D
		if icon != null and is_instance_valid(icon) and icon.visible:
			var origin: Vector2 = icon.get_global_transform_with_canvas().origin
			var click_rect: Rect2 = _area_screen_rect(click)
			var half: Vector2 = Vector2(40, 40)
			if click_rect.size.x > 1.0:
				half = Vector2(
					maxf(40.0, click_rect.size.x * 0.5 + 12.0),
					maxf(40.0, click_rect.size.y * 0.5 + 12.0)
				)
			return Rect2(origin - half, half * 2.0).grow(padding)
	# World wildling: prefer precomputed click/sprite rect so camera + spotlight agree.
	if str(result.get("kind", "")) == "world_target":
		var stored_world: Rect2 = result.get("rect", Rect2()) as Rect2
		if stored_world.size.x > 1.0 and stored_world.size.y > 1.0:
			return stored_world.grow(padding) if padding > 0.0 else stored_world
		var wnode: Node2D = result.get("node2d") as Node2D
		if wnode != null and is_instance_valid(wnode):
			var wrect: Rect2 = _wildling_screen_rect(wnode)
			if wrect.size.x > 1.0:
				return wrect.grow(padding) if padding > 0.0 else wrect
	var node: Node2D = result.get("node2d") as Node2D
	if node != null and is_instance_valid(node):
		if str(result.get("kind", "")) == "city_building":
			var city_rect: Rect2 = _city_building_screen_rect(node)
			return city_rect.grow(padding) if padding > 0.0 else city_rect
		return _node2d_screen_rect(node, padding)
	var stored: Rect2 = result.get("rect", Rect2()) as Rect2
	if stored.size.x > 0.0 and stored.size.y > 0.0:
		return stored.grow(padding)
	return Rect2()


static func _resolve_hud_control(hud: Node, tid: String) -> Dictionary:
	var paths: Dictionary = {
		"WorldCityButton": "Control/BottomBarTexture/BottomButtons/WorldCityButton",
		"AllianceButton": "Control/BottomBarTexture/BottomButtons/AllianceButton",
		"MailButton": "Control/MailButton",
		"QuestButton": "Control/BottomBarTexture/BottomButtons/QuestButton",
		"BagButton": "Control/BottomBarTexture/BottomButtons/BagButton",
		"HeroesButton": "Control/BottomBarTexture/BottomButtons/HeroesButton",
	}
	var path: String = str(paths.get(tid, ""))
	var control: Control = null
	if not path.is_empty():
		control = hud.get_node_or_null(path) as Control
	if control == null:
		control = hud.find_child(tid, true, false) as Control
	if control == null or not is_instance_valid(control):
		_log("Target unresolved: hud_control/%s" % tid)
		return {"ok": false, "kind": "hud_control", "control": null, "node2d": null, "rect": Rect2(), "label": tid}
	return {
		"ok": true,
		"kind": "hud_control",
		"control": control,
		"node2d": null,
		"rect": control.get_global_rect(),
		"label": tid,
	}


static func _resolve_city_building(hud: Node, building_id: String) -> Dictionary:
	# Only resolve under City/Buildings — never HUD Controls / find_child first-match.
	var node: Node2D = _find_city_building(hud, building_id)
	if node == null or not is_instance_valid(node):
		_log("Target unresolved: city_building/%s" % building_id)
		return {"ok": false, "kind": "city_building", "control": null, "node2d": null, "rect": Rect2(), "label": building_id}

	# Frame the interactive building center (Sprite/UpgradeArea), NOT the Node2D root.
	# Academy root sits at Buildings origin while art/hitbox are heavily offset — without
	# camera framing the spotlight lands near the left/bottom edge over unrelated towers.
	var focus_world: Vector2 = _building_interactive_world_pos(node)
	_focus_city_camera(hud, focus_world)

	var screen_rect: Rect2 = _city_building_screen_rect(node)
	_log(
		"Resolved city_building/%s → %s rect=%s focus=%s" % [
			building_id,
			str(node.get_path()),
			str(screen_rect),
			str(focus_world),
		]
	)
	return {
		"ok": true,
		"kind": "city_building",
		"control": null,
		"node2d": node,
		"rect": screen_rect,
		"label": building_id,
	}


static func _focus_city_camera(hud: Node, world_pos: Vector2) -> void:
	if hud == null or hud.get_tree() == null:
		return
	var scene: Node = hud.get_tree().current_scene
	if scene == null:
		return
	var cam: Camera2D = scene.get_viewport().get_camera_2d() if scene.get_viewport() else null
	if cam == null:
		cam = scene.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	if cam.has_method("focus_world_position"):
		cam.call("focus_world_position", world_pos)
	else:
		cam.global_position = world_pos


static func _building_interactive_world_pos(building: Node2D) -> Vector2:
	## Prefer UpgradeArea collision center, then Sprite2D, then building origin.
	var upgrade: Area2D = building.get_node_or_null("UpgradeArea") as Area2D
	if upgrade != null:
		var shape: CollisionShape2D = upgrade.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape != null:
			return shape.global_position
		return upgrade.global_position
	var sprite: Sprite2D = building.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		return sprite.global_position
	return building.global_position


static func _city_building_screen_rect(building: Node2D) -> Rect2:
	## UpgradeArea hitbox first (canonical tap), else compact pad around Sprite2D origin.
	## Avoid full Sprite2D texture bounds — large transparent padding misplaces the hole.
	var upgrade_rect: Rect2 = _area_screen_rect(building.get_node_or_null("UpgradeArea") as Area2D)
	if upgrade_rect.size.x > 1.0 and upgrade_rect.size.y > 1.0:
		return upgrade_rect
	var sprite: Sprite2D = building.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null and is_instance_valid(sprite):
		var origin: Vector2 = sprite.get_global_transform_with_canvas().origin
		return Rect2(origin - Vector2(64, 64), Vector2(128, 128))
	var click_rect: Rect2 = _area_screen_rect(building.get_node_or_null("ClickArea") as Area2D)
	if click_rect.size.x > 1.0:
		return click_rect
	var root_o: Vector2 = building.get_global_transform_with_canvas().origin
	return Rect2(root_o - Vector2(48, 48), Vector2(96, 96))


static var _collect_unavailable_logged: Dictionary = {}


static func _resolve_resource_collect_icon(hud: Node, building_id: String) -> Dictionary:
	## Spotlight the LIVE collect interaction (CollectIcon + ClickArea), not the building art.
	var building: Node2D = _find_city_building(hud, building_id)
	if building == null or not is_instance_valid(building):
		_log("Target unresolved: resource_collect_icon/%s (building missing)" % building_id)
		return {
			"ok": false,
			"kind": "resource_collect_icon",
			"control": null,
			"node2d": null,
			"rect": Rect2(),
			"label": building_id,
		}

	var ready: bool = true
	if "ready_to_collect" in building:
		ready = bool(building.get("ready_to_collect"))
	var icon: Sprite2D = building.get_node_or_null("CollectIcon") as Sprite2D
	var click_area: Area2D = building.get_node_or_null("ClickArea") as Area2D
	var icon_ready: bool = ready and icon != null and is_instance_valid(icon) and icon.visible
	if not icon_ready:
		if not bool(_collect_unavailable_logged.get(building_id, false)):
			_collect_unavailable_logged[building_id] = true
			if building_id == "farm":
				_log("Farm collect icon not currently available")
			else:
				_log("%s collect icon not currently available" % building_id)
		return {
			"ok": false,
			"kind": "resource_collect_icon",
			"control": null,
			"node2d": null,
			"rect": Rect2(),
			"label": building_id,
		}
	_collect_unavailable_logged.erase(building_id)

	# CollectIcon textures are large with transparency — do NOT use full sprite bounds.
	# City camera collects via ClickArea; center the hole on the visible icon origin.
	var icon_origin: Vector2 = icon.get_global_transform_with_canvas().origin
	var click_rect: Rect2 = _area_screen_rect(click_area)
	var screen_rect: Rect2
	if click_rect.size.x > 1.0 and click_rect.size.y > 1.0:
		var c: Vector2 = icon_origin
		var half: Vector2 = Vector2(
			maxf(40.0, click_rect.size.x * 0.5 + 12.0),
			maxf(40.0, click_rect.size.y * 0.5 + 12.0)
		)
		screen_rect = Rect2(c - half, half * 2.0)
	else:
		screen_rect = Rect2(icon_origin - Vector2(40, 40), Vector2(80, 80))

	_log(
		"Resolved resource_collect_icon/%s → %s rect=%s" % [
			building_id,
			str(icon.get_path()),
			str(screen_rect),
		]
	)
	return {
		"ok": true,
		"kind": "resource_collect_icon",
		"control": null,
		# Track ClickArea so camera pans refresh the live hitbox; icon used for center.
		"node2d": click_area if click_area != null else icon,
		"collect_icon": icon,
		"click_area": click_area,
		"rect": screen_rect,
		"label": building_id,
	}


static func _find_city_building(hud: Node, building_id: String) -> Node2D:
	var scene: Node = hud.get_tree().current_scene if hud.get_tree() else null
	if scene == null:
		return null
	var buildings: Node = scene.get_node_or_null("Buildings")
	if buildings == null:
		return null
	for child: Node in buildings.get_children():
		if not (child is Node2D):
			continue
		if str(child.get("building_id")) == building_id:
			return child as Node2D
	var name_map := {
		"castle": "Castle",
		"farm": "Farm",
		"infantry_barracks": "InfantryBarracks",
		"academy": "Academy",
		"marksmen_camp": "MarksmenCamp",
		"cavalry_stable": "CavalryStable",
	}
	var nn: String = str(name_map.get(building_id, ""))
	if nn.is_empty():
		return null
	return buildings.get_node_or_null(nn) as Node2D


static func _resolve_screen_control(hud: Node, tid: String) -> Dictionary:
	## tid examples: TroopTrainingScreen/ActionButton (ActionButton may be nested).
	var control: Control = null
	var screen_root: Node = hud.get_node_or_null("ScreenRoot")
	var leaf: String = tid.get_file() if tid.contains("/") else tid
	var screen_name: String = tid.get_slice("/", 0) if tid.contains("/") else ""
	if screen_root != null:
		control = screen_root.get_node_or_null(tid) as Control
		if control == null and not screen_name.is_empty():
			var screen: Node = screen_root.get_node_or_null(screen_name)
			if screen != null:
				control = screen.find_child(leaf, true, false) as Control
		if control == null:
			control = screen_root.find_child(leaf, true, false) as Control
	if control == null:
		control = hud.find_child(leaf, true, false) as Control
	if control == null or not is_instance_valid(control):
		_log("Target unresolved: screen_control/%s" % tid)
		return {"ok": false, "kind": "screen_control", "control": null, "node2d": null, "rect": Rect2(), "label": tid}
	# Soft OK even if not visible yet — training screen may open mid-step.
	return {
		"ok": true,
		"kind": "screen_control",
		"control": control,
		"node2d": null,
		"rect": control.get_global_rect(),
		"label": tid,
	}


static func _resolve_world_target(hud: Node, tid: String) -> Dictionary:
	var scene: Node = hud.get_tree().current_scene if hud.get_tree() else null
	if scene == null:
		_log("Target unresolved: world_target/%s (no scene)" % tid)
		return {"ok": false, "kind": "world_target", "control": null, "node2d": null, "rect": Rect2(), "label": tid}

	# City→World enter-at-home must finish before FTUE pans to wildlings/resources.
	if _enter_at_home_blocks_camera(hud.get_tree()):
		_log("world_target/%s deferred — enter-at-home unresolved" % tid)
		return {
			"ok": false,
			"kind": "world_target",
			"control": null,
			"node2d": null,
			"rect": Rect2(),
			"label": tid,
			"pending_home": true,
		}

	match tid:
		"wildling_l1", "wildling":
			return _resolve_wildling_l1_target(hud, scene, tid)

	var node: Node2D = null
	match tid:
		"resource_tile", "resource":
			node = _find_nearest_resource(scene)
		_:
			node = scene.find_child(tid, true, false) as Node2D

	if node == null or not is_instance_valid(node):
		_log("Target unresolved: world_target/%s" % tid)
		return {"ok": false, "kind": "world_target", "control": null, "node2d": null, "rect": Rect2(), "label": tid}

	# Non-wildling world targets keep prior root-center behavior.
	var cam: Camera2D = scene.get_node_or_null("Camera2D") as Camera2D
	if cam != null and cam.has_method("focus_world_position"):
		cam.call("focus_world_position", node.global_position)

	return {
		"ok": true,
		"kind": "world_target",
		"control": null,
		"node2d": node,
		"rect": _node2d_screen_rect(node, 0.0),
		"label": tid,
	}


## True while City→World home centering request is still outstanding.
static func _enter_at_home_blocks_camera(tree: SceneTree) -> bool:
	if tree == null or not tree.has_meta("world_enter_at_home"):
		return false
	return bool(tree.get_meta("world_enter_at_home"))


const META_FOCUSED_WILDLING_IID := "ftue_world_focused_wildling_iid"
## Usable KingdomMap bounds (matches MapCamera map_size).
const WORLD_MAP_BOUNDS := Rect2(0.0, 0.0, 8192.0, 8192.0)
const WORLD_MAP_EDGE_MARGIN := 8.0


## Clears transient FTUE wildling focus tracking (scene reload / step change / new home entry).
static func clear_world_focus_tracking(tree: SceneTree) -> void:
	if tree == null:
		return
	if tree.has_meta(META_FOCUSED_WILDLING_IID):
		tree.remove_meta(META_FOCUSED_WILDLING_IID)


static func _resolve_wildling_l1_target(hud: Node, scene: Node, tid: String) -> Dictionary:
	var pending: Dictionary = {
		"ok": false,
		"kind": "world_target",
		"control": null,
		"node2d": null,
		"rect": Rect2(),
		"label": tid,
		"pending_wildling": true,
	}
	var node: Node2D = _find_nearest_valid_wildling_l1(scene)
	if node == null:
		var on_cooldown: bool = false
		if hud != null and hud.get_tree() != null:
			var wss: Node = hud.get_tree().root.get_node_or_null("WildlingSpawnState")
			if wss != null and wss.has_method("is_tutorial_l1_on_cooldown"):
				on_cooldown = bool(wss.call("is_tutorial_l1_on_cooldown"))
		if on_cooldown:
			_log("world_target/%s unavailable — tutorial L1 slot on defeat cooldown" % tid)
			pending["unavailable_cooldown"] = true
			pending["label"] = "wildling_l1_cooldown"
		else:
			_log("world_target/%s deferred — no validated L1 wildling yet" % tid)
		_clear_stale_focused_wildling(hud.get_tree() if hud else null)
		return pending

	var focus_world: Vector2 = _wildling_focus_world_pos(node)
	if not _is_valid_world_focus_point(focus_world):
		_log("world_target/%s deferred — invalid focus point %s" % [tid, str(focus_world)])
		return pending

	var screen_rect: Rect2 = _wildling_screen_rect(node)
	if screen_rect.size.x < 1.0 or screen_rect.size.y < 1.0:
		_log("world_target/%s deferred — empty visual/click rect" % tid)
		return pending

	var tree: SceneTree = hud.get_tree() if hud != null else null
	var iid: int = node.get_instance_id()
	var already_focused: bool = (
		tree != null
		and tree.has_meta(META_FOCUSED_WILDLING_IID)
		and int(tree.get_meta(META_FOCUSED_WILDLING_IID)) == iid
	)

	if not already_focused:
		var cam: Camera2D = scene.get_node_or_null("Camera2D") as Camera2D
		if cam != null and cam.has_method("focus_world_position"):
			cam.call("focus_world_position", focus_world)
		elif cam != null:
			cam.global_position = focus_world
		if tree != null:
			tree.set_meta(META_FOCUSED_WILDLING_IID, iid)
		var castle_dist: float = _distance_from_player_castle(scene, focus_world)
		_log(
			"Focused wildling_l1 path=%s focus=%s castle_dist=%.1f (already=%s)" % [
				str(node.get_path()),
				str(focus_world),
				castle_dist,
				str(already_focused),
			]
		)
	else:
		_log("wildling_l1 already focused iid=%d — skip re-pan" % iid)

	return {
		"ok": true,
		"kind": "world_target",
		"control": null,
		"node2d": node,
		"rect": screen_rect,
		"focus_world": focus_world,
		"label": tid,
	}


static func _clear_stale_focused_wildling(tree: SceneTree) -> void:
	if tree == null or not tree.has_meta(META_FOCUSED_WILDLING_IID):
		return
	var iid: int = int(tree.get_meta(META_FOCUSED_WILDLING_IID))
	var obj: Object = instance_from_id(iid)
	if obj == null or not is_instance_valid(obj) or not (obj is Node) or not (obj as Node).is_inside_tree():
		tree.remove_meta(META_FOCUSED_WILDLING_IID)


## Click/collision center first (global transform includes root scale + child offsets).
static func _wildling_focus_world_pos(node: Node2D) -> Vector2:
	if node == null or not is_instance_valid(node):
		return Vector2.INF
	var click: Area2D = node.get_node_or_null("ClickArea") as Area2D
	if click != null and is_instance_valid(click):
		var shape: CollisionShape2D = click.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape != null and is_instance_valid(shape) and not shape.disabled:
			return shape.global_position
		return click.global_position
	var sprite: Sprite2D = node.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null and is_instance_valid(sprite) and sprite.texture != null:
		return sprite.global_position
	# Do not use root — WildlingNode art/hitbox are heavily offset from origin.
	return Vector2.INF


static func _wildling_screen_rect(node: Node2D) -> Rect2:
	if node == null or not is_instance_valid(node):
		return Rect2()
	var click_rect: Rect2 = _area_screen_rect(node.get_node_or_null("ClickArea") as Area2D)
	if click_rect.size.x > 1.0 and click_rect.size.y > 1.0:
		return click_rect
	var sprite_rect: Rect2 = _sprite_screen_rect(node.get_node_or_null("Sprite2D") as Sprite2D)
	if sprite_rect.size.x > 1.0 and sprite_rect.size.y > 1.0:
		return sprite_rect
	return Rect2()


static func _is_valid_world_focus_point(pos: Vector2) -> bool:
	if not pos.is_finite():
		return false
	var bounds: Rect2 = WORLD_MAP_BOUNDS.grow(-WORLD_MAP_EDGE_MARGIN)
	return bounds.has_point(pos)


static func _validate_wildling_l1(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not node.is_inside_tree():
		return false
	if node.is_queued_for_deletion():
		return false
	if not node.visible:
		return false
	var sprite: Sprite2D = node.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or not is_instance_valid(sprite) or not sprite.visible:
		return false
	if sprite.texture == null:
		return false
	var click: Area2D = node.get_node_or_null("ClickArea") as Area2D
	if click == null or not is_instance_valid(click):
		return false
	if not click.visible:
		return false
	if not click.input_pickable:
		return false
	if not ("level" in click) or int(click.get("level")) != 1:
		return false
	var shape: CollisionShape2D = click.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null or not is_instance_valid(shape) or shape.disabled or shape.shape == null:
		return false
	var focus: Vector2 = _wildling_focus_world_pos(node)
	if not _is_valid_world_focus_point(focus):
		return false
	return true


static func _find_nearest_valid_wildling_l1(scene: Node) -> Node2D:
	var host: Node = scene.get_node_or_null("WildlingSpawns")
	if host == null:
		return null
	var cam: Camera2D = scene.get_viewport().get_camera_2d() if scene.get_viewport() else null
	var origin: Vector2 = cam.global_position if cam != null else Vector2.ZERO
	var best: Node2D = null
	var best_d: float = INF
	for child: Node in host.get_children():
		if not (child is Node2D):
			continue
		var n: Node2D = child as Node2D
		if not _validate_wildling_l1(n):
			continue
		var focus: Vector2 = _wildling_focus_world_pos(n)
		var d: float = origin.distance_squared_to(focus)
		if d < best_d:
			best_d = d
			best = n
	return best


static func _distance_from_player_castle(scene: Node, world_pos: Vector2) -> float:
	if scene == null:
		return -1.0
	var marker: Node2D = scene.get_node_or_null("PlayerCastleMarker") as Node2D
	if marker == null or not is_instance_valid(marker):
		return -1.0
	return marker.global_position.distance_to(world_pos)


static func _find_nearest_wildling(scene: Node, max_level: int) -> Node2D:
	var host: Node = scene.get_node_or_null("WildlingSpawns")
	if host == null:
		host = scene
	var cam: Camera2D = scene.get_viewport().get_camera_2d() if scene.get_viewport() else null
	var origin: Vector2 = cam.global_position if cam != null else Vector2.ZERO
	var best: Node2D = null
	var best_d: float = INF
	for child: Node in host.get_children():
		if not (child is Node2D):
			continue
		if not (child as Node2D).visible:
			continue
		var area: Node = child.get_node_or_null("ClickArea")
		var level: int = 1
		if area != null and "level" in area:
			level = int(area.get("level"))
		elif "level" in child:
			level = int(child.get("level"))
		if level > max_level:
			continue
		var d: float = origin.distance_squared_to((child as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = child as Node2D
	return best


static func _find_nearest_resource(scene: Node) -> Node2D:
	var host: Node = scene.get_node_or_null("ResourceSpawns")
	if host == null:
		host = scene
	var cam: Camera2D = scene.get_viewport().get_camera_2d() if scene.get_viewport() else null
	var origin: Vector2 = cam.global_position if cam != null else Vector2.ZERO
	var best: Node2D = null
	var best_d: float = INF
	for child: Node in host.get_children():
		if not (child is Node2D):
			continue
		if not (child as Node2D).visible:
			continue
		var d: float = origin.distance_squared_to((child as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = child as Node2D
	return best


static func _node2d_screen_rect(node: Node2D, padding: float) -> Rect2:
	## Use VISIBLE artwork / click areas — NOT the building root origin.
	## City buildings (e.g. Farm) keep the root near the top while Sprite2D/UpgradeArea are offset.
	## Prefer UpgradeArea (gameplay hitbox over the art). Full Sprite2D textures often include
	## large transparent padding that would drag the spotlight into the HUD.
	if node is Sprite2D:
		var self_sprite: Rect2 = _sprite_screen_rect(node as Sprite2D)
		if self_sprite.size.x > 1.0:
			return self_sprite.grow(padding) if padding > 0.0 else self_sprite
	if node is Area2D:
		var self_area: Rect2 = _area_screen_rect(node as Area2D)
		if self_area.size.x > 1.0:
			return self_area.grow(padding) if padding > 0.0 else self_area

	var upgrade_rect: Rect2 = _area_screen_rect(node.get_node_or_null("UpgradeArea") as Area2D)
	var sprite_rect: Rect2 = _sprite_screen_rect(node.get_node_or_null("Sprite2D") as Sprite2D)
	var click_rect: Rect2 = _area_screen_rect(node.get_node_or_null("ClickArea") as Area2D)
	var rect: Rect2 = Rect2()
	if upgrade_rect.size.x > 1.0 and upgrade_rect.size.y > 1.0:
		rect = upgrade_rect
	elif sprite_rect.size.x > 1.0 and sprite_rect.size.y > 1.0:
		rect = sprite_rect
	elif click_rect.size.x > 1.0 and click_rect.size.y > 1.0:
		rect = click_rect
	else:
		# Last resort: small pad around root canvas point (avoid giant false HUD hits).
		var origin: Vector2 = node.get_global_transform_with_canvas().origin
		rect = Rect2(origin - Vector2(48, 48), Vector2(96, 96))
	if padding > 0.0:
		rect = rect.grow(padding)
	return rect


static func _sprite_screen_rect(sprite: Sprite2D) -> Rect2:
	if sprite == null or not is_instance_valid(sprite) or sprite.texture == null:
		return Rect2()
	var tex_size: Vector2 = sprite.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return Rect2()
	var local: Rect2
	if sprite.centered:
		local = Rect2(-tex_size * 0.5, tex_size)
	else:
		local = Rect2(Vector2.ZERO, tex_size)
	# Region / frame support.
	if sprite.region_enabled:
		var rs: Vector2 = sprite.region_rect.size
		if sprite.centered:
			local = Rect2(-rs * 0.5, rs)
		else:
			local = Rect2(Vector2.ZERO, rs)
	return _xform_local_rect_to_canvas(sprite.get_global_transform_with_canvas(), local)


static func _area_screen_rect(area: Area2D) -> Rect2:
	if area == null or not is_instance_valid(area):
		return Rect2()
	var shape_node: CollisionShape2D = area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return Rect2()
	var local: Rect2 = Rect2()
	if shape_node.shape is RectangleShape2D:
		var ext: Vector2 = (shape_node.shape as RectangleShape2D).size
		local = Rect2(-ext * 0.5, ext)
	elif shape_node.shape is CircleShape2D:
		var r: float = (shape_node.shape as CircleShape2D).radius
		local = Rect2(Vector2(-r, -r), Vector2(r * 2.0, r * 2.0))
	else:
		return Rect2()
	# Shape may be offset under the Area2D.
	var xf: Transform2D = shape_node.get_global_transform_with_canvas()
	return _xform_local_rect_to_canvas(xf, local)


static func _xform_local_rect_to_canvas(xf: Transform2D, local: Rect2) -> Rect2:
	var p0: Vector2 = xf * local.position
	var p1: Vector2 = xf * (local.position + Vector2(local.size.x, 0.0))
	var p2: Vector2 = xf * (local.position + Vector2(0.0, local.size.y))
	var p3: Vector2 = xf * (local.position + local.size)
	var min_v: Vector2 = Vector2(
		minf(minf(p0.x, p1.x), minf(p2.x, p3.x)),
		minf(minf(p0.y, p1.y), minf(p2.y, p3.y))
	)
	var max_v: Vector2 = Vector2(
		maxf(maxf(p0.x, p1.x), maxf(p2.x, p3.x)),
		maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y))
	)
	var out := Rect2(min_v, max_v - min_v)
	# Keep a usable tap target even for tiny sprites.
	if out.size.x < 72.0 or out.size.y < 72.0:
		var c: Vector2 = out.get_center()
		out = Rect2(c - Vector2(36, 36), Vector2(72, 72))
	return out


static func _log(msg: String) -> void:
	print("%s %s" % [LOG_PREFIX, msg])
