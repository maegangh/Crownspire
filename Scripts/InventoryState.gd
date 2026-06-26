extends Node

var items = {}

func add_item(item_name: String, amount := 1):
	if !items.has(item_name):
		items[item_name] = 0

	items[item_name] += amount

func get_item_count(item_name: String) -> int:
	return items.get(item_name, 0)

func remove_item(item_name: String, amount := 1) -> bool:
	if get_item_count(item_name) < amount:
		return false

	items[item_name] -= amount

	if items[item_name] <= 0:
		items.erase(item_name)

	return true
