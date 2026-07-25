extends CanvasLayer

@export var is_world_screen: bool = false
@export var bottom_bar_home: Texture2D
@export var bottom_bar_world: Texture2D

@onready var bottom_bar_texture: TextureRect = $Control/BottomBarTexture

@onready var food_label: Label = $Control/TopBarTexture/TopLabels/FoodLabel
@onready var wood_label: Label = $Control/TopBarTexture/TopLabels/WoodLabel
@onready var stone_label: Label = $Control/TopBarTexture/TopLabels/StoneLabel
@onready var iron_label: Label = $Control/TopBarTexture/TopLabels/IronLabel
@onready var diamond_label: Label = $Control/TopBarTexture/TopLabels/DiamondLabel
@onready var power_label: Label = $Control/TopBarTexture/TopLabels/PowerLabel
@onready var vip_label: Label = $Control/TopBarTexture/TopLabels/VipLabel

@onready var portrait_button: TextureButton = $Control/PlayerPortraitButton
@onready var shop_button: TextureButton = $Control/ShopButton
@onready var mail_button: TextureButton = $Control/MailButton
@onready var mail_unread_badge: Label = $Control/MailButton/UnreadBadge

@onready var heroes_button: Button = $Control/BottomBarTexture/BottomButtons/HeroesButton
@onready var wayfinder_button: Button = $Control/BottomBarTexture/BottomButtons/WayfinderButton
@onready var bag_button: Button = $Control/BottomBarTexture/BottomButtons/BagButton
@onready var quest_button: Button = $Control/BottomBarTexture/BottomButtons/QuestButton
@onready var alliance_button: Button = $Control/BottomBarTexture/BottomButtons/AllianceButton
@onready var world_city_button: Button = $Control/BottomBarTexture/BottomButtons/WorldCityButton

var _queue_status_hud: Control = null
var _world_search_button: Button = null
var _world_search_panel: Control = null
var _active_marches_hud: Control = null

func _ready():
	setup_bottom_bar()
	_configure_bottom_nav()
	_setup_queue_status_hud()
	_setup_active_marches_hud()
	_setup_world_search_ui()
	update_resources()
	connect_buttons()
	_refresh_mail_badge()
	call_deferred("_validate_bottom_nav_hitboxes")
	call_deferred("_validate_mail_hitbox")
	call_deferred("_run_hud_navigation_smoke_test_if_headless")
	if has_node("/root/MarchState"):
		if not MarchState.march_battle_resolved.is_connected(_on_wildling_march_battle):
			MarchState.march_battle_resolved.connect(_on_wildling_march_battle)
		if is_world_screen and MarchState.has_method("resync_map_visuals"):
			call_deferred("_resync_marches")
	if has_node("/root/MailManager") and not MailManager.mail_changed.is_connected(_on_mail_changed):
		MailManager.mail_changed.connect(_on_mail_changed)


func _setup_queue_status_hud() -> void:
	# City-only persistent queue strip. World map keeps the same GameHUD scene but hides this.
	_queue_status_hud = get_node_or_null("Control/QueueStatusHUD") as Control
	if _queue_status_hud == null:
		var packed: PackedScene = load("res://Scenes/UI/QueueStatusHUD.tscn") as PackedScene
		if packed == null:
			push_warning("[GameHUD] QueueStatusHUD.tscn missing.")
			return
		_queue_status_hud = packed.instantiate() as Control
		_queue_status_hud.name = "QueueStatusHUD"
		var host: Node = get_node_or_null("Control")
		if host == null:
			host = self
		host.add_child(_queue_status_hud)
	_sync_queue_status_visibility()


## Brief highlight when a queue-full attempt fails (beta UX).
func pulse_queue_status(kind: String) -> void:
	if _queue_status_hud != null and _queue_status_hud.has_method("pulse_queue"):
		_queue_status_hud.call("pulse_queue", kind)


