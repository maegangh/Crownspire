extends Node

signal training_updated

var infantry: int = 0
var marksmen: int = 0
var cavalry: int = 0

var wounded_infantry: int = 0
var wounded_marksmen: int = 0
var wounded_cavalry: int = 0

var hospital_capacity: int = 1000
var sanctuary_capacity: int = 500
var sanctuary_troops: int = 0

var infantry_training_active: bool = false
var marksmen_training_active: bool = false
var cavalry_training_active: bool = false

var infantry_training_ready: bool = false
var marksmen_training_ready: bool = false
var cavalry_training_ready: bool = false

var infantry_training_amount: int = 0
var marksmen_training_amount: int = 0
var cavalry_training_amount: int = 0

var infantry_finish_time: int = 0
var marksmen_finish_time: int = 0
var cavalry_finish_time: int = 0


func _ready() -> void:
	load_troops()
	check_finished_training()


func _process(_delta: float) -> void:
	check_finished_training()


func start_training(troop_type: String, amount: int) -> bool:
	var time_needed: int = amount * 2
	var finish_time: int = int(Time.get_unix_time_from_system()) + time_needed

	if troop_type == "Infantry":
		if infantry_training_active or infantry_training_ready:
			return false
		infantry_training_active = true
		infantry_training_ready = false
		infantry_training_amount = amount
		infantry_finish_time = finish_time

	elif troop_type == "Marksmen":
		if marksmen_training_active or marksmen_training_ready:
			return false
		marksmen_training_active = true
		marksmen_training_ready = false
		marksmen_training_amount = amount
		marksmen_finish_time = finish_time

	elif troop_type == "Cavalry":
		if cavalry_training_active or cavalry_training_ready:
			return false
		cavalry_training_active = true
		cavalry_training_ready = false
		cavalry_training_amount = amount
		cavalry_finish_time = finish_time

	save_troops()
	training_updated.emit()
	return true


func check_finished_training() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var changed: bool = false

	if infantry_training_active and now >= infantry_finish_time:
		infantry_training_active = false
		infantry_training_ready = true
		changed = true

	if marksmen_training_active and now >= marksmen_finish_time:
		marksmen_training_active = false
		marksmen_training_ready = true
		changed = true

	if cavalry_training_active and now >= cavalry_finish_time:
		cavalry_training_active = false
		cavalry_training_ready = true
		changed = true

	if changed:
		save_troops()
		training_updated.emit()


func collect_training(troop_type: String) -> bool:
	var amount: int = get_training_amount(troop_type)

	if troop_type == "Infantry" and infantry_training_ready:
		infantry += infantry_training_amount
		infantry_training_amount = 0
		infantry_finish_time = 0
		infantry_training_ready = false

	elif troop_type == "Marksmen" and marksmen_training_ready:
		marksmen += marksmen_training_amount
		marksmen_training_amount = 0
		marksmen_finish_time = 0
		marksmen_training_ready = false

	elif troop_type == "Cavalry" and cavalry_training_ready:
		cavalry += cavalry_training_amount
		cavalry_training_amount = 0
		cavalry_finish_time = 0
		cavalry_training_ready = false

	else:
		return false

	save_troops()
	training_updated.emit()

	if has_node("/root/GameEvents"):
		GameEvents.emit_troops_trained(amount)

	return true


func speedup_training(troop_type: String, seconds: int) -> void:
	if troop_type == "Infantry" and infantry_training_active:
		infantry_finish_time = max(int(Time.get_unix_time_from_system()), infantry_finish_time - seconds)

	elif troop_type == "Marksmen" and marksmen_training_active:
		marksmen_finish_time = max(int(Time.get_unix_time_from_system()), marksmen_finish_time - seconds)

	elif troop_type == "Cavalry" and cavalry_training_active:
		cavalry_finish_time = max(int(Time.get_unix_time_from_system()), cavalry_finish_time - seconds)

	save_troops()
	check_finished_training()
	training_updated.emit()


