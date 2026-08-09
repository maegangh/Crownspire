extends Node

signal rewards_claimed(rewards: Array)


func claim_rewards(rewards: Array) -> void:
	for reward in rewards:
		var reward_type: String = str(reward.get("type", ""))
		var id: String = str(reward.get("id", ""))
		var amount: int = int(reward.get("amount", 0))

		match reward_type:
			"resource":
				_claim_resource(id, amount)

			"diamond":
				_claim_resource("diamonds", amount)

			"hero_shard":
				HeroState.add_hero_shards(id, amount)

			"hero_xp":
				HeroState.add_hero_xp(amount)

			"item", "speedup", "boost", "chest":
				BagState.add_item(id, amount)

			_:
				print("Unknown reward:", reward_type, id, amount)

	GameState.save_resources()
	rewards_claimed.emit(rewards)


func _claim_resource(id: String, amount: int) -> void:
	match id:
		"food":
			GameState.add_food(amount)
		"wood":
			GameState.add_wood(amount)
		"stone":
			GameState.add_stone(amount)
		"iron":
			GameState.add_iron(amount)
		"diamonds":
			GameState.diamonds += amount
		_:
			print("Unknown resource:", id)
