class_name CampaignManager
extends Node

## CampaignManager
## Standalone battle progression and bot-scaling engine for Eternal Realms.
## Integrates with autoloads: GameState, TroopState, CampaignState, QuestState.
##
## Usage (from UI or another system):
##   var manager := CampaignManager.new()
##   var result := manager.run_campaign_battle()
## Or register as an autoload and call run_campaign_battle() directly.

# ---------------------------------------------------------------------------
# 1. CORE DATA ENUM
# ---------------------------------------------------------------------------

enum TroopType {
	INFANTRY,
	MARKSMEN,
	CAVALRY,
}

# String keys used in troop dictionaries (matches TroopState / CampaignState naming).
const TROOP_KEYS: Array[String] = ["infantry", "marksmen", "cavalry"]

# 4X combat tuning constants.
const COUNTER_DAMAGE_BONUS: float = 0.25          ## +25% damage on favorable matchups.
const DAMAGE_PER_TROOP: float = 1.0               ## Base casualties dealt per troop per round.
const MAX_BATTLE_TURNS: int = 10_000              ## Safety cap to prevent infinite loops.

# Casualty routing (player losses only).
const HOSPITAL_RATE: float = 0.60
const SANCTUARY_RATE: float = 0.20
const DEATH_RATE: float = 0.20

# Scaled loot multipliers (applied on victory).
const LOOT_FOOD_PER_LEVEL: int = 150
const LOOT_WOOD_PER_LEVEL: int = 150
const LOOT_STONE_PER_LEVEL: int = 80
const LOOT_IRON_PER_LEVEL: int = 40

# Bot army scaling baselines (added to level-scaled growth).
const BOT_INFANTRY_BASE: int = 100
const BOT_MARKSMEN_BASE: int = 80
const BOT_CAVALRY_BASE: int = 60
const BOT_INFANTRY_SCALE: int = 15
const BOT_MARKSMEN_SCALE: int = 12
const BOT_CAVALRY_SCALE: int = 10

# Counter lookup: attacker TroopType -> troop type it deals bonus damage against.
const _COUNTER_TARGETS: Dictionary = {
	TroopType.INFANTRY: TroopType.MARKSMEN,
	TroopType.MARKSMEN: TroopType.CAVALRY,
	TroopType.CAVALRY: TroopType.INFANTRY,
}


# ---------------------------------------------------------------------------
# 2. BOT ARMY SCALING ENGINE
# ---------------------------------------------------------------------------

## Generates a scaled enemy bot configuration for the given campaign position.
## Returns a Dictionary with enemy_level, troop counts, and computed enemy_power.
func generate_enemy_bot_stage(chapter: int, stage: int) -> Dictionary:
	var enemy_level: int = (chapter * 10) + stage

	var infantry: int = BOT_INFANTRY_BASE + (enemy_level * BOT_INFANTRY_SCALE)
	var marksmen: int = BOT_MARKSMEN_BASE + (enemy_level * BOT_MARKSMEN_SCALE)
	var cavalry: int = BOT_CAVALRY_BASE + (enemy_level * BOT_CAVALRY_SCALE)

	# 4X baseline power uses counter-aware bonus vs the player's current army.
	var enemy_power: int = calculate_combat_power(
		infantry,
		marksmen,
		cavalry,
		TroopState.infantry,
		TroopState.marksmen,
		TroopState.cavalry
	)

	return {
		"enemy_level": enemy_level,
		"infantry": infantry,
		"marksmen": marksmen,
		"cavalry": cavalry,
		"enemy_power": enemy_power,
	}


## Standard 4X combat power formula (matches existing UI battle power calculation).
## Base troop sum plus counter matchup bonus: min(attacker, counter_target) * 0.5 per lane.
func calculate_combat_power(
	att_inf: int,
	att_marks: int,
	att_cav: int,
	def_inf: int,
	def_marks: int,
	def_cav: int
) -> int:
	var base: float = float(att_inf + att_marks + att_cav)
	var bonus: float = 0.0

	bonus += min(att_inf, def_marks) * 0.5
	bonus += min(att_marks, def_cav) * 0.5
	bonus += min(att_cav, def_inf) * 0.5

	return int(base + bonus)


## Syncs generated bot data into CampaignState for UI and save-game compatibility.
func apply_enemy_bot_to_campaign_state(chapter: int, stage: int) -> Dictionary:
	var bot_data: Dictionary = generate_enemy_bot_stage(chapter, stage)

	CampaignState.enemy_level = bot_data["enemy_level"]
	CampaignState.enemy_infantry = bot_data["infantry"]
	CampaignState.enemy_marksmen = bot_data["marksmen"]
	CampaignState.enemy_cavalry = bot_data["cavalry"]
	CampaignState.enemy_power = bot_data["enemy_power"]

	return bot_data


