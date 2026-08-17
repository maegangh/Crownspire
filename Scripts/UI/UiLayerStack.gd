extends Node

## Topmost-first Android / system Back stack.
## close_cb may return true to keep the layer (inner navigation). Any other result pops it.
## Empty stack: Back is consumed so City/World does not quit.

const KIND_MODAL := "modal"
const KIND_SCREEN := "screen"

var _layers: Array[Dictionary] = []
var _handling: bool = false
var _back_frame: int = -1
var _prevent_quit: bool = true


func _ready() -> void:
	# Godot quits on Android Back unless this is disabled. We consume Back ourselves.
	get_tree().quit_on_go_back = false
	var win: Window = get_tree().root
	if win != null and win.has_signal("go_back_requested"):
		if not win.go_back_requested.is_connected(_on_go_back_requested):
			win.go_back_requested.connect(_on_go_back_requested)
	set_process_unhandled_input(true)


func _on_go_back_requested() -> void:
	handle_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if handle_back():
			get_viewport().set_input_as_handled()


func push_layer(id: String, close_cb: Callable, kind: String = KIND_MODAL, blocking: bool = false) -> void:
	var key: String = id.strip_edges()
	if key.is_empty() or not close_cb.is_valid():
		return
	remove_layer(key)
	_layers.append({
		"id": key,
		"close": close_cb,
		"kind": kind,
		"blocking": blocking,
	})


func remove_layer(id: String) -> void:
	var key: String = id.strip_edges()
	if key.is_empty():
		return
	for i in range(_layers.size() - 1, -1, -1):
		if str(_layers[i].get("id", "")) == key:
			_layers.remove_at(i)
			return


func set_layer_blocking(id: String, blocking: bool) -> void:
	var key: String = id.strip_edges()
	for i in range(_layers.size()):
		if str(_layers[i].get("id", "")) == key:
			_layers[i]["blocking"] = blocking
			return


func is_layer_blocking(id: String) -> bool:
	var key: String = id.strip_edges()
	for item: Dictionary in _layers:
		if str(item.get("id", "")) == key:
			return bool(item.get("blocking", false))
	return false


func debug_stack_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for item: Dictionary in _layers:
		out.append(str(item.get("id", "")))
	return out


func layer_count() -> int:
	return _layers.size()


func top_id() -> String:
	if _layers.is_empty():
		return ""
	return str(_layers[_layers.size() - 1].get("id", ""))


func reset_for_tests() -> void:
	_layers.clear()
	_handling = false
	_back_frame = -1


## Returns true if Back was consumed (including empty City/World — do not quit).
func handle_back() -> bool:
	var frame: int = Engine.get_process_frames()
	if frame == _back_frame:
		return true
	_back_frame = frame
	if _handling:
		return true
	if _layers.is_empty():
		return _prevent_quit
	var top: Dictionary = _layers[_layers.size() - 1]
	if bool(top.get("blocking", false)):
		return true
	_handling = true
	var id: String = str(top.get("id", ""))
	var stay: bool = false
	var cb: Callable = top.get("close", Callable())
	if cb.is_valid():
		var result: Variant = cb.call()
		stay = typeof(result) == TYPE_BOOL and bool(result)
	if not stay:
		remove_layer(id)
	_handling = false
	return true
