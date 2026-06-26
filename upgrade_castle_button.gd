extends Control

var valor = 100
var stored_food = 0
var stored_wood = 0
var stored_stone = 0
var stored_iron = 0
var production_timer = 0.0

const TRAIN_AMOUNT := 10

@onready var castle_label = $CastleLevelLabel
@onready var food_label = $FoodLabel
@onready var wood_label = $WoodLabel
@onready var stone_label = $StoneLabel
@onready var iron_label = $IronLabel
@onready var upgrade_button = $UpgradeCastleButton
@onready var gather_button = $GatherResourcesButton
@onready var farm_label = $FarmLevelLabel
@onready var upgrade_farm_button = $UpgradeFarmButton
@onready var lumber_mill_label = $LumberMillLevelLabel
@onready var upgrade_lumber_mill_button = $UpgradeLumberMillButton
@onready var quarry_label = $QuarryLevelLabel
@onready var upgrade_quarry_button = $UpgradeQuarryButton
@onready var iron_mine_label = $IronMineLevelLabel
@onready var upgrade_iron_mine_button = $UpgradeIronMineButton
@onready var infantry_label = $InfantryLabel
@onready var marksmen_label = $marksmenLabel
@onready var cavalry_label = $CavalryLabel
@onready var previous_hero_button = $PreviousHeroButton
@onready var next_hero_button = $NextHeroButton
@onready var quest1_label = $Quest1Label
@onready var quest1_progress_label = $Quest1ProgressLabel
@onready var quest1_reward_label = $Quest1RewardLabel
@onready var claim_quest1_button = $ClaimQuest1Button
@onready var quest2_label = $Quest2Label
@onready var quest2_progress_label = $Quest2ProgressLabel
@onready var quest2_reward_label = $Quest2RewardLabel
@onready var claim_quest2_button = $ClaimQuest2Button
@onready var train_infantry_button = $TrainInfantryButton
@onready var train_marksmen_button = $TrainmarksmenButton
@onready var train_cavalry_button = $TrainCavalryButton
@onready var hero_tickets_label = $HeroTicketsLabel
@onready var valor_label = $ValorLabel
@onready var hero_name_label = $HeroNameLabel
@onready var hero_level_label = $HeroLevelLabel
@onready var hero_attack_label = $HeroAttackLabel
@onready var hero_defense_label = $HeroDefenseLabel
@onready var recruit_hero_button = $RecruitHeroButton
@onready var level_up_hero_button = $LevelUpHeroButton
@onready var ascend_hero_button = $AscendHeroButton
@onready var stored_food_label = $StoredFoodLabel
@onready var stored_wood_label = $StoredWoodLabel
@onready var stored_stone_label = $StoredStoneLabel
@onready var stored_iron_label = $StoredIronLabel
@onready var collect_resources_button = $CollectResourcesButton
@onready var research_hall_label = $ResearchHallLevelLabel
@onready var upgrade_research_hall_button = $UpgradeResearchHallButton
@onready var economy_research_label = $EconomyResearchLabel
@onready var research_economy_button = $ResearchEconomyButton
@onready var military_research_label = $MilitaryResearchLabel
@onready var research_military_button = $ResearchMilitaryButton
@onready var troop_attack_bonus_label = $TroopAttackBonusLabel
@onready var enemy_infantry_label = $EnemyInfantryLabel
@onready var battle_result_label = $BattleResultLabel
@onready var battle_enemy_button = $BattleEnemyButton
@onready var enemy_level_label = $EnemyLevelLabel
@onready var enemy_marksmen_label = $EnemymarksmenLabel
@onready var enemy_cavalry_label = $EnemyCavalryLabel
@onready var player_power_label = $PlayerPowerLabel
@onready var enemy_power_label = $EnemyPowerLabel
@onready var add_hero_ticket_button = $AddHeroTicketButton
@onready var hero_role_label = $HeroRoleLabel
@onready var hero_bonus_label = $HeroBonusLabel
@onready var hero_ability_label = $HeroAbilityLabel
@onready var hero_xp_label = $HeroXPLabel
@onready var campaign_stage_label = $CampaignStageLabel
@onready var campaign_progress_label = $CampaignProgressLabel
@onready var hospital_capacity_label = $HospitalCapacityLabel
@onready var hospital_troops_label = $HospitalTroopsLabel
@onready var sanctuary_capacity_label = $SanctuaryCapacityLabel
@onready var sanctuary_troops_label = $SanctuaryTroopsLabel
@onready var warehouse_label = $WarehouseLevelLabel
@onready var upgrade_warehouse_button = $UpgradeWarehouseButton
@onready var warehouse_protection_label = $WarehouseProtectionLabel
@onready var hero_shards_label = $HeroShardsLabel
@onready var hero_skills_label = $HeroSkillsLabel
@onready var monster_reward_popup = $MonsterRewardPopup
@onready var monster_reward_text = $MonsterRewardPopup/MonsterRewardText
@onready var close_monster_reward_button = $MonsterRewardPopup/CloseMonsterRewardButton
@onready var bag_button = $BagButton
@onready var bag_panel = $BagPanel
@onready var bag_items_label = $BagPanel/BagItemsLabel
@onready var close_bag_button = $BagPanel/CloseBagButton
@onready var world_map_button = $WorldMapButton
@onready var world_map_panel = $WorldMapPanel
@onready var world_map_info_label = $WorldMapPanel/WorldMapInfoLabel
@onready var close_world_map_button = get_node_or_null("WorldMapPanel/CloseWorldMapButton")
@onready var monster_button = $WorldMapPanel/MonsterButton
@onready var monster_list_container = $WorldMapPanel/MonsterListContainer



func _ready():
	if castle_label == null:
		print("Skipping old UI script. This scene does not have old labels.")
		return

	load_game()
	connect_buttons()
	update_labels()
	save_game()
	
	
