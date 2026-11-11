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


## Pre-Renewal weight limit: 2000 + STR * 30 (+ job bonus; Novice 0). High confidence.
func max_weight() -> int:
	return 2000 + int(stats.str) * 30


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
		"is_player": is_player(), "can_crit": is_player(),
	}
