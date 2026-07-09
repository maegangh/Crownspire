extends Node

var items: Dictionary = {}


func add_item(item_id: String, amount: int = 1) -> void:
	if not items.has(item_id):
		items[item_id] = 0

	items[item_id] += max(0, amount)
	save_bag()


func get_item_count(item_id: String) -> int:
	return int(items.get(item_id, 0))


func remove_item(item_id: String, amount: int = 1) -> bool:
	var safe_amount: int = max(0, amount)

	if get_item_count(item_id) < safe_amount:
		return false

	items[item_id] = get_item_count(item_id) - safe_amount

	if items[item_id] <= 0:
		items.erase(item_id)

	save_bag()
	return true


func save_bag() -> void:
	var save := ConfigFile.new()

	for item_id in items.keys():
		save.set_value("items", item_id, items[item_id])

	save.save("user://bag.cfg")


func load_bag() -> void:
	var save := ConfigFile.new()

	if save.load("user://bag.cfg") != OK:
		return

	items.clear()

	for item_id in save.get_section_keys("items"):
		items[item_id] = int(save.get_value("items", item_id, 0))


func _ready() -> void:
	load_bag()
