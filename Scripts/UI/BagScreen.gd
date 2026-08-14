extends Control

const MobileScrollUtil = preload("res://Scripts/UI/MobileScroll.gd")
const ITEM_SLOT_SCENE := preload("res://Scenes/UI/ItemSlot.tscn")

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/Header/Title
@onready var close_button: Button = $Panel/Header/CloseButton

@onready var all_button: Button = $Panel/Tabs/AllButton
@onready var resources_button: Button = $Panel/Tabs/ResourcesButton
@onready var speedups_button: Button = $Panel/Tabs/SpeedupsButton
@onready var boosts_button: Button = $Panel/Tabs/BoostsButton
@onready var chests_button: Button = $Panel/Tabs/ChestsButton
@onready var hero_button: Button = $Panel/Tabs/HeroButton
@onready var event_button: Button = $Panel/Tabs/EventButton

@onready var grid_container: GridContainer = $Panel/ItemGrid/GridContainer

@onready var detail_icon: TextureRect = $Panel/ItemPopup/Icon
@onready var detail_name: Label = $Panel/ItemPopup/NameLabel
@onready var detail_description: Label = $Panel/ItemPopup/DescriptionLabel
@onready var detail_quantity: Label = $Panel/ItemPopup/QuantityLabel
@onready var use_button: Button = $Panel/ItemPopup/UseButton
@onready var item_popup: Panel = $Panel/ItemPopup

@onready var ui_manager = $"../../UIManager"

var current_filter: String = "all"
var selected_item_id: String = ""


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	title_label.text = "Bag"
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(64, 48)

	all_button.text = "All"
	resources_button.text = "Resources"
	speedups_button.text = "Speedups"
	boosts_button.text = "Boosts"
	chests_button.text = "Chests"
	hero_button.text = "Heroes & Gear"
	event_button.text = "Events"
	use_button.text = "Use"

	if panel:
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if item_popup:
		item_popup.mouse_filter = Control.MOUSE_FILTER_STOP

	close_button.pressed.connect(hide_bag)
	all_button.pressed.connect(func(): show_category("all"))
	resources_button.pressed.connect(func(): show_category("resource"))
	speedups_button.pressed.connect(func(): show_category("speedup"))
	boosts_button.pressed.connect(func(): show_category("boost"))
	chests_button.pressed.connect(func(): show_category("chest"))
	hero_button.pressed.connect(func(): show_category("hero"))
	event_button.pressed.connect(func(): show_category("event"))

	use_button.pressed.connect(_on_use_pressed)

	var item_scroll: ScrollContainer = get_node_or_null("Panel/ItemGrid") as ScrollContainer
	if item_scroll != null:
		MobileScrollUtil.ensure(self, item_scroll, "MobileScrollBag")

	_clear_details()


func on_open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Keep bag content above the shared PopupBackground blocker.
	move_to_front()
	refresh_items()


func on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	selected_item_id = ""
	_clear_details()


func hide_bag() -> void:
	if ui_manager != null and ui_manager.has_method("close_current_screen"):
		ui_manager.close_current_screen()
	else:
		on_close()


func show_category(category: String) -> void:
	current_filter = category
	selected_item_id = ""
	_clear_details()
	refresh_items()


func refresh_items() -> void:
	

	for child in grid_container.get_children():
		child.queue_free()

	if BagState.items.is_empty():
		_clear_details()
		return

	for item_id in BagState.items.keys():
		if not _passes_filter(item_id):
			continue

		var amount: int = int(BagState.items[item_id])
		_add_item_slot(item_id, amount)


func _passes_filter(item_id: String) -> bool:
	if current_filter == "all":
		return true

	var item: Dictionary = ItemDatabase.get_item(item_id)
	return str(item.get("category", "misc")) == current_filter


func _add_item_slot(item_id: String, amount: int) -> void:
	

	var slot = ITEM_SLOT_SCENE.instantiate()
	grid_container.add_child(slot)

	var icon_texture: Texture2D = null
	var icon_path := ItemDatabase.get_item_icon_path(item_id)

	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon_texture = load(icon_path)

	slot.setup(item_id, amount, icon_texture)

	if slot.has_signal("item_selected"):
		slot.item_selected.connect(_on_item_selected)


func _on_item_selected(item_id: String) -> void:
	selected_item_id = item_id
	_show_details(item_id)


