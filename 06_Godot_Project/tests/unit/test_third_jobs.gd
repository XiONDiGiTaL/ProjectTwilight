extends RefCounted
## Full progression: every first job reaches a canonical second job, a
## transcendent class and a third job. The Dark Knight and Shaman lines keep
## their own custom continuations (Dread Knight / Abyss Knight and Oracle /
## Spirit Sage) so their ids do not collide with canonical Lord Knight /
## High Priest.

const FLAT := {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5}
const CANONICAL_PATHS := [
	{"first": "swordman", "second": "knight", "transcendent": "lord_knight", "third": "rune_knight"},
	{"first": "swordman", "second": "crusader", "transcendent": "paladin", "third": "royal_guard"},
	{"first": "mage", "second": "wizard", "transcendent": "high_wizard", "third": "warlock"},
	{"first": "mage", "second": "sage", "transcendent": "professor", "third": "sorcerer"},
	{"first": "archer", "second": "hunter", "transcendent": "sniper", "third": "ranger"},
	{"first": "archer", "second": "bard", "transcendent": "clown", "third": "minstrel"},
	{"first": "archer", "second": "dancer", "transcendent": "gypsy", "third": "wanderer"},
	{"first": "acolyte", "second": "priest", "transcendent": "high_priest", "third": "arch_bishop"},
	{"first": "acolyte", "second": "monk", "transcendent": "champion", "third": "sura"},
	{"first": "merchant", "second": "blacksmith", "transcendent": "whitesmith", "third": "mechanic"},
	{"first": "merchant", "second": "alchemist", "transcendent": "creator", "third": "genetic"},
	{"first": "thief", "second": "assassin", "transcendent": "assassin_cross", "third": "guillotine_cross"},
	{"first": "thief", "second": "rogue", "transcendent": "stalker", "third": "shadow_chaser"},
]
const CUSTOM_PATHS := [
	{"first": "dark_knight", "transcendent": "dread_knight", "third": "abyss_knight"},
	{"first": "shaman", "transcendent": "oracle", "third": "spirit_sage"},
]


static func _open_gat(w := 40, h := 40) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


static func _sim() -> FieldSimulation:
	return FieldSimulation.new(_open_gat(), 31, RuleConfig.new())


func _assert_third_data(sim: FieldSimulation, id: String) -> String:
	if not sim.job_db.has(id):
		return "missing third job %s" % id
	var j: Dictionary = sim.job_db[id]
	if int(j.tier) != 4 or int(j.max_job_level) != 70 or int(j.max_base_level) != 150:
		return "%s caps/tier wrong: %s" % [id, str(j)]
	if String(j.job_table) != "job_third":
		return "%s should use job_third" % id
	if not sim.job_db.has(String(j.parent)) or int(sim.job_db[String(j.parent)].tier) != 3:
		return "%s should have a transcendent parent" % id
	if not ClassInsignia.classes().has(id):
		return "%s missing from classes.json" % id
	if int(ClassInsignia.classes()[id].get("max_base_level", 99)) != 150:
		return "%s class registry should allow base level 150" % id
	if (j.skills as Array).size() < 2:
		return "%s should have its own skill tree" % id
	for code in j.skills:
		if not sim.skill_db.has(code):
			return "%s lists missing skill %s" % [id, code]
		if String(sim.skill_db[code].get("job", "")) != id:
			return "%s skill %s belongs to another job" % [id, code]
	return ""


func test_all_third_job_data(_t) -> Variant:
	var sim := _sim()
	if sim.exp_tables.base_normal.size() != 149:
		return "base EXP table should cover levels 1-150 (%d entries)" % sim.exp_tables.base_normal.size()
	if sim.exp_tables.job_third.size() != 69:
		return "job_third table should cover job levels 1-70 (%d entries)" % sim.exp_tables.job_third.size()
	for path in CANONICAL_PATHS:
		for id in [path.second, path.transcendent, path.third]:
			if not sim.job_db.has(id):
				return "missing job %s" % id
		var err := _assert_third_data(sim, String(path.third))
		if err != "":
			return err
	for path in CUSTOM_PATHS:
		var err := _assert_third_data(sim, String(path.third))
		if err != "":
			return err
	return true


func _walk_path(sim: FieldSimulation, first: String, second: String, transcendent: String, third: String, female: bool) -> String:
	var p := sim.add_player("Walker", Vector2i(10, 10), FLAT)
	p.male = not female
	p.job = first
	p.sprite = String(sim.job_db[first].sprite)
	p.level = 99
	p.job_level = 40
	if second != "" and not sim.command_job_change(p.id, second):
		return "cannot become %s: %s" % [second, sim.job_change_unmet(p, second)]
	p.job_level = 50
	if not sim.command_job_change(p.id, transcendent):
		return "cannot transcend to %s: %s" % [transcendent, sim.job_change_unmet(p, transcendent)]
	p.job_level = 70
	if not sim.command_job_change(p.id, third):
		return "cannot take third job %s: %s" % [third, sim.job_change_unmet(p, third)]
	if p.job != third or p.job_level != 1 or p.level != 99:
		return "%s changed the wrong fields" % third
	if sim.base_level_cap(p) != 150:
		return "%s base cap should be 150" % third
	return ""