func _sync_queue_status_visibility() -> void:
	if _queue_status_hud == null or not is_instance_valid(_queue_status_hud):
		return
	if is_world_screen:
		_queue_status_hud.visible = false
		return
	# Hide under full ScreenRoot screens (Bag/Alliance/etc). Keep visible during city popups.
	var show_queue: bool = true
	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("is_screen_open") and bool(manager.is_screen_open()):
		show_queue = false
	_queue_status_hud.visible = show_queue


func _setup_active_marches_hud() -> void:
	# World-only march status. Separate from City QueueStatusHUD.
	var host: Control = get_node_or_null("Control") as Control
	if host == null:
		return
	_active_marches_hud = host.get_node_or_null("ActiveMarchesHUD") as Control
	if _active_marches_hud == null:
		var packed: PackedScene = load("res://Scenes/UI/ActiveMarchesHUD.tscn") as PackedScene
		if packed == null:
			push_warning("[GameHUD] ActiveMarchesHUD.tscn missing.")
			return
		_active_marches_hud = packed.instantiate() as Control
		_active_marches_hud.name = "ActiveMarchesHUD"
		host.add_child(_active_marches_hud)
	_sync_active_marches_visibility()


func _sync_active_marches_visibility() -> void:
	if _active_marches_hud == null or not is_instance_valid(_active_marches_hud):
		return
	var show_marches: bool = is_world_screen
	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("is_screen_open") and bool(manager.is_screen_open()):
		show_marches = false
	_active_marches_hud.visible = show_marches
	# Root stays IGNORE so empty space never blocks map pan.
	_active_marches_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _setup_world_search_ui() -> void:
	var host: Control = get_node_or_null("Control") as Control
	if host == null:
		return

	_world_search_button = host.get_node_or_null("WorldSearchButton") as Button
	if _world_search_button == null:
		_world_search_button = Button.new()
		_world_search_button.name = "WorldSearchButton"
		_world_search_button.text = "🔍\nSEARCH"
		_world_search_button.focus_mode = Control.FOCUS_NONE
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.12, 0.11, 0.16, 0.92)
		fill.border_color = Color(0.78, 0.66, 0.34, 0.95)
		fill.set_border_width_all(2)
		fill.set_corner_radius_all(14)
		_world_search_button.add_theme_stylebox_override("normal", fill)
		_world_search_button.add_theme_font_size_override("font_size", 16)
		_world_search_button.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82, 1.0))
		host.add_child(_world_search_button)
	# Bottom-left above nav — clear of Mail (right) and ActiveMarchesHUD (top-left).
	_world_search_button.custom_minimum_size = Vector2(96, 96)
	_world_search_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_world_search_button.anchor_left = 0.0
	_world_search_button.anchor_top = 1.0
	_world_search_button.anchor_right = 0.0
	_world_search_button.anchor_bottom = 1.0
	# Bottom nav top ≈ offset -179; keep ~16px clearance above it.
	_world_search_button.offset_left = 14.0
	_world_search_button.offset_top = -291.0
	_world_search_button.offset_right = 110.0
	_world_search_button.offset_bottom = -195.0
	_world_search_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_world_search_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if not _world_search_button.pressed.is_connected(_on_world_search_pressed):
		_world_search_button.pressed.connect(_on_world_search_pressed)

	_world_search_panel = host.get_node_or_null("WorldSearchPanel") as Control
	if _world_search_panel == null:
		var packed: PackedScene = load("res://Scenes/UI/WorldSearchPanel.tscn") as PackedScene
		if packed != null:
			_world_search_panel = packed.instantiate() as Control
			_world_search_panel.name = "WorldSearchPanel"
			host.add_child(_world_search_panel)
	_sync_world_search_visibility()


func _sync_world_search_visibility() -> void:
	var show_search: bool = is_world_screen
	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("is_screen_open") and bool(manager.is_screen_open()):
		show_search = false
	if _world_search_button != null and is_instance_valid(_world_search_button):
		_world_search_button.visible = show_search
		_world_search_button.mouse_filter = (
			Control.MOUSE_FILTER_STOP if show_search else Control.MOUSE_FILTER_IGNORE
		)
	if not show_search and _world_search_panel != null and is_instance_valid(_world_search_panel):
		if _world_search_panel.has_method("close_panel"):
			_world_search_panel.call("close_panel")
		else:
			_world_search_panel.visible = false


