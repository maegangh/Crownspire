extends Node

var hero_tickets: int = 5
var recruited_heroes: Array[Dictionary] = []
var current_hero_index: int = -1

var campaign_chapter: int = 1
var campaign_stage: int = 1
var campaign_progress: int = 0

var hero_shards: Dictionary = {}
var hero_xp: int = 50000


func get_hero_index(hero_id: String) -> int:
	for i in range(recruited_heroes.size()):
		var hero: Dictionary = recruited_heroes[i]
		if str(hero.get("id", "")) == hero_id:
			return i
	return -1


func get_or_create_hero(hero_id: String) -> Dictionary:
	var index: int = get_hero_index(hero_id)

	if index != -1:
		return recruited_heroes[index]

	var hero: Dictionary = {
		"id": hero_id,
		"level": 1,
		"starLevel": 5,
		"starProgress": 0,
	}

	recruited_heroes.append(hero)
	return hero


func save_hero_progress(hero_id: String, hero_data: Dictionary) -> void:
	var index: int = get_hero_index(hero_id)

	if index == -1:
		recruited_heroes.append(hero_data)
	else:
		recruited_heroes[index] = hero_data


func get_level_cap(star_level: int) -> int:
	return clamp(star_level, 5, 12) * 10


func get_star_power_multiplier(star_level: int, star_progress: int) -> float:
	var safe_star_level: int = clamp(star_level, 5, 12)
	var safe_star_progress: int = clamp(star_progress, 0, 5)
	var extra_stars: int = safe_star_level - 5

	return 1.0 + (float(extra_stars) * 0.10) + (float(safe_star_progress) * 0.02)


func get_level_up_cost(level: int) -> int:
	return max(1, level) * 100


func get_star_upgrade_cost(star_level: int) -> int:
	match star_level:
		5:
			return 50
		6:
			return 100
		7:
			return 150
		8:
			return 200
		9:
			return 250
		10:
			return 300
		11:
			return 400
	return 999999


func get_hero_xp() -> int:
	return hero_xp


func add_hero_xp(amount: int) -> void:
	hero_xp += max(0, amount)


func spend_hero_xp(amount: int) -> bool:
	var safe_amount: int = max(0, amount)

	if hero_xp < safe_amount:
		return false

	hero_xp -= safe_amount
	return true


func get_hero_shards(hero_id: String) -> int:
	return int(hero_shards.get(hero_id, 0))


func add_hero_shards(hero_id: String, amount: int) -> void:
	if not hero_shards.has(hero_id):
		hero_shards[hero_id] = 0

	hero_shards[hero_id] = int(hero_shards[hero_id]) + max(0, amount)


func spend_hero_shards(hero_id: String, amount: int) -> bool:
	var safe_amount: int = max(0, amount)

	if get_hero_shards(hero_id) < safe_amount:
		return false

	hero_shards[hero_id] = get_hero_shards(hero_id) - safe_amount
	return true


func level_up_hero(hero_id: String) -> bool:
	var hero: Dictionary = get_or_create_hero(hero_id)

	var current_level: int = int(hero.get("level", 1))
	var star_level: int = int(hero.get("starLevel", 5))
	var max_level: int = get_level_cap(star_level)

	if current_level >= max_level:
		print("Hero is at level cap")
		return false

	var cost: int = get_level_up_cost(current_level)

	if not spend_hero_xp(cost):
		print("Not enough Hero XP")
		return false

	hero["level"] = current_level + 1
	save_hero_progress(hero_id, hero)

	print(hero_id, " leveled to ", hero["level"], " cost ", cost, " XP left ", hero_xp)
	return true


func ascend_hero(hero_id: String) -> bool:
	var hero: Dictionary = get_or_create_hero(hero_id)

	var star_level: int = int(hero.get("starLevel", 5))
	var star_progress: int = int(hero.get("starProgress", 0))

	if star_level >= 12 and star_progress >= 5:
		print("Hero is already max stars")
		return false

	if star_level >= 12:
		print("Hero is already max stars")
		return false

	var cost: int = get_star_upgrade_cost(star_level)

	if not spend_hero_shards(hero_id, cost):
		print("Not enough shards for ", hero_id)
		return false

	star_progress += 1

	if star_progress >= 5:
		star_progress = 0
		star_level += 1

	hero["starLevel"] = star_level
	hero["starProgress"] = star_progress
	save_hero_progress(hero_id, hero)

	print(hero_id, " star progress: ", star_progress, "/5 | stars: ", star_level)
	return true
