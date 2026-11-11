extends RefCounted
## Dark Knight: advancement, weapons, masteries, buffs, skills, persistence.


static func _gat(w := 40, h := 40) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


## A Swordman at job level 40, then (optionally) a Dark Knight with many points.
static func _dk(sim: FieldSimulation, advance := true) -> SimUnit:
	var p := sim.add_player("Umbra", Vector2i(10, 10), {"str": 60, "agi": 30, "vit": 40, "int": 5, "dex": 40, "luk": 20})
	p.level = 60
	p.job_level = 10
	p.skills.NV_BASIC = 9
	sim.command_job_change(p.id, "swordman")
	p.job_level = 40
	if advance:
		sim.command_job_change(p.id, "dark_knight")
	p.skill_points = 200
	p.max_sp = 2000
	p.sp = 2000
	return p


static func _learn(sim: FieldSimulation, p: SimUnit, code: String, levels: int) -> void:
	for i in levels:
		sim.command_learn_skill(p.id, code)


static func _give_weapon(sim: FieldSimulation, p: SimUnit, item_id: int) -> void:
	p.inventory.add(item_id, 1, sim.item_db, 99999)
	sim.command_equip(p.id, p.inventory.entries.size() - 1)


static func _dummy(sim: FieldSimulation, cell: Vector2i, hp := 100000) -> SimUnit:
	var m := sim.add_monster("1002", cell)
	m.walker.walk_speed = 1e9
	m.max_hp = hp
	m.hp = hp
	m.stats.vit = 0
	m.stats.int = 0
	m.stats.agi = 0
	return m


static func _events(sim: FieldSimulation, type: String) -> Array:
	return sim.drain_events().filter(func(e): return e.type == type)


func test_advancement_rules(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 31)
	var p := _dk(sim, false)
	p.job_level = 39
	if sim.command_job_change(p.id, "dark_knight"):
		return "advanced below job level 40"
	p.job_level = 40
	var pts := p.skill_points
	if not sim.command_job_change(p.id, "dark_knight"):
		return "eligible advancement failed: %s" % sim.job_change_unmet(p, "dark_knight")
	if p.job != "dark_knight" or p.job_level != 1 or p.skill_points != pts:
		return "job/points wrong after advancement"
	var avail := sim.available_skills(p)
	for code in ["NV_BASIC", "SM_BASH", "SM_TWOHAND", "DK_HELLIMPACT"]:
		if not avail.has(code):
			return "%s missing from the Dark Knight list" % code
	var mage := sim.add_player("Wrong", Vector2i(12, 12), {"str": 1, "agi": 1, "vit": 1, "int": 1, "dex": 1, "luk": 1})
	mage.job = "mage"
	mage.job_level = 50
	return true if sim.job_change_unmet(mage, "dark_knight") != "" else "a Mage may not become a Dark Knight"


func test_weapon_permissions(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 32)
	var p := _dk(sim)
	for id in [1116, 1301, 1351, 1201]:
		_give_weapon(sim, p, id)
		if int(p.equipment.get("weapon", 0)) != id:
			return "Dark Knight could not equip %d" % id
	_give_weapon(sim, p, 1501)   # Club: maces are not Dark Knight weapons
	if int(p.equipment.get("weapon", 0)) == 1501:
		return "Dark Knight equipped a mace"
	# Two-handed weapons push the shield off.
	_give_weapon(sim, p, 1301)
	p.inventory.add(2101, 1, sim.item_db, 99999)
	sim.command_equip(p.id, p.inventory.entries.size() - 1)
	if not p.equipment.has("shield"):
		return "shield not equipped with a one-handed axe"
	_give_weapon(sim, p, 1351)
	return true if not p.equipment.has("shield") else "two-handed axe kept the shield"


func test_masteries_are_weapon_specific(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 33)
	var p := _dk(sim)
	_learn(sim, p, "SM_SWORD", 5)
	_learn(sim, p, "SM_TWOHAND", 5)
	_learn(sim, p, "DK_AXEMASTERY", 4)
	if int(p.skills.DK_AXEMASTERY) != 4:
		return "axe mastery not learned"
	_give_weapon(sim, p, 1301)
	if p.mastery_atk != 12:
		return "axe mastery 4 should give +12 with an axe, got %d" % p.mastery_atk
	_give_weapon(sim, p, 1351)
	if p.mastery_atk != 12:
		return "axe mastery must apply to two-handed axes"
	_give_weapon(sim, p, 1116)
	if p.mastery_atk != 20:
		return "two-handed sword: only 2H mastery (+20) expected, got %d" % p.mastery_atk
	_give_weapon(sim, p, 1201)
	return true if p.mastery_atk == 20 else "dagger: only sword mastery (+20) expected, got %d" % p.mastery_atk