func _on_world_search_pressed() -> void:
	if not is_world_screen:
		return
	if _world_search_panel == null or not is_instance_valid(_world_search_panel):
		return
	if _world_search_panel.has_method("open_panel"):
		_world_search_panel.call("open_panel")


func _resync_marches() -> void:
	if has_node("/root/MarchState") and MarchState.has_method("resync_map_visuals"):
		MarchState.resync_map_visuals()


## Battle results go to Mail — no interrupting AcceptDialog.
func _on_wildling_march_battle(_march_id: String, _result: Dictionary) -> void:
	_refresh_mail_badge()


func _on_mail_changed() -> void:
	_refresh_mail_badge()


func _refresh_mail_badge() -> void:
	if mail_unread_badge == null:
		return
	var count: int = 0
	if has_node("/root/MailManager"):
		count = MailManager.get_unread_count()
	if count <= 0:
		mail_unread_badge.text = ""
	elif count > 9:
		mail_unread_badge.text = "●9+"
	else:
		mail_unread_badge.text = "●%d" % count

func _run_hud_navigation_smoke_test_if_headless() -> void:
	if DisplayServer.get_name() != "headless":
		return

	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("run_navigation_smoke_test"):
		manager.run_navigation_smoke_test()

	# Alliance smoke tests write saves — only when explicitly enabled, and always isolated.
	if OS.get_environment("CROWNSPIR_ALLIANCE_SMOKE") == "1":
		if has_node("/root/AllianceState") and AllianceState.has_method("run_sprint_1b_smoke_test"):
			AllianceState.run_sprint_1b_smoke_test()
		if has_node("/root/AllianceState") and AllianceState.has_method("run_sprint_1c_smoke_test"):
			AllianceState.run_sprint_1c_smoke_test()
		if has_node("/root/AllianceState") and AllianceState.has_method("run_persistence_smoke_test"):
			AllianceState.run_persistence_smoke_test()
		if has_node("/root/AllianceState") and AllianceState.has_method("run_research_smoke_test"):
			AllianceState.run_research_smoke_test()
	else:
		print("[GameHUD] Skipping Alliance smoke tests (set CROWNSPIR_ALLIANCE_SMOKE=1 for isolated runs).")

	if OS.get_environment("CROWNSPIR_MARCH_SMOKE") == "1":
		if has_node("/root/MarchState") and MarchState.has_method("run_wildling_march_smoke_test"):
			MarchState.run_wildling_march_smoke_test()
	else:
		print("[GameHUD] Skipping March smoke tests (set CROWNSPIR_MARCH_SMOKE=1 for isolated runs).")

	if OS.get_environment("CROWNSPIR_RESOURCE_TILE_SMOKE") == "1":
		if has_node("/root/ResourceTileState") and ResourceTileState.has_method("run_resource_tile_step3_smoke_test"):
			ResourceTileState.run_resource_tile_step3_smoke_test()
		if has_node("/root/MarchState") and MarchState.has_method("run_gather_tile_sync_smoke_test"):
			MarchState.run_gather_tile_sync_smoke_test()
	else:
		print("[GameHUD] Skipping ResourceTile smoke tests (set CROWNSPIR_RESOURCE_TILE_SMOKE=1 for isolated runs).")

	if OS.get_environment("CROWNSPIR_HERO_SMOKE") == "1":
		if has_node("/root/HeroState") and HeroState.has_method("run_hero_roster_smoke_test"):
			HeroState.run_hero_roster_smoke_test()
	else:
		print("[GameHUD] Skipping Hero smoke tests (set CROWNSPIR_HERO_SMOKE=1 for isolated runs).")

func _process(_delta):
	update_resources()
	_sync_secondary_hud_visibility()
	_sync_queue_status_visibility()
	_sync_active_marches_visibility()
	_sync_world_search_visibility()