# ---------------------------------------------------------------------------
# 3. 4X COMBAT COUNTER LOGIC ENGINE
# ---------------------------------------------------------------------------

## Simulates a turn-based battle until one side reaches zero troops.
## Troop dictionaries expect keys: "infantry", "marksmen", "cavalry".
##
## Counter rules (rock-paper-scissors):
##   Infantry  -> +25% damage vs Marksmen
##   Marksmen  -> +25% damage vs Cavalry
##   Cavalry   -> +25% damage vs Infantry
func resolve_battle(player_troops: Dictionary, enemy_troops: Dictionary) -> Dictionary:
	var player: Dictionary = _normalize_troop_dict(player_troops)
	var enemy: Dictionary = _normalize_troop_dict(enemy_troops)
	var initial_player: Dictionary = player.duplicate()

	var turns: int = 0

	while _total_troops(player) > 0 and _total_troops(enemy) > 0 and turns < MAX_BATTLE_TURNS:
		# Simultaneous exchange: both sides strike using troop counts at round start.
		var player_at_round_start: Dictionary = player.duplicate()
		var enemy_at_round_start: Dictionary = enemy.duplicate()

		player = _apply_round_damage(enemy_at_round_start, player)
		enemy = _apply_round_damage(player_at_round_start, enemy)
		turns += 1

	var victory: bool = _total_troops(enemy) <= 0 and _total_troops(player) > 0
	var defeat: bool = _total_troops(player) <= 0 and _total_troops(enemy) > 0
	var draw: bool = not victory and not defeat

	return {
		"victory": victory,
		"defeat": defeat,
		"draw": draw,
		"turns": turns,
		"player_remaining": player,
		"enemy_remaining": enemy,
		"player_losses": {
			"infantry": initial_player["infantry"] - player["infantry"],
			"marksmen": initial_player["marksmen"] - player["marksmen"],
			"cavalry": initial_player["cavalry"] - player["cavalry"],
		},
	}


## One combat round: `attacker` strikes `defender`, returning updated defender counts.
func _apply_round_damage(attacker: Dictionary, defender: Dictionary) -> Dictionary:
	var updated: Dictionary = defender.duplicate()

	for troop_type: TroopType in [TroopType.INFANTRY, TroopType.MARKSMEN, TroopType.CAVALRY]:
		var type_key: String = _troop_type_to_key(troop_type)
		var attacking_count: int = int(attacker.get(type_key, 0))
		if attacking_count <= 0:
			continue

		updated = _apply_type_damage(attacking_count, troop_type, updated)

	return updated


## Routes all damage from one attacker stack to defenders, prioritizing counter targets.
func _apply_type_damage(attacker_count: int, attacker_type: TroopType, defender: Dictionary) -> Dictionary:
	var result: Dictionary = defender.duplicate()
	var soldiers_left: int = attacker_count

	var counter_key: String = _troop_type_to_key(_COUNTER_TARGETS[attacker_type])

	# Phase 1: counter matchup at +25% effectiveness (1.25 damage per soldier).
	if soldiers_left > 0 and int(result.get(counter_key, 0)) > 0:
		var counter_pool: int = int(result[counter_key])
		var counter_kills: int = mini(
			counter_pool,
			int(floor(float(soldiers_left) * (1.0 + COUNTER_DAMAGE_BONUS)))
		)
		result[counter_key] = counter_pool - counter_kills
		var soldiers_spent: int = int(ceil(float(counter_kills) / (1.0 + COUNTER_DAMAGE_BONUS)))
		soldiers_left -= soldiers_spent

	# Phase 2: remaining soldiers attack other troop types at base rate (1 damage per soldier).
	for spill_type: TroopType in _get_spill_order(attacker_type):
		if soldiers_left <= 0:
			break

		var spill_key: String = _troop_type_to_key(spill_type)
		var spill_pool: int = int(result.get(spill_key, 0))
		if spill_pool <= 0:
			continue

		var spill_kills: int = mini(spill_pool, soldiers_left)
		result[spill_key] = spill_pool - spill_kills
		soldiers_left -= spill_kills

	return result


# ---------------------------------------------------------------------------
# 4. CASUALTY & HOSPITAL SYSTEM
# ---------------------------------------------------------------------------

