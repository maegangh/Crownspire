extends RefCounted
class_name ChatEmojiCatalog

## Stable ASCII emoji tokens for Nakama chat + PNG rendering on Android.
## Folder: res://assets/UI/chat_emoji/
## Never interprets BBCode — only :token: names from this catalog (and legacy Unicode glyphs).

const ASSET_DIR: String = "res://assets/UI/chat_emoji/"
const TOKEN_RE_PATTERN: String = ":([a-z0-9_]+):"

## Parallel tables — index i is one emoji entry.
static var TOKENS: PackedStringArray = PackedStringArray([
	"grinning", "beaming", "joy", "rofl", "blush", "heart_eyes", "sunglasses", "thinking",
	"sweat_smile", "cry", "sob", "rage", "thumbsup", "thumbsdown", "clap", "pray",
	"fire", "sparkles", "muscle", "tada", "heart", "broken_heart", "swords", "castle",
	"dragon", "shield", "crown", "check", "x", "star", "glowing_star", "100",
])
static var FILES: PackedStringArray = PackedStringArray([
	"1f600.png", "1f601.png", "1f602.png", "1f923.png", "1f60a.png", "1f60d.png", "1f60e.png", "1f914.png",
	"1f605.png", "1f622.png", "1f62d.png", "1f621.png", "1f44d.png", "1f44e.png", "1f44f.png", "1f64f.png",
	"1f525.png", "2728.png", "1f4aa.png", "1f389.png", "2764.png", "1f494.png", "2694.png", "1f3f0.png",
	"1f409.png", "1f6e1.png", "1f451.png", "2705.png", "274c.png", "2b50.png", "1f31f.png", "1f4af.png",
])
## Legacy Unicode glyphs (optional VS16). Used only for display of old messages + outbound normalize.
static var LEGACY_UNICODE: PackedStringArray = PackedStringArray([
	"😀", "😁", "😂", "🤣", "😊", "😍", "😎", "🤔",
	"😅", "😢", "😭", "😡", "👍", "👎", "👏", "🙏",
	"🔥", "✨", "💪", "🎉", "❤️", "💔", "⚔️", "🏰",
	"🐉", "🛡️", "👑", "✅", "❌", "⭐", "🌟", "💯",
])

static var _tex_cache: Dictionary = {} ## file -> Texture2D
static var _token_to_file: Dictionary = {}
static var _unicode_to_token: Dictionary = {}
static var _maps_ready: bool = false


static func ensure_maps() -> void:
	if _maps_ready:
		return
	_token_to_file.clear()
	_unicode_to_token.clear()
	var n: int = mini(TOKENS.size(), FILES.size())
	n = mini(n, LEGACY_UNICODE.size())
	for i in range(n):
		var tok: String = str(TOKENS[i])
		var file_name: String = str(FILES[i])
		_token_to_file[tok] = file_name
		var glyph: String = str(LEGACY_UNICODE[i])
		_unicode_to_token[glyph] = tok
		## Also map base codepoint without emoji presentation selector (U+FE0F).
		var stripped: String = glyph.replace("\uFE0F", "")
		if stripped != glyph and stripped != "":
			_unicode_to_token[stripped] = tok
	_maps_ready = true


static func token_literal(token_name: String) -> String:
	return ":%s:" % token_name


static func file_for_token(token_name: String) -> String:
	ensure_maps()
	return str(_token_to_file.get(token_name, ""))


static func token_for_unicode(glyph: String) -> String:
	ensure_maps()
	return str(_unicode_to_token.get(glyph, ""))


static func is_known_token(token_name: String) -> bool:
	ensure_maps()
	return _token_to_file.has(token_name)


static func load_texture(file_name: String) -> Texture2D:
	if file_name == "":
		return null
	if _tex_cache.has(file_name):
		return _tex_cache[file_name] as Texture2D
	var path: String = ASSET_DIR + file_name
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(path)) == OK:
			tex = ImageTexture.create_from_image(img)
	if tex != null:
		_tex_cache[file_name] = tex
	return tex


static func texture_for_token(token_name: String) -> Texture2D:
	return load_texture(file_for_token(token_name))


static func _unicode_glyphs_longest_first() -> PackedStringArray:
	ensure_maps()
	var keys: Array = _unicode_to_token.keys()
	keys.sort_custom(func(a, b): return str(a).length() > str(b).length())
	var out := PackedStringArray()
	for k in keys:
		out.append(str(k))
	return out


