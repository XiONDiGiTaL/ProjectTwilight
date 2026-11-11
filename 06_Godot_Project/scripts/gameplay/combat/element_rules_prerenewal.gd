class_name ElementRulesPreRenewal
extends RefCounted
## Pre-Renewal element table and magic damage. Pure functions.
##
## Table: attack element (row) vs defence element (column) for defence levels
## 1-4, in percent. Negative values heal in the original; this build clamps
## them to 0 damage (documented simplification). Values as documented by
## iRO Wiki classic / rAthena pre-re attr_fix (facts only). Confidence: Medium,
## cross-check pending (see GAME_MECHANICS.md).

const ELEMENTS := ["neutral", "water", "earth", "fire", "wind", "poison", "holy", "shadow", "ghost", "undead"]

const TABLE := [
	[ # level 1
		[100, 100, 100, 100, 100, 100, 100, 100,  25, 100],
		[100,  25, 100, 150,  50, 100,  75, 100, 100, 100],
		[100, 100,  25,  50, 150, 100,  75, 100, 100, 100],
		[100,  50, 150,  25, 100, 100,  75, 100, 100, 125],
		[100, 175,  50, 100,  25, 100,  75, 100, 100, 100],
		[100, 100, 125, 125, 125,   0,  75,  50, 100, -25],
		[100, 100, 100, 100, 100, 100,   0, 125, 100, 150],
		[100, 100, 100, 100, 100,  50, 125,   0, 100, -25],
		[ 25, 100, 100, 100, 100, 100,  75,  75, 125, 100],
		[100, 100, 100, 100, 100,  50, 100,   0, 100,   0],
	],
	[ # level 2
		[100, 100, 100, 100, 100, 100, 100, 100,  25, 100],
		[100,   0, 100, 175,  25, 100,  50,  75, 100, 100],
		[100, 100,   0,  25, 175, 100,  50,  75, 100, 100],
		[100,  25, 175,   0, 100, 100,  50,  75, 100, 150],
		[100, 175,  25, 100,   0, 100,  50,  75, 100, 100],
		[100,  75, 125, 125, 125,   0,  50,  25,  75, -50],
		[100, 100, 100, 100, 100, 100, -25, 150, 100, 175],
		[100, 100, 100, 100, 100,  25, 150, -25, 100, -50],
		[  0,  75,  75,  75,  75,  75,  50,  50, 150, 125],
		[100,  75,  75,  75,  75,  25, 125,   0, 100,   0],
	],
	[ # level 3
		[100, 100, 100, 100, 100, 100, 100, 100,   0, 100],
		[100, -25, 100, 200,   0, 100,  25,  50, 100, 125],
		[100, 100, -25,   0, 200, 100,  25,  50, 100,  75],
		[100,   0, 200, -25, 100, 100,  25,  50, 100, 175],
		[100, 200,   0, 100, -25, 100,  25,  50, 100, 100],
		[100,  50, 100, 100, 100,   0,  25,   0,  50, -75],
		[100, 100, 100, 100, 100, 125, -50, 175, 100, 200],
		[100, 100, 100, 100, 100,   0, 175, -50, 100, -75],
		[  0,  50,  50,  50,  50,  50,  25,  25, 175, 150],
		[100,  50,  50,  50,  50,   0, 150,   0, 100,   0],
	],
	[ # level 4
		[100, 100, 100, 100, 100, 100, 100, 100,   0, 100],
		[100, -50, 100, 200,   0,  75,   0,  25, 100, 150],
		[100, 100, -50,   0, 200,  75,   0,  25, 100,  50],
		[100,   0, 200, -50, 100,  75,   0,  25, 100, 200],
		[100, 200,   0, 100, -50,  75,   0,  25, 100, 100],
		[100,  25,  75,  75,  75,   0,   0, -25,  25, -100],
		[100,  75,  75,  75,  75, 125, -100, 200, 100, 200],
		[100,  75,  75,  75,  75, -25, 200, -100, 100, -100],
		[  0,  25,  25,  25,  25,  25,   0,   0, 200, 175],
		[100,  25,  25,  25,  25, -25, 175,   0, 100,   0],
	],
]


static func index_of(element: String) -> int:
	return maxi(0, ELEMENTS.find(element))


## Damage modifier in percent (may be negative in the raw table).
static func modifier(attack: String, defence: String, defence_level: int) -> int:
	var lv := clampi(defence_level, 1, 4) - 1
	return int(TABLE[lv][index_of(attack)][index_of(defence)])


## Applies the element modifier; negative (healing) results clamp to 0.
static func apply(damage: int, attack: String, defence: String, defence_level: int) -> int:
	return maxi(0, damage * modifier(attack, defence, defence_level) / 100)


## Pre-Renewal MATK range: min INT + (INT/7)^2, max INT + (INT/5)^2. High confidence.
static func matk_range(int_: int) -> Vector2i:
	return Vector2i(int_ + (int_ / 7) * (int_ / 7), int_ + (int_ / 5) * (int_ / 5))


## Soft MDEF: INT + VIT/2 (pre-re status calc). Medium confidence.
static func soft_mdef(int_: int, vit: int) -> int:
	return int_ + vit / 2


## Pre-Renewal cast time: base * (1 - DEX/150), instant at 150 DEX. High confidence.
static func cast_time_ms(base_ms: float, dex: int) -> float:
	return maxf(0.0, base_ms * (1.0 - dex / 150.0))


## One magic hit: rand(MATK) * skill% -> hard MDEF (% reduction) -> soft MDEF -> element.
## Magic never misses in Pre-Renewal. Minimum 1 before the element modifier.
static func magic_hit(matk: Vector2i, skill_pct: int, target: Dictionary, element: String, rng: RandomNumberGenerator) -> int:
	var raw := rng.randi_range(matk.x, maxi(matk.x, matk.y)) * skill_pct / 100
	var hard := clampi(int(target.get("mdef", 0)), 0, 99)
	var d := raw * (100 - hard) / 100 - soft_mdef(int(target.get("int", 0)), int(target.get("vit", 0)))
	d = maxi(1, d)
	return apply(d, element, String(target.get("element", "neutral")), int(target.get("element_level", 1)))