## Applies 4X hospital routing to player battle losses:
##   60% -> Hospital (wounded troops, per-type on GameState + TroopState)
##   20% -> Sanctuary
##   20% -> Permanent death
func apply_player_casualties(player_losses: Dictionary) -> Dictionary:
	var summary: Dictionary = {
		"hospital": {"infantry": 0, "marksmen": 0, "cavalry": 0},
		"sanctuary": 0,
		"permanent_death": 0,
	}

	for troop_type: TroopType in [TroopType.INFANTRY, TroopType.MARKSMEN, TroopType.CAVALRY]:
		var type_key: String = _troop_type_to_key(troop_type)
		var lost: int = int(player_losses.get(type_key, 0))
		if lost <= 0:
			continue

		var to_hospital: int = int(floor(float(lost) * HOSPITAL_RATE))
		var to_sanctuary: int = int(floor(float(lost) * SANCTUARY_RATE))
		var to_death: int = lost - to_hospital - to_sanctuary

		_apply_hospital_casualties(troop_type, to_hospital)
		summary["hospital"][type_key] = to_hospital

		var sanctuary_applied: int = _apply_sanctuary_casualties(to_sanctuary)
		summary["sanctuary"] += sanctuary_applied
		summary["permanent_death"] += to_death + (to_sanctuary - sanctuary_applied)

	# Hospital overflow beyond capacity is treated as permanent death.
	var hospital_overflow: int = _apply_hospital_capacity_overflow()
	summary["permanent_death"] += hospital_overflow

	return summary


## Adds wounded troops to hospital pools on both GameState and TroopState autoloads.
func _apply_hospital_casualties(troop_type: TroopType, amount: int) -> void:
	if amount <= 0:
		return

	match troop_type:
		TroopType.INFANTRY:
			GameState.wounded_infantry += amount
			TroopState.wounded_infantry += amount
		TroopType.MARKSMEN:
			GameState.wounded_marksmen += amount
			TroopState.wounded_marksmen += amount
		TroopType.CAVALRY:
			GameState.wounded_cavalry += amount
			TroopState.wounded_cavalry += amount


## Adds troops to sanctuary, respecting sanctuary capacity on GameState + TroopState.
## Returns the number actually stored (overflow becomes permanent death via caller).
func _apply_sanctuary_casualties(amount: int) -> int:
	if amount <= 0:
		return 0

	var sanctuary_used: int = TroopState.sanctuary_troops
	var sanctuary_space: int = TroopState.sanctuary_capacity - sanctuary_used
	var applied: int = mini(amount, maxi(sanctuary_space, 0))

	TroopState.sanctuary_troops += applied
	GameState.sanctuary_troops = TroopState.sanctuary_troops

	return applied


## If hospital exceeds capacity, excess wounded become permanent deaths (removed from pools).
func _apply_hospital_capacity_overflow() -> int:
	var hospital_used: int = (
		TroopState.wounded_infantry
		+ TroopState.wounded_marksmen
		+ TroopState.wounded_cavalry
	)
	var overflow: int = maxi(0, hospital_used - TroopState.hospital_capacity)
	if overflow <= 0:
		return 0

	# Remove overflow starting from cavalry, then marksmen, then infantry (deterministic).
	overflow = _reduce_wounded_stack(TroopType.CAVALRY, overflow)
	overflow = _reduce_wounded_stack(TroopType.MARKSMEN, overflow)
	overflow = _reduce_wounded_stack(TroopType.INFANTRY, overflow)

	return overflow


func _reduce_wounded_stack(troop_type: TroopType, amount: int) -> int:
	if amount <= 0:
		return 0

	match troop_type:
		TroopType.INFANTRY:
			var removed: int = mini(amount, TroopState.wounded_infantry)
			TroopState.wounded_infantry -= removed
			GameState.wounded_infantry = TroopState.wounded_infantry
			return amount - removed
		TroopType.MARKSMEN:
			var removed: int = mini(amount, TroopState.wounded_marksmen)
			TroopState.wounded_marksmen -= removed
			GameState.wounded_marksmen = TroopState.wounded_marksmen
			return amount - removed
		TroopType.CAVALRY:
			var removed: int = mini(amount, TroopState.wounded_cavalry)
			TroopState.wounded_cavalry -= removed
			GameState.wounded_cavalry = TroopState.wounded_cavalry
			return amount - removed

	return amount


# ---------------------------------------------------------------------------
# 5. SCALE LOOT PAYOUTS
# ---------------------------------------------------------------------------

## Grants scaled resource rewards to GameState after a campaign victory.
func grant_victory_loot(enemy_level: int) -> Dictionary:
	var food_reward: int = enemy_level * LOOT_FOOD_PER_LEVEL
	var wood_reward: int = enemy_level * LOOT_WOOD_PER_LEVEL
	var stone_reward: int = enemy_level * LOOT_STONE_PER_LEVEL
	var iron_reward: int = enemy_level * LOOT_IRON_PER_LEVEL

	GameState.food += food_reward
	GameState.wood += wood_reward
	GameState.stone += stone_reward
	GameState.iron += iron_reward

	return {
		"food": food_reward,
		"wood": wood_reward,
		"stone": stone_reward,
		"iron": iron_reward,
	}


