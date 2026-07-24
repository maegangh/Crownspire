extends Button

signal hero_selected(hero_id: String)

const PORTRAIT_KEYS := ["portraitPath", "portrait", "portrait_path"]
const RARITY_FRAME_KEYS := ["rarityFramePath", "rarityFrame", "rarity_frame"]
const ROLE_ICON_KEYS := ["roleIconPath", "roleIcon", "role_icon"]
const CARD_BACKGROUND_KEYS := ["cardBackgroundPath", "cardBackground", "card_background"]

static var _placeholder_texture: Texture2D

@onready var card_background: TextureRect = $CardBackground
@onready var hero_portrait: TextureRect = $HeroPortrait
@onready var rarity_frame: TextureRect = $RarityFrame
@onready var role_icon: TextureRect = $RoleIcon
@onready var notification_dot: TextureRect = $NotificationDot
@onready var hero_name: Label = $HeroName
@onready var stars: HBoxContainer = $Stars
@onready var level_label: Label = $LevelLabel

var _hero_id: String = ""

func set_manual_hero_id(hero_id: String) -> void:
	_hero_id = hero_id

func _ready() -> void:
	_ensure_node_refs()
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)
	if notification_dot != null:
		 notification_dot.visible = false


func set_hero(hero_data: Dictionary) -> void:
	_ensure_node_refs()
	if hero_name == null or level_label == null:
		push_error("HeroCard: required Label nodes HeroName/LevelLabel are missing from the scene.")
		return

	_hero_id = str(hero_data.get("id", hero_data.get("name", "")))
	hero_name.text = str(hero_data.get("name", "Unknown"))

	var level := int(hero_data.get("level", 1))
	level_label.text = "Lv. %d" % level

	var portrait_path := _resolve_path(hero_data, PORTRAIT_KEYS)
	if portrait_path.is_empty():
		portrait_path = _default_portrait_path(hero_data)
	_set_texture(hero_portrait, portrait_path)

	var rarity_path := _resolve_path(hero_data, RARITY_FRAME_KEYS)
	_set_texture(rarity_frame, rarity_path)
	if rarity_frame != null:
		rarity_frame.visible = not rarity_path.is_empty()

	var role_path := _resolve_path(hero_data, ROLE_ICON_KEYS)
	_set_texture(role_icon, role_path)
	if role_icon != null:
		role_icon.visible = not role_path.is_empty()

	var background_path := _resolve_path(hero_data, CARD_BACKGROUND_KEYS)
	_set_texture(card_background, background_path)

	_update_stars(int(hero_data.get("ascension", 0)))


func _ensure_node_refs() -> void:
	# Safe if set_hero runs before @onready binds (should not after roster fix).
	if card_background == null:
		card_background = get_node_or_null("CardBackground") as TextureRect
	if hero_portrait == null:
		hero_portrait = get_node_or_null("HeroPortrait") as TextureRect
	if rarity_frame == null:
		rarity_frame = get_node_or_null("RarityFrame") as TextureRect
	if role_icon == null:
		role_icon = get_node_or_null("RoleIcon") as TextureRect
	if notification_dot == null:
		notification_dot = get_node_or_null("NotificationDot") as TextureRect
	if hero_name == null:
		hero_name = get_node_or_null("HeroName") as Label
	if stars == null:
		stars = get_node_or_null("Stars") as HBoxContainer
	if level_label == null:
		level_label = get_node_or_null("LevelLabel") as Label


func _on_pressed() -> void:
	if _hero_id.is_empty():
		push_warning("HeroCard: clicked card with no hero id.")
		return
	hero_selected.emit(_hero_id)


func _update_stars(star_count: int) -> void:
	if stars == null:
		return
	for child in stars.get_children():
		child.queue_free()

	for i in star_count:
		var star_label := Label.new()
		star_label.text = "★"
		stars.add_child(star_label)


func _resolve_path(hero_data: Dictionary, keys: Array) -> String:
	for key in keys:
		if hero_data.has(key):
			return str(hero_data.get(key, ""))
	return ""


func _default_portrait_path(hero_data: Dictionary) -> String:
	var hero_name_value := str(hero_data.get("name", ""))
	if hero_name_value.is_empty():
		return ""
	return "res://Art/Heroes/%s/portrait.png" % hero_name_value


func _set_texture(target: TextureRect, path: String) -> void:
	if target == null:
		return
	if path.is_empty():
		target.texture = _get_placeholder_texture()
		return

	if not ResourceLoader.exists(path):
		push_warning("HeroCard: texture not found at '%s'." % path)
		target.texture = _get_placeholder_texture()
		return

	var loaded := load(path)
	if loaded is Texture2D:
		target.texture = loaded
	else:
		push_warning("HeroCard: resource at '%s' is not a Texture2D." % path)
		target.texture = _get_placeholder_texture()


func _get_placeholder_texture() -> Texture2D:
	if _placeholder_texture == null:
		var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
		image.fill(Color(0.22, 0.22, 0.28))
		_placeholder_texture = ImageTexture.create_from_image(image)
	return _placeholder_texture
