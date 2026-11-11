class_name StatusRules
extends RefCounted
## Status effects (debuffs and buffs) used by FieldSimulation. Pure data and
## functions; durations in ms. Values and confidence in GAME_MECHANICS.md.
##
## Flags: blocks_action (no move/attack/skill/cast), blocks_skill (silence),
## breaks_on_damage (sleep), debuff (cleared by death, resistible).
## resist: stat names whose average is the % resistance to the chance and
## duration (Pre-Renewal style; Medium confidence).

const DEFS := {
	"stun":      {"debuff": true, "blocks_action": true, "duration": 5000, "resist": ["vit"], "name": "Stun"},
	"sleep":     {"debuff": true, "blocks_action": true, "breaks_on_damage": true, "duration": 30000, "resist": ["int"], "name": "Sleep"},
	"stone":     {"debuff": true, "blocks_action": true, "duration": 20000, "resist": ["mdef"], "name": "Stone"},
	"silence":   {"debuff": true, "blocks_skill": true, "duration": 30000, "resist": ["vit"], "name": "Silence"},
	"blind":     {"debuff": true, "duration": 30000, "resist": ["int", "vit"], "name": "Blind"},
	"confusion": {"debuff": true, "duration": 30000, "resist": ["str", "int"], "name": "Confusion"},
	"dark_breath":    {"name": "Dark Breath"},
	"shadow_quicken": {"name": "Shadow Quicken"},
	"dark_weapon":    {"name": "Dark Weapon", "weapon_buff": true},
	"mistletoe":      {"name": "Mistletoe", "weapon_buff": true},
	"auto_counter":   {"name": "Auto Counter"},
	"protection":     {"name": "Spiritual Protection"},
	"wrath":          {"name": "Spiritual Wrath"},
	"rain_dance":     {"name": "Rain Dance"},
	"se_wind":        {"name": "Southeast Wind"},
}

const BLIND_HIT_FLEE_PCT := 75     # blind: HIT and FLEE x 0.75
const DRAIN_INTERVAL_MS := 2000.0  # Dark Breath / Shadow Quicken HP drain tick
const DRAIN_FLOOR_PCT := 10        # drains end the buff before HP would drop below this
const ASPD_CAP_INTERVAL_MS := 200.0  # ASPD 190 cap -> 200 ms between attacks


static func is_debuff(status: String) -> bool:
	return bool(DEFS.get(status, {}).get("debuff", false))


static func display_name(status: String) -> String:
	return String(DEFS.get(status, {}).get("name", status.capitalize()))


## Resistance in percent for a target profile {str,int,vit,mdef,...}.
static func resistance(status: String, target: Dictionary) -> int:
	var keys: Array = DEFS.get(status, {}).get("resist", [])
	if keys.is_empty():
		return 0
	var total := 0
	for k in keys:
		total += int(target.get(k, 0))
	return clampi(total / keys.size(), 0, 100)


## Chance after resistance (percent).
static func effective_chance(status: String, base_chance: int, target: Dictionary) -> int:
	return base_chance * (100 - resistance(status, target)) / 100


## Duration after resistance (ms), at least 1 s for debuffs.
static func effective_duration(status: String, target: Dictionary) -> float:
	var base := float(DEFS.get(status, {}).get("duration", 5000))
	return maxf(1000.0, base * (100 - resistance(status, target)) / 100.0)


## HP drained per tick by the Dark Knight's HP-cost buffs.
static func drain_amount(max_hp: int, permille: int) -> int:
	return 1 + max_hp * permille / 1000
