extends Node

## Crownspire Nakama connection — authentication + realtime socket.
## Resolves host for desktop (localhost) and Android (LAN / config), never silently skips release builds.

signal authenticated
signal socket_connected
signal connection_failed(reason: String)
signal connection_state_changed(state: String) ## connecting | connected | reconnecting | offline

enum ConnState { OFFLINE, CONNECTING, CONNECTED, RECONNECTING }

const CONFIG_RES_PATH: String = "res://config/nakama_client.cfg"
const CONFIG_USER_PATH: String = "user://nakama_config.cfg"
const DEVICE_ID_PATH_DEFAULT: String = "user://nakama_device_id.cfg"
const DEVICE_ID_SECTION: String = "device"
const DEVICE_ID_KEY: String = "id"

## Desktop local defaults.
const DEV_HOST_DESKTOP: String = "127.0.0.1"
const DEV_PORT: int = 7350
const DEV_SCHEME: String = "http"
const DEV_SERVER_KEY: String = "defaultkey"
## Used only if res://config/nakama_client.cfg is missing from the Android APK.
## Keep in sync with [server] mobile_host in that cfg file.
const FALLBACK_MOBILE_HOST: String = "192.168.1.240"

const RECONNECT_BASE_SEC: float = 2.0
const RECONNECT_MAX_SEC: float = 30.0

var _client: NakamaClient = null
var _session: NakamaSession = null
var _socket: NakamaSocket = null
var _socket_connected: bool = false
var _connecting: bool = false
var _conn_state: int = ConnState.OFFLINE
var _reconnect_attempts: int = 0
var _reconnect_timer: Timer = null
var _host: String = DEV_HOST_DESKTOP
var _port: int = DEV_PORT
var _scheme: String = DEV_SCHEME
var _server_key: String = DEV_SERVER_KEY
var _last_fail_reason: String = ""


func _ready() -> void:
	_ensure_reconnect_timer()
	_load_endpoint_config()
	# Always attempt connection on desktop and mobile (release + debug).
	call_deferred("_attempt_connection")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_on_app_resumed()


func is_authenticated() -> bool:
	return _session != null and not _session.is_exception() and _session.is_valid()


func is_socket_connected() -> bool:
	if _socket == null:
		return false
	return _socket_connected and _socket.is_connected_to_host()


func get_connection_state() -> String:
	match _conn_state:
		ConnState.CONNECTING:
			return "connecting"
		ConnState.CONNECTED:
			return "connected"
		ConnState.RECONNECTING:
			return "reconnecting"
		_:
			return "offline"


func get_connection_status_label() -> String:
	match _conn_state:
		ConnState.CONNECTING:
			return "Connecting..."
		ConnState.CONNECTED:
			return "Connected"
		ConnState.RECONNECTING:
			return "Reconnecting..."
		_:
			return "Offline"


func get_last_fail_reason() -> String:
	return _last_fail_reason


func get_endpoint_summary() -> String:
	return "%s://%s:%d" % [_scheme, _host, _port]


func get_session() -> NakamaSession:
	return _session


func get_user_id() -> String:
	if not is_authenticated():
		return ""
	return str(_session.user_id)


func get_client() -> NakamaClient:
	return _client


func get_socket() -> NakamaSocket:
	return _socket


func reconnect_now() -> void:
	_reconnect_attempts = 0
	_attempt_connection(true)


func _set_state(state: int) -> void:
	if _conn_state == state:
		return
	_conn_state = state
	connection_state_changed.emit(get_connection_state())


func _is_mobile_platform() -> bool:
	## Prefer feature tags; also check OS name — some Android builds miss "android" feature early.
	var name: String = OS.get_name()
	return (
		OS.has_feature("android")
		or OS.has_feature("ios")
		or name == "Android"
		or name == "iOS"
	)


func _is_loopback_host(host: String) -> bool:
	var h: String = host.strip_edges().to_lower()
	return h == "127.0.0.1" or h == "localhost" or h == "::1"