func is_training_active(troop_type: String) -> bool:
	if troop_type == "Infantry":
		return infantry_training_active
	if troop_type == "Marksmen":
		return marksmen_training_active
	if troop_type == "Cavalry":
		return cavalry_training_active
	return false


func is_training_ready(troop_type: String) -> bool:
	if troop_type == "Infantry":
		return infantry_training_ready
	if troop_type == "Marksmen":
		return marksmen_training_ready
	if troop_type == "Cavalry":
		return cavalry_training_ready
	return false


func get_training_amount(troop_type: String) -> int:
	if troop_type == "Infantry":
		return infantry_training_amount
	if troop_type == "Marksmen":
		return marksmen_training_amount
	if troop_type == "Cavalry":
		return cavalry_training_amount
	return 0


func get_troop_count(troop_type: String) -> int:
	if troop_type == "Infantry":
		return infantry
	if troop_type == "Marksmen":
		return marksmen
	if troop_type == "Cavalry":
		return cavalry
	return 0


func get_training_time_left(troop_type: String) -> float:
	var now: int = int(Time.get_unix_time_from_system())

	if troop_type == "Infantry":
		return max(0, infantry_finish_time - now)
	if troop_type == "Marksmen":
		return max(0, marksmen_finish_time - now)
	if troop_type == "Cavalry":
		return max(0, cavalry_finish_time - now)

	return 0


func save_troops() -> void:
	var save: ConfigFile = ConfigFile.new()

	save.set_value("troops", "infantry", infantry)
	save.set_value("troops", "marksmen", marksmen)
	save.set_value("troops", "cavalry", cavalry)

	save.set_value("training", "infantry_active", infantry_training_active)
	save.set_value("training", "marksmen_active", marksmen_training_active)
	save.set_value("training", "cavalry_active", cavalry_training_active)

	save.set_value("training", "infantry_ready", infantry_training_ready)
	save.set_value("training", "marksmen_ready", marksmen_training_ready)
	save.set_value("training", "cavalry_ready", cavalry_training_ready)

	save.set_value("training", "infantry_amount", infantry_training_amount)
	save.set_value("training", "marksmen_amount", marksmen_training_amount)
	save.set_value("training", "cavalry_amount", cavalry_training_amount)

	save.set_value("training", "infantry_finish_time", infantry_finish_time)
	save.set_value("training", "marksmen_finish_time", marksmen_finish_time)
	save.set_value("training", "cavalry_finish_time", cavalry_finish_time)

	save.save("user://troops.cfg")


func load_troops() -> void:
	var save: ConfigFile = ConfigFile.new()

	if save.load("user://troops.cfg") == OK:
		infantry = int(save.get_value("troops", "infantry", 0))
		marksmen = int(save.get_value("troops", "marksmen", 0))
		cavalry = int(save.get_value("troops", "cavalry", 0))

		infantry_training_active = bool(save.get_value("training", "infantry_active", false))
		marksmen_training_active = bool(save.get_value("training", "marksmen_active", false))
		cavalry_training_active = bool(save.get_value("training", "cavalry_active", false))

		infantry_training_ready = bool(save.get_value("training", "infantry_ready", false))
		marksmen_training_ready = bool(save.get_value("training", "marksmen_ready", false))
		cavalry_training_ready = bool(save.get_value("training", "cavalry_ready", false))

		infantry_training_amount = int(save.get_value("training", "infantry_amount", 0))
		marksmen_training_amount = int(save.get_value("training", "marksmen_amount", 0))
		cavalry_training_amount = int(save.get_value("training", "cavalry_amount", 0))

		infantry_finish_time = int(save.get_value("training", "infantry_finish_time", 0))
		marksmen_finish_time = int(save.get_value("training", "marksmen_finish_time", 0))
		cavalry_finish_time = int(save.get_value("training", "cavalry_finish_time", 0))
