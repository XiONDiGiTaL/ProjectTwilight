class_name RaConstants
extends RefCounted
## Script constants needed by the supported rAthena NPC scripts. Values are
## the documented rAthena ones (facts, doc/script_commands.txt and the
## constants list), not copied code. Unknown names fall back to variables.

## rAthena Class id -> [Project Twilight job id or "", EA class bits, display name]
const CLASSES := {
	0: ["novice", 0x0, "Novice"], 1: ["swordman", 0x1, "Swordman"], 2: ["mage", 0x2, "Mage"], 3: ["archer", 0x3, "Archer"],
	4: ["acolyte", 0x4, "Acolyte"], 5: ["merchant", 0x5, "Merchant"], 6: ["thief", 0x6, "Thief"],
	7: ["knight", 0x101, "Knight"], 8: ["priest", 0x104, "Priest"], 9: ["wizard", 0x102, "Wizard"], 10: ["blacksmith", 0x105, "Blacksmith"],
	11: ["hunter", 0x103, "Hunter"], 12: ["assassin", 0x106, "Assassin"], 14: ["crusader", 0x201, "Crusader"], 15: ["monk", 0x204, "Monk"],
	16: ["sage", 0x202, "Sage"], 17: ["rogue", 0x206, "Rogue"], 18: ["alchemist", 0x205, "Alchemist"], 19: ["bard", 0x203, "Bard"],
	20: ["dancer", 0x203, "Dancer"], 23: ["super_novice", 0x100, "Super Novice"], 24: ["gunslinger", 0x9, "Gunslinger"], 25: ["ninja", 0xA, "Ninja"],
	4001: ["high_novice", 0x1000, "High Novice"], 4002: ["high_swordman", 0x1001, "High Swordman"], 4003: ["high_mage", 0x1002, "High Mage"],
	4004: ["high_archer", 0x1003, "High Archer"], 4005: ["high_acolyte", 0x1004, "High Acolyte"], 4006: ["high_merchant", 0x1005, "High Merchant"],
	4007: ["high_thief", 0x1006, "High Thief"], 4008: ["lord_knight", 0x1101, "Lord Knight"], 4009: ["high_priest", 0x1104, "High Priest"],
	4010: ["high_wizard", 0x1102, "High Wizard"], 4011: ["whitesmith", 0x1105, "Whitesmith"], 4012: ["sniper", 0x1103, "Sniper"],
	4013: ["assassin_cross", 0x1106, "Assassin Cross"], 4015: ["paladin", 0x1201, "Paladin"], 4016: ["champion", 0x1204, "Champion"],
	4017: ["professor", 0x1202, "Professor"], 4018: ["stalker", 0x1206, "Stalker"], 4019: ["creator", 0x1205, "Creator"],
	4020: ["clown", 0x1203, "Clown"], 4021: ["gypsy", 0x1203, "Gypsy"], 4046: ["taekwon_kid", 0x7, "Taekwon"],
	4047: ["star_gladiator", 0x107, "Star Gladiator"], 4049: ["soul_linker", 0x207, "Soul Linker"],
	# Project Twilight second jobs (no rAthena equivalent; ids outside rAthena's range).
	5001: ["dark_knight", 0x301, "Dark Knight"], 5002: ["shaman", 0x304, "Shaman"],
}