## Secondary HUD chrome (Mail). Hidden while a main ScreenRoot screen or city popup is open.
func set_secondary_hud_visible(is_visible: bool) -> void:
	if mail_button == null or not is_instance_valid(mail_button):
		return
	mail_button.visible = is_visible
	# Hidden Mail must never leave an active hitbox over Close/X controls.
	mail_button.mouse_filter = Control.MOUSE_FILTER_STOP if is_visible else Control.MOUSE_FILTER_IGNORE
	if mail_unread_badge != null and is_instance_valid(mail_unread_badge):
		mail_unread_badge.visible = is_visible
		mail_unread_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _sync_secondary_hud_visibility() -> void:
	var show_secondary: bool = true
	var manager: Node = get_node_or_null("UIManager")
	if manager != null and manager.has_method("is_screen_open") and bool(manager.is_screen_open()):
		show_secondary = false
	elif has_node("/root/GameState") and bool(GameState.popup_open):
		# Tavern / building upgrade / other city popups.
		show_secondary = false
	set_secondary_hud_visible(show_secondary)

func setup_bottom_bar():
	if is_world_screen:
		bottom_bar_texture.texture = bottom_bar_home
	else:
		bottom_bar_texture.texture = bottom_bar_world


## Invisible equal-width hit targets over the bottom bar art.
## Resets any broken editor scale/anchors so Alliance no longer maps to Map/City.
func _configure_bottom_nav() -> void:
	var buttons_box: HBoxContainer = $Control/BottomBarTexture/BottomButtons

	bottom_bar_texture.mouse_filter = Control.MOUSE_FILTER_STOP
	buttons_box.scale = Vector2.ONE
	buttons_box.modulate = Color(1, 1, 1, 0)
	buttons_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	buttons_box.offset_left = 28.0
	buttons_box.offset_top = 42.0
	buttons_box.offset_right = -28.0
	buttons_box.offset_bottom = -10.0
	buttons_box.add_theme_constant_override("separation", 2)
	buttons_box.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var nav_buttons: Array[Button] = [
		heroes_button,
		wayfinder_button,
		bag_button,
		quest_button,
		alliance_button,
		world_city_button,
	]

	for button: Button in nav_buttons:
		if button == null:
			continue
		button.text = ""
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.size_flags_stretch_ratio = 1.0


func _validate_bottom_nav_hitboxes() -> void:
	var nav_buttons: Array[Button] = [
		heroes_button,
		wayfinder_button,
		bag_button,
		quest_button,
		alliance_button,
		world_city_button,
	]

	var rects: Array[Rect2] = []
	for button: Button in nav_buttons:
		if button == null:
			push_error("[GameHUD] Missing bottom nav button.")
			return
		rects.append(button.get_global_rect())

	for i: int in range(rects.size()):
		if rects[i].size.x < 8.0 or rects[i].size.y < 8.0:
			push_error("[GameHUD] Bottom nav hitbox too small: %s" % nav_buttons[i].name)
		for j: int in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				push_error("[GameHUD] Bottom nav overlap: %s vs %s" % [
					nav_buttons[i].name,
					nav_buttons[j].name,
				])

	# Left-to-right order must match visual art slots.
	for i: int in range(rects.size() - 1):
		if rects[i].position.x >= rects[i + 1].position.x:
			push_error("[GameHUD] Bottom nav order broken between %s and %s" % [
				nav_buttons[i].name,
				nav_buttons[i + 1].name,
			])

	print("[GameHUD] Bottom nav OK: Heroes→Wayfinder→Bag→Quest→Alliance→WorldCity (no overlaps).")


