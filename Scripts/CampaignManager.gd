extends Node

enum TroopType {
	INFANTRY,
	MARKSMEN,
	CAVALRY
}

const BASE_POWER_MULTIPLIER := 4
const COUNTER_BONUS := 1.25
const DAMAGE_RATE := 0.10
const MAX_battle_roundS := 100


func generate_enemy_bot_stage(chapter: int, stage: int) -> Dictionary:
	var enemy_level: int = int((chapter * 10) + stage)

	var enemy_troops := {
		TroopType.INFANTRY: 100 + (enemy_level * 15),
		TroopType.MARKSMEN: 80 + (enemy_level * 12),
		TroopType.CAVALRY: 60 + (enemy_level * 10)
	}

	var total_troops = enemy_troops[TroopType.INFANTRY] + enemy_troops[TroopType.MARKSMEN] + enemy_troops[TroopType.CAVALRY]
	var enemy_power = total_troops * BASE_POWER_MULTIPLIER

	return {
		"enemy_level": enemy_level,
		"troops": enemy_troops,
		"enemy_power": enemy_power
	}


func resolve_battle(player_troops: Dictionary, enemy_troops: Dictionary) -> Dictionary:
	var player := player_troops.duplicate(true)
	var enemy := enemy_troops.duplicate(true)

	var starting_player_total := get_total_troops(player)
	var starting_enemy_total := get_total_troops(enemy)

	var battle_round := 0

	while get_total_troops(player) > 0 and get_total_troops(enemy) > 0 and battle_round < MAX_battle_roundS:
		battle_round += 1

		var player_damage := calculate_army_damage(player, enemy)
		var enemy_damage := calculate_army_damage(enemy, player)

		apply_damage(enemy, player_damage)
		apply_damage(player, enemy_damage)

	var player_remaining := get_total_troops(player)
	var enemy_remaining := get_total_troops(enemy)

	var victory := player_remaining > 0 and enemy_remaining <= 0
	var player_losses := starting_player_total - player_remaining
	var enemy_losses := starting_enemy_total - enemy_remaining

	if player_losses > 0:
		apply_hospital_losses(player_losses)

	if victory:
		handle_victory_rewards()
		advance_campaign_after_victory()

	return {
		"victory": victory,
		"battle_rounds": battle_round,
		"player_remaining": player,
		"enemy_remaining": enemy,
		"player_losses": player_losses,
		"enemy_losses": enemy_losses
	}


func calculate_army_damage(attacker: Dictionary, defender: Dictionary) -> float:
	var damage: float = 0.0

	var infantry: int = int(attacker.get(TroopType.INFANTRY, 0))
	var marksmen: int = int(attacker.get(TroopType.MARKSMEN, 0))
	var cavalry: int = int(attacker.get(TroopType.CAVALRY, 0))

	damage += infantry
	damage += marksmen
	damage += cavalry

	if int(defender.get(TroopType.MARKSMEN, 0)) > 0:
		damage += infantry * 0.25

	if int(defender.get(TroopType.CAVALRY, 0)) > 0:
		damage += marksmen * 0.25

	if int(defender.get(TroopType.INFANTRY, 0)) > 0:
		damage += cavalry * 0.25

	return damage * DAMAGE_RATE

func apply_damage(troops: Dictionary, damage: float) -> void:
	var remaining_damage := int(damage)

	for troop_type in [TroopType.INFANTRY, TroopType.MARKSMEN, TroopType.CAVALRY]:
		if remaining_damage <= 0:
			return

		var current_amount: int = troops.get(troop_type, 0)
		var losses = min(current_amount, remaining_damage)

		troops[troop_type] = current_amount - losses
		remaining_damage -= losses


func apply_hospital_losses(total_losses: int) -> void:
	var hospital_amount := int(total_losses * 0.60)
	var sanctuary_amount := int(total_losses * 0.20)
	var dead_amount := total_losses - hospital_amount - sanctuary_amount

	TroopState.wounded_infantry += hospital_amount
	TroopState.sanctuary_troops += sanctuary_amount

	print("Hospital wounded: ", hospital_amount)
	print("Sanctuary troops: ", sanctuary_amount)
	print("Permanent deaths: ", dead_amount)


func handle_victory_rewards() -> void:
	var enemy_level: int = int((CampaignState.campaign_chapter * 10) + CampaignState.campaign_stage)
	var food_reward := enemy_level * 150
	var wood_reward := enemy_level * 150
	var stone_reward := enemy_level * 80
	var iron_reward := enemy_level * 40

	GameState.food += food_reward
	GameState.wood += wood_reward
	GameState.stone += stone_reward
	GameState.iron += iron_reward

	print("Victory rewards:")
	print("Food: ", food_reward)
	print("Wood: ", wood_reward)
	print("Stone: ", stone_reward)
	print("Iron: ", iron_reward)


func advance_campaign_after_victory() -> void:
	CampaignState.campaign_stage += 1

	if CampaignState.campaign_stage > 10:
		CampaignState.campaign_stage = 1
		CampaignState.campaign_chapter += 1

	QuestState.quest2_progress += 1

	if QuestState.quest2_progress >= QuestState.quest2_target:
		QuestState.quest2_progress = QuestState.quest2_target
		QuestState.quest2_completed = true

	var next_enemy := generate_enemy_bot_stage(
		CampaignState.campaign_chapter,
		CampaignState.campaign_stage
	)

	CampaignState.enemy_level = next_enemy["enemy_level"]
	CampaignState.enemy_infantry = next_enemy["troops"][TroopType.INFANTRY]
	CampaignState.enemy_marksmen = next_enemy["troops"][TroopType.MARKSMEN]
	CampaignState.enemy_cavalry = next_enemy["troops"][TroopType.CAVALRY]
	CampaignState.enemy_power = next_enemy["enemy_power"]


func get_total_troops(troops: Dictionary) -> int:
	return int(
		troops.get(TroopType.INFANTRY, 0)
		+ troops.get(TroopType.MARKSMEN, 0)
		+ troops.get(TroopType.CAVALRY, 0)
	)


func battle_current_campaign_stage() -> Dictionary:
	var enemy_data := generate_enemy_bot_stage(
		CampaignState.campaign_chapter,
		CampaignState.campaign_stage
	)

	var player_troops := {
		TroopType.INFANTRY: TroopState.infantry,
		TroopType.MARKSMEN: TroopState.marksmen,
		TroopType.CAVALRY: TroopState.cavalry
	}

	var result := resolve_battle(player_troops, enemy_data["troops"])

	TroopState.infantry = result["player_remaining"][TroopType.INFANTRY]
	TroopState.marksmen = result["player_remaining"][TroopType.MARKSMEN]
	TroopState.cavalry = result["player_remaining"][TroopType.CAVALRY]

	return result
