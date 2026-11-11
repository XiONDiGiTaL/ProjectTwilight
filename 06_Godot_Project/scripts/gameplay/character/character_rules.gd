class_name CharacterRules
extends RefCounted
## Character creation rules (classic Pre-Renewal).
##
## Stat hexagon: three opposing pairs (STR/INT, AGI/LUK, VIT/DEX). Each stat is
## 1..9 and each pair sums to 10. Raising a stat from 1 to n costs 2 per point
## below 11, so every pair costs exactly 16 and every valid build spends the 48
## starting status points (High confidence; matches the classic creation screen).

const PAIRS := [["str", "int"], ["agi", "luk"], ["vit", "dex"]]
const PAIR_SUM := 10
const MIN_STAT := 1
const MAX_STAT := 9
const NAME_MIN := 4
const NAME_MAX := 23
const MAX_SLOTS := 6
const HAIR_COLORS := 9          # palettes 0..8
const HAIR_STYLES := 23         # offered styles 1..23 (filtered by what the client has)
const START_MAP := "prt_fild08"
const START_CELL := Vector2i(170, 200)


## Builds the six stats from the first stat of each pair (STR, AGI, VIT).
static func stats_from_pairs(str_: int, agi: int, vit: int) -> Dictionary:
	var a := clampi(str_, MIN_STAT, MAX_STAT)
	var b := clampi(agi, MIN_STAT, MAX_STAT)
	var c := clampi(vit, MIN_STAT, MAX_STAT)
	return {"str": a, "int": PAIR_SUM - a, "agi": b, "luk": PAIR_SUM - b, "vit": c, "dex": PAIR_SUM - c}


## True if the stats form a legal creation hexagon.
static func valid_hexagon(stats: Dictionary) -> bool:
	for p in PAIRS:
		var x := int(stats.get(p[0], 0))
		var y := int(stats.get(p[1], 0))
		if x < MIN_STAT or x > MAX_STAT or y < MIN_STAT or y > MAX_STAT or x + y != PAIR_SUM:
			return false
	return true


## Status points left after creation (always 0 for a legal hexagon).
static func remaining_points(stats: Dictionary) -> int:
	var spent := 0
	for k in stats:
		spent += StatRulesPreRenewal.total_raise_cost(1, int(stats[k]))
	return StatRulesPreRenewal.NOVICE_START_POINTS - spent


## Returns "" if the name is acceptable, otherwise a human-readable reason.
## Rules: 4-23 characters, letters/digits/single spaces, no leading/trailing
## space, unique among local characters (case-insensitive).
static func validate_name(name: String, existing: Array) -> String:
	if name != name.strip_edges():
		return "Names cannot start or end with a space."
	if name.length() < NAME_MIN or name.length() > NAME_MAX:
		return "Names must be %d to %d characters." % [NAME_MIN, NAME_MAX]
	if name.contains("  "):
		return "Names cannot contain double spaces."
	for i in name.length():
		var c := name.unicode_at(i)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 32 \
			or (c >= 0xAC00 and c <= 0xD7A3)  # Hangul syllables
		if not ok:
			return "Names may only use letters, numbers and spaces."
	for n in existing:
		if String(n).to_lower() == name.to_lower():
			return "You already have a character with that name."
	return ""


## A fresh level-1 Novice character record (SaveGame "character" schema).
static func new_character(name: String, male: bool, hair_style: int, hair_color: int, stats: Dictionary) -> Dictionary:
	return {
		"name": name, "job": "novice", "level": 1, "job_level": 1, "base_exp": 0, "job_exp": 0,
		"stats": stats.duplicate(), "status_points": remaining_points(stats),
		"hp": 0, "sp": 0, "zeny": 0,  # 0 = start at full HP / SP
		"inventory": [{"id": 501, "amount": 3}],
		"equipment": {"weapon": 1201, "body": 2301},  # classic Novice starting gear
		"male": male, "hair_style": hair_style, "hair_color": hair_color, "aura": "class", "cloth_color": 0,
		"map": START_MAP, "cell": START_CELL,
	}
