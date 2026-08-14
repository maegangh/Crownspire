extends Node

## Deterministic beta Wildling PvE combat.
## Uses StatResolver march combat stats. Does NOT own saves.
## Permanent deaths = 0 this sprint — all combat losses become wounded.

const MAX_ROUNDS: int = 40
const DEFENSE_FACTOR: float = 0.45
## Cap wounded share of the army (keeps tiny skirmishes from wiping everyone).
const MAX_WOUNDED_RATIO: float = 0.92
const MIN_WOUNDED_RATIO_ON_DEFEAT: float = 0.20


## L1–L30 progression. Species band is cosmetic for now (level drives stats).
func get_wildling_combat_stats(level: int, species: String = "") -> Dictionary:
	var lv: int = clampi(level, 1, 30)
	# Tuned so early packs are farmable; L26–30 need serious armies.
	var atk: float = roundf(45.0 * pow(1.20, float(lv - 1)))
	var deff: float = roundf(35.0 * pow(1.19, float(lv - 1)))
	var hp: float = roundf(900.0 * pow(1.22, float(lv - 1)))
	return {
		"level": lv,
		"species": species.strip_edges().to_lower(),
		"attack": atk,
		"defense": deff,
		"health": hp,
	}


## TEMPORARY BETA / PROTOTYPE — NOT final competitive PvP combat authority.
## Derives defender stats from public citadel_level + power only.
## There is NO server-authoritative defender garrison/troop snapshot yet.
## Do not award plunder/loot from this approximation. Replace with real
## garrison authority before competitive PvP economy.
func get_city_defense_stats(citadel_level: int, power: int) -> Dictionary:
	var lv: int = clampi(citadel_level, 1, 40)
	var pwr: float = maxf(0.0, float(power))
	# Scale public power into combat stats; citadel level floors early cities.
	var atk: float = maxf(40.0, roundf(30.0 * float(lv) + pwr * 0.08))
	var deff: float = maxf(25.0, roundf(25.0 * float(lv) + pwr * 0.06))
	var hp: float = maxf(800.0, roundf(500.0 * float(lv) + pwr * 0.35))
	return {
		"level": lv,
		"species": "player_city",
		"attack": atk,
		"defense": deff,
		"health": hp,
		"power": int(pwr),
		"authority": "temporary_public_power_beta",
	}


## Resolve one Wildling battle from StatResolver march stats + troop_tiers.
## troop_tiers: { infantry:{tier:qty}, marksmen:{}, cavalry:{} }
func resolve_battle(
	player_march_stats: Dictionary,
	wildling_stats: Dictionary,
	troop_tiers: Dictionary
) -> Dictionary:
	var totals: Dictionary = player_march_stats.get("totals", {}) as Dictionary
	var p_atk: float = maxf(1.0, float(totals.get("attack", 0.0)))
	var p_def: float = maxf(0.0, float(totals.get("defense", 0.0)))
	var p_hp: float = maxf(1.0, float(totals.get("health", 0.0)))
	var w_atk: float = maxf(1.0, float(wildling_stats.get("attack", 1.0)))
	var w_def: float = maxf(0.0, float(wildling_stats.get("defense", 0.0)))
	var w_hp: float = maxf(1.0, float(wildling_stats.get("health", 1.0)))

	var p_remain: float = p_hp
	var w_remain: float = w_hp
	var rounds: int = 0
	while p_remain > 0.0 and w_remain > 0.0 and rounds < MAX_ROUNDS:
		rounds += 1
		var dmg_to_w: float = maxf(1.0, p_atk - w_def * DEFENSE_FACTOR)
		w_remain -= dmg_to_w
		if w_remain <= 0.0:
			break
		var dmg_to_p: float = maxf(1.0, w_atk - p_def * DEFENSE_FACTOR)
		p_remain -= dmg_to_p

	var victory: bool = w_remain <= 0.0 and p_remain > 0.0
	if w_remain <= 0.0 and p_remain <= 0.0:
		# Simultaneous KO — award victory if player dealt the finishing blow this round.
		victory = true
		p_remain = maxf(1.0, p_hp * 0.05)

	var hp_lost_ratio: float = clampf(1.0 - (maxf(0.0, p_remain) / p_hp), 0.0, MAX_WOUNDED_RATIO)
	if not victory:
		hp_lost_ratio = maxf(hp_lost_ratio, MIN_WOUNDED_RATIO_ON_DEFEAT)
		hp_lost_ratio = minf(hp_lost_ratio, MAX_WOUNDED_RATIO)

	var split: Dictionary = distribute_casualties(troop_tiers, hp_lost_ratio)
	var surviving_tiers: Dictionary = split.get("survivors", {}) as Dictionary
	var wounded_tiers: Dictionary = split.get("wounded", {}) as Dictionary
	var survivor_flat: Dictionary = _flatten_tiers(surviving_tiers)
	var wounded_flat: Dictionary = _flatten_tiers(wounded_tiers)

	return {
		"victory": victory,
		"summary": "Victory!" if victory else "Defeat. Your survivors retreat.",
		"rounds": rounds,
		"player_stats": {
			"attack": p_atk,
			"defense": p_def,
			"health": p_hp,
			"health_remaining": maxf(0.0, p_remain),
		},
		"wildling_stats": {
			"attack": w_atk,
			"defense": w_def,
			"health": w_hp,
			"health_remaining": maxf(0.0, w_remain),
			"level": int(wildling_stats.get("level", 1)),
			"species": str(wildling_stats.get("species", "")),
		},
		"surviving_troop_tiers": surviving_tiers,
		"wounded_troop_tiers": wounded_tiers,
		"surviving_troops": survivor_flat,
		"losses": wounded_flat, # beta: losses == wounded (no permanent deaths)
		"wounded": wounded_flat,
		"casualty_ratio": hp_lost_ratio,
		"permanent_losses": {"infantry": 0, "marksmen": 0, "cavalry": 0},
	}


