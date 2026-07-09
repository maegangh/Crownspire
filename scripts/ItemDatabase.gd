extends Node

var items: Dictionary = {}


func _ready() -> void:
	load_items()


func load_items() -> void:
	items.clear()

	var path := "res://Data/items.json"

	if not FileAccess.file_exists(path):
		push_error("items.json not found: " + path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()

	var parsed = JSON.parse_string(text)

	if typeof(parsed) != TYPE_ARRAY:
		push_error("items.json must be an Array")
		return

	for item in parsed:
		if typeof(item) != TYPE_DICTIONARY:
			continue

		var item_id: String = str(item.get("id", ""))

		if item_id == "":
			continue

		items[item_id] = item

	print("Items loaded:", items.size())


func get_item(item_id: String) -> Dictionary:
	return items.get(item_id, {})


func has_item(item_id: String) -> bool:
	return items.has(item_id)


func get_items_by_category(category: String) -> Array:
	var result: Array = []

	for item_id in items.keys():
		var item: Dictionary = items[item_id]

		if str(item.get("category", "")) == category:
			result.append(item)

	return result


func get_item_name(item_id: String) -> String:
	var item := get_item(item_id)
	return str(item.get("name", item_id))


func get_item_description(item_id: String) -> String:
	var item := get_item(item_id)
	return str(item.get("description", ""))


func get_item_category(item_id: String) -> String:
	var item := get_item(item_id)
	return str(item.get("category", "misc"))


func get_item_icon_path(item_id: String) -> String:
	var item := get_item(item_id)
	return str(item.get("icon", ""))