func connect_buttons():
	safe_connect(recruit_hero_button, _on_recruit_hero_button_pressed)
	safe_connect(level_up_hero_button, _on_level_up_hero_button_pressed)
	safe_connect(ascend_hero_button, _on_ascend_hero_button_pressed)
	safe_connect(previous_hero_button, _on_previous_hero_button_pressed)
	safe_connect(next_hero_button, _on_next_hero_button_pressed)
	safe_connect(upgrade_button, _on_upgrade_castle_button_pressed)
	safe_connect(gather_button, _on_gather_resources_button_pressed)
	safe_connect(upgrade_farm_button, _on_upgrade_farm_button_pressed)
	safe_connect(upgrade_lumber_mill_button, _on_upgrade_lumber_mill_button_pressed)
	safe_connect(upgrade_quarry_button, _on_upgrade_quarry_button_pressed)
	safe_connect(upgrade_iron_mine_button, _on_upgrade_iron_mine_button_pressed)
	safe_connect(train_infantry_button, _on_train_infantry_button_pressed)
	safe_connect(train_marksmen_button, _on_train_marksmen_button_pressed)
	safe_connect(train_cavalry_button, _on_train_cavalry_button_pressed)
	safe_connect(collect_resources_button, _on_collect_resources_button_pressed)
	safe_connect(upgrade_research_hall_button, _on_upgrade_research_hall_button_pressed)
	safe_connect(research_economy_button, _on_research_economy_button_pressed)
	safe_connect(research_military_button, _on_research_military_button_pressed)
	safe_connect(battle_enemy_button, _on_battle_enemy_button_pressed)
	safe_connect(add_hero_ticket_button, _on_add_hero_ticket_button_pressed)
	safe_connect(claim_quest1_button, _on_claim_quest1_button_pressed)
	safe_connect(claim_quest2_button, _on_claim_quest2_button_pressed)
	safe_connect(upgrade_warehouse_button, _on_upgrade_warehouse_button_pressed)
	safe_connect(close_monster_reward_button, _on_close_monster_reward_button_pressed)
	safe_connect(bag_button, _on_bag_button_pressed)
	safe_connect(close_bag_button, _on_close_bag_button_pressed)
	safe_connect(world_map_button, _on_world_map_button_pressed)
	safe_connect(monster_button, _on_monster_button_pressed)
	safe_connect(close_world_map_button, _on_close_world_map_button_pressed)

func safe_connect(button, function_to_call):
	if button == null:
		return

	if not button.pressed.is_connected(function_to_call):
		button.pressed.connect(function_to_call)
	
	if close_world_map_button:
		close_world_map_button.pressed.connect(_on_close_world_map_button_pressed)
	else:
		print("CloseWorldMapButton not found")
		
func _on_monster_button_pressed():
	hunt_monster("monster_common_l1_s1_frost_lupine")

func _on_world_map_button_pressed():
	world_map_info_label.text = "World Map Loaded\n\nSpawns: " + str(DataManager.world_map_spawns.size())

	populate_world_map_monsters()

	world_map_panel.visible = true
	
func _on_close_world_map_button_pressed():
	world_map_panel.visible = false

func _on_bag_button_pressed():
	print("Bag opened. Items: ", InventoryState.items)
	
	var text = ""

	for item_name in InventoryState.items.keys():
		text += item_name + " x" + str(InventoryState.items[item_name]) + "\n"

	if text == "":
		text = "Bag Empty"

	bag_items_label.text = text
	bag_panel.visible = true
	
	
func populate_world_map_monsters():
	for child in monster_list_container.get_children():
		child.queue_free()

	for spawn in DataManager.monster_spawns:
		var monster_id = spawn.get("monsterId", "")
		var monster_name = spawn.get("name", "Unknown Monster")
		var monster_level = int(spawn.get("level", 1))

		var button = Button.new()
		button.text = "🐺 " + monster_name + " Lvl " + str(monster_level)

		button.pressed.connect(
			func():
				hunt_monster(monster_id)
		)

		monster_list_container.add_child(button)

	for spawn in DataManager.monster_spawns:
		var monster_id = spawn.get("monsterId", "")
		var monster_name = spawn.get("name", "Unknown Monster")
		var monster_level = int(spawn.get("level", 1))

		var button = Button.new()
		button.text = "🐺 " + monster_name + " Lvl " + str(monster_level)

		button.pressed.connect(
			func():
				hunt_monster(monster_id)
		)

		monster_list_container.add_child(button)

	for spawn in DataManager.monster_spawns:
		var monster_id = spawn.get("monsterId", "")
		var monster_name = spawn.get("name", "Unknown Monster")
		var monster_level = int(spawn.get("level", 1))

		var button = Button.new()
		button.text = "🐺 " + monster_name + " Lvl " + str(monster_level)

		button.pressed.connect(
			func():
				hunt_monster(monster_id)
		)

		monster_list_container.add_child(button)

func _on_close_bag_button_pressed():
	bag_panel.visible = false

func _on_close_monster_reward_button_pressed():
	monster_reward_popup.visible = false


