extends Node
var infantry_training_time_left: float = 0.0
var marksmen_training_time_left: float = 0.0
var cavalry_training_time_left: float = 0.0
var infantry = 0
var marksmen = 0
var cavalry = 0

var wounded_infantry: int = 0
var wounded_marksmen: int = 0
var wounded_cavalry: int = 0

var hospital_capacity: int = 1000
var sanctuary_capacity: int = 500
var sanctuary_troops: int = 0

var infantry_training_active = false
var marksmen_training_active = false
var cavalry_training_active = false

var infantry_training_amount = 0
var marksmen_training_amount = 0
var cavalry_training_amount = 0

var infantry_finish_time = 0
var marksmen_finish_time = 0
var cavalry_finish_time = 0

func _ready():
	load_troops()
	check_finished_training()

func _process(_delta):
	check_finished_training()

func start_training(troop_type: String, amount: int):
	var time_needed = amount * 2
	var finish_time = Time.get_unix_time_from_system() + time_needed

	if troop_type == "Infantry":
		if infantry_training_active:
			return false
		infantry_training_active = true
		infantry_training_amount = amount
		infantry_finish_time = finish_time

	elif troop_type == "Marksmen":
		if marksmen_training_active:
			return false
		marksmen_training_active = true
		marksmen_training_amount = amount
		marksmen_finish_time = finish_time

	elif troop_type == "Cavalry":
		if cavalry_training_active:
			return false
		cavalry_training_active = true
		cavalry_training_amount = amount
		cavalry_finish_time = finish_time

	save_troops()
	return true

func check_finished_training():
	var now = Time.get_unix_time_from_system()

	if infantry_training_active and now >= infantry_finish_time:
		infantry += infantry_training_amount
		infantry_training_active = false
		infantry_training_amount = 0
		infantry_finish_time = 0
		save_troops()

	if marksmen_training_active and now >= marksmen_finish_time:
		marksmen += marksmen_training_amount
		marksmen_training_active = false
		marksmen_training_amount = 0
		marksmen_finish_time = 0
		save_troops()

	if cavalry_training_active and now >= cavalry_finish_time:
		cavalry += cavalry_training_amount
		cavalry_training_active = false
		cavalry_training_amount = 0
		cavalry_finish_time = 0
		save_troops()

func get_troop_count(troop_type: String) -> int:
	if troop_type == "Infantry":
		return infantry
	elif troop_type == "Marksmen":
		return marksmen
	elif troop_type == "Cavalry":
		return cavalry
	return 0

func is_training_active(troop_type: String) -> bool:
	if troop_type == "Infantry":
		return infantry_training_active
	elif troop_type == "Marksmen":
		return marksmen_training_active
	elif troop_type == "Cavalry":
		return cavalry_training_active
	return false

func get_training_time_left(troop_type: String) -> float:
	var now = Time.get_unix_time_from_system()

	if troop_type == "Infantry":
		return max(0, infantry_finish_time - now)
	elif troop_type == "Marksmen":
		return max(0, marksmen_finish_time - now)
	elif troop_type == "Cavalry":
		return max(0, cavalry_finish_time - now)

	return 0

func save_troops():
	var save = ConfigFile.new()

	save.set_value("troops", "infantry", infantry)
	save.set_value("troops", "marksmen", marksmen)
	save.set_value("troops", "cavalry", cavalry)

	save.set_value("training", "infantry_active", infantry_training_active)
	save.set_value("training", "marksmen_active", marksmen_training_active)
	save.set_value("training", "cavalry_active", cavalry_training_active)

	save.set_value("training", "infantry_amount", infantry_training_amount)
	save.set_value("training", "marksmen_amount", marksmen_training_amount)
	save.set_value("training", "cavalry_amount", cavalry_training_amount)

	save.set_value("training", "infantry_finish_time", infantry_finish_time)
	save.set_value("training", "marksmen_finish_time", marksmen_finish_time)
	save.set_value("training", "cavalry_finish_time", cavalry_finish_time)

	save.save("user://troops.cfg")

func load_troops():
	var save = ConfigFile.new()

	if save.load("user://troops.cfg") == OK:
		infantry = save.get_value("troops", "infantry", 0)
		marksmen = save.get_value("troops", "marksmen", 0)
		cavalry = save.get_value("troops", "cavalry", 0)

		infantry_training_active = save.get_value("training", "infantry_active", false)
		marksmen_training_active = save.get_value("training", "marksmen_active", false)
		cavalry_training_active = save.get_value("training", "cavalry_active", false)

		infantry_training_amount = save.get_value("training", "infantry_amount", 0)
		marksmen_training_amount = save.get_value("training", "marksmen_amount", 0)
		cavalry_training_amount = save.get_value("training", "cavalry_amount", 0)

		infantry_finish_time = save.get_value("training", "infantry_finish_time", 0)
		marksmen_finish_time = save.get_value("training", "marksmen_finish_time", 0)
		cavalry_finish_time = save.get_value("training", "cavalry_finish_time", 0)
