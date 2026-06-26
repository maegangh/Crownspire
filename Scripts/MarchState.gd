extends Node

var march_active = false
var march_type = ""
var target_name = ""
var finish_time = 0

func start_march(type, target, seconds):
	if march_active:
		return false

	march_active = true
	march_type = type
	target_name = target
	finish_time = int(Time.get_unix_time_from_system()) + seconds
	return true

func get_time_left():
	if not march_active:
		return 0

	return max(
		0,
		finish_time - int(Time.get_unix_time_from_system())
	)

func finish_march():
	march_active = false
	march_type = ""
	target_name = ""
	finish_time = 0
