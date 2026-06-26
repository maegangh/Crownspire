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

@onready var heroes_button: Button = $Control/BottomBarTexture/BottomButtons/HeroesButton
@onready var wayfinder_button: Button = $Control/BottomBarTexture/BottomButtons/WayfinderButton
@onready var bag_button: Button = $Control/BottomBarTexture/BottomButtons/BagButton
@onready var quest_button: Button = $Control/BottomBarTexture/BottomButtons/QuestButton
@onready var alliance_button: Button = $Control/BottomBarTexture/BottomButtons/AllianceButton
@onready var world_city_button: Button = $Control/BottomBarTexture/BottomButtons/WorldCityButton

func _ready():
	setup_bottom_bar()
	update_resources()
	connect_buttons()

func _process(_delta):
	update_resources()

func setup_bottom_bar():
	if is_world_screen:
		bottom_bar_texture.texture = bottom_bar_home
	else:
		bottom_bar_texture.texture = bottom_bar_world

func update_resources():
	food_label.text = str(GameState.food)
	wood_label.text = str(GameState.wood)
	stone_label.text = str(GameState.stone)
	iron_label.text = str(GameState.iron)
	diamond_label.text = str(GameState.diamonds)

	power_label.text = "1,614,990"
	vip_label.text = "VIP 1"

func connect_buttons():
	if portrait_button:
		portrait_button.pressed.connect(_on_portrait_pressed)
	if shop_button:
		shop_button.pressed.connect(_on_shop_pressed)
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
	print("Open Shop")

func _on_heroes_pressed():
	print("Open Heroes")
	get_tree().change_scene_to_file.call_deferred("res://Scenes/UI/HeroRoster.tscn")

func _on_wayfinder_pressed():
	print("Wayfinder coming soon")

func _on_bag_pressed():
	print("Open Bag")

func _on_quest_pressed():
	print("Open Quest")

func _on_alliance_pressed():
	print("Open Alliance")

func _on_world_city_pressed():
	print("World/City button clicked")

	if world_city_button:
		world_city_button.disabled = true

	if is_world_screen:
		get_tree().change_scene_to_file.call_deferred("res://Scenes/City/City.tscn")
	else:
		get_tree().change_scene_to_file.call_deferred("res://Scenes/WorldMap_Beta.tscn")