func update_labels():
	warehouse_label.text = "Warehouse Level " + str(GameState.warehouse_level)
	warehouse_protection_label.text = "Protected Resources: " + str(get_warehouse_protection_limit())

	CampaignState.player_power = calculate_power(
		TroopState.infantry,
		TroopState.marksmen,
		TroopState.cavalry,
		CampaignState.enemy_infantry,
		CampaignState.enemy_marksmen,
		CampaignState.enemy_cavalry
	)

	ResearchState.troop_attack_bonus = ResearchState.military_research_level * 5
	CampaignState.player_power += int(CampaignState.player_power * (ResearchState.troop_attack_bonus / 100.0))

	CampaignState.enemy_power = calculate_power(
		CampaignState.enemy_infantry,
		CampaignState.enemy_marksmen,
		CampaignState.enemy_cavalry,
		TroopState.infantry,
		TroopState.marksmen,
		TroopState.cavalry
	)

	TroopState.hospital_capacity = GameState.castle_level * 1000
	TroopState.sanctuary_capacity = GameState.castle_level * 500

	campaign_stage_label.text = "Campaign Stage: " + str(CampaignState.campaign_chapter) + "-" + str(CampaignState.campaign_stage)
	campaign_progress_label.text = "Campaign Progress: " + str(CampaignState.campaign_progress) + "/10"

	quest1_label.text = "Quest 1: Train 50 Troops"
	quest1_progress_label.text = "Progress: " + str(QuestState.quest1_progress) + "/" + str(QuestState.quest1_target)
	quest1_reward_label.text = "Reward: 500 Food"
	claim_quest1_button.disabled = not QuestState.quest1_completed

	quest2_label.text = "Quest 2: Win 3 Campaign Battles"
	quest2_progress_label.text = "Progress: " + str(QuestState.quest2_progress) + "/" + str(QuestState.quest2_target)
	quest2_reward_label.text = "Reward: 50 Valor"
	claim_quest2_button.disabled = not QuestState.quest2_completed

	castle_label.text = "Castle Level " + str(GameState.castle_level)
	food_label.text = "Food: " + str(GameState.food)
	wood_label.text = "Wood: " + str(GameState.wood)
	stone_label.text = "Stone: " + str(GameState.stone)
	iron_label.text = "Iron: " + str(GameState.iron)

	farm_label.text = "Farm Level " + str(GameState.farm_level)
	lumber_mill_label.text = "Lumber Mill Level " + str(GameState.lumber_mill_level)
	quarry_label.text = "Quarry Level " + str(GameState.quarry_level)
	iron_mine_label.text = "Iron Mine Level " + str(GameState.iron_mine_level)

	stored_food_label.text = "Stored Food: " + str(stored_food)
	stored_wood_label.text = "Stored Wood: " + str(stored_wood)
	stored_stone_label.text = "Stored Stone: " + str(stored_stone)
	stored_iron_label.text = "Stored Iron: " + str(stored_iron)

	infantry_label.text = "Infantry: " + str(TroopState.infantry)
	marksmen_label.text = "Marksmen: " + str(TroopState.marksmen)
	cavalry_label.text = "Cavalry: " + str(TroopState.cavalry)

	hero_tickets_label.text = "Hero Tickets: " + str(HeroState.hero_tickets)
	valor_label.text = "Valor: " + str(valor)
	research_hall_label.text = "Research Hall Level " + str(ResearchState.research_hall_level)
	economy_research_label.text = "Economy Research Level " + str(ResearchState.economy_research_level)
	military_research_label.text = "Military Research Level " + str(ResearchState.military_research_level)
	troop_attack_bonus_label.text = "Troop Attack Bonus: +" + str(ResearchState.troop_attack_bonus) + "%"

	hospital_capacity_label.text = "Hospital Capacity: " + str(TroopState.hospital_capacity)
	hospital_troops_label.text = "Hospital Troops: " + str(TroopState.wounded_infantry + TroopState.wounded_marksmen + TroopState.wounded_cavalry)
	sanctuary_capacity_label.text = "Sanctuary Capacity: " + str(TroopState.sanctuary_capacity)
	sanctuary_troops_label.text = "Sanctuary Troops: " + str(TroopState.sanctuary_troops)

	enemy_infantry_label.text = "Enemy Infantry: " + str(CampaignState.enemy_infantry)
	enemy_marksmen_label.text = "Enemy Marksmen: " + str(CampaignState.enemy_marksmen)
	enemy_cavalry_label.text = "Enemy Cavalry: " + str(CampaignState.enemy_cavalry)
	enemy_level_label.text = "Enemy Level: " + str(CampaignState.enemy_level)
	player_power_label.text = "Player Power: " + str(CampaignState.player_power)
	enemy_power_label.text = "Enemy Power: " + str(CampaignState.enemy_power)

	recruit_hero_button.text = "Recruit Hero"

	update_hero_labels()
	
	
func hunt_monster(monster_id: String):
	var monster = {}

	for m in DataManager.monsters:
		if m.has("id") and m["id"] == monster_id:
			monster = m
			break

	if monster.is_empty():
		print("Monster not found: " + monster_id)
		return

	if HeroState.current_hero_index < 0 or HeroState.current_hero_index >= HeroState.recruited_heroes.size():
		print("Recruit a hero before hunting monsters!")
		return

	var monster_power = int(monster.get("power", 0))
	var hero = HeroState.recruited_heroes[HeroState.current_hero_index]
	var hero_stats = get_recruited_hero_stats(hero)
	var troop_power = TroopState.infantry + TroopState.marksmen + TroopState.cavalry

	var player_power = int(
		hero_stats["attack"] +
		hero_stats["defense"] +
		(troop_power * 10)
	)

	print("Player Power: ", player_power)
	print("Monster Power: ", monster_power)

	if player_power < monster_power:
		print("Monster hunt failed! Need more power.")
		battle_result_label.text = "Monster Hunt: Failed. Need more power."
		return

	var rewards = monster.get("rewards", {})
	var item_drops = rewards.get("itemDrops", [])

	for item in item_drops:
		InventoryState.add_item(item, 1)
		print("Added item to bag: ", item)
	

	GameState.food += int(rewards.get("food", 0))
	GameState.wood += int(rewards.get("wood", 0))
	GameState.stone += int(rewards.get("stone", 0))
	GameState.iron += int(rewards.get("iron", 0))
	valor += int(rewards.get("valor", 0))

	give_current_hero_xp(int(rewards.get("heroXP", 0)))

	print("Monster defeated: " + monster.get("name", "Unknown"))
	print("Rewards claimed!")

	monster_reward_text.text = (
		"Monster Defeated!\n" +
		monster.get("name", "Unknown") + "\n\n" +
		"+Food: " + str(rewards.get("food", 0)) + "\n" +
		"+Wood: " + str(rewards.get("wood", 0)) + "\n" +
		"+Stone: " + str(rewards.get("stone", 0)) + "\n" +
		"+Iron: " + str(rewards.get("iron", 0)) + "\n" +
		"+Valor: " + str(rewards.get("valor", 0)) + "\n" +
		"+Hero XP: " + str(rewards.get("heroXP", 0)) + "\n\n" +
		"Items:\n" +
		str(item_drops)
	)

	monster_reward_popup.visible = true
	battle_result_label.text = "Monster defeated!"

	update_labels()
	save_game()

func get_skills_for_hero(hero_id: String) -> Array:
	var results = []

	for skill in DataManager.hero_skills:
		if skill.has("heroId") and skill["heroId"] == hero_id:
			results.append(skill)

	return results

