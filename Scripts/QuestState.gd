extends Node

signal quest_updated
signal quest_claimed(quest_id: String, rewards: Array)

const QUESTS_PATH: String = "res://data/quests.json"
const SAVE_PATH: String = "user://quests.cfg"

var quests: Array[Dictionary] = []
var claimed: Dictionary = {}


func _ready() -> void:
	load_quest_database()
	load_quests()
	
	if has_node("/root/GameEvents"):
		GameEvents.troops_trained.connect(on_troops_trained)
		GameEvents.building_upgraded.connect(on_building_upgraded)
		GameEvents.research_completed.connect(on_research_completed)
		GameEvents.wildling_defeated.connect(on_wildling_defeated)


func get_save_path() -> String:
	if has_node("/root/AccountSavePaths"):
		return AccountSavePaths.path_for("quests.cfg")
	return SAVE_PATH


func load_quest_database() -> void:
	quests.clear()

	if not FileAccess.file_exists(QUESTS_PATH):
		push_error("QuestState: Missing quests.json at " + QUESTS_PATH)
		return

	var file: FileAccess = FileAccess.open(QUESTS_PATH, FileAccess.READ)
	if file == null:
		push_error("QuestState: Could not open quests.json")
		return

	var text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)

	if typeof(parsed) != TYPE_ARRAY:
		push_error("QuestState: quests.json must be an Array.")
		return

	for item: Variant in parsed:
		if typeof(item) == TYPE_DICTIONARY:
			var quest: Dictionary = item
			var quest_id: String = str(quest.get("id", ""))

			if quest_id == "":
				continue

			if not quest.has("is_claimed"):
				quest["is_claimed"] = false

			if not quest.has("is_completed"):
				quest["is_completed"] = false

			quests.append(quest)

	print("QuestState Loaded: ", quests.size(), " quests")