func test_prerequisites_and_points(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 34)
	var p := _dk(sim)
	if sim.command_learn_skill(p.id, "DK_AXEMASTERY"):
		return "axe mastery learned without its prerequisites"
	if sim.command_learn_skill(p.id, "SH_COMFORT"):
		return "learned another class's skill"
	p.skill_points = 0
	if sim.command_learn_skill(p.id, "DK_BLOODYCRASH"):
		return "learned without skill points"
	p.skill_points = 50
	_learn(sim, p, "DK_DARKWEAPON", 7)
	if int(p.skills.DK_DARKWEAPON) != 5:
		return "exceeded max level"
	return true if not sim.command_use_skill(p.id, "DK_GUILLOTINE", 0) else "used an unlearned skill"


func test_critical_rate_up(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 35)
	var p := _dk(sim)
	p.skills.DK_CRITUP = 10
	sim._recalc_player(p)
	if p.crit_bonus != 100:
		return "crit bonus should be 100 permille, got %d" % p.crit_bonus
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var crits := 0
	var m := _dummy(sim, Vector2i(11, 10))
	var base := CombatRulesPreRenewal.crit_chance_permille(20, int(m.stats.luk))
	for i in 2000:
		if CombatRulesPreRenewal.resolve_attack(p.combat_profile(), m.combat_profile(), rng).crit:
			crits += 1
	var expected := (base + 100) * 2
	return true if absi(crits - expected) < 90 else "crit count %d, expected about %d" % [crits, expected]


func test_auto_counter(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 36)
	var p := _dk(sim)
	p.skills.DK_AUTOCOUNTER = 5
	var m := _dummy(sim, Vector2i(11, 10), 5000)
	m.target_id = p.id
	sim.command_use_skill(p.id, "DK_AUTOCOUNTER")
	if not p.has_status("auto_counter"):
		return "stance not active"
	var hp := p.hp
	sim._attack(m, p)
	var ev := sim.drain_events()
	var countered := ev.any(func(e): return e.type == "counter")
	var crit_on_monster := ev.any(func(e): return e.type == "damage" and e.dst == m.id and e.crit)
	if not countered or not crit_on_monster or p.hp != hp:
		return "melee swing should be blocked and countered with a crit"
	# Ranged attackers are not countered.
	sim.command_use_skill(p.id, "DK_AUTOCOUNTER")
	m.attack_range = 5
	sim._attack(m, p)
	ev = sim.drain_events()
	if ev.any(func(e): return e.type == "counter"):
		return "ranged attack was countered"
	# The window expires.
	p.skill_delay = 0
	sim.command_use_skill(p.id, "DK_AUTOCOUNTER")
	sim.tick(2100.0)
	return true if not p.has_status("auto_counter") else "stance did not expire"


func test_dark_breath_and_quicken_drain(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 37)
	var p := _dk(sim)
	p.skills.DK_DARKBREATH = 10
	p.skills.DK_SHADOWQUICKEN = 10
	var interval := p.attack_interval
	sim.command_use_skill(p.id, "DK_DARKBREATH")
	p.skill_delay = 0
	sim.command_use_skill(p.id, "DK_SHADOWQUICKEN")
	if int(p.combat_profile().atk_pct) != 135:
		return "dark breath 10 should give +35%% ATK, got %s" % p.combat_profile().atk_pct
	if p.attack_interval > interval * 0.71 + 0.01 and p.attack_interval > StatusRules.ASPD_CAP_INTERVAL_MS:
		return "shadow quicken did not cut attack delay (%f -> %f)" % [interval, p.attack_interval]
	if p.attack_interval < StatusRules.ASPD_CAP_INTERVAL_MS:
		return "ASPD cap broken"
	var hp := p.hp
	sim.tick(2000.0)
	var per := StatusRules.drain_amount(p.max_hp, 6)
	if p.hp != hp - 2 * per:
		return "two drains of %d expected: %d -> %d" % [per, hp, p.hp]
	# Near the floor the buffs end instead of killing.
	p.hp = p.max_hp / 10 + 1
	sim.tick(2000.0)
	if p.has_status("dark_breath") or p.has_status("shadow_quicken") or p.hp <= 0:
		return "buffs should end before HP drops below 10%"
	return true if is_equal_approx(p.attack_interval, interval) else "attack delay not restored"