func update_hero_labels():
	if HeroState.current_hero_index >= 0 and HeroState.current_hero_index < HeroState.recruited_heroes.size():
		var hero = HeroState.recruited_heroes[HeroState.current_hero_index]
		var template = get_hero_template(hero)
		var stats = get_recruited_hero_stats(hero)

		hero_name_label.text = "Hero: " + hero.get("name", "Unknown") + " (" + template.get("rarity", "Unknown") + ")"
		hero_level_label.text = "Level: " + str(hero.get("level", 1)) + "  +" + str(hero.get("ascension", 0))
		hero_attack_label.text = "Attack: " + str(stats["attack"])
		hero_defense_label.text = "Defense: " + str(stats["defense"])
		hero_xp_label.text = "XP: " + str(hero.get("xp", 0)) + "/100"

		var hero_id = hero.get("id", "")
		var hero_skills = get_skills_for_hero(hero_id)

		var skill_text = ""

		for skill in hero_skills:
			skill_text += skill.get("skillName", "Unknown Skill") + "\n"

		hero_skills_label.text = skill_text

		var current_shards = HeroState.get_hero_shards(hero_id)
		var ascension = int(hero.get("ascension", 0))
		var shards_needed = (ascension + 1) * 50

		hero_shards_label.text = "Shards: " + str(current_shards) + "/" + str(shards_needed)

		hero_role_label.text = "Role: " + template.get("role", "Unknown")
		hero_bonus_label.text = "Troop: " + template.get("troopType", "none")

		var active_skills = template.get("activeSkills", [])

		if active_skills.size() > 0:
			hero_ability_label.text = "Ability: " + str(active_skills[0].get("name", "None"))
		else:
			hero_ability_label.text = "Ability: None"

	else:
		hero_name_label.text = "Hero: None"
		hero_level_label.text = "Level: 0"
		hero_attack_label.text = "Attack: 0"
		hero_defense_label.text = "Defense: 0"
		hero_xp_label.text = "XP: 0/100"
		hero_role_label.text = "Role: None"
		hero_bonus_label.text = "Bonus: None"
		hero_ability_label.text = "Ability: None"
		hero_shards_label.text = "Shards: 0/0"
		hero_skills_label.text = "Skills: None"
func get_hero_template(hero: Dictionary) -> Dictionary:
	var hero_id = hero.get("id", "")

	for template in DataManager.heroes:
		if template.has("id") and template["id"] == hero_id:
			return template

	return {}

func get_hero_skill_bonus(hero: Dictionary, stat_name: String) -> float:
	var hero_id = hero.get("id", "")
	var ascension = int(hero.get("ascension", 0))
	var total_bonus = 0.0

	for skill in get_skills_for_hero(hero_id):
		if int(skill.get("unlockAscension", 0)) > ascension:
			continue

		var scaling = skill.get("powerScaling", {})
		if scaling.get("stat", "") != stat_name:
			continue

		var base_value = float(scaling.get("baseValue", 0))
		var increment = float(scaling.get("increment", 0))

		total_bonus += base_value + (increment * ascension)

	return total_bonus / 100.0


func get_recruited_hero_stats(hero: Dictionary) -> Dictionary:
	var template = get_hero_template(hero)

	if template.is_empty():
		return {
			"attack": 0,
			"defense": 0,
			"health": 0,
			"leadership": 0,
			"power": 0
		}

	var level = int(hero.get("level", 1))
	var ascension = int(hero.get("ascension", 0))
	var asc_key = "ascension" + str(ascension)
	var asc_data = template.get(asc_key, {})

	var level_factor = 1.0 + ((level - 1) * 0.25)

	var attack = int(template.get("baseAttack", 0) * level_factor * asc_data.get("attackMultiplier", 1.0))
	var defense = int(template.get("baseDefense", 0) * level_factor * asc_data.get("defenseMultiplier", 1.0))
	var health = int(template.get("baseHealth", 0) * level_factor * asc_data.get("healthMultiplier", 1.0))
	var troop_attack_bonus = get_hero_skill_bonus(hero, "Troop Attack")
	var troop_defense_bonus = get_hero_skill_bonus(hero, "Troop Defense")
	var infantry_damage_bonus = get_hero_skill_bonus(hero, "Infantry Damage")
	var infantry_defense_bonus = get_hero_skill_bonus(hero, "Infantry Defense")

	attack = int(attack * (1.0 + troop_attack_bonus + infantry_damage_bonus))
	defense = int(defense * (1.0 + troop_defense_bonus + infantry_defense_bonus))
	var leadership = int(template.get("leadership", 0) * level_factor * asc_data.get("leadershipMultiplier", 1.0))
	var power = int((attack + defense) * 12 + (health * 0.5) + leadership)

	return {
		"attack": attack,
		"defense": defense,
		"health": health,
		"leadership": leadership,
		"power": power
	}


func calculate_power(att_inf, att_marks, att_cav, def_inf, def_marks, def_cav) -> int:
	var base = att_inf + att_marks + att_cav
	var bonus = 0.0

	bonus += min(att_inf, def_marks) * 0.5
	bonus += min(att_marks, def_cav) * 0.5
	bonus += min(att_cav, def_inf) * 0.5

	return int(base + bonus)


func _process(delta):
	production_timer += delta

	if production_timer >= 60.0:
		production_timer = 0.0
		produce_resources()

	if TroopState.infantry_training_time_left > 0:
		TroopState.infantry_training_time_left -= delta
		if TroopState.infantry_training_time_left <= 0:
			TroopState.infantry_training_time_left = 0
			complete_training("infantry")

	if TroopState.marksmen_training_time_left > 0:
		TroopState.marksmen_training_time_left -= delta
		if TroopState.marksmen_training_time_left <= 0:
			TroopState.marksmen_training_time_left = 0
			complete_training("marksmen")

	if TroopState.cavalry_training_time_left > 0:
		TroopState.cavalry_training_time_left -= delta
		if TroopState.cavalry_training_time_left <= 0:
			TroopState.cavalry_training_time_left = 0
			complete_training("cavalry")


func produce_resources():
	var economy_bonus = 1.0 + (ResearchState.economy_research_level * 0.05)

	var food_gain = int((GameState.farm_level * 2) * economy_bonus)
	var wood_gain = int((GameState.lumber_mill_level * 2) * economy_bonus)
	var stone_gain = int((GameState.quarry_level * 1) * economy_bonus)
	var iron_gain = int((GameState.iron_mine_level * 1) * economy_bonus)

	stored_food = min(stored_food + food_gain, get_food_storage_limit())
	stored_wood = min(stored_wood + wood_gain, get_wood_storage_limit())
	stored_stone = min(stored_stone + stone_gain, get_stone_storage_limit())
	stored_iron = min(stored_iron + iron_gain, get_iron_storage_limit())

	update_labels()
	
