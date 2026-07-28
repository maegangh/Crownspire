extends Node

## Crownspire Nakama connection wrapper — LOCAL DEVELOPMENT FIRST CONNECTION TEST ONLY.
## Owns client / session / realtime socket. No gameplay, Alliance, Mail, or rallies.
## Chat traffic lives in ChatManager.

signal authenticated
signal socket_connected
signal connection_failed(reason: String)

## LOCAL DEVELOPMENT ONLY — never treat defaultkey as production-safe.
const DEV_HOST: String = "127.0.0.1"
const DEV_PORT: int = 7350
const DEV_SCHEME: String = "http"
const DEV_SERVER_KEY: String = "defaultkey"

const DEVICE_ID_PATH_DEFAULT: String = "user://nakama_device_id.cfg"
const DEVICE_ID_SECTION: String = "device"
const DEVICE_ID_KEY: String = "id"

## Debug: set CROWNSPIR_NAKAMA_DEVICE_SLOT=2 to authenticate a second local identity
## without destroying the primary development account (slot 1 / default).

var _client: NakamaClient = null
var _session: NakamaSession = null
var _socket: NakamaSocket = null
var _socket_connected: bool = false
var _connecting: bool = false


func _ready() -> void:
	if not OS.is_debug_build():
		return
	# Defer so other autoloads finish bootstrapping local gameplay first.
	call_deferred("_attempt_local_dev_connection")


func is_authenticated() -> bool:
	return _session != null and not _session.is_exception() and _session.is_valid()


func is_socket_connected() -> bool:
	if _socket == null:
		return false
	return _socket_connected and _socket.is_connected_to_host()


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


func _attempt_local_dev_connection() -> void:
	if _connecting:
		return
	_connecting = true
	await _connect_local_dev()
	_connecting = false


func _connect_local_dev() -> void:
	_socket_connected = false
	_session = null
	_socket = null

	if not has_node("/root/Nakama"):
		_fail("Nakama autoload missing")
		return

	var nakama: Node = get_node_or_null("/root/Nakama")
	if nakama == null:
		_fail("Nakama autoload missing")
		return

	var device_id: String = _get_or_create_device_id()
	if device_id == "":
		_fail("Could not resolve a stable development device ID")
		return

	_client = nakama.create_client(
		DEV_SERVER_KEY,
		DEV_HOST,
		DEV_PORT,
		DEV_SCHEME,
		3,
		NakamaLogger.LOG_LEVEL.ERROR
	)
	if _client == null:
		_fail("Nakama.create_client returned null")
		return
	# Fail fast when the local server is down; do not spam retries/logs.
	_client.auto_retry = false
	_client.auto_retry_count = 0

	print("[Nakama] Connecting to %s://%s:%d (device auth)..." % [DEV_SCHEME, DEV_HOST, DEV_PORT])

	var session: NakamaSession = await _client.authenticate_device_async(device_id)
	if session == null or session.is_exception():
		var reason: String = "authentication failed"
		if session != null and session.get_exception() != null:
			reason = str(session.get_exception().message)
		_fail(reason)
		return

	_session = session
	print("[Nakama] Authentication successful")
	print("[Nakama] User ID: %s" % str(session.user_id))
	if str(session.username) != "":
		print("[Nakama] Username: %s" % str(session.username))
	authenticated.emit()

	_socket = nakama.create_socket_from(_client)
	if _socket == null:
		_fail("Nakama.create_socket_from returned null")
		return

	var socket_result: NakamaAsyncResult = await _socket.connect_async(_session)
	if socket_result == null or socket_result.is_exception():
		var sock_reason: String = "realtime socket connection failed"
		if socket_result != null and socket_result.get_exception() != null:
			sock_reason = str(socket_result.get_exception().message)
		_fail(sock_reason)
		return

	if not _socket.is_connected_to_host():
		_fail("realtime socket did not report connected")
		return

	_socket_connected = true
	print("[Nakama] Realtime socket connected")
	socket_connected.emit()


func _fail(reason: String) -> void:
	_socket_connected = false
	push_error("[Nakama] Local development connection failed: %s" % reason)
	print("[Nakama] Local development connection failed: %s" % reason)
	connection_failed.emit(reason)


func get_device_id_path() -> String:
	var slot: String = OS.get_environment("CROWNSPIR_NAKAMA_DEVICE_SLOT").strip_edges()
	if slot == "" or slot == "1":
		return DEVICE_ID_PATH_DEFAULT
	# Sanitize slot token for filename safety.
	var safe: String = ""
	for i in slot.length():
		var ch: String = slot[i]
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			safe += ch
	if safe == "":
		safe = "2"
	return "user://nakama_device_id_slot_%s.cfg" % safe


func _get_or_create_device_id() -> String:
	# Always reuse a previously persisted ID so restarts map to the same Nakama account.
	var path: String = get_device_id_path()
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		var existing: String = str(cfg.get_value(DEVICE_ID_SECTION, DEVICE_ID_KEY, "")).strip_edges()
		if existing != "":
			return existing

	# First launch: prefer Godot's stable OS unique ID when available (slot 1 only).
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
	print("[Nakama] Created persisted development device ID at %s" % path)
	return generated