const VALUES := {
	"true": 1, "false": 0, "SKILL_PERM": 0, "SKILL_TEMP": 1, "SKILL_TEMPLEVEL": 2, "SKILL_PERM_GRANT": 3,
	"SEX_FEMALE": 0, "SEX_MALE": 1, "PACKETVER": 20200401,
	"LOOK_BASE": 0, "LOOK_HAIR": 1, "LOOK_WEAPON": 2, "LOOK_HEAD_BOTTOM": 3, "LOOK_HEAD_TOP": 4, "LOOK_HEAD_MID": 5,
	"LOOK_HAIR_COLOR": 6, "LOOK_CLOTHES_COLOR": 7, "LOOK_SHIELD": 8, "LOOK_SHOES": 9, "LOOK_BODY2": 13,
	"EAJL_2_1": 0x100, "EAJL_2_2": 0x200, "EAJL_2": 0x300, "EAJL_UPPER": 0x1000, "EAJL_BABY": 0x2000,
	"EAJL_THIRD": 0x4000, "EAJL_FOURTH": 0x8000,
	"EAJ_BASEMASK": 0xFF, "EAJ_UPPERMASK": 0xFFF, "EAJ_THIRDMASK": 0x4FFF, "EAJ_FOURTHMASK": 0xCFFF,
	"EAJ_NOVICE": 0x0, "EAJ_SWORDMAN": 0x1, "EAJ_MAGE": 0x2, "EAJ_ARCHER": 0x3, "EAJ_ACOLYTE": 0x4, "EAJ_MERCHANT": 0x5,
	"EAJ_THIEF": 0x6, "EAJ_TAEKWON": 0x7, "EAJ_GUNSLINGER": 0x9, "EAJ_NINJA": 0xA, "EAJ_GANGSI": 0xE,
	"EAJ_SUPER_NOVICE": 0x100, "EAJ_KNIGHT": 0x101, "EAJ_WIZARD": 0x102, "EAJ_HUNTER": 0x103, "EAJ_PRIEST": 0x104,
	"EAJ_BLACKSMITH": 0x105, "EAJ_ASSASSIN": 0x106, "EAJ_STAR_GLADIATOR": 0x107, "EAJ_REBELLION": 0x109, "EAJ_KAGEROUOBORO": 0x10A,
	"EAJ_CRUSADER": 0x201, "EAJ_SAGE": 0x202, "EAJ_BARDDANCER": 0x203, "EAJ_MONK": 0x204, "EAJ_ALCHEMIST": 0x205,
	"EAJ_ROGUE": 0x206, "EAJ_SOUL_LINKER": 0x207, "EAJ_NOVICE_HIGH": 0x1000, "EAJ_RUNE_KNIGHT": 0x4101,
	"EAJ_RANGER": 0x4103, "EAJ_MECHANIC": 0x4105, "EAJ_NIGHT_WATCH": 0x8109,
	"Job_Novice": 0, "Job_Swordman": 1, "Job_Mage": 2, "Job_Archer": 3, "Job_Acolyte": 4, "Job_Merchant": 5, "Job_Thief": 6,
	"Job_Knight": 7, "Job_Priest": 8, "Job_Wizard": 9, "Job_Blacksmith": 10, "Job_Hunter": 11, "Job_Assassin": 12,
	"Job_Knight2": 13, "Job_Crusader": 14, "Job_Monk": 15, "Job_Sage": 16, "Job_Rogue": 17, "Job_Alchemist": 18,
	"Job_Bard": 19, "Job_Dancer": 20, "Job_Crusader2": 21, "Job_Wedding": 22, "Job_Super_Novice": 23, "Job_SuperNovice": 23,
	"Job_Gunslinger": 24, "Job_Ninja": 25, "Job_Novice_High": 4001, "Job_Swordman_High": 4002, "Job_Mage_High": 4003,
	"Job_Archer_High": 4004, "Job_Acolyte_High": 4005, "Job_Merchant_High": 4006, "Job_Thief_High": 4007,
	"Job_Lord_Knight": 4008, "Job_High_Priest": 4009, "Job_High_Wizard": 4010, "Job_Whitesmith": 4011, "Job_Sniper": 4012,
	"Job_Assassin_Cross": 4013, "Job_Paladin": 4015, "Job_Champion": 4016, "Job_Professor": 4017, "Job_Stalker": 4018,
	"Job_Creator": 4019, "Job_Clown": 4020, "Job_Gypsy": 4021, "Job_Taekwon": 4046, "Job_Star_Gladiator": 4047,
	"Job_Soul_Linker": 4049, "Job_Dark_Knight": 5001, "Job_Shaman": 5002,
	"Option_Falcon": 0x10, "Option_Riding": 0x20, "Option_Cart": 0x8,
}


## Unknown job / class constants (third and fourth classes, summoners...)
## resolve to a value no Pre-Renewal class has, so comparisons stay false.
const UNKNOWN_CLASS := -0x7FFF0000


static func has(name: String) -> bool:
	return VALUES.has(name) or name.begins_with("EAJ_") or name.begins_with("EAJL_") or name.begins_with("Job_")


static func value(name: String) -> int:
	return int(VALUES.get(name, UNKNOWN_CLASS))


## rAthena Class id for a Project Twilight job id (-1 if none).
static func class_of(job: String) -> int:
	for id in CLASSES:
		if CLASSES[id][0] == job:
			return int(id)
	return -1


static func job_of(class_id: int) -> String:
	return String(CLASSES.get(class_id, ["", 0, ""])[0])


static func eaclass_of(class_id: int) -> int:
	return int(CLASSES.get(class_id, ["", -1, ""])[1])


## roclass(eac, sex): first class id with that EA code (Bard/Dancer by sex).
static func roclass(eac: int, male := true) -> int:
	if eac == 0x203:
		return 19 if male else 20
	if eac == 0x1203:
		return 4020 if male else 4021
	for id in CLASSES:
		if int(CLASSES[id][1]) == eac:
			return int(id)
	return -1


static func class_name_of(class_id: int) -> String:
	return String(CLASSES.get(class_id, ["", 0, "Unknown"])[2])