func apply_offline_production(seconds_away: float):
	if seconds_away <= 0:
		return

	var economy_bonus = 1.0 + (ResearchState.economy_research_level * 0.05)

	var food_gain = int((GameState.farm_level * 2) * economy_bonus * (seconds_away / 60.0))
	var wood_gain = int((GameState.lumber_mill_level * 2) * economy_bonus * (seconds_away / 60.0))
	var stone_gain = int((GameState.quarry_level * 1) * economy_bonus * (seconds_away / 60.0))
	var iron_gain = int((GameState.iron_mine_level * 1) * economy_bonus * (seconds_away / 60.0))

	stored_food = min(stored_food + food_gain, get_food_storage_limit())
	stored_wood = min(stored_wood + wood_gain, get_wood_storage_limit())
	stored_stone = min(stored_stone + stone_gain, get_stone_storage_limit())
	stored_iron = min(stored_iron + iron_gain, get_iron_storage_limit())

	print("Offline production added:")
	print("Food +", food_gain)
	print("Wood +", wood_gain)
	print("Stone +", stone_gain)
	print("Iron +", iron_gain)
	
func apply_offline_training(seconds_away: float):
	if seconds_away <= 0:
		return

	if TroopState.infantry_training_time_left > 0:
		TroopState.infantry_training_time_left -= seconds_away
		if TroopState.infantry_training_time_left <= 0:
			TroopState.infantry_training_time_left = 0
			complete_training("infantry")

	if TroopState.marksmen_training_time_left > 0:
		TroopState.marksmen_training_time_left -= seconds_away
		if TroopState.marksmen_training_time_left <= 0:
			TroopState.marksmen_training_time_left = 0
			complete_training("marksmen")

	if TroopState.cavalry_training_time_left > 0:
		TroopState.cavalry_training_time_left -= seconds_away
		if TroopState.cavalry_training_time_left <= 0:
			TroopState.cavalry_training_time_left = 0
			complete_training("cavalry")

func get_food_storage_limit() -> int:
	return GameState.farm_level * 1000


func get_wood_storage_limit() -> int:
	return GameState.lumber_mill_level * 1000


func get_stone_storage_limit() -> int:
	return GameState.quarry_level * 800


func get_iron_storage_limit() -> int:
	return GameState.iron_mine_level * 500


func get_warehouse_protection_limit() -> int:
	return GameState.warehouse_level * 50000


func complete_training(training_type: String):
	match training_type:
		"infantry":
			TroopState.infantry += TRAIN_AMOUNT
		"marksmen":
			TroopState.marksmen += TRAIN_AMOUNT
		"cavalry":
			TroopState.cavalry += TRAIN_AMOUNT
		_:
			print("Unknown training type: " + str(training_type))
			return

	add_quest1_progress(TRAIN_AMOUNT)
	update_labels()
	save_game()


func add_quest1_progress(amount: int):
	QuestState.quest1_progress += amount

	if QuestState.quest1_progress >= QuestState.quest1_target:
		QuestState.quest1_progress = QuestState.quest1_target
		QuestState.quest1_completed = true


func _on_battle_enemy_button_pressed():
	hunt_monster("monster_common_l1_s1_frost_lupine")
	
	var enemy_level_before_battle: int = int(CampaignState.enemy_level)
	var result: Dictionary = CampaignManager1.battle_current_campaign_stage()

	if result["victory"]:
		battle_result_label.text = "Battle Result: Victory!"
		valor += enemy_level_before_battle * 5
		give_current_hero_xp(enemy_level_before_battle * 25)
	else:
		battle_result_label.text = "Battle Result: Defeat!"

	update_labels()
	save_game()


func give_current_hero_xp(amount: int):
	if HeroState.current_hero_index < 0 or HeroState.current_hero_index >= HeroState.recruited_heroes.size():
		return

	var hero = HeroState.recruited_heroes[HeroState.current_hero_index]
	hero["xp"] = hero.get("xp", 0) + amount

	var template = get_hero_template(hero)
	var max_level = int(template.get("maxLevel", HeroState.max_hero_level))

	while hero["xp"] >= 100 and hero["level"] < max_level:
		hero["xp"] -= 100
		hero["level"] += 1


func _on_upgrade_castle_button_pressed():
	var next_level = GameState.castle_level + 1
	var cost = DataManager.get_building_cost("castle", next_level)

	if cost.is_empty():
		print("Castle upgrade data missing for level " + str(next_level))
		return

	var food_cost = int(cost.get("food", 0))
	var wood_cost = int(cost.get("wood", 0))
	var stone_cost = int(cost.get("stone", 0))
	var iron_cost = int(cost.get("iron", 0))
	var valor_cost = int(cost.get("valor", 0))

	if GameState.food < food_cost or GameState.wood < wood_cost or GameState.stone < stone_cost or GameState.iron < iron_cost or valor < valor_cost:
		print("Not enough resources to upgrade Castle!")
		return

	GameState.food -= food_cost
	GameState.wood -= wood_cost
	GameState.stone -= stone_cost
	GameState.iron -= iron_cost
	valor -= valor_cost

	GameState.castle_level = next_level

	var power_gain = DataManager.get_building_power_gain("castle", next_level)
	print("Castle upgraded to Level " + str(next_level) + " | Power +" + str(power_gain))

	update_labels()
	save_game()


func _on_gather_resources_button_pressed():
	var food_gain = (GameState.farm_level * 50) + 50
	var wood_gain = (GameState.lumber_mill_level * 50) + 50
	var stone_gain = (GameState.quarry_level * 25) + 25
	var iron_gain = (GameState.iron_mine_level * 15) + 10

	for hero in HeroState.recruited_heroes:
		var template = get_hero_template(hero)
		var bonuses = template.get("passiveBonuses", [])

		for bonus in bonuses:
			var stat = bonus.get("stat", "")
			var value = float(bonus.get("value", 0.0))
			var level = int(hero.get("level", 1))

			match stat:
				"Food Production":
					food_gain += int(food_gain * value * level)
				"Wood Production":
					wood_gain += int(wood_gain * value * level)
				"Stone Production":
					stone_gain += int(stone_gain * value * level)
				"Iron Production":
					iron_gain += int(iron_gain * value * level)

	GameState.food += food_gain
	GameState.wood += wood_gain
	GameState.stone += stone_gain
	GameState.iron += iron_gain

	update_labels()
	save_game()


