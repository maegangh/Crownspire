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

func _ready():
	setup_bottom_bar()
	_configure_bottom_nav()
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

	if OS.get_environment("CROWNSPIR_HERO_SMOKE") == "1":
		if has_node("/root/HeroState") and HeroState.has_method("run_hero_roster_smoke_test"):
			HeroState.run_hero_roster_smoke_test()
	else:
		print("[GameHUD] Skipping Hero smoke tests (set CROWNSPIR_HERO_SMOKE=1 for isolated runs).")

func _process(_delta):
	update_resources()

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


## Mail sits below the top resource strip on the right — must not cover Diamonds/VIP/Shop.
func _validate_mail_hitbox() -> void:
	if mail_button == null or not is_instance_valid(mail_button):
		push_error("[GameHUD] Mail button missing.")
		return
	var mail_rect: Rect2 = mail_button.get_global_rect()
	if mail_rect.size.x < 40.0 or mail_rect.size.y < 40.0:
		push_error("[GameHUD] Mail hitbox too small: %s" % str(mail_rect))
		return

	if shop_button != null and is_instance_valid(shop_button):
		var shop_rect: Rect2 = shop_button.get_global_rect()
		if mail_rect.intersects(shop_rect):
			push_error("[GameHUD] Mail overlaps Shop hitbox.")
			return

	# Diamonds / VIP live in the upper resource strip (roughly y < 160 on 1280 portrait).
	if mail_rect.position.y < 160.0:
		push_error("[GameHUD] Mail sits too high — may cover Diamonds/VIP (y=%.1f)." % mail_rect.position.y)
		return

	print("[GameHUD] Mail hitbox OK: %s (below resource strip, no Shop overlap)." % str(mail_rect))


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
	