func test_all_canonical_paths_reachable(_t) -> Variant:
	for path in CANONICAL_PATHS:
		var sim := _sim()
		var female := String(path.second) in ["dancer"]
		var err := _walk_path(sim, String(path.first), String(path.second), String(path.transcendent), String(path.third), female)
		if err != "":
			return "%s -> %s: %s" % [path.first, path.third, err]
	return true


func test_custom_lines_reachable(_t) -> Variant:
	var sim := _sim()
	var err := _walk_path(sim, "dark_knight", "", "dread_knight", "abyss_knight", false)
	if err != "":
		return "Dark Knight line: %s" % err
	var dark := sim.units[sim.units.keys()[0]] as SimUnit
	var codes := sim.available_skills(dark)
	for code in ["SM_BASH", "DK_BLOODYCRASH", "AK_ABYSSSTRIKE"]:
		if not codes.has(code):
			return "Abyss Knight chain missing %s" % code
	if sim.job_change_unmet(dark, "rune_knight") == "":
		return "an Abyss Knight must not take the canonical Rune Knight path"

	var shaman_sim := _sim()
	err = _walk_path(shaman_sim, "shaman", "", "oracle", "spirit_sage", true)
	if err != "":
		return "Shaman line: %s" % err
	var sage := shaman_sim.units[shaman_sim.units.keys()[0]] as SimUnit
	codes = shaman_sim.available_skills(sage)
	for code in ["SH_COMFORT", "SH_SPIRITFIRE", "SS_SPIRITSTORM"]:
		if not codes.has(code):
			return "Spirit Sage chain missing %s" % code
	return true


func test_third_job_skill_trees(_t) -> Variant:
	for path in CANONICAL_PATHS:
		var sim := _sim()
		var p := sim.add_player("Tree", Vector2i(10, 10), FLAT)
		p.job = String(path.third)
		p.sprite = String(sim.job_db[p.job].sprite)
		var codes := sim.available_skills(p)
		for code in sim.job_db[p.job].skills:
			if not codes.has(code):
				return "%s tree missing %s" % [p.job, code]
	for path in CUSTOM_PATHS:
		var sim := _sim()
		var p := sim.add_player("Tree", Vector2i(10, 10), FLAT)
		p.job = String(path.third)
		var codes := sim.available_skills(p)
		for code in sim.job_db[p.job].skills:
			if not codes.has(code):
				return "%s tree missing %s" % [p.job, code]
	return true


func test_base_exp_uses_class_cap(_t) -> Variant:
	var rules := RuleConfig.new()
	rules.max_level = 150
	rules.exp_rate = 100
	var sim := FieldSimulation.new(_open_gat(), 32, rules)
	var lower := sim.add_player("Transcendent", Vector2i(10, 10), FLAT)
	lower.job = "lord_knight"
	lower.level = 99
	lower.base_exp = 0
	var threshold := int(sim.exp_tables.base_normal[98])
	sim._gain_exp(lower, threshold, 0)
	if lower.level != 99:
		return "transcendent class levelled past 99"
	if sim.next_base_exp(lower) != 0:
		return "transcendent class should report MAX at 99"
	var third := sim.add_player("Third", Vector2i(11, 10), FLAT)
	third.job = "warlock"
	third.level = 99
	third.base_exp = 0
	sim._gain_exp(third, threshold, 0)
	if third.level != 100:
		return "third job did not level past 99 (level %d)" % third.level
	if sim.next_base_exp(third) <= 0:
		return "third job should have EXP for level 101"
	return true


func test_save_validation_respects_class_caps(_t) -> Variant:
	var sim := _sim()
	var p := sim.add_player("Saver", Vector2i(10, 10), FLAT)
	p.job = "rune_knight"
	p.sprite = String(sim.job_db.rune_knight.sprite)
	p.level = 120
	p.job_level = 70
	var data := SaveGame.capture(p, "prontera")
	var third := SaveGame.validate(JSON.parse_string(JSON.stringify(data)), sim.item_db, ClassInsignia.classes())
	if not third.ok or int(third.character.level) != 120 or String(third.character.job) != "rune_knight":
		return "third-job save should keep base level 120"
	p.job = "lord_knight"
	p.level = 120
	data = SaveGame.capture(p, "prontera")
	var lower := SaveGame.validate(JSON.parse_string(JSON.stringify(data)), sim.item_db, ClassInsignia.classes())
	if not lower.ok or int(lower.character.level) != 99:
		return "non-third save should clamp base level to 99"
	var custom := sim.add_player("Abyss", Vector2i(12, 10), FLAT)
	custom.job = "abyss_knight"
	custom.sprite = String(sim.job_db.abyss_knight.sprite)
	custom.level = 140
	data = SaveGame.capture(custom, "prontera")
	var saved := SaveGame.validate(JSON.parse_string(JSON.stringify(data)), sim.item_db, ClassInsignia.classes())
	return true if saved.ok and int(saved.character.level) == 140 else "custom third-job save should keep level 140"