func _on_upgrade_farm_button_pressed():
	var food_cost = 100 * GameState.farm_level
	var wood_cost = 200 * GameState.farm_level

	if GameState.food >= food_cost and GameState.wood >= wood_cost:
		GameState.food -= food_cost
		GameState.wood -= wood_cost
		GameState.farm_level += 1
		update_labels()
		save_game()
	else:
		print("Not enough resources to upgrade Farm!")


func _on_upgrade_lumber_mill_button_pressed():
	var food_cost = GameState.lumber_mill_level * 100
	var wood_cost = GameState.lumber_mill_level * 150

	if GameState.food >= food_cost and GameState.wood >= wood_cost:
		GameState.food -= food_cost
		GameState.wood -= wood_cost
		GameState.lumber_mill_level += 1
		update_labels()
		save_game()
	else:
		print("Not enough resources to upgrade Lumber Mill!")


func _on_upgrade_quarry_button_pressed():
	var wood_cost = GameState.quarry_level * 150
	var stone_cost = GameState.quarry_level * 100

	if GameState.wood >= wood_cost and GameState.stone >= stone_cost:
		GameState.wood -= wood_cost
		GameState.stone -= stone_cost
		GameState.quarry_level += 1
		update_labels()
		save_game()
	else:
		print("Not enough resources to upgrade Quarry!")


func _on_upgrade_iron_mine_button_pressed():
	var stone_cost = GameState.iron_mine_level * 150
	var iron_cost = GameState.iron_mine_level * 100

	if GameState.stone >= stone_cost and GameState.iron >= iron_cost:
		GameState.stone -= stone_cost
		GameState.iron -= iron_cost
		GameState.iron_mine_level += 1
		update_labels()
		save_game()
	else:
		print("Not enough resources to upgrade Iron Mine!")


func _on_train_infantry_button_pressed():
	start_training_from_database("infantry_t1")


func _on_train_marksmen_button_pressed():
	start_training_from_database("marksmen_t1")


func _on_train_cavalry_button_pressed():
	start_training_from_database("cavalry_t1")


func start_training_from_database(troop_id: String):
	var troop = DataManager.get_troop(troop_id)

	if troop.is_empty():
		print("Troop not found: " + troop_id)
		return

	var training_type = troop["troopType"]
	var cost = troop["trainingCost"]

	var food_cost = int(cost.get("food", 0))
	var wood_cost = int(cost.get("wood", 0))
	var stone_cost = int(cost.get("stone", 0))
	var iron_cost = int(cost.get("iron", 0))
	var time_needed = float(troop.get("trainingTimeSec", 10))

	if GameState.food < food_cost or GameState.wood < wood_cost or GameState.stone < stone_cost or GameState.iron < iron_cost:
		print("Not enough resources to train " + training_type + "!")
		return

	match training_type:
		"infantry":
			if TroopState.infantry_training_time_left > 0:
				print("Infantry is already training!")
				return
			TroopState.infantry_training_time_left = time_needed

		"marksmen":
			if TroopState.marksmen_training_time_left > 0:
				print("Marksmen are already training!")
				return
			TroopState.marksmen_training_time_left = time_needed

		"cavalry":
			if TroopState.cavalry_training_time_left > 0:
				print("Cavalry is already training!")
				return
			TroopState.cavalry_training_time_left = time_needed

	GameState.food -= food_cost
	GameState.wood -= wood_cost
	GameState.stone -= stone_cost
	GameState.iron -= iron_cost

	update_labels()
	save_game()


func _on_collect_resources_button_pressed():
	GameState.food += stored_food
	GameState.wood += stored_wood
	GameState.stone += stored_stone
	GameState.iron += stored_iron

	stored_food = 0
	stored_wood = 0
	stored_stone = 0
	stored_iron = 0

	update_labels()
	save_game()


func _on_upgrade_research_hall_button_pressed():
	var wood_cost = ResearchState.research_hall_level * 200
	var stone_cost = ResearchState.research_hall_level * 150

	if GameState.wood >= wood_cost and GameState.stone >= stone_cost:
		GameState.wood -= wood_cost
		GameState.stone -= stone_cost
		ResearchState.research_hall_level += 1
		update_labels()
		save_game()
	else:
		print("Not enough resources to upgrade Research Hall!")


func _on_research_economy_button_pressed():
	var food_cost = (ResearchState.economy_research_level + 1) * 100
	var wood_cost = (ResearchState.economy_research_level + 1) * 100

	if ResearchState.research_hall_level > ResearchState.economy_research_level and GameState.food >= food_cost and GameState.wood >= wood_cost:
		GameState.food -= food_cost
		GameState.wood -= wood_cost
		ResearchState.economy_research_level += 1
		update_labels()
		save_game()
	else:
		print("Need higher Research Hall or more resources!")


func _on_research_military_button_pressed():
	var iron_cost = (ResearchState.military_research_level + 1) * 100
	var stone_cost = (ResearchState.military_research_level + 1) * 100

	if ResearchState.research_hall_level > ResearchState.military_research_level and GameState.iron >= iron_cost and GameState.stone >= stone_cost:
		GameState.iron -= iron_cost
		GameState.stone -= stone_cost
		ResearchState.military_research_level += 1
		update_labels()
		save_game()
	else:
		print("Need higher Research Hall or more resources!")

func _on_ascend_hero_button_pressed():
	ascend_current_hero()

func _on_recruit_hero_button_pressed():
	if HeroState.hero_tickets <= 0:
		print("No hero tickets!")
		return

	var hero_list = DataManager.get_all_heroes()

	if hero_list.is_empty():
		print("No heroes loaded!")
		return

	var random_index = randi() % hero_list.size()
	var hero_template = hero_list[random_index]
	var hero_id = hero_template["id"]

	for hero in HeroState.recruited_heroes:
		if hero.get("id", "") == hero_id:
			if !HeroState.hero_shards.has(hero_id):
				HeroState.hero_shards[hero_id] = 0

			HeroState.hero_shards[hero_id] += get_duplicate_shard_amount(hero_template)
			HeroState.hero_tickets -= 1

			print("Duplicate hero! Shards added for " + hero_template["name"])

			update_labels()
			save_game()
			return

	var recruited_hero = {
		"id": hero_template["id"],
		"name": hero_template["name"],
		"level": 1,
		"xp": 0,
		"ascension": 0
	}

	HeroState.recruited_heroes.append(recruited_hero)
	HeroState.current_hero_index = HeroState.recruited_heroes.size() - 1
	HeroState.hero_tickets -= 1

	print("Recruited: " + hero_template["name"])

	update_labels()
	save_game()


