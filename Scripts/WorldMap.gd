extends Node2D

@onready var march_label: Label = get_parent().get_node_or_null("MarchLabel")

func _process(_delta: float) -> void:
	if march_label == null:
		return

	if not MarchState.march_active:
		march_label.text = ""
		return

	var time_left: int = int(MarchState.get_time_left())
	march_label.text = "March: %s -> %s (%ds)" % [MarchState.march_type, MarchState.target_name, time_left]

	if time_left <= 0:
		MarchState.finish_march()