## Proportional tier-aware casualty split. original = survivors + wounded (per tier).
func distribute_casualties(troop_tiers: Dictionary, loss_ratio: float) -> Dictionary:
	var ratio: float = clampf(loss_ratio, 0.0, 1.0)
	var survivors: Dictionary = {"infantry": {}, "marksmen": {}, "cavalry": {}}
	var wounded: Dictionary = {"infantry": {}, "marksmen": {}, "cavalry": {}}
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = troop_tiers.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			by_tier = {}
		var total: int = 0
		var tiers: Array = []
		for tk: Variant in by_tier.keys():
			var qty: int = int(by_tier[tk])
			if qty <= 0:
				continue
			total += qty
			tiers.append({"tier": int(tk), "qty": qty})
		if total <= 0 or tiers.is_empty():
			continue
		var to_wound: int = int(floor(float(total) * ratio))
		to_wound = clampi(to_wound, 0, total)
		# Largest-remainder proportional distribution across tiers.
		var assigned: int = 0
		var parts: Array = []
		for entry: Variant in tiers:
			var row: Dictionary = entry
			var exact: float = float(row["qty"]) * float(to_wound) / float(total)
			var base_n: int = int(floor(exact))
			parts.append({
				"tier": int(row["tier"]),
				"qty": int(row["qty"]),
				"base": base_n,
				"frac": exact - float(base_n),
			})
			assigned += base_n
		parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("frac", 0.0)) > float(b.get("frac", 0.0))
		)
		var remain: int = to_wound - assigned
		for i: int in range(parts.size()):
			if remain <= 0:
				break
			parts[i]["base"] = int(parts[i]["base"]) + 1
			remain -= 1
		for part: Variant in parts:
			var p: Dictionary = part
			var tier: int = int(p["tier"])
			var qty2: int = int(p["qty"])
			var w: int = clampi(int(p["base"]), 0, qty2)
			var s: int = qty2 - w
			if s > 0:
				survivors[kind][tier] = s
			if w > 0:
				wounded[kind][tier] = w
	return {"survivors": survivors, "wounded": wounded}


func _flatten_tiers(tiers: Dictionary) -> Dictionary:
	var out: Dictionary = {"infantry": 0, "marksmen": 0, "cavalry": 0}
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var by_tier: Dictionary = tiers.get(kind, {}) as Dictionary
		if typeof(by_tier) != TYPE_DICTIONARY:
			continue
		var sum: int = 0
		for tk: Variant in by_tier.keys():
			sum += int(by_tier[tk])
		out[kind] = sum
	return out


