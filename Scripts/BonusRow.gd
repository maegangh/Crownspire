extends PanelContainer

func setup(
	stat_title: String,
	icon_path: String,
	current_text: String,
	next_text: String,
	increase_text: String
) -> void:
	var icon: TextureRect = find_child("Icon", true, false)
	var stat_name_label: Label = find_child("StatNameLabel", true, false)
	var current_value_label: Label = find_child("CurrentValue", true, false)
	var new_value_label: Label = find_child("NewValue", true, false)
	var increase_value_label: Label = find_child("IncreaseValue", true, false)

	if stat_name_label:
		stat_name_label.text = stat_title

	if current_value_label:
		current_value_label.text = current_text

	if new_value_label:
		new_value_label.text = next_text

	if increase_value_label:
		if increase_text == "":
			increase_value_label.text = ""
		elif increase_text.begins_with("+"):
			increase_value_label.text = increase_text
		else:
			increase_value_label.text = "+" + increase_text

	if icon and icon_path != "":
		var tex := load(icon_path)
		if tex:
			icon.texture = tex