func _load_endpoint_config() -> void:
	_host = DEV_HOST_DESKTOP
	_port = DEV_PORT
	_scheme = DEV_SCHEME
	_server_key = DEV_SERVER_KEY

	var mobile: bool = _is_mobile_platform()
	var cfg_host: String = ""
	var cfg_mobile_host: String = ""
	var selected_source: String = "default_desktop"

	# 1) Environment overrides (CI / desktop debug slots).
	var env_host: String = OS.get_environment("CROWNSPIR_NAKAMA_HOST").strip_edges()
	var env_port: String = OS.get_environment("CROWNSPIR_NAKAMA_PORT").strip_edges()
	var env_scheme: String = OS.get_environment("CROWNSPIR_NAKAMA_SCHEME").strip_edges()
	var env_key: String = OS.get_environment("CROWNSPIR_NAKAMA_SERVER_KEY").strip_edges()
	if env_host != "":
		# On mobile, ignore env loopback — it is never reachable on-device.
		if mobile and _is_loopback_host(env_host):
			push_warning("[Nakama] Ignoring CROWNSPIR_NAKAMA_HOST=%s on mobile (loopback)." % env_host)
		else:
			_host = env_host
			selected_source = "env"
	if env_port.is_valid_int():
		_port = int(env_port)
	if env_scheme != "":
		_scheme = env_scheme
	if env_key != "":
		_server_key = env_key

	# 2) Shipped project config (mobile beta LAN IP lives here).
	var res_loaded: Dictionary = _apply_cfg_file(CONFIG_RES_PATH, env_host == "" or (mobile and selected_source != "env"))
	if bool(res_loaded.get("ok", false)):
		cfg_host = str(res_loaded.get("host", ""))
		cfg_mobile_host = str(res_loaded.get("mobile_host", ""))
		if bool(res_loaded.get("host_applied", false)):
			selected_source = "res://config/nakama_client.cfg"
	else:
		push_warning("[Nakama] Failed to load %s (exists=%s). Android exports must include this file." % [
			CONFIG_RES_PATH,
			str(FileAccess.file_exists(CONFIG_RES_PATH)),
		])

	# 3) Per-device override (editable without rebuild). Never let it force loopback on mobile.
	var user_loaded: Dictionary = _apply_cfg_file(CONFIG_USER_PATH, true)
	if bool(user_loaded.get("ok", false)) and bool(user_loaded.get("host_applied", false)):
		selected_source = "user://nakama_config.cfg"

	# 4) Final mobile safety: if still loopback, force mobile_host from shipped config / fallback.
	if mobile and _is_loopback_host(_host):
		if cfg_mobile_host != "" and not _is_loopback_host(cfg_mobile_host):
			_host = cfg_mobile_host
			selected_source = "res_mobile_host_fallback"
		else:
			# Re-read shipped mobile_host directly as last resort.
			var cfg := ConfigFile.new()
			if cfg.load(CONFIG_RES_PATH) == OK:
				var mh: String = str(cfg.get_value("server", "mobile_host", "")).strip_edges()
				if mh != "" and not _is_loopback_host(mh):
					_host = mh
					cfg_mobile_host = mh
					selected_source = "res_mobile_host_reread"
		if _is_loopback_host(_host) and not _is_loopback_host(FALLBACK_MOBILE_HOST):
			_host = FALLBACK_MOBILE_HOST
			selected_source = "embedded_fallback_mobile_host"
			push_warning("[Nakama] Using embedded FALLBACK_MOBILE_HOST=%s (cfg missing or loopback)." % FALLBACK_MOBILE_HOST)

	print("[Nakama] Config loaded host=%s mobile_host=%s selected_host=%s platform=%s mobile=%s source=%s res_exists=%s" % [
		cfg_host if cfg_host != "" else str(_read_cfg_value(CONFIG_RES_PATH, "host")),
		cfg_mobile_host if cfg_mobile_host != "" else str(_read_cfg_value(CONFIG_RES_PATH, "mobile_host")),
		_host,
		OS.get_name(),
		str(mobile),
		selected_source,
		str(FileAccess.file_exists(CONFIG_RES_PATH)),
	])

	if mobile and _is_loopback_host(_host):
		push_warning("[Nakama] Mobile build still on localhost after config. Set mobile_host in res://config/nakama_client.cfg")


