extends Node

## Optional Android Credential Manager wrapper for Crownspire Google identity.
## Never logs ID tokens, access tokens, refresh tokens, or emails.
## Never persists those values. Availability requires native plugin + web client ID.

const AccountEmailAuthScript = preload("res://Scripts/Backend/AccountEmailAuth.gd")

const LOCAL_CFG := "res://config/google_oauth.local.cfg"
const COMMITTED_CFG := "res://config/google_oauth.cfg"
const NATIVE_SINGLETON := "GodotGoogleSignIn"
const REQUEST_TIMEOUT_SEC := 90.0

var _requesting: bool = false
var _got_result: bool = false
var _pending: Dictionary = {}


func is_native_plugin_present() -> bool:
	return Engine.has_singleton(NATIVE_SINGLETON)


func has_oauth_config() -> bool:
	return _is_valid_web_client_id_format(_read_web_client_id())


func web_client_id_is_well_formed() -> bool:
	return has_oauth_config()


func has_client_secret_in_config() -> bool:
	for path: String in [LOCAL_CFG, COMMITTED_CFG]:
		var cfg := ConfigFile.new()
		if cfg.load(path) != OK:
			continue
		if str(cfg.get_value("oauth", "client_secret", "")).strip_edges() != "":
			return true
		if cfg.has_section_key("oauth", "client_secret"):
			return true
	return false


func is_android_runtime() -> bool:
	return OS.get_name() == "Android" or OS.has_feature("android")


func is_ready() -> bool:
	return is_android_runtime() and is_native_plugin_present() and has_oauth_config()


func get_availability_status() -> Dictionary:
	var blockers: PackedStringArray = PackedStringArray()
	if not is_android_runtime():
		blockers.append("Google Sign-In native plugin only runs on Android")
	if not is_native_plugin_present():
		blockers.append("GodotGoogleSignIn Android plugin is not loaded")
	if not has_oauth_config():
		blockers.append("Web OAuth client ID is not configured")
	return {
		"available": blockers.is_empty(),
		"native_plugin": is_native_plugin_present(),
		"oauth_configured": has_oauth_config(),
		"android": is_android_runtime(),
		"blockers": blockers,
	}


func request_id_token() -> Dictionary:
	if _requesting:
		return _fail(AccountEmailAuthScript.ERR_AUTH_FAILED, "Google sign-in is already in progress.")
	if not is_ready():
		return _unavailable()
	var native: Object = Engine.get_singleton(NATIVE_SINGLETON)
	if native == null:
		return _unavailable()
	var web_client_id: String = _read_web_client_id()
	if web_client_id.is_empty():
		return _unavailable()
	_requesting = true
	if native.has_method("initialize"):
		native.call("initialize", web_client_id)
	web_client_id = ""
	if native.has_signal("sign_in_success") and not native.is_connected("sign_in_success", _on_native_success):
		native.connect("sign_in_success", _on_native_success)
	if native.has_signal("sign_in_failed") and not native.is_connected("sign_in_failed", _on_native_failed):
		native.connect("sign_in_failed", _on_native_failed)
	_pending = {}
	_got_result = false
	if native.has_method("signInWithGoogleButton"):
		native.call("signInWithGoogleButton")
	elif native.has_method("signIn"):
		native.call("signIn")
	else:
		_requesting = false
		return _unavailable()
	var deadline: int = Time.get_ticks_msec() + int(REQUEST_TIMEOUT_SEC * 1000.0)
	while not _got_result and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_requesting = false
	_disconnect_native(native)
	if not _got_result:
		return _fail(AccountEmailAuthScript.ERR_NETWORK, "Google sign-in timed out.")
	var result: Dictionary = _pending.duplicate(true)
	_pending.clear()
	return result


func _on_native_success(id_token: String, _email: String, _display_name: String) -> void:
	## Do not log id_token, email, or display name.
	_pending = {
		"ok": true,
		"id_token": str(id_token),
	}
	_got_result = true


func _on_native_failed(_error: String) -> void:
	## Native error strings must not be forwarded if they might contain tokens.
	_pending = _fail(AccountEmailAuthScript.ERR_AUTH_FAILED, "Google sign-in was cancelled or failed.")
	_got_result = true


func _disconnect_native(native: Object) -> void:
	if native == null:
		return
	if native.has_signal("sign_in_success") and native.is_connected("sign_in_success", _on_native_success):
		native.disconnect("sign_in_success", _on_native_success)
	if native.has_signal("sign_in_failed") and native.is_connected("sign_in_failed", _on_native_failed):
		native.disconnect("sign_in_failed", _on_native_failed)


func _read_web_client_id() -> String:
	for path: String in [LOCAL_CFG, COMMITTED_CFG]:
		var cfg := ConfigFile.new()
		if cfg.load(path) != OK:
			continue
		var value: String = str(cfg.get_value("oauth", "web_client_id", "")).strip_edges()
		if _is_valid_web_client_id_format(value):
			return value
	return ""


func _is_valid_web_client_id_format(value: String) -> bool:
	if value.is_empty() or value.find("secret") >= 0:
		return false
	if not value.ends_with(".apps.googleusercontent.com"):
		return false
	var dash: int = value.find("-")
	if dash < 6:
		return false
	var prefix: String = value.substr(0, dash)
	if not prefix.is_valid_int():
		return false
	return true


func _unavailable() -> Dictionary:
	return {
		"ok": false,
		"available": false,
		"error": AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE,
		"message": AccountEmailAuthScript.user_message_for_code(AccountEmailAuthScript.ERR_PROVIDER_UNAVAILABLE),
	}


func _fail(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": code,
		"message": message,
	}
