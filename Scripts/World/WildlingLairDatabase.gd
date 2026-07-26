extends RefCounted
class_name WildlingLairDatabase

## Presentation catalog for Wildling Lairs (Lv.1–10).
## Backend-safe: load-only JSON. No authoritative rally/combat state.
## Future: Nakama may own the same schema; Godot keeps this as UI catalog / fallback.

const DATA_PATH := "res://data/wildling_lairs.json"

## Target on-map footprint for dedicated lair art (~1.5–2× Wildling importance).
const WORLD_SPRITE_SCALE := 0.135

static var _cache: Dictionary = {}
static var _loaded: bool = false
static var _texture_cache: Dictionary = {} # variant -> Texture2D


static func reload() -> void:
	_loaded = false
	_cache.clear()
	_texture_cache.clear()
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_cache = {}
	if not FileAccess.file_exists(DATA_PATH):
		push_error("[WildlingLairDatabase] Missing %s" % DATA_PATH)
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("[WildlingLairDatabase] Failed to open %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[WildlingLairDatabase] Invalid JSON root")
		return
	_cache = parsed as Dictionary


static func get_catalog() -> Dictionary:
	_ensure_loaded()
	return _cache.duplicate(true)


static func level_min() -> int:
	_ensure_loaded()
	return int(_cache.get("levelMin", 1))


static func level_max() -> int:
	_ensure_loaded()
	return int(_cache.get("levelMax", 10))


static func get_level_def(level: int) -> Dictionary:
	_ensure_loaded()
	var levels: Array = _cache.get("levels", []) as Array
	for entry_v: Variant in levels:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		if int(entry.get("level", -1)) == level:
			return entry.duplicate(true)
	return {}


static func is_beta() -> bool:
	_ensure_loaded()
	return bool(_cache.get("beta", true))


## Fallback only when a level def omits visual_variant.
## Canonical mapping lives in data/wildling_lairs.json (tier progression).
static func visual_variant_for_species(species: String) -> String:
	match species.strip_edges().to_lower():
		"wolf", "bear":
			return "beast"
		"spider", "boar":
			return "horror"
		"troll", "dragon":
			return "ancient"
		_:
			return "beast"


static func get_texture_path(variant: String) -> String:
	_ensure_loaded()
	var variants: Dictionary = _cache.get("visual_variants", {}) as Dictionary
	var key: String = variant.strip_edges().to_lower()
	if variants.has(key):
		return str(variants[key])
	return str(variants.get("beast", "res://assets/World/WildlingLairs/BeastWildlingLair.png"))


static func get_texture_for_variant(variant: String) -> Texture2D:
	var key: String = variant.strip_edges().to_lower()
	if key.is_empty():
		key = "beast"
	if _texture_cache.has(key) and _texture_cache[key] != null:
		return _texture_cache[key] as Texture2D
	var path: String = get_texture_path(key)
	if not ResourceLoader.exists(path):
		push_warning("[WildlingLairDatabase] Missing texture: %s" % path)
		return null
	var tex: Texture2D = load(path) as Texture2D
	_texture_cache[key] = tex
	return tex


static func get_texture_for_level_def(def: Dictionary) -> Texture2D:
	var variant: String = str(def.get("visual_variant", ""))
	if variant.is_empty():
		variant = visual_variant_for_species(str(def.get("species", "wolf")))
	return get_texture_for_variant(variant)


static func creature_title(def: Dictionary) -> String:
	var title: String = str(def.get("creature_title", "")).strip_edges()
	if not title.is_empty():
		return title
	var species: String = str(def.get("species", "")).strip_edges()
	if species.is_empty():
		return "Wildling Lair"
	return "%s Lair" % species.capitalize()


static func format_power(value: int) -> String:
	var text: String = str(maxi(0, value))
	if text.length() <= 3:
		return text
	var parts: PackedStringArray = []
	while text.length() > 3:
		parts.insert(0, text.substr(text.length() - 3, 3))
		text = text.substr(0, text.length() - 3)
	if not text.is_empty():
		parts.insert(0, text)
	return ",".join(parts)


static func format_reward_preview(rewards: Dictionary) -> String:
	if rewards.is_empty():
		return "Rewards pending balance."
	var parts: PackedStringArray = []
	for key: Variant in rewards.keys():
		var k: String = str(key)
		var v: int = int(rewards.get(k, 0))
		if v <= 0:
			continue
		parts.append("%s %s" % [k.replace("_", " ").capitalize(), format_power(v)])
	if parts.is_empty():
		return "Rewards pending balance."
	return "\n".join(parts)
