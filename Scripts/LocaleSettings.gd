extends Node

## Crownspire locale preference — thin TranslationServer helper (Phase 0).
## Does NOT store translation strings. Catalog lives in locales/ + TranslationServer.

signal locale_changed(locale: String)

const SAVE_PATH: String = "user://locale.cfg"
const SECTION: String = "locale"
const KEY_PREFERRED: String = "preferred"
const LOCALE_EN: String = "en"
const LOCALE_TR: String = "tr"
const FALLBACK_LOCALE: String = LOCALE_EN
const SUPPORTED_LOCALES: PackedStringArray = [LOCALE_EN, LOCALE_TR]
const TRANSLATION_RESOURCES: PackedStringArray = [
	"res://locales/crownspire_ui.en.translation",
	"res://locales/crownspire_ui.tr.translation",
	# Text mirrors kept for diff-friendly review / rebuild source.
	"res://locales/crownspire_ui.en.tres",
	"res://locales/crownspire_ui.tr.tres",
]

## Effective UI locale after boot apply (always one of SUPPORTED_LOCALES).
var current_locale: String = FALLBACK_LOCALE
var _translations_registered: bool = false


func _enter_tree() -> void:
	# project.godot lists these resources; also register explicitly so headless/runtime
	# always has TranslationServer messages even if remaps fail to auto-load.
	_register_translations()


func _ready() -> void:
	_register_translations()
	var preferred: String = load_preferred_locale()
	if preferred != "":
		apply_locale(preferred, false)
	else:
		apply_locale(_detect_device_locale(), false)


func _register_translations() -> void:
	if _translations_registered:
		return
	var added_locales: Dictionary = {}
	for path: String in TRANSLATION_RESOURCES:
		if not ResourceLoader.exists(path):
			continue
		var res: Resource = load(path)
		if not (res is Translation):
			continue
		var loc: String = str((res as Translation).locale)
		# Prefer .translation binaries once; skip duplicate locale from .tres mirror.
		if added_locales.has(loc):
			continue
		TranslationServer.add_translation(res as Translation)
		added_locales[loc] = path
	if added_locales.is_empty():
		push_warning("LocaleSettings: no translation resources registered")
	_translations_registered = true


## Saved preference only — empty when the player has never chosen a language.
func load_preferred_locale() -> String:
	if not FileAccess.file_exists(SAVE_PATH):
		return ""
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return ""
	return normalize_locale(str(cfg.get_value(SECTION, KEY_PREFERRED, "")))


func save_preferred_locale(locale: String) -> void:
	var loc: String = normalize_locale(locale)
	if loc.is_empty():
		loc = FALLBACK_LOCALE
	var cfg := ConfigFile.new()
	# Preserve any future unrelated keys in this file.
	cfg.load(SAVE_PATH)
	cfg.set_value(SECTION, KEY_PREFERRED, loc)
	var err: Error = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("LocaleSettings: failed to save %s (err=%d)" % [SAVE_PATH, err])


## Player-driven change: apply + persist + notify.
func set_player_locale(locale: String) -> String:
	return apply_locale(locale, true)


## Apply locale to TranslationServer. Persist only when requested (manual selection).
func apply_locale(locale: String, persist: bool) -> String:
	var loc: String = normalize_locale(locale)
	if loc.is_empty():
		loc = FALLBACK_LOCALE
	TranslationServer.set_locale(loc)
	current_locale = loc
	if persist:
		save_preferred_locale(loc)
	locale_changed.emit(loc)
	return loc


func get_current_locale() -> String:
	return current_locale


func is_supported_locale(locale: String) -> bool:
	return normalize_locale(locale) != ""


## Map free-form / OS tags onto Phase-0 supported locales. Unsupported → "".
func normalize_locale(locale: String) -> String:
	var raw: String = locale.strip_edges().to_lower().replace("_", "-")
	if raw.is_empty():
		return ""
	if raw == LOCALE_EN or raw.begins_with("en-"):
		return LOCALE_EN
	if raw == LOCALE_TR or raw.begins_with("tr-"):
		return LOCALE_TR
	return ""


func _detect_device_locale() -> String:
	# Prefer language code (Godot 4); fall back to full locale string.
	var lang: String = ""
	if OS.has_method("get_locale_language"):
		lang = str(OS.call("get_locale_language"))
	if lang.is_empty():
		lang = OS.get_locale()
	var mapped: String = normalize_locale(lang)
	if mapped != "":
		return mapped
	return FALLBACK_LOCALE
