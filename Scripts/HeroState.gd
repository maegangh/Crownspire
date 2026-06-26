extends Node

var hero_tickets = 5
var recruited_heroes = []
var current_hero_index = -1

var max_hero_level = 10

var campaign_chapter = 1
var campaign_stage = 1
var campaign_progress = 0
var hero_shards = {}


func get_hero_shards(hero_id: String) -> int:
	return hero_shards.get(hero_id, 0)


func add_hero_shards(hero_id: String, amount: int):
	if !hero_shards.has(hero_id):
		hero_shards[hero_id] = 0

	hero_shards[hero_id] += amount


func spend_hero_shards(hero_id: String, amount: int) -> bool:
	if get_hero_shards(hero_id) < amount:
		return false

	hero_shards[hero_id] -= amount
	return true
	
