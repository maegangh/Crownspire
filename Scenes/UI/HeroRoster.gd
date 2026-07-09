extends Control

const HERO_CARD_SCENES := [
	"res://Scenes/UI/HeroCards/MaeganHeroCard.tscn",
	"res://Scenes/UI/HeroCards/LorelaiHeroCard.tscn",
	"res://Scenes/UI/HeroCards/AllannaHeroCard.tscn",
	"res://Scenes/UI/HeroCards/ShadowHeroCard.tscn",
	"res://Scenes/UI/HeroCards/DemonHeroCard.tscn",
	"res://Scenes/UI/HeroCards/MyshlaHeroCard.tscn",
	"res://Scenes/UI/HeroCards/LumiHeroCard.tscn",
	"res://Scenes/UI/HeroCards/SkyeHeroCard.tscn",
	"res://Scenes/UI/HeroCards/RemiHeroCard.tscn",
	"res://Scenes/UI/HeroCards/RayneHeroCard.tscn",
	"res://Scenes/UI/HeroCards/RubbleHeroCard.tscn",
]

const HERO_IDS := [
	"maegan",
	"lorelai",
	"allanna",
	"shadow",
	"demon",
	"myshla",
	"lumi",
	"skye",
	"remi",
	"rayne",
	"rubble",
]

@onready var hero_grid: GridContainer = get_node_or_null("ScrollContainer/HeroGrid")
@onready var hero_details_panel: Control = get_node_or_null("HeroDetails")
@onready var back_button: TextureButton = get_node_or_null("BackButton")

func _ready() -> void:
	if hero_grid == null:
		push_error("HeroRoster ERROR: Missing node ScrollContainer/HeroGrid")
		return

	if hero_details_panel == null:
		push_error("HeroRoster ERROR: Missing node HeroDetails")
		return

	if back_button == null:
		push_error("HeroRoster ERROR: Missing node BackButton")
		return

	hero_details_panel.visible = false
	_populate_roster()

	if not back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.connect(_on_back_pressed)


func _populate_roster() -> void:
	for child in hero_grid.get_children():
		child.queue_free()

	for i in range(HERO_CARD_SCENES.size()):
		var scene_path: String = HERO_CARD_SCENES[i]
		var hero_id: String = HERO_IDS[i]

		var packed_scene: PackedScene = load(scene_path)

		if packed_scene == null:
			push_warning("HeroRoster WARNING: Missing hero card scene: " + scene_path)
			continue

		var card = packed_scene.instantiate()
		hero_grid.add_child(card)

		if card.has_method("set_manual_hero_id"):
			card.set_manual_hero_id(hero_id)
		elif "_hero_id" in card:
			card._hero_id = hero_id

		if card.has_signal("hero_selected"):
			if not card.hero_selected.is_connected(_on_hero_selected):
				card.hero_selected.connect(_on_hero_selected)


func _on_hero_selected(hero_id: String) -> void:
	print("Hero selected: ", hero_id)

	if not Engine.has_singleton("DataManager") and not typeof(DataManager) == TYPE_OBJECT:
		push_error("HeroRoster ERROR: DataManager not found.")
		return

	var hero_data: Dictionary = DataManager.get_hero(hero_id)

	if hero_data.is_empty():
		push_error("HeroRoster ERROR: Hero not found: " + hero_id)
		return

	hero_details_panel.visible = true

	if hero_details_panel.has_method("show_hero"):
		hero_details_panel.show_hero(hero_data)
	else:
		push_error("HeroRoster ERROR: HeroDetails does not have show_hero(hero_data).")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/City/City.tscn")
