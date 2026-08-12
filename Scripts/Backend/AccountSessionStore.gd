extends RefCounted
class_name AccountSessionStore

## Local-only Nakama session persistence for Crownspire Phase 1.
## Never log token or refresh_token values.

const STORE_PATH := "user://account_session.cfg"
const SMOKE_STORE_PATH := "user://account_session_smoke_test.cfg"
const SECTION := "session"
const META_SECTION := "meta"

var _path_override: String = ""


func begin_smoke_isolation() -> void:
	_path_override = SMOKE_STORE_PATH
	clear()


func end_smoke_isolation() -> void:
	clear()
	_path_override = ""


func get_store_path() -> String:
	if _path_override != "":
		return _path_override
	return STORE_PATH


func has_stored_session() -> bool:
	var data: Dictionary = load_session_data()
	return str(data.get("auth_token", "")).strip_edges() != ""


func load_session_data() -> Dictionary:
	## Returns {auth_token, refresh_token, user_id, stored_at} — callers must not print tokens.
	var cfg := ConfigFile.new()
	var path: String = get_store_path()
	if cfg.load(path) != OK:
		return {}
	return {
		"auth_token": str(cfg.get_value(SECTION, "auth_token", "")).strip_edges(),
		"refresh_token": str(cfg.get_value(SECTION, "refresh_token", "")).strip_edges(),
		"user_id": str(cfg.get_value(SECTION, "user_id", "")).strip_edges(),
		"stored_at": int(cfg.get_value(META_SECTION, "stored_at", 0)),
	}


func save_session(session: NakamaSession) -> bool:
	if session == null or session.is_exception() or not session.is_valid():
		return false
	var token: String = str(session.token).strip_edges()
	if token.is_empty():
		return false
	var cfg := ConfigFile.new()
	var path: String = get_store_path()
	# Preserve unrelated keys if any.
	cfg.load(path)
	cfg.set_value(SECTION, "auth_token", token)
	cfg.set_value(SECTION, "refresh_token", str(session.refresh_token).strip_edges())
	cfg.set_value(SECTION, "user_id", str(session.user_id).strip_edges())
	cfg.set_value(META_SECTION, "stored_at", int(Time.get_unix_time_from_system()))
	cfg.set_value(META_SECTION, "version", 1)
	var err: Error = cfg.save(path)
	return err == OK


func clear() -> void:
	var path: String = get_store_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Build a NakamaSession from stored tokens without network I/O.
func restore_session_object() -> NakamaSession:
	var data: Dictionary = load_session_data()
	var token: String = str(data.get("auth_token", "")).strip_edges()
	if token.is_empty():
		return null
	var refresh: String = str(data.get("refresh_token", "")).strip_edges()
	var session: NakamaSession = NakamaSession.new(token, false, refresh if refresh != "" else null)
	if session == null or session.is_exception() or not session.is_valid():
		return null
	return session


func redact_for_log(message: String) -> String:
	## Strip JWT-looking blobs from a log line (defense in depth).
	var out: String = message
	# Rough JWT pattern: three base64url segments.
	var re := RegEx.new()
	if re.compile("eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+") == OK:
		out = re.sub(out, "<REDACTED_JWT>", true)
	return out
