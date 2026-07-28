extends RefCounted
class_name CrownspireChatTranslationService

## Translation provider hook for Crownspire chat.
## No external/paid translation provider is configured in this phase.
## Plug in a real provider later without rewriting Chat UI.

const STATUS_UNAVAILABLE: String = "unavailable"
const STATUS_OK: String = "ok"


func is_configured() -> bool:
	return false


func translate_text(_source_text: String, _source_lang: String = "", _target_lang: String = "en") -> Dictionary:
	## Contract:
	## { ok: bool, status: String, translated_text: String, error: String }
	return {
		"ok": false,
		"status": STATUS_UNAVAILABLE,
		"translated_text": "",
		"error": "Translation service not configured.",
	}