func _show_details(item_id: String) -> void:
	var item: Dictionary = ItemDatabase.get_item(item_id)
	var amount: int = BagState.get_item_count(item_id)

	item_popup.visible = true

	detail_name.text = str(item.get("name", item_id))
	detail_description.text = str(item.get("description", ""))
	detail_quantity.text = "Owned: " + str(amount)

	var icon_path := str(item.get("icon", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		detail_icon.texture = load(icon_path)
	else:
		detail_icon.texture = null

	use_button.disabled = not bool(item.get("usable", false))

func _clear_details() -> void:
	item_popup.visible = false
	detail_icon.texture = null
	detail_name.text = ""
	detail_description.text = ""
	detail_quantity.text = ""
	use_button.disabled = true


func _on_use_pressed() -> void:
	if selected_item_id == "":
		return

	_use_item(selected_item_id)


func _use_item(item_id: String) -> void:
	var item: Dictionary = ItemDatabase.get_item(item_id)
	var category := str(item.get("category", ""))

	var used_successfully := false

	match category:
		"resource":
			used_successfully = _use_resource_item(item_id)
		"hero":
			used_successfully = _use_hero_item(item_id)
		"speedup", "chest":
			used_successfully = BagState.remove_item(item_id, 1)
		"boost":
			used_successfully = await _use_boost_item(item_id)
		"teleport":
			await _use_teleport_item(item_id)
			refresh_items()
			return
		_:
			print("Use item coming soon:", item_id)
			return

	refresh_items()

	if BagState.get_item_count(item_id) > 0:
		_show_details(item_id)
	else:
		selected_item_id = ""
		_clear_details()


func _use_boost_item(item_id: String) -> bool:
	if item_id == "boost_shield_peace_3d":
		if not has_node("/root/CityProtectionState"):
			print("CityProtectionState missing")
			return false
		if not BagState.remove_item(item_id, 1):
			return false
		var act: Dictionary = CityProtectionState.activate_peace_shield_from_item()
		if has_node("/root/AllianceBackend") and AllianceBackend.has_method("activate_peace_shield"):
			await AllianceBackend.activate_peace_shield(int(act.get("duration_sec", CityProtectionState.PEACE_SHIELD_DURATION_SEC)))
		print("[Bag] Peace Shield activated expires_at=%s" % str(act.get("expires_at", 0)))
		return true
	if item_id == "boost_anti_scout_24h":
		if not has_node("/root/CityProtectionState"):
			print("CityProtectionState missing")
			return false
		if not BagState.remove_item(item_id, 1):
			return false
		var act2: Dictionary = CityProtectionState.activate_anti_scout_from_item()
		if has_node("/root/AllianceBackend") and AllianceBackend.has_method("activate_anti_scout"):
			await AllianceBackend.activate_anti_scout(int(act2.get("duration_sec", CityProtectionState.ANTI_SCOUT_DURATION_SEC)))
		print("[Bag] Anti-Scout activated expires_at=%s" % str(act2.get("expires_at", 0)))
		return true
	# Other boosts still consume without buff authority (pre-existing behavior).
	return BagState.remove_item(item_id, 1)


func _use_teleport_item(item_id: String) -> void:
	if item_id != "teleport_advanced_compass":
		print("Teleport item not hooked up yet:", item_id)
		return
	var ab: Node = get_node_or_null("/root/AllianceBackend")
	if ab == null:
		print("Teleport requires AllianceBackend")
		return
	## Ensure server inventory is reconciled before placement.
	if ab.has_method("sync_teleport_inventory_from_bag"):
		var sync_res: Dictionary = await ab.sync_teleport_inventory_from_bag()
		if not bool(sync_res.get("ok", false)):
			print("Teleport inventory sync failed:", sync_res.get("error", ""))
			refresh_items()
			return
		if int(sync_res.get("balance", 0)) < 1:
			print("No Advanced Teleport remaining on server.")
			refresh_items()
			return
	## Close bag UI then open Kingdom Map in placement mode.
	var manager := get_node_or_null("../../UIManager")
	if manager == null:
		var hud := get_tree().root.find_child("GameHUD", true, false)
		if hud != null:
			manager = hud.get_node_or_null("UIManager")
	if manager != null and manager.has_method("close_current_screen"):
		manager.close_current_screen()
	elif manager != null and manager.has_method("close_screen"):
		manager.close_screen()
	var tree := get_tree()
	if tree == null:
		return
	## Flag for KingdomMap to enter placement after load.
	if has_node("/root/GameEvents") and GameEvents.has_method("set"):
		pass
	tree.set_meta("pending_city_teleport", true)
	if str(tree.current_scene.name) == "KingdomMap":
		_start_map_teleport_placement()
	else:
		tree.change_scene_to_file.call_deferred("res://Scenes/World/KingdomMap.tscn")
		call_deferred("_deferred_start_teleport_when_map_ready")


func _deferred_start_teleport_when_map_ready() -> void:
	for _i in range(90):
		await get_tree().process_frame
		if get_tree() == null:
			return
		if str(get_tree().current_scene.name) == "KingdomMap":
			_start_map_teleport_placement()
			return


func _start_map_teleport_placement() -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var ctrl: Node = tree.current_scene.get_node_or_null("CityTeleportController")
	if ctrl == null:
		ctrl = tree.root.find_child("CityTeleportController", true, false)
	if ctrl != null and ctrl.has_method("begin_placement"):
		ctrl.call("begin_placement")
		if tree.has_meta("pending_city_teleport"):
			tree.remove_meta("pending_city_teleport")
	else:
		print("CityTeleportController missing on KingdomMap")


func _use_resource_item(item_id: String) -> bool:
	var item: Dictionary = ItemDatabase.get_item(item_id)
	var subcategory := str(item.get("subcategory", ""))

	match item_id:
		"resource_food_100k":
			GameState.add_food(100000)
		"resource_wood_100k":
			GameState.add_wood(100000)
		"resource_stone_50k":
			GameState.add_stone(50000)
		"resource_iron_25k":
			GameState.add_iron(25000)
		"resource_diamond_1000":
			GameState.diamonds += 1000
			GameState.save_resources()
		_:
			print("Resource item not hooked up yet:", item_id, subcategory)
			return false

	return BagState.remove_item(item_id, 1)


func _use_hero_item(item_id: String) -> bool:
	if not item_id.begins_with("hero_shard_"):
		print("Hero item not hooked up yet:", item_id)
		return false

	var hero_id := item_id.replace("hero_shard_", "")
	HeroState.add_hero_shards(hero_id, 1)

	return BagState.remove_item(item_id, 1)
	
func _input(event: InputEvent) -> void:
	if not visible or not item_popup.visible:
		return

	if event is InputEventMouseButton and event.pressed:
		var popup_rect := item_popup.get_global_rect()
		if not popup_rect.has_point(event.global_position):
			# Don't steal clicks meant for tabs/close/nav — only dismiss detail popup.
			_clear_details()