func test_dark_weapon_element(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 38)
	var p := _dk(sim)
	p.skills.DK_DARKWEAPON = 5
	if sim.command_use_skill(p.id, "DK_DARKWEAPON"):
		return "dark weapon worked bare-handed"
	_give_weapon(sim, p, 1116)
	sim.command_use_skill(p.id, "DK_DARKWEAPON")
	if p.weapon_element() != "shadow":
		return "weapon element not shadow"
	_give_weapon(sim, p, 1301)
	if p.has_status("dark_weapon"):
		return "dark weapon survived a weapon change"
	p.skill_delay = 0
	sim.command_use_skill(p.id, "DK_DARKWEAPON")
	sim._kill(p, p)
	return true if not p.has_status("dark_weapon") else "dark weapon survived death"


func test_bloody_crash_lifesteal(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 39)
	var p := _dk(sim)
	p.skills.DK_BLOODYCRASH = 10
	var m := _dummy(sim, Vector2i(11, 10))
	p.hp = 10
	var mhp := m.hp
	sim.command_use_skill(p.id, "DK_BLOODYCRASH", m.id)
	sim._attack(p, m)
	var dealt := mhp - m.hp
	if dealt <= 0:
		return "bloody crash dealt no damage"
	var expected := mini(p.max_hp - 10, maxi(1, dealt * 20 / 100))
	return true if p.hp == 10 + expected else "lifesteal %d, expected %d (dealt %d)" % [p.hp - 10, expected, dealt]


func test_guillotine_axe_and_stun(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 40)
	var p := _dk(sim)
	p.skills.DK_GUILLOTINE = 10
	_give_weapon(sim, p, 1116)
	var m := _dummy(sim, Vector2i(11, 10))
	if sim.command_use_skill(p.id, "DK_GUILLOTINE", m.id):
		return "guillotine accepted with a sword"
	_give_weapon(sim, p, 1351)
	var stuns := 0
	for i in 60:
		m.statuses.clear()
		p.sp = 2000
		p.skill_delay = 0
		sim.command_use_skill(p.id, "DK_GUILLOTINE", m.id)
		sim._attack(p, m)
		if m.has_status("stun"):
			stuns += 1
	if stuns == 0:
		return "no stun in 60 guillotines at 30%"
	m.statuses.clear()
	sim.apply_status(m, "stun", 1000.0)
	var cell := m.walker.cell
	m.target_id = p.id
	sim.tick(500.0)
	return true if m.walker.cell == cell and m.is_incapacitated() else "stunned monster acted"


func test_genocide_chaos_area_status(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 41)
	var p := _dk(sim)
	p.skills.DK_GENOCIDE = 10
	p.skills.DK_CHAOS = 10
	var near := [_dummy(sim, Vector2i(11, 10)), _dummy(sim, Vector2i(12, 12))]
	var far := _dummy(sim, Vector2i(20, 20))
	var blinded := 0
	for i in 20:
		for m in near:
			m.statuses.clear()
		p.sp = 2000
		p.skill_delay = 0
		sim.command_use_skill(p.id, "DK_GENOCIDE")
		for m in near:
			if m.has_status("blind"):
				blinded += 1
	for m in near:
		if m.hp >= m.max_hp:
			return "genocide missed a monster in range"
	if far.hp != far.max_hp:
		return "genocide hit outside its area"
	if blinded == 0:
		return "genocide never blinded"
	var shadow := sim.drain_events().any(func(e): return e.type == "skill_fx" and e.element == "shadow")
	if not shadow:
		return "genocide should be shadow element"
	var confused := 0
	for i in 20:
		for m in near:
			m.statuses.clear()
		p.sp = 2000
		p.skill_delay = 0
		sim.command_use_skill(p.id, "DK_CHAOS")
		for m in near:
			if m.has_status("confusion"):
				confused += 1
	return true if confused > 0 else "chaos never confused"