## Mail sits bottom-right, directly above the bottom nav bar.
func _validate_mail_hitbox() -> void:
	if mail_button == null or not is_instance_valid(mail_button):
		push_error("[GameHUD] Mail button missing.")
		return
	var mail_rect: Rect2 = mail_button.get_global_rect()
	if mail_rect.size.x < 40.0 or mail_rect.size.y < 40.0:
		push_error("[GameHUD] Mail hitbox too small: %s" % str(mail_rect))
		return

	# Must sit in the lower HUD band (above bottom bar), not near top resources.
	if mail_rect.position.y < 900.0:
		push_error("[GameHUD] Mail not bottom-anchored (y=%.1f)." % mail_rect.position.y)
		return

	if shop_button != null and is_instance_valid(shop_button):
		var shop_rect: Rect2 = shop_button.get_global_rect()
		if mail_rect.intersects(shop_rect):
			push_error("[GameHUD] Mail overlaps Shop hitbox.")
			return

	if bottom_bar_texture != null and is_instance_valid(bottom_bar_texture):
		var bar_rect: Rect2 = bottom_bar_texture.get_global_rect()
		if mail_rect.intersects(bar_rect):
			push_error("[GameHUD] Mail overlaps bottom navigation bar.")
			return

	if world_city_button != null and is_instance_valid(world_city_button):
		var world_rect: Rect2 = world_city_button.get_global_rect()
		if mail_rect.intersects(world_rect):
			push_error("[GameHUD] Mail overlaps World/City button.")
			return

	if alliance_button != null and is_instance_valid(alliance_button):
		var alliance_rect: Rect2 = alliance_button.get_global_rect()
		if mail_rect.intersects(alliance_rect):
			push_error("[GameHUD] Mail overlaps Alliance button.")
			return

	print("[GameHUD] Mail hitbox OK: %s (bottom-right above nav)." % str(mail_rect))


func update_resources():
	food_label.text = format_number(GameState.food)
	wood_label.text = format_number(GameState.wood)
	stone_label.text = format_number(GameState.stone)
	iron_label.text = format_number(GameState.iron)
	diamond_label.text = format_with_commas(GameState.diamonds)

	power_label.text = format_with_commas(GameState.power)
	vip_label.text = "VIP %d" % GameState.vip_level

func format_number(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	elif value >= 1000:
		return "%.1fK" % (value / 1000.0)
	return str(value)

func connect_buttons():
	if portrait_button:
		portrait_button.pressed.connect(_on_portrait_pressed)
	if shop_button:
		shop_button.pressed.connect(_on_shop_pressed)
	if mail_button:
		mail_button.pressed.connect(_on_mail_pressed)
	if heroes_button:
		heroes_button.pressed.connect(_on_heroes_pressed)
	if wayfinder_button:
		wayfinder_button.pressed.connect(_on_wayfinder_pressed)
	if bag_button:
		bag_button.pressed.connect(_on_bag_pressed)
	if quest_button:
		quest_button.pressed.connect(_on_quest_pressed)
	if alliance_button:
		alliance_button.pressed.connect(_on_alliance_pressed)
	if world_city_button:
		world_city_button.pressed.connect(_on_world_city_pressed)

func _on_portrait_pressed():
	print("Open Player Profile")

func _on_shop_pressed():
	$UIManager.open_screen("ShopScreen")

func _on_mail_pressed():
	$UIManager.open_screen("MailScreen")

func _on_heroes_pressed():
	print("Open Heroes")
	get_tree().change_scene_to_file.call_deferred("res://Scenes/UI/HeroRoster.tscn")

func _on_wayfinder_pressed():
	print("Wayfinder coming soon")

func _on_bag_pressed():
	$UIManager.open_screen("BagScreen")

func _on_quest_pressed():
	$UIManager.open_screen("QuestScreen")

func _on_alliance_pressed():
	$UIManager.open_screen("AllianceScreen")

func _on_world_city_pressed():
	print("World/City button clicked")

	if world_city_button:
		world_city_button.disabled = true

	if is_world_screen:
		get_tree().change_scene_to_file.call_deferred("res://Scenes/City/City.tscn")
	else:
		get_tree().change_scene_to_file.call_deferred("res://Scenes/World/KingdomMap.tscn")

func format_with_commas(value: int) -> String:
	var text := str(value)
	var result := ""

	while text.length() > 3:
		result = "," + text.substr(text.length() - 3, 3) + result
		text = text.substr(0, text.length() - 3)

	return text + result
	