## Convert known legacy Unicode glyphs to :token: before send. Leaves other text untouched.
static func normalize_outbound(text_value: String) -> String:
	ensure_maps()
	var out := ""
	var i: int = 0
	var s: String = str(text_value)
	var glyphs: PackedStringArray = _unicode_glyphs_longest_first()
	while i < s.length():
		## Keep existing :token: spans intact (known or unknown).
		if s.substr(i, 1) == ":":
			var token_span: Dictionary = _try_read_token(s, i)
			if bool(token_span.get("ok", false)):
				out += str(token_span.get("literal", ""))
				i = int(token_span.get("end", i + 1))
				continue
		var matched_glyph: String = ""
		var matched_tok: String = ""
		for g in glyphs:
			if g != "" and s.substr(i, g.length()) == g:
				matched_glyph = g
				matched_tok = str(_unicode_to_token[g])
				break
		if matched_glyph != "":
			out += token_literal(matched_tok)
			i += matched_glyph.length()
		else:
			out += s.substr(i, 1)
			i += 1
	return out


## Segments for UI: {kind:"text"|"emoji", text?:String, token?:String, file?:String}
static func parse_segments(text_value: String) -> Array:
	ensure_maps()
	var segments: Array = []
	var plain := ""
	var i: int = 0
	var s: String = str(text_value)
	var glyphs: PackedStringArray = _unicode_glyphs_longest_first()
	while i < s.length():
		if s.substr(i, 1) == ":":
			var token_span: Dictionary = _try_read_token(s, i)
			if bool(token_span.get("ok", false)):
				var tok: String = str(token_span.get("name", ""))
				if is_known_token(tok):
					if plain != "":
						segments.append({"kind": "text", "text": plain})
						plain = ""
					segments.append({
						"kind": "emoji",
						"token": tok,
						"file": file_for_token(tok),
						"text": str(token_span.get("literal", "")),
					})
					i = int(token_span.get("end", i + 1))
					continue
				## Unknown :token: stays as visible text (do not drop).
				plain += str(token_span.get("literal", ""))
				i = int(token_span.get("end", i + 1))
				continue
		## Legacy Unicode → render as emoji image when known.
		var matched_glyph: String = ""
		var matched_tok: String = ""
		for g in glyphs:
			if g != "" and s.substr(i, g.length()) == g:
				matched_glyph = g
				matched_tok = str(_unicode_to_token[g])
				break
		if matched_glyph != "" and matched_tok != "":
			if plain != "":
				segments.append({"kind": "text", "text": plain})
				plain = ""
			segments.append({
				"kind": "emoji",
				"token": matched_tok,
				"file": file_for_token(matched_tok),
				"text": matched_glyph,
			})
			i += matched_glyph.length()
			continue
		plain += s.substr(i, 1)
		i += 1
	if plain != "":
		segments.append({"kind": "text", "text": plain})
	return segments


static func list_tokens_in_text(text_value: String) -> PackedStringArray:
	var found := PackedStringArray()
	for seg in parse_segments(text_value):
		if str(seg.get("kind", "")) == "emoji":
			found.append(str(seg.get("token", "")))
	return found


static func _try_read_token(s: String, start: int) -> Dictionary:
	## Match :name: where name is [a-z0-9_]+ — never treats [url] / BBCode as markup.
	if start < 0 or start >= s.length() or s.substr(start, 1) != ":":
		return {"ok": false}
	var j: int = start + 1
	var name := ""
	while j < s.length():
		var ch: String = s.substr(j, 1)
		var code: int = ch.unicode_at(0)
		var ok_ch: bool = (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95
		if not ok_ch:
			break
		name += ch
		j += 1
	if name == "" or j >= s.length() or s.substr(j, 1) != ":":
		return {"ok": false}
	return {
		"ok": true,
		"name": name,
		"literal": ":%s:" % name,
		"end": j + 1,
	}


static func verify_all_assets() -> Dictionary:
	## Returns {ok, missing: PackedStringArray, loaded: int}
	ensure_maps()
	var missing := PackedStringArray()
	var loaded: int = 0
	for i in range(FILES.size()):
		var file_name: String = str(FILES[i])
		var path: String = ASSET_DIR + file_name
		if not FileAccess.file_exists(path):
			missing.append(file_name)
			continue
		var tex: Texture2D = load_texture(file_name)
		if tex == null:
			missing.append(file_name)
		else:
			loaded += 1
	return {"ok": missing.is_empty(), "missing": missing, "loaded": loaded, "total": FILES.size()}
