class_name SimUnit
extends RefCounted
## One player or monster inside a FieldSimulation. Plain data plus a walker.

enum Kind { PLAYER, MONSTER }

var id := 0
var kind := Kind.MONSTER
var mob_id := ""          # monster database key
var name := ""
var sprite := ""          # sprite base name (monsters) or job sprite (players)
var job := "novice"       # class id in data/prerenewal/classes.json (players)
var male := true          # appearance (players)
var hair_style := 2
var hair_color := 0
var level := 1
var job_level := 1
var stats := {"str": 1, "agi": 1, "vit": 1, "int": 1, "dex": 1, "luk": 1}
var hp := 1
var max_hp := 1
var sp := 0
var max_sp := 0
var base_exp := 0
var job_exp := 0
var status_points := 0
var atk_min := 1
var atk_max := 1
var hard_def := 0
var attack_range := 1
var attack_interval := 1000.0  # ms between attacks
var attack_motion := 500.0     # ms of the attack animation
var walker: GridWalker

# AI / combat state
var target_id := 0
var attack_cooldown := 0.0
var dead := false
var respawn_in := 0.0          # ms until respawn (monsters) / revive (players)
var spawn_cell := Vector2i.ZERO
var spawn_radius := 0
var idle_timer := 0.0
var damaged_by := {}           # attacker id -> total damage (for EXP credit)
var data: Dictionary = {}      # raw database entry
var inventory := Inventory.new()
var zeny := 0
var pickup_target := 0         # ground item id being walked to
var talk_target := 0           # NPC id being walked to
var open_shop := 0             # NPC id whose shop is open (server-side check for trades)
## Equipped items: slot -> item id. Slots: weapon, shield, body, garment, shoes, acc1, acc2, head_top, head_mid, head_low.
var equipment: Dictionary = {}
var batk := 1                  # status ATK (players)
var watk_min := 0
var watk_max := 0
var weapon_type := "fist"
var size := "medium"
## Skills: code (e.g. "NV_BASIC") -> learned level.
var skills: Dictionary = {}
var skill_points := 0
var skill_delay := 0.0         # ms until another skill may be used (after-cast delay)
var sitting := false
var trickdead := false         # Play Dead active
var warping := false           # stepped on a warp; the scene is changing maps
var hp_regen_t := 0.0
var sp_regen_t := 0.0
## Hotkey bar (9 slots): null or {"type": "item"|"skill", "id": int|String}. Saved per character.
var hotkeys: Array = [null, null, null, null, null, null, null, null, null]
var weight_bonus := 0          # class weight bonus (Swordman +800, ...)
var mastery_atk := 0           # weapon-mastery ATK (added after DEF)
var queued_skill := ""         # targeted skill to use when the target is in range
var recovery_t := 0.0          # Increase HP Recovery timer
var element := "neutral"       # defence element (players: neutral 1 until armours add one)
var element_level := 1
var mdef := 0                  # hard MDEF (percent reduction)
var aura := "class"            # cosmetic player aura style (see PlayerAura.STYLES)
# Casting (Pre-Renewal cast time; moving or taking damage interrupts).
var cast_skill := ""
var cast_level := 0
var cast_target := 0
var cast_total := 0.0          # ms
var cast_left := 0.0           # ms


func is_casting() -> bool:
	return cast_skill != ""


func matk() -> Vector2i:
	return ElementRulesPreRenewal.matk_range(int(stats.int))


## Pre-Renewal weight limit: 2000 + STR * 30 (+ job bonus; Novice 0). High confidence.
func max_weight() -> int:
	return 2000 + int(stats.str) * 30 + weight_bonus


## Weight of equipped items (they still count toward the carry limit).
func equipment_weight(db: Dictionary) -> int:
	var w := 0
	for slot in equipment:
		w += int(db.get(str(equipment[slot]), {}).get("weight", 0))
	return w


func is_player() -> bool:
	return kind == Kind.PLAYER


func cell() -> Vector2i:
	return walker.cell


func hit() -> int:
	return level + int(stats.dex)


func flee() -> int:
	return level + int(stats.agi)


## Snapshot used by CombatRulesPreRenewal.resolve_attack.
func combat_profile() -> Dictionary:
	return {
		"hit": hit(), "flee": flee(), "luk": int(stats.luk), "vit": int(stats.vit),
		"atk_min": atk_min, "atk_max": atk_max, "def": hard_def,
		"is_player": is_player(), "can_crit": is_player(), "size": size,
		"int": int(stats.int), "mdef": mdef, "element": element, "element_level": element_level,
	} if not is_player() else {
		"hit": hit(), "flee": flee(), "luk": int(stats.luk), "vit": int(stats.vit),
		"atk_min": atk_min, "atk_max": atk_max, "def": hard_def,
		"is_player": true, "can_crit": true, "size": size,
		"batk": batk, "watk_min": watk_min, "watk_max": watk_max, "weapon_type": weapon_type,
		"mastery": mastery_atk,
		"int": int(stats.int), "mdef": mdef, "element": element, "element_level": element_level,
	}