func get_duplicate_shard_amount(hero_template: Dictionary) -> int:
	match hero_template.get("rarity", "Rare"):
		"Mythic":
			return 120
		"Legendary":
			return 80
		"Epic":
			return 40
		"Rare":
			return 20
		_:
			return 10


func _on_level_up_hero_button_pressed():
	if HeroState.current_hero_index < 0:
		print("Recruit a hero first!")
		return

	if valor < 10:
		print("Not enough Valor!")
		return

	var hero = HeroState.recruited_heroes[HeroState.current_hero_index]
	var template = get_hero_template(hero)
	var max_level = int(template.get("maxLevel", HeroState.max_hero_level))

	if int(hero.get("level", 1)) >= max_level:
		print("Hero is max level!")
		return

	hero["level"] = int(hero.get("level", 1)) + 1
	valor -= 10
	

	update_labels()
	save_game()


func _on_previous_hero_button_pressed():
	if HeroState.recruited_heroes.size() == 0:
		return

	HeroState.current_hero_index -= 1

	if HeroState.current_hero_index < 0:
		HeroState.current_hero_index = HeroState.recruited_heroes.size() - 1

	update_labels()
	save_game()


func _on_next_hero_button_pressed():
	if HeroState.recruited_heroes.size() == 0:
		return

	HeroState.current_hero_index += 1

	if HeroState.current_hero_index >= HeroState.recruited_heroes.size():
		HeroState.current_hero_index = 0

	update_labels()
	save_game()


func _on_add_hero_ticket_button_pressed():
	HeroState.hero_tickets += 1
	HeroState.add_hero_shards(
	HeroState.recruited_heroes[0]["id"],
	500
)
	update_labels()
	save_game()
	
func ascend_current_hero():
	if HeroState.current_hero_index < 0:
		return

	var hero = HeroState.recruited_heroes[HeroState.current_hero_index]

	var hero_id = hero["id"]
	var ascension = int(hero.get("ascension", 0))

	if ascension >= 5:
		print("Hero already max ascension")
		return

	var shards_needed = (ascension + 1) * 50
	
	print("Current Shards: ", HeroState.get_hero_shards(hero_id))
	print("Shards Needed: ", shards_needed)
	if HeroState.get_hero_shards(hero_id) < shards_needed:
		print("Need " + str(shards_needed) + " shards")
		return

	HeroState.spend_hero_shards(hero_id, shards_needed)

	hero["ascension"] += 1

	print(hero["name"] + " ascended to +" + str(hero["ascension"]))

	update_labels()
	save_game()


func _on_claim_quest1_button_pressed():
	if not QuestState.quest1_completed:
		print("Quest not completed!")
		return

	GameState.food += 500
	QuestState.quest1_progress = 0
	QuestState.quest1_completed = false

	update_labels()
	save_game()


func _on_claim_quest2_button_pressed():
	if not QuestState.quest2_completed:
		print("Quest not completed!")
		return

	valor += 50
	QuestState.quest2_progress = 0
	QuestState.quest2_completed = false

	update_labels()
	save_game()


func add_casualties_to_hospital(amount):
	var hospital_used = TroopState.wounded_infantry + TroopState.wounded_marksmen + TroopState.wounded_cavalry
	var hospital_space = TroopState.hospital_capacity - hospital_used

	if amount <= hospital_space:
		TroopState.wounded_infantry += amount
		return

	TroopState.wounded_infantry += hospital_space

	var overflow = amount - hospital_space
	var sanctuary_space = TroopState.sanctuary_capacity - TroopState.sanctuary_troops

	if overflow <= sanctuary_space:
		TroopState.sanctuary_troops += overflow
		return

	TroopState.sanctuary_troops = TroopState.sanctuary_capacity

	var permanently_dead = overflow - sanctuary_space
	print(str(permanently_dead) + " troops permanently died.")


func _on_upgrade_warehouse_button_pressed():
	var wood_cost = GameState.warehouse_level * 300
	var stone_cost = GameState.warehouse_level * 200

	if GameState.wood >= wood_cost and GameState.stone >= stone_cost:
		GameState.wood -= wood_cost
		GameState.stone -= stone_cost
		GameState.warehouse_level += 1
		update_labels()
		save_game()
	else:
		print("Not enough resources to upgrade Warehouse!")


