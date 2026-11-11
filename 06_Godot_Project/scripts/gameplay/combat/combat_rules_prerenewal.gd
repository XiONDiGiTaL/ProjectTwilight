class_name CombatRulesPreRenewal
extends RefCounted
## Pre-Renewal physical combat. Pure functions; randomness comes from the
## caller's RandomNumberGenerator so simulations are reproducible.
## Formulas and confidence levels are listed in GAME_MECHANICS.md.

const MIN_HIT_RATE := 5
const MAX_HIT_RATE := 95


## Hit chance in percent: 80 + HIT - FLEE, clamped to 5..95. High confidence.
static func hit_rate(attacker_hit: int, target_flee: int) -> int:
	return clampi(80 + attacker_hit - target_flee, MIN_HIT_RATE, MAX_HIT_RATE)


## Critical chance in tenths of a percent: player crit (1 + LUK*0.3 %) minus the
## target's critical shield (LUK * 0.2 %). High confidence.
static func crit_chance_permille(attacker_luk: int, target_luk: int) -> int:
	return maxi(0, 10 + attacker_luk * 3 - target_luk * 2)


## Monster soft DEF (VIT): VIT + rnd(0, max(0, floor(VIT/20)^2 - 1)). High confidence.
static func monster_vit_def(vit: int, rng: RandomNumberGenerator) -> int:
	var spread := maxi(0, (vit / 20) * (vit / 20) - 1)
	return vit + (rng.randi_range(0, spread) if spread > 0 else 0)


## Player soft DEF (VIT): floor(VIT*0.5) + rnd(floor(VIT*0.3), max(floor(VIT*0.3), floor(VIT^2/150) - 1)).
## Medium-high confidence.
static func player_vit_def(vit: int, rng: RandomNumberGenerator) -> int:
	var lo := int(vit * 0.3)
	var hi := maxi(lo, vit * vit / 150 - 1)
	return int(vit * 0.5) + rng.randi_range(lo, hi)


## Applies hard DEF (percent) then soft DEF (flat). Damage never drops below 1.
static func apply_defense(raw: int, hard_def: int, soft_def: int) -> int:
	var d := raw * (100 - clampi(hard_def, 0, 99)) / 100
	return maxi(1, d - soft_def)


## Pre-Renewal ASPD: 200 - (WD - (floor(WD*AGI/25) + floor(WD*DEX/100)) / 10), WD = 50 * BTBA.
## High confidence for the formula; per-class BTBA values are data.
static func aspd(btba_seconds: float, agi: int, dex: int) -> float:
	var wd := 50.0 * btba_seconds
	return 200.0 - (wd - (floorf(wd * agi / 25.0) + floorf(wd * dex / 100.0)) / 10.0)


## Milliseconds between attacks for an ASPD value: (200 - ASPD) * 20.
static func attack_interval_ms(aspd_value: float) -> float:
	return maxf(100.0, (200.0 - aspd_value) * 20.0)


## Weapon size modifiers in percent: weapon type -> [small, medium, large]. High confidence.
const SIZE_MODIFIERS := {
	"fist": [100, 100, 100],
	"dagger": [100, 75, 50],
	"sword": [75, 100, 75],
	"two_hand_sword": [75, 75, 100],
	"spear": [75, 75, 100],
	"axe": [50, 75, 100],
	"mace": [75, 100, 100],
	"rod": [100, 100, 100],
	"bow": [100, 100, 75],
	"katar": [75, 100, 75],
	"book": [100, 100, 50],
	"knuckle": [100, 75, 50],
	"instrument": [75, 100, 75],
	"whip": [75, 100, 50],
}


static func size_modifier(weapon_type: String, target_size: String) -> int:
	var row: Array = SIZE_MODIFIERS.get(weapon_type, SIZE_MODIFIERS.fist)
	match target_size:
		"small": return int(row[0])
		"large": return int(row[2])
		_: return int(row[1])


## Pre-Renewal weapon ATK range: minimum raised by DEX up to the weapon's ATK:
## [min(watk, floor(DEX * (0.8 + 0.2 * weapon_level))), watk]. Medium confidence.
static func weapon_atk_range(watk: int, weapon_level: int, dex: int) -> Vector2i:
	if watk <= 0:
		return Vector2i.ZERO
	var lo := mini(watk, int(dex * (0.8 + 0.2 * weapon_level)))
	return Vector2i(lo, watk)


## Resolves one physical attack. Returns {"miss": bool, "crit": bool, "damage": int}.
## attacker / target: {"hit", "flee", "luk", "atk_min", "atk_max", "def", "vit", "is_player", "can_crit", "size"}
## Players also pass {"batk", "watk_min", "watk_max", "weapon_type"}: damage is then
## status ATK + weapon ATK scaled by the weapon-vs-size modifier.
static func resolve_attack(attacker: Dictionary, target: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var has_weapon_model := attacker.has("batk")
	var mod := size_modifier(String(attacker.get("weapon_type", "fist")), String(target.get("size", "medium")))
	# Critical hits ignore FLEE and DEF and always deal maximum ATK (Pre-Renewal: no x1.4).
	if attacker.get("can_crit", false):
		if rng.randi_range(0, 999) < crit_chance_permille(attacker.luk, target.luk):
			var crit_dmg: int = int(attacker.batk) + int(attacker.watk_max) * mod / 100 if has_weapon_model else int(attacker.atk_max)
			return {"miss": false, "crit": true, "damage": maxi(1, crit_dmg)}
	if rng.randi_range(0, 99) >= hit_rate(attacker.hit, target.flee):
		return {"miss": true, "crit": false, "damage": 0}
	var raw: int
	if has_weapon_model:
		raw = int(attacker.batk) + rng.randi_range(int(attacker.watk_min), int(attacker.watk_max)) * mod / 100
	else:
		raw = rng.randi_range(int(attacker.atk_min), int(attacker.atk_max))
	var soft := player_vit_def(target.vit, rng) if target.get("is_player", false) else monster_vit_def(target.vit, rng)
	return {"miss": false, "crit": false, "damage": apply_defense(raw, int(target.def), soft)}


## Novice-style max HP: (35 + 5 * level) * (1 + VIT/100). Medium confidence;
## other jobs need their HP factors from data.
static func novice_max_hp(level: int, vit: int) -> int:
	return int((35 + 5 * level) * (1.0 + vit / 100.0))


static func novice_max_sp(level: int, int_: int) -> int:
	return int((10 + level) * (1.0 + int_ / 100.0))
