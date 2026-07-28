extends RefCounted
class_name PlayerAvatarCatalog

## Default fantasy avatars for closed beta (procedural textures).
## IDs must match server ALLOWED_AVATAR_IDS.

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
	"avatar_01": "Ember Knight",
	"avatar_02": "Frost Mage",
	"avatar_03": "Forest Ranger",
	"avatar_04": "Shadow Assassin",
	"avatar_05": "Solar Priest",
	"avatar_06": "Storm Barbarian",
	"avatar_07": "Crystal Seer",
	"avatar_08": "Iron Warden",
}

const _PALETTES := {
	"avatar_01": [Color(0.72, 0.28, 0.18), Color(0.95, 0.72, 0.32)],
	"avatar_02": [Color(0.22, 0.42, 0.78), Color(0.72, 0.88, 1.0)],
	"avatar_03": [Color(0.18, 0.52, 0.28), Color(0.62, 0.88, 0.42)],
	"avatar_04": [Color(0.28, 0.14, 0.38), Color(0.72, 0.42, 0.88)],
	"avatar_05": [Color(0.78, 0.62, 0.18), Color(1.0, 0.92, 0.55)],
	"avatar_06": [Color(0.42, 0.22, 0.12), Color(0.92, 0.55, 0.28)],
	"avatar_07": [Color(0.28, 0.55, 0.68), Color(0.72, 0.95, 0.98)],
	"avatar_08": [Color(0.35, 0.38, 0.42), Color(0.78, 0.82, 0.88)],
}

const _GLYPHS := {
	"avatar_01": "⚔",
	"avatar_02": "✦",
	"avatar_03": "☘",
	"avatar_04": "◉",
	"avatar_05": "☀",
	"avatar_06": "⚡",
	"avatar_07": "◇",
	"avatar_08": "⛨",
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


static func get_glyph(avatar_id: String) -> String:
	var id: String = normalize_id(avatar_id)
	return str(_GLYPHS.get(id, "?"))


static func get_texture(avatar_id: String, size: int = 128) -> Texture2D:
	var id: String = normalize_id(avatar_id)
	var key: String = "%s_%d" % [id, size]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var tex: ImageTexture = _make_texture(id, size)
	_texture_cache[key] = tex
	return tex


static func _make_texture(avatar_id: String, size: int) -> ImageTexture:
	var colors: Array = _PALETTES.get(avatar_id, [Color(0.3, 0.3, 0.35), Color(0.8, 0.75, 0.6)])
	var base: Color = colors[0]
	var accent: Color = colors[1]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var cx: float = size * 0.5
	var cy: float = size * 0.5
	var r: float = size * 0.46
	for y in range(size):
		for x in range(size):
			var dx: float = float(x) + 0.5 - cx
			var dy: float = float(y) + 0.5 - cy
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist > r:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var t: float = clamp(dist / r, 0.0, 1.0)
			var c: Color = base.lerp(accent, 0.35 + 0.45 * (1.0 - t))
			# Soft rim
			if dist > r * 0.86:
				c = accent.lerp(Color(0.95, 0.88, 0.55), 0.55)
			img.set_pixel(x, y, c)
	# Inner diamond glyph as bright pixels
	var inner: float = size * 0.18
	for y2 in range(size):
		for x2 in range(size):
			var dx2: float = abs(float(x2) + 0.5 - cx)
			var dy2: float = abs(float(y2) + 0.5 - cy)
			if dx2 + dy2 < inner:
				var prev: Color = img.get_pixel(x2, y2)
				if prev.a > 0.0:
					img.set_pixel(x2, y2, accent.lerp(Color.WHITE, 0.35))
	var tex := ImageTexture.create_from_image(img)
	return tex
