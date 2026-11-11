class_name StatRulesPreRenewal
extends RefCounted
## Pre-Renewal character stat formulas. Pure functions, no engine state, so the
## same rules run in offline, co-op host and dedicated server processes.
## Every formula lists its evidence and confidence; see GAME_MECHANICS.md.

const MAX_BASE_STAT := 99
const NOVICE_START_POINTS := 48  # High confidence: 6 stats at 1 + 48 points (iRO Wiki, rAthena pre-re)


## Points gained when levelling from `old_level` to old_level + 1.
## floor(old_level / 5) + 3. Confirmed by the well-known total of 1273 at level 99.
static func status_points_gained(old_level: int) -> int:
	return old_level / 5 + 3


## Total status points available at a base level (normal, non-transcendent).
static func total_status_points(base_level: int) -> int:
	var total := NOVICE_START_POINTS
	for lv in range(1, base_level):
		total += status_points_gained(lv)
	return total


## Cost to raise a stat from `current` to current + 1: floor((current - 1) / 10) + 2.
## High confidence: yields the known 628 points to raise a stat 1 -> 99.
static func raise_cost(current: int) -> int:
	if current >= MAX_BASE_STAT:
		return -1
	return (current - 1) / 10 + 2


static func total_raise_cost(from: int, to: int) -> int:
	var total := 0
	for v in range(from, to):
		total += raise_cost(v)
	return total


## Pre-Renewal HIT = BaseLv + DEX (+ equipment/skill bonuses). High confidence.
static func hit(base_level: int, dex: int) -> int:
	return base_level + dex


## Pre-Renewal FLEE = BaseLv + AGI (+ bonuses). High confidence.
static func flee(base_level: int, agi: int) -> int:
	return base_level + agi


## Perfect dodge = 1 + floor(LUK / 10). High confidence.
static func perfect_dodge(luk: int) -> int:
	return 1 + luk / 10


## Critical rate shown in the status window, in percent: 1 + LUK * 0.3. High confidence.
static func critical_rate(luk: int) -> float:
	return 1.0 + luk * 0.3


## Status ATK for melee weapons: STR + floor(STR/10)^2 + floor(DEX/5) + floor(LUK/5).
## Ranged weapons swap STR and DEX. High confidence (iRO Wiki pre-re, rAthena).
static func status_atk(str_: int, dex: int, luk: int, ranged: bool = false) -> int:
	var primary := dex if ranged else str_
	var secondary := str_ if ranged else dex
	var b := primary / 10
	return primary + b * b + secondary / 5 + luk / 5


## MATK range: min = INT + floor(INT/7)^2, max = INT + floor(INT/5)^2. High confidence.
static func matk_range(int_: int) -> Vector2i:
	var a := int_ / 7
	var b := int_ / 5
	return Vector2i(int_ + a * a, int_ + b * b)