func _read_cfg_value(path: String, key: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	return str(cfg.get_value("server", key, "")).strip_edges()


## Returns {ok, host, mobile_host, host_applied}.
func _apply_cfg_file(path: String, allow_host: bool) -> Dictionary:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(path)
	if err != OK:
		return {"ok": false, "host": "", "mobile_host": "", "host_applied": false, "error": err}
	var file_host: String = str(cfg.get_value("server", "host", "")).strip_edges()
	var file_mobile_host: String = str(cfg.get_value("server", "mobile_host", "")).strip_edges()
	var host_applied := false
	if allow_host:
		var mobile: bool = _is_mobile_platform()
		var h: String = ""
		if mobile:
			# Android/iOS: always prefer mobile_host.
			h = file_mobile_host
			if h == "" or _is_loopback_host(h):
				# Accept non-loopback host= as a valid mobile override (user:// quick fix).
				if file_host != "" and not _is_loopback_host(file_host):
					h = file_host
				else:
					h = ""
		else:
			h = file_host
		# Never overwrite a good LAN host with loopback from a later cfg (e.g. stale user://).
		if h != "":
			if mobile and _is_loopback_host(h) and not _is_loopback_host(_host):
				push_warning("[Nakama] Ignoring loopback host from %s (keeping %s)" % [path, _host])
			else:
				_host = h
				host_applied = true
	var p = cfg.get_value("server", "port", _port)
	if typeof(p) == TYPE_INT or (typeof(p) == TYPE_STRING and str(p).is_valid_int()):
		_port = int(p)
	var s: String = str(cfg.get_value("server", "scheme", "")).strip_edges()
	if s != "":
		_scheme = s
	var k: String = str(cfg.get_value("server", "server_key", "")).strip_edges()
	if k != "":
		_server_key = k
	return {
		"ok": true,
		"host": file_host,
		"mobile_host": file_mobile_host,
		"host_applied": host_applied,
	}


func _ensure_reconnect_timer() -> void:
	if _reconnect_timer != null and is_instance_valid(_reconnect_timer):
		return
	_reconnect_timer = Timer.new()
	_reconnect_timer.name = "NakamaReconnectTimer"
	_reconnect_timer.one_shot = true
	add_child(_reconnect_timer)
	_reconnect_timer.timeout.connect(_on_reconnect_timer)


func _attempt_connection(force: bool = false) -> void:
	if _connecting:
		return
	if is_socket_connected() and is_authenticated() and not force:
		_set_state(ConnState.CONNECTED)
		return
	_connecting = true
	if _conn_state == ConnState.OFFLINE or force:
		_set_state(ConnState.CONNECTING if _reconnect_attempts == 0 else ConnState.RECONNECTING)
	await _connect_async()
	_connecting = false


func _connect_async() -> void:
	_socket_connected = false

	# Re-resolve immediately before client creation so nothing stale can stick.
	_load_endpoint_config()

	if _is_mobile_platform() and _is_loopback_host(_host):
		_fail("Server address is localhost — set your PC LAN IP in config/nakama_client.cfg mobile_host (current Wi‑Fi IP).")
		return

	if not has_node("/root/Nakama"):
		_fail("Nakama plugin missing")
		return

	var nakama: Node = get_node("/root/Nakama")
	var device_id: String = _get_or_create_device_id()
	if device_id == "":
		_fail("Could not resolve a stable device ID")
		return

	print("[Nakama] Final endpoint before create_client: %s://%s:%d (platform=%s mobile=%s)" % [
		_scheme, _host, _port, OS.get_name(), str(_is_mobile_platform())
	])
	_client = nakama.create_client(
		_server_key,
		_host,
		_port,
		_scheme,
		8,
		NakamaLogger.LOG_LEVEL.ERROR
	)
	if _client == null:
		_fail("Nakama.create_client returned null")
		return
	_client.auto_retry = true
	_client.auto_retry_count = 2

	print("[Nakama] Connecting to %s://%s:%d ..." % [_scheme, _host, _port])

	var session: NakamaSession = await _client.authenticate_device_async(device_id)
	if session == null or session.is_exception():
		var reason: String = "authentication failed"
		if session != null and session.get_exception() != null:
			reason = str(session.get_exception().message)
		_fail(reason)
		_schedule_reconnect()
		return

	_session = session
	print("[Nakama] Authentication successful user=%s" % str(session.user_id))
	authenticated.emit()

	_socket = nakama.create_socket_from(_client)
	if _socket == null:
		_fail("Nakama.create_socket_from returned null")
		_schedule_reconnect()
		return

	_bind_socket_signals()
	var socket_result: NakamaAsyncResult = await _socket.connect_async(_session)
	if socket_result == null or socket_result.is_exception():
		var sock_reason: String = "realtime socket connection failed"
		if socket_result != null and socket_result.get_exception() != null:
			sock_reason = str(socket_result.get_exception().message)
		_fail(sock_reason)
		_schedule_reconnect()
		return

	if not _socket.is_connected_to_host():
		_fail("realtime socket did not report connected")
		_schedule_reconnect()
		return

	_socket_connected = true
	_reconnect_attempts = 0
	_last_fail_reason = ""
	_set_state(ConnState.CONNECTED)
	print("[Nakama] Realtime socket connected")
	socket_connected.emit()


func _bind_socket_signals() -> void:
	if _socket == null:
		return
	if _socket.has_signal("closed") and not _socket.closed.is_connected(_on_socket_closed):
		_socket.closed.connect(_on_socket_closed)
	if _socket.has_signal("received_error") and not _socket.received_error.is_connected(_on_socket_error):
		_socket.received_error.connect(_on_socket_error)
	if _socket.has_signal("connected") and not _socket.connected.is_connected(_on_socket_connected_signal):
		_socket.connected.connect(_on_socket_connected_signal)


func _on_socket_connected_signal() -> void:
	_socket_connected = true
	_reconnect_attempts = 0
	_set_state(ConnState.CONNECTED)


func _on_socket_closed() -> void:
	_socket_connected = false
	if _conn_state == ConnState.CONNECTED or _conn_state == ConnState.RECONNECTING:
		_set_state(ConnState.RECONNECTING)
		_schedule_reconnect()


func _on_socket_error(err) -> void:
	push_warning("[Nakama] Socket error: %s" % str(err))


func _on_app_resumed() -> void:
	if is_socket_connected() and is_authenticated():
		return
	_set_state(ConnState.RECONNECTING)
	_reconnect_attempts = 0
	_attempt_connection(true)


func _schedule_reconnect() -> void:
	_ensure_reconnect_timer()
	if _reconnect_timer.time_left > 0.05:
		return
	_reconnect_attempts += 1
	var delay: float = minf(RECONNECT_MAX_SEC, RECONNECT_BASE_SEC * float(_reconnect_attempts))
	_set_state(ConnState.RECONNECTING)
	_reconnect_timer.start(delay)
	print("[Nakama] Reconnect scheduled in %.1fs (attempt %d)" % [delay, _reconnect_attempts])


func _on_reconnect_timer() -> void:
	_attempt_connection(true)


func _fail(reason: String) -> void:
	_socket_connected = false
	_last_fail_reason = reason
	_set_state(ConnState.OFFLINE if _reconnect_attempts == 0 else ConnState.RECONNECTING)
	push_error("[Nakama] Connection failed: %s (endpoint %s)" % [reason, get_endpoint_summary()])
	print("[Nakama] Connection failed: %s (endpoint %s)" % [reason, get_endpoint_summary()])
	connection_failed.emit(reason)


func get_device_id_path() -> String:
	var slot: String = OS.get_environment("CROWNSPIR_NAKAMA_DEVICE_SLOT").strip_edges()
	if slot == "" or slot == "1":
		return DEVICE_ID_PATH_DEFAULT
	var safe: String = ""
	for i in slot.length():
		var ch: String = slot[i]
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			safe += ch
	if safe == "":
		safe = "2"
	return "user://nakama_device_id_slot_%s.cfg" % safe


func _get_or_create_device_id() -> String:
	var path: String = get_device_id_path()
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		var existing: String = str(cfg.get_value(DEVICE_ID_SECTION, DEVICE_ID_KEY, "")).strip_edges()
		if existing != "":
			return existing

	var generated: String = ""
	var slot: String = OS.get_environment("CROWNSPIR_NAKAMA_DEVICE_SLOT").strip_edges()
	if slot == "" or slot == "1":
		generated = str(OS.get_unique_id()).strip_edges()
	if generated == "" or generated.to_lower() == "unknown":
		var crypto := Crypto.new()
		var bytes: PackedByteArray = crypto.generate_random_bytes(16)
		generated = "crownspire-dev-%s" % bytes.hex_encode()

	cfg.set_value(DEVICE_ID_SECTION, DEVICE_ID_KEY, generated)
	cfg.save(path)
	print("[Nakama] Created persisted device ID at %s" % path)
	return generated
