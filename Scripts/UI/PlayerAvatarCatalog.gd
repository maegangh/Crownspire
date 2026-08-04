extends RefCounted
class_name PlayerAvatarCatalog

## Beta fantasy avatar portraits. IDs must match server ALLOWED_AVATAR_IDS.

const AVATAR_IDS: PackedStringArray = [
	"avatar_01",
	"avatar_02",
	"avatar_03",
	"avatar_04",
	"avatar_05",
	"avatar_06",
	"avatar_07",
	"avatar_08",
]

const AVATAR_LABELS := {
	"avatar_01": "Knight",
	"avatar_02": "Mage",
	"avatar_03": "Archer",
	"avatar_04": "Paladin",
	"avatar_05": "Assassin",
	"avatar_06": "Priest",
	"avatar_07": "Druid",
	"avatar_08": "Necromancer",
}

const AVATAR_PATHS := {
	"avatar_01": "res://Art/UI/Avatars/avatar_01_knight.png",
	"avatar_02": "res://Art/UI/Avatars/avatar_02_mage.png",
	"avatar_03": "res://Art/UI/Avatars/avatar_03_archer.png",
	"avatar_04": "res://Art/UI/Avatars/avatar_04_paladin.png",
	"avatar_05": "res://Art/UI/Avatars/avatar_05_assassin.png",
	"avatar_06": "res://Art/UI/Avatars/avatar_06_priest.png",
	"avatar_07": "res://Art/UI/Avatars/avatar_07_druid.png",
	"avatar_08": "res://Art/UI/Avatars/avatar_08_necromancer.png",
}

static var _texture_cache: Dictionary = {}


static func is_valid_id(avatar_id: String) -> bool:
	return AVATAR_IDS.has(avatar_id.strip_edges())


static func normalize_id(avatar_id: String) -> String:
	var id: String = avatar_id.strip_edges()
	if is_valid_id(id):
		return id
	return "avatar_01"


static func get_label(avatar_id: String) -> String:
	var id: String = normalize_id(avatar_id)
	return str(AVATAR_LABELS.get(id, id))


static func get_texture(avatar_id: String, size: int = 128) -> Texture2D:
	var id: String = normalize_id(avatar_id)
	var key: String = "%s_%d" % [id, size]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var path: String = str(AVATAR_PATHS.get(id, ""))
	var tex: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		tex = _make_fallback_texture(id, size)
	_texture_cache[key] = tex
	return tex


static func _make_fallback_texture(avatar_id: String, size: int) -> Texture2D:
	## Only used if portrait files are missing from the export.
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var hue: float = float(avatar_id.hash() % 1000) / 1000.0
	var base := Color.from_hsv(hue, 0.45, 0.55)
	img.fill(base)
	return ImageTexture.create_from_image(img)