# ---------------------------------------------------------------------------
# 6. AUTO-ADVANCE LOOP
# ---------------------------------------------------------------------------

## Advances campaign stage/chapter and updates quest progress after a victory.
func advance_campaign_after_victory() -> void:
	CampaignState.campaign_stage += 1

	if CampaignState.campaign_stage > 10:
		CampaignState.campaign_stage = 1
		CampaignState.campaign_chapter += 1

	# Keep GameState campaign mirrors in sync for save compatibility.
	GameState.campaign_stage = CampaignState.campaign_stage
	GameState.campaign_chapter = CampaignState.campaign_chapter

	_increment_quest2_progress()

	# Regenerate the next enemy bot for the new stage.
	apply_enemy_bot_to_campaign_state(
		CampaignState.campaign_chapter,
		CampaignState.campaign_stage
	)


func _increment_quest2_progress() -> void:
	QuestState.quest2_progress += 1

	if QuestState.quest2_progress >= QuestState.quest2_target:
		QuestState.quest2_progress = QuestState.quest2_target
		QuestState.quest2_completed = true


# ---------------------------------------------------------------------------
# HIGH-LEVEL ORCHESTRATION
# ---------------------------------------------------------------------------

## Full battle pipeline: simulate combat, apply casualties, loot, and auto-advance on win.
## Reads live troop counts from TroopState and enemy data from CampaignState.
func run_campaign_battle() -> Dictionary:
	var player_troops: Dictionary = {
		"infantry": TroopState.infantry,
		"marksmen": TroopState.marksmen,
		"cavalry": TroopState.cavalry,
	}

	var enemy_troops: Dictionary = {
		"infantry": CampaignState.enemy_infantry,
		"marksmen": CampaignState.enemy_marksmen,
		"cavalry": CampaignState.enemy_cavalry,
	}

	var enemy_level: int = CampaignState.enemy_level
	var battle_result: Dictionary = resolve_battle(player_troops, enemy_troops)

	# Write surviving player troops back to TroopState (and GameState mirrors).
	var remaining: Dictionary = battle_result["player_remaining"]
	TroopState.infantry = int(remaining["infantry"])
	TroopState.marksmen = int(remaining["marksmen"])
	TroopState.cavalry = int(remaining["cavalry"])
	GameState.infantry = TroopState.infantry
	GameState.marksmen = TroopState.marksmen
	GameState.cavalry = TroopState.cavalry

	var casualty_summary: Dictionary = apply_player_casualties(battle_result["player_losses"])
	battle_result["casualty_summary"] = casualty_summary

	if battle_result["victory"]:
		battle_result["loot"] = grant_victory_loot(enemy_level)
		advance_campaign_after_victory()
	else:
		battle_result["loot"] = {}

	# Refresh power ratings for UI.
	CampaignState.player_power = calculate_combat_power(
		TroopState.infantry,
		TroopState.marksmen,
		TroopState.cavalry,
		CampaignState.enemy_infantry,
		CampaignState.enemy_marksmen,
		CampaignState.enemy_cavalry
	)
	CampaignState.enemy_power = calculate_combat_power(
		CampaignState.enemy_infantry,
		CampaignState.enemy_marksmen,
		CampaignState.enemy_cavalry,
		TroopState.infantry,
		TroopState.marksmen,
		TroopState.cavalry
	)

	return battle_result


# ---------------------------------------------------------------------------
# INTERNAL HELPERS
# ---------------------------------------------------------------------------

func _normalize_troop_dict(troops: Dictionary) -> Dictionary:
	return {
		"infantry": maxi(0, int(troops.get("infantry", 0))),
		"marksmen": maxi(0, int(troops.get("marksmen", 0))),
		"cavalry": maxi(0, int(troops.get("cavalry", 0))),
	}


func _total_troops(troops: Dictionary) -> int:
	return int(troops.get("infantry", 0)) + int(troops.get("marksmen", 0)) + int(troops.get("cavalry", 0))


func _troop_type_to_key(troop_type: TroopType) -> String:
	match troop_type:
		TroopType.INFANTRY:
			return "infantry"
		TroopType.MARKSMEN:
			return "marksmen"
		TroopType.CAVALRY:
			return "cavalry"
		_:
			return "infantry"


func _get_spill_order(attacker_type: TroopType) -> Array[TroopType]:
	# After the counter target, spill to the remaining types in stable order.
	var order: Array[TroopType] = [TroopType.INFANTRY, TroopType.MARKSMEN, TroopType.CAVALRY]
	var counter_type: TroopType = _COUNTER_TARGETS[attacker_type]
	order.erase(counter_type)
	return order