func test_blind_wave_and_death_blade(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 42)
	var p := _dk(sim)
	p.skills.DK_BLINDWAVE = 10
	p.skills.DK_DEATHBLADE = 10
	_give_weapon(sim, p, 1301)
	var a := _dummy(sim, Vector2i(13, 10))
	var b := _dummy(sim, Vector2i(15, 10))
	if sim.command_use_skill(p.id, "DK_BLINDWAVE", b.id) or sim.command_use_skill(p.id, "DK_DEATHBLADE", a.id):
		return "sword skills accepted with an axe"
	_give_weapon(sim, p, 1116)
	for i in 10:   # each target can miss (95% hit cap); retry until both are struck
		p.sp = 2000
		p.skill_delay = 0
		sim.command_use_skill(p.id, "DK_BLINDWAVE", b.id)
		sim._attack(p, b)
		if a.hp < a.max_hp and b.hp < b.max_hp:
			break
	if a.hp == a.max_hp or b.hp == b.max_hp:
		return "blind wave should pierce both monsters on the line"
	p.skill_delay = 0
	sim.drain_events()
	var c := _dummy(sim, Vector2i(11, 11))
	sim.command_use_skill(p.id, "DK_DEATHBLADE", c.id)
	sim._attack(p, c)
	var dmg: Array = sim.drain_events().filter(func(e): return e.type == "damage" and e.dst == c.id)
	return true if not dmg.is_empty() and int(dmg[0].hits) == 5 else "death blade 10 should report 5 hits: %s" % [dmg]


func test_hell_impact_axe_area(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 43)
	var p := _dk(sim)
	p.skills.DK_HELLIMPACT = 10
	var t := _dummy(sim, Vector2i(11, 10))
	var side := _dummy(sim, Vector2i(12, 12))
	if sim.command_use_skill(p.id, "DK_HELLIMPACT", t.id):
		return "hell impact accepted bare-handed"
	_give_weapon(sim, p, 1351)
	sim.command_use_skill(p.id, "DK_HELLIMPACT", t.id)
	if not p.is_casting():
		return "hell impact should wind up (cast)"
	sim.tick(1100.0)
	if t.hp == t.max_hp or side.hp == side.max_hp:
		return "hell impact should hit the target and its 5x5 area"
	return true


func test_save_roundtrip(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 44)
	var p := _dk(sim)
	p.skills.DK_AXEMASTERY = 3
	p.cloth_color = 12
	var data := SaveGame.capture(p, "prontera")
	var item_db := FieldSimulation._load_json(FieldSimulation.ITEM_DB)
	var r := SaveGame.validate(JSON.parse_string(JSON.stringify(data)), item_db, ClassInsignia.classes())
	if not r.ok or r.character.job != "dark_knight":
		return "dark knight job not restored: %s" % r.get("error", "")
	var sim2 := FieldSimulation.new(_gat(), 45)
	var q := sim2.add_player_from_save(r.character)
	return true if q.job == "dark_knight" and int(q.skills.get("DK_AXEMASTERY", 0)) == 3 and q.cloth_color == 12 and q.skill_points == p.skill_points else "restored dark knight differs"


## Sword and axe specialists reach their top skills without the other family.
func test_branches_are_independent(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 46)
	var sword := _dk(sim)
	for step in [["SM_SWORD", 5], ["SM_TWOHAND", 5], ["DK_BLOODYCRASH", 3], ["DK_CRITUP", 3], ["DK_BLINDWAVE", 5], ["DK_DEATHBLADE", 1]]:
		_learn(sim, sword, step[0], step[1])
		if int(sword.skills.get(step[0], 0)) != step[1]:
			return "sword path blocked at %s: %s" % [step[0], sim.skill_requirements_unmet(sword, step[0])]
	for axe_skill in ["DK_AXEMASTERY", "DK_GUILLOTINE", "DK_HELLIMPACT"]:
		if int(sword.skills.get(axe_skill, 0)) != 0:
			return "sword build was forced into %s" % axe_skill
	var axe := _dk(sim)
	for step in [["SM_SWORD", 3], ["SM_TWOHAND", 3], ["DK_AXEMASTERY", 5], ["DK_BLOODYCRASH", 3], ["DK_GUILLOTINE", 5], ["DK_DARKWEAPON", 5], ["DK_HELLIMPACT", 1]]:
		_learn(sim, axe, step[0], step[1])
		if int(axe.skills.get(step[0], 0)) != step[1]:
			return "axe path blocked at %s: %s" % [step[0], sim.skill_requirements_unmet(axe, step[0])]
	return true if int(axe.skills.get("DK_BLINDWAVE", 0)) == 0 and int(axe.skills.get("DK_CRITUP", 0)) == 0 else "axe build touched sword skills"
