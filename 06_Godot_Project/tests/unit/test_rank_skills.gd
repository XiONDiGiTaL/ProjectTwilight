extends RefCounted
## Every canonical second job and transcendent class has a dedicated two-skill
## tree, and representative physical, magic and healing skills execute.

const SECOND_JOBS := [
	"knight", "crusader", "wizard", "sage", "hunter", "bard", "dancer",
	"priest", "monk", "blacksmith", "alchemist", "assassin", "rogue",
]
const TRANSCENDENT_JOBS := [
	"lord_knight", "paladin", "high_wizard", "professor", "sniper", "clown",
	"gypsy", "high_priest", "champion", "whitesmith", "creator",
	"assassin_cross", "stalker",
]
const CUSTOM_TRANSCENDENT := ["dread_knight", "oracle"]


static func _gat(w := 40, h := 40) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


static func _dummy(sim: FieldSimulation, cell: Vector2i, hp := 100000) -> SimUnit:
	var m := sim.add_monster("1002", cell)
	m.walker.walk_speed = 1e9
	m.max_hp = hp
	m.hp = hp
	m.stats.vit = 0
	m.stats.int = 0
	m.stats.agi = 0
	return m


static func _cast_to_end(sim: FieldSimulation, p: SimUnit) -> void:
	for i in 200:
		if not p.is_casting():
			return
		sim.tick(50.0)


func test_every_rank_has_own_skills(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 61)
	for id in SECOND_JOBS + TRANSCENDENT_JOBS + CUSTOM_TRANSCENDENT:
		var job: Dictionary = sim.job_db.get(id, {})
		if job.is_empty():
			return "missing job %s" % id
		var codes: Array = job.get("skills", [])
		if codes.size() < 2:
			return "%s has %d dedicated skills" % [id, codes.size()]
		var p := sim.add_player("Tester", Vector2i(10, 10), {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5})
		p.job = id
		p.skill_points = 20
		var available := sim.available_skills(p)
		for code in codes:
			var s: Dictionary = sim.skill_db.get(code, {})
			if s.is_empty():
				return "%s lists missing skill %s" % [id, code]
			if String(s.get("job", "")) != id:
				return "%s skill %s belongs to %s" % [id, code, s.get("job")]
			if int(s.get("max_level", 0)) < 1 or int(s.get("sp_cost", []).size()) < int(s.max_level):
				return "%s skill %s has incomplete level data" % [id, code]
			if String(s.get("desc", "")).strip_edges() == "":
				return "%s skill %s has no description" % [id, code]
			if not available.has(code):
				return "%s does not expose %s" % [id, code]
			if not sim.command_learn_skill(p.id, code):
				return "%s cannot learn %s: %s" % [id, code, sim.skill_requirements_unmet(p, code)]
			if String(s.get("type", "")) != "active":
				return "%s skill %s should be active" % [id, code]
			if s.has("effect"):
				if not (String(s.effect) in ["heal", "sp", "buff", "resurrect"]):
					return "%s skill %s has unsupported effect %s" % [id, code, s.effect]
			elif not (bool(s.get("physical", false)) or bool(s.get("magic", false))):
				return "%s skill %s has no damage or support effect" % [id, code]
			if not (String(s.get("target", "")) in ["enemy", "ally", "self", "self_area", "dead_ally"]):
				return "%s skill %s has no supported target" % [id, code]
	return true


func test_representative_skills_execute(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 62)
	var knight := sim.add_player("Knight", Vector2i(10, 10), {"str": 60, "agi": 20, "vit": 30, "int": 5, "dex": 20, "luk": 10})
	knight.job = "knight"
	knight.level = 99
	knight.max_sp = 2000
	knight.sp = 2000
	knight.skills["KN_SPEARSTAB"] = 10
	var target := _dummy(sim, Vector2i(11, 10))
	var hp := target.hp
	if not sim.command_use_skill(knight.id, "KN_SPEARSTAB", target.id):
		return "spear stab was rejected"
	sim._attack(knight, target)
	if target.hp >= hp or not sim.drain_events().any(func(e): return e.type == "skill" and e.skill == "KN_SPEARSTAB"):
		return "spear stab did not deal damage"

	var wizard := sim.add_player("Wizard", Vector2i(10, 20), {"str": 5, "agi": 10, "vit": 20, "int": 60, "dex": 30, "luk": 5})
	wizard.job = "wizard"
	wizard.level = 99
	wizard.max_sp = 2000
	wizard.sp = 2000
	wizard.skills["WZ_FROSTNOVA"] = 10
	var frost_target := _dummy(sim, Vector2i(12, 20))
	var frost_hp := frost_target.hp
	if not sim.command_use_skill(wizard.id, "WZ_FROSTNOVA", frost_target.id):
		return "frost nova was rejected"
	_cast_to_end(sim, wizard)
	if frost_target.hp >= frost_hp or not sim.drain_events().any(func(e): return e.type == "magic" and e.skill == "WZ_FROSTNOVA"):
		return "frost nova did not deal magic damage"

	var priest := sim.add_player("Priest", Vector2i(10, 30), {"str": 5, "agi": 5, "vit": 20, "int": 40, "dex": 20, "luk": 5})
	priest.job = "priest"
	priest.level = 99
	priest.max_sp = 2000
	priest.sp = 2000
	priest.skills["PR_HEAL"] = 10
	var ally := sim.add_player("Ally", Vector2i(10, 32), {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5})
	ally.hp = 1
	if not sim.command_use_skill(priest.id, "PR_HEAL", ally.id):
		return "heal was rejected"
	_cast_to_end(sim, priest)
	if ally.hp <= 1:
		return "heal restored no HP"
	return true