func get_quests_for_tab(tab_name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for quest: Dictionary in quests:
		var category: String = str(quest.get("category", quest.get("tab", "")))

		if category == tab_name:
			result.append(quest)

	return result


func get_progress(quest: Dictionary) -> int:
	var objectives: Array = quest.get("objectives", [])

	if objectives.is_empty():
		return 0

	var first_objective: Dictionary = objectives[0]
	return int(first_objective.get("current", 0))


func get_target(quest: Dictionary) -> int:
	var objectives: Array = quest.get("objectives", [])

	if objectives.is_empty():
		return 1

	var first_objective: Dictionary = objectives[0]
	return int(first_objective.get("target", 1))


func is_complete(quest: Dictionary) -> bool:
	return bool(quest.get("is_completed", false))


func is_claimed(quest: Dictionary) -> bool:
	var quest_id: String = str(quest.get("id", ""))
	return bool(claimed.get(quest_id, quest.get("is_claimed", false)))


func can_claim(quest: Dictionary) -> bool:
	return is_complete(quest) and not is_claimed(quest)


func has_claimable(tab_name: String = "") -> bool:
	for quest: Dictionary in quests:
		var category: String = str(quest.get("category", quest.get("tab", "")))

		if tab_name != "" and category != tab_name:
			continue

		if can_claim(quest):
			return true

	return false


func claim_quest(quest_id: String) -> bool:
	var quest: Dictionary = get_quest_by_id(quest_id)

	if quest.is_empty():
		return false

	_update_completion(quest)

	if not can_claim(quest):
		return false

	var rewards: Array = quest.get("rewards", [])
	_apply_rewards(rewards)

	quest["is_claimed"] = true
	claimed[quest_id] = true

	save_quests()
	quest_claimed.emit(quest_id, rewards)
	quest_updated.emit()

	return true


func get_quest_by_id(quest_id: String) -> Dictionary:
	for quest: Dictionary in quests:
		if str(quest.get("id", "")) == quest_id:
			return quest

	return {}


func on_troops_trained(amount: int) -> void:
	_add_objective_progress("training", amount)

func on_quest_screen_opened() -> void:
	_add_objective_progress("quest_screen_opened", 1)

func on_research_completed(_research_id: String = "") -> void:
	## GameEvents.research_completed now carries research_id; quests still +1.
	_add_objective_progress("research", 1)


func on_wildling_defeated(_wildling_id: String = "") -> void:
	## GameEvents.wildling_defeated now carries wildling_id; quests still +1.
	_add_objective_progress("wildling", 1)


func on_building_upgraded(building_id: String, level: int) -> void:
	## GameEvents.building_upgraded(building_id, level) — first arg is the upgraded building.
	var upgraded_id: String = str(building_id).strip_edges().to_lower()
	for quest: Dictionary in quests:
		for objective: Dictionary in quest.get("objectives", []):
			if str(objective.get("type", "")) != "building":
				continue
			var required_building: String = str(objective.get("building_id", "")).strip_edges().to_lower()
			# Objectives with building_id only advance for that building; others keep legacy behavior.
			if not required_building.is_empty() and required_building != upgraded_id:
				continue
			var target: int = int(objective.get("target", 1))
			objective["current"] = min(max(int(objective.get("current", 0)), level), target)

		_update_completion(quest)

	save_quests()
	quest_updated.emit()


func _add_objective_progress(objective_type: String, amount: int) -> void:
	for quest: Dictionary in quests:
		for objective: Dictionary in quest.get("objectives", []):
			if str(objective.get("type", "")) == objective_type:
				var current: int = int(objective.get("current", 0))
				var target: int = int(objective.get("target", 1))
				objective["current"] = min(current + amount, target)

		_update_completion(quest)

	save_quests()
	quest_updated.emit()


func _update_completion(quest: Dictionary) -> void:
	var complete: bool = true

	for objective: Dictionary in quest.get("objectives", []):
		var current: int = int(objective.get("current", 0))
		var target: int = int(objective.get("target", 1))

		if current < target:
			complete = false
			break

	quest["is_completed"] = complete


func save_quests() -> void:
	var cfg: ConfigFile = ConfigFile.new()

	for quest: Dictionary in quests:
		var quest_id: String = str(quest.get("id", ""))

		if quest_id == "":
			continue

		cfg.set_value(quest_id, "is_completed", bool(quest.get("is_completed", false)))
		cfg.set_value(quest_id, "is_claimed", bool(quest.get("is_claimed", false)))

		var objectives: Array = quest.get("objectives", [])

		for i: int in range(objectives.size()):
			var objective: Dictionary = objectives[i]
			cfg.set_value(quest_id, "objective_%d_current" % i, int(objective.get("current", 0)))

	cfg.save(get_save_path())


func load_quests() -> void:
	var cfg: ConfigFile = ConfigFile.new()

	if cfg.load(get_save_path()) != OK:
		return

	for quest: Dictionary in quests:
		var quest_id: String = str(quest.get("id", ""))

		if quest_id == "":
			continue

		quest["is_completed"] = bool(cfg.get_value(quest_id, "is_completed", quest.get("is_completed", false)))
		quest["is_claimed"] = bool(cfg.get_value(quest_id, "is_claimed", quest.get("is_claimed", false)))
		claimed[quest_id] = bool(quest["is_claimed"])

		var objectives: Array = quest.get("objectives", [])

		for i: int in range(objectives.size()):
			var objective: Dictionary = objectives[i]
			objective["current"] = int(cfg.get_value(quest_id, "objective_%d_current" % i, objective.get("current", 0)))


func _apply_rewards(rewards: Array) -> void:
	for reward: Dictionary in rewards:
		var reward_name: String = str(reward.get("name", reward.get("id", ""))).to_lower()
		var amount: int = int(reward.get("amount", 0))

		match reward_name:
			"food":
				GameState.add_food(amount)
			"wood":
				GameState.add_wood(amount)
			"stone":
				GameState.add_stone(amount)
			"iron":
				GameState.add_iron(amount)
			"diamonds", "diamond":
				GameState.diamonds += amount
			_:
				print("Quest reward not connected yet: ", reward_name, " x", amount)

	if GameState.has_method("save_resources"):
		GameState.save_resources()

func refresh_auto_progress() -> void:
	quest_updated.emit()
