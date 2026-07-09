extends Node

signal troops_trained(amount: int)
signal building_upgraded(building_id: String, level: int)
signal research_completed(amount: int)
signal wildling_defeated(amount: int)

func emit_troops_trained(amount: int) -> void:
	troops_trained.emit(amount)

func emit_building_upgraded(building_id: String, level: int) -> void:
	building_upgraded.emit(building_id, level)

func emit_research_completed(amount: int = 1) -> void:
	research_completed.emit(amount)

func emit_wildling_defeated(amount: int = 1) -> void:
	wildling_defeated.emit(amount)