func save_game():
	var save_data = {
		"warehouse_level": GameState.warehouse_level,
		"castle_level": GameState.castle_level,
		"food": GameState.food,
		"wood": GameState.wood,
		"stone": GameState.stone,
		"iron": GameState.iron,
		"farm_level": GameState.farm_level,
		"lumber_mill_level": GameState.lumber_mill_level,
		"quarry_level": GameState.quarry_level,
		"iron_mine_level": GameState.iron_mine_level,
		"TroopState.infantry": TroopState.infantry,
		"TroopState.marksmen": TroopState.marksmen,
		"TroopState.cavalry": TroopState.cavalry,
		"TroopState.infantry_training_time_left": TroopState.infantry_training_time_left,
		"TroopState.marksmen_training_time_left": TroopState.marksmen_training_time_left,
		"TroopState.cavalry_training_time_left": TroopState.cavalry_training_time_left,
		"HeroState.hero_tickets": HeroState.hero_tickets,
		"HeroState.recruited_heroes": HeroState.recruited_heroes,
		"HeroState.current_hero_index": HeroState.current_hero_index,
		"HeroState.hero_shards": HeroState.hero_shards,
		"InventoryState.items": InventoryState.items,
		"valor": valor,
		"stored_food": stored_food,
		"stored_wood": stored_wood,
		"stored_stone": stored_stone,
		"stored_iron": stored_iron,
		"ResearchState.research_hall_level": ResearchState.research_hall_level,
		"ResearchState.economy_research_level": ResearchState.economy_research_level,
		"ResearchState.military_research_level": ResearchState.military_research_level,
		"CampaignState.campaign_chapter": CampaignState.campaign_chapter,
		"CampaignState.campaign_stage": CampaignState.campaign_stage,
		"CampaignState.campaign_progress": CampaignState.campaign_progress,
		"CampaignState.enemy_level": CampaignState.enemy_level,
		"CampaignState.enemy_infantry": CampaignState.enemy_infantry,
		"CampaignState.enemy_marksmen": CampaignState.enemy_marksmen,
		"CampaignState.enemy_cavalry": CampaignState.enemy_cavalry,
		"CampaignState.player_power": CampaignState.player_power,
		"CampaignState.enemy_power": CampaignState.enemy_power,
		"QuestState.quest1_progress": QuestState.quest1_progress,
		"QuestState.quest1_completed": QuestState.quest1_completed,
		"QuestState.quest2_progress": QuestState.quest2_progress,
		"QuestState.quest2_completed": QuestState.quest2_completed,
		"TroopState.wounded_infantry": TroopState.wounded_infantry,
		"TroopState.wounded_marksmen": TroopState.wounded_marksmen,
		"TroopState.wounded_cavalry": TroopState.wounded_cavalry,
		"TroopState.sanctuary_troops": TroopState.sanctuary_troops,
		"TroopState.hospital_capacity": TroopState.hospital_capacity,
		"TroopState.sanctuary_capacity": TroopState.sanctuary_capacity,
		"last_save_time": Time.get_unix_time_from_system(),
		
	}

	var file = FileAccess.open("user://savegame.save", FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data))
	file.close()


func load_game():
	if not FileAccess.file_exists("user://savegame.save"):
		return

	var file = FileAccess.open("user://savegame.save", FileAccess.READ)
	var content = file.get_as_text()
	file.close()

	var save_data = JSON.parse_string(content)

	if save_data == null:
		return

	GameState.castle_level = save_data.get("castle_level", 1)
	GameState.food = save_data.get("food", 1000)
	GameState.wood = save_data.get("wood", 1000)
	GameState.stone = save_data.get("stone", 1000)
	GameState.iron = save_data.get("iron", 1000)
	GameState.farm_level = save_data.get("farm_level", 1)
	GameState.lumber_mill_level = save_data.get("lumber_mill_level", 1)
	GameState.quarry_level = save_data.get("quarry_level", 1)
	GameState.iron_mine_level = save_data.get("iron_mine_level", 1)
	GameState.warehouse_level = save_data.get("warehouse_level", 1)

	TroopState.infantry = save_data.get("TroopState.infantry", 0)
	TroopState.marksmen = save_data.get("TroopState.marksmen", 0)
	TroopState.cavalry = save_data.get("TroopState.cavalry", 0)
	TroopState.infantry_training_time_left = save_data.get("TroopState.infantry_training_time_left", 0.0)
	TroopState.marksmen_training_time_left = save_data.get("TroopState.marksmen_training_time_left", 0.0)
	TroopState.cavalry_training_time_left = save_data.get("TroopState.cavalry_training_time_left", 0.0)
	TroopState.wounded_infantry = int(save_data.get("TroopState.wounded_infantry", 0))
	TroopState.wounded_marksmen = int(save_data.get("TroopState.wounded_marksmen", 0))
	TroopState.wounded_cavalry = int(save_data.get("TroopState.wounded_cavalry", 0))
	TroopState.sanctuary_troops = int(save_data.get("TroopState.sanctuary_troops", 0))
	TroopState.hospital_capacity = int(save_data.get("TroopState.hospital_capacity", 1000))
	TroopState.sanctuary_capacity = int(save_data.get("TroopState.sanctuary_capacity", 500))

	HeroState.hero_tickets = save_data.get("HeroState.hero_tickets", 5)
	HeroState.recruited_heroes = save_data.get("HeroState.recruited_heroes", [])
	HeroState.current_hero_index = save_data.get("HeroState.current_hero_index", -1)
	HeroState.hero_shards = save_data.get("HeroState.hero_shards", {})
	InventoryState.items = save_data.get("InventoryState.items", {})

	valor = save_data.get("valor", 100)

	stored_food = save_data.get("stored_food", 0)
	stored_wood = save_data.get("stored_wood", 0)
	stored_stone = save_data.get("stored_stone", 0)
	stored_iron = save_data.get("stored_iron", 0)

	ResearchState.research_hall_level = save_data.get("ResearchState.research_hall_level", 1)
	ResearchState.economy_research_level = save_data.get("ResearchState.economy_research_level", 0)
	ResearchState.military_research_level = save_data.get("ResearchState.military_research_level", 0)

	CampaignState.campaign_chapter = save_data.get("CampaignState.campaign_chapter", 1)
	CampaignState.campaign_stage = save_data.get("CampaignState.campaign_stage", 1)
	CampaignState.campaign_progress = save_data.get("CampaignState.campaign_progress", 0)
	CampaignState.enemy_level = save_data.get("CampaignState.enemy_level", 1)
	CampaignState.enemy_infantry = save_data.get("CampaignState.enemy_infantry", 50)
	CampaignState.enemy_marksmen = save_data.get("CampaignState.enemy_marksmen", 30)
	CampaignState.enemy_cavalry = save_data.get("CampaignState.enemy_cavalry", 20)
	CampaignState.player_power = save_data.get("CampaignState.player_power", 0)
	CampaignState.enemy_power = save_data.get("CampaignState.enemy_power", 0)

	QuestState.quest1_progress = save_data.get("QuestState.quest1_progress", 0)
	QuestState.quest1_completed = save_data.get("QuestState.quest1_completed", false)
	QuestState.quest2_progress = save_data.get("QuestState.quest2_progress", 0)
	QuestState.quest2_completed = save_data.get("QuestState.quest2_completed", false)
	
	var last_save_time = save_data.get("last_save_time", Time.get_unix_time_from_system())
	var current_time = Time.get_unix_time_from_system()

	var seconds_away = current_time - last_save_time

	print("Offline Time:", seconds_away, "seconds")
	apply_offline_production(seconds_away)
	apply_offline_training(seconds_away)
	save_game()