func run_phase3_smoke_test() -> bool:
	var failed: int = 0
	if not has_node("/root/StatResolver") or not has_node("/root/TroopDatabase"):
		push_error("[WildlingCombat] smoke missing StatResolver/TroopDatabase")
		return false

	# Easy: many T3 infantry vs L1
	var strong_tiers: Dictionary = {"infantry": {3: 200}, "marksmen": {2: 50}, "cavalry": {2: 50}}
	var strong_stats: Dictionary = StatResolver.resolve_march_combat_stats(strong_tiers, [])
	var w1: Dictionary = get_wildling_combat_stats(1, "wolf")
	var easy: Dictionary = resolve_battle(strong_stats, w1, strong_tiers)
	if not bool(easy.get("victory", false)):
		push_error("[WildlingCombat] smoke easy should win")
		failed += 1
	else:
		print("[WildlingCombat] smoke easy victory OK rounds=%d ratio=%.2f" % [
			int(easy.get("rounds", 0)), float(easy.get("casualty_ratio", 0.0)),
		])

	# Hard: few T1 vs L25
	var weak_tiers: Dictionary = {"infantry": {1: 20}, "marksmen": {}, "cavalry": {}}
	var weak_stats: Dictionary = StatResolver.resolve_march_combat_stats(weak_tiers, [])
	var w25: Dictionary = get_wildling_combat_stats(25, "troll")
	var hard: Dictionary = resolve_battle(weak_stats, w25, weak_tiers)
	if bool(hard.get("victory", false)):
		push_error("[WildlingCombat] smoke hard should lose")
		failed += 1
	else:
		print("[WildlingCombat] smoke hard defeat OK")

	# Tier identity: original = survivors + wounded
	var mix: Dictionary = {"infantry": {1: 100, 3: 50}, "marksmen": {2: 40}, "cavalry": {4: 10}}
	var mix_stats: Dictionary = StatResolver.resolve_march_combat_stats(mix, [])
	var mid: Dictionary = resolve_battle(mix_stats, get_wildling_combat_stats(8, "bear"), mix)
	for kind: String in ["infantry", "marksmen", "cavalry"]:
		var orig_by: Dictionary = mix.get(kind, {}) as Dictionary
		var surv_by: Dictionary = (mid.get("surviving_troop_tiers", {}) as Dictionary).get(kind, {}) as Dictionary
		var wound_by: Dictionary = (mid.get("wounded_troop_tiers", {}) as Dictionary).get(kind, {}) as Dictionary
		for tk: Variant in orig_by.keys():
			var o: int = int(orig_by[tk])
			var s: int = int(surv_by.get(int(tk), surv_by.get(str(tk), 0)))
			var w: int = int(wound_by.get(int(tk), wound_by.get(str(tk), 0)))
			if s + w != o:
				push_error("[WildlingCombat] smoke tier identity fail %s t%s %d!=%d+%d" % [
					kind, str(tk), o, s, w,
				])
				failed += 1

	# Permanent losses must be zero.
	var perm: Dictionary = mid.get("permanent_losses", {}) as Dictionary
	if int(perm.get("infantry", 0)) + int(perm.get("marksmen", 0)) + int(perm.get("cavalry", 0)) != 0:
		push_error("[WildlingCombat] smoke permanent losses should be 0")
		failed += 1

	# Hero combat bonus (maegan) must raise resolved Attack vs no-hero.
	var hero_tiers: Dictionary = {"infantry": {2: 80}, "marksmen": {2: 40}, "cavalry": {2: 20}}
	var no_hero: Dictionary = StatResolver.resolve_march_combat_stats(hero_tiers, [])
	var with_hero: Dictionary = StatResolver.resolve_march_combat_stats(hero_tiers, ["maegan"])
	var atk0: float = float((no_hero.get("totals", {}) as Dictionary).get("attack", 0.0))
	var atk1: float = float((with_hero.get("totals", {}) as Dictionary).get("attack", 0.0))
	if atk1 <= atk0:
		push_error("[WildlingCombat] smoke hero ATK should exceed no-hero (%.1f vs %.1f)" % [atk1, atk0])
		failed += 1
	else:
		print("[WildlingCombat] smoke hero ATK OK %.1f -> %.1f" % [atk0, atk1])

	# Wounded routing API presence (do not mutate live TroopState save in smoke).
	if not has_node("/root/TroopState") or not TroopState.has_method("route_wounded_by_tiers"):
		push_error("[WildlingCombat] smoke TroopState.route_wounded_by_tiers missing")
		failed += 1

	if failed == 0:
		print("[WildlingCombat] Phase-3 smoke PASSED")
		return true
	print("[WildlingCombat] Phase-3 smoke FAILED count=%d" % failed)
	return false
