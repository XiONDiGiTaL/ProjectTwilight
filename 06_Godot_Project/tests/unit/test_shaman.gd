extends RefCounted
## Shaman: advancement (female only), weapons, support, buffs, spirits, persistence.
## "Multiplayer" cases run two players inside one authoritative FieldSimulation
## (the same code a co-op host or server runs); there is no network transport yet.


static func _gat(w := 40, h := 40) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


static func _shaman(sim: FieldSimulation, advance := true, female := true) -> SimUnit:
	var p := sim.add_player("Aelin", Vector2i(10, 10), {"str": 5, "agi": 10, "vit": 20, "int": 60, "dex": 40, "luk": 10})
	p.male = not female
	p.level = 60
	p.job_level = 10
	p.skills.NV_BASIC = 9
	sim.command_job_change(p.id, "acolyte")
	p.job_level = 40
	if advance:
		sim.command_job_change(p.id, "shaman")
	p.skill_points = 200
	p.max_sp = 2000
	p.sp = 2000
	return p


static func _ally(sim: FieldSimulation, cell := Vector2i(12, 10)) -> SimUnit:
	var a := sim.add_player("Ally", cell, {"str": 20, "agi": 10, "vit": 20, "int": 5, "dex": 10, "luk": 5})
	return a


static func _dummy(sim: FieldSimulation, cell: Vector2i, hp := 100000) -> SimUnit:
	var m := sim.add_monster("1002", cell)
	m.walker.walk_speed = 1e9
	m.max_hp = hp
	m.hp = hp
	m.stats.int = 0
	m.stats.vit = 0
	m.stats.str = 0
	m.mdef = 0
	m.element = "neutral"
	return m


static func _cast_to_end(sim: FieldSimulation, p: SimUnit) -> void:
	for i in 200:
		if not p.is_casting():
			return
		sim.tick(50.0)


func test_advancement_female_only(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 51)
	var man := _shaman(sim, false, false)
	if sim.command_job_change(man.id, "shaman"):
		return "a male Acolyte became a Shaman"
	var woman := _shaman(sim, false, true)
	if not sim.command_job_change(woman.id, "shaman"):
		return "female Acolyte could not advance: %s" % sim.job_change_unmet(woman, "shaman")
	var avail := sim.available_skills(woman)
	return true if avail.has("SH_DIVINE") and avail.has("NV_FIRSTAID") else "skill list wrong"


func test_weapons(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 52)
	var p := _shaman(sim)
	for id in [1501, 1601, 1550]:
		p.inventory.add(id, 1, sim.item_db, 99999)
		sim.command_equip(p.id, p.inventory.entries.size() - 1)
		if int(p.equipment.get("weapon", 0)) != id:
			return "Shaman could not equip %d" % id
	p.inventory.add(1116, 1, sim.item_db, 99999)
	sim.command_equip(p.id, p.inventory.entries.size() - 1)
	return true if int(p.equipment.get("weapon", 0)) != 1116 else "Shaman equipped a two-handed sword"


func test_auto_heal_sp_regen(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 53)
	var a := _shaman(sim)
	var b := _shaman(sim)
	a.skills.SH_AUTOHEAL = 10
	b.skills.SH_AUTOHEAL = 0
	a.sp = 0
	b.sp = 0
	sim.tick(9000.0)
	return true if a.sp > b.sp else "auto heal gave no extra SP (%d vs %d)" % [a.sp, b.sp]


func test_comfort_and_blessing(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 54)
	var p := _shaman(sim)
	var ally := _ally(sim)
	p.skills.SH_COMFORT = 10
	p.skills.SH_BLESSING = 10
	ally.hp = 1
	sim.command_use_skill(p.id, "SH_COMFORT", ally.id)
	var heal := FieldSimulation.heal_amount_for(p.level, int(p.stats.int), 10)
	if ally.hp != mini(ally.max_hp, 1 + heal):
		return "heal %d, expected %d" % [ally.hp - 1, heal]
	if sim.command_use_skill(p.id, "SH_BLESSING", 0):
		return "blessing targeted the caster"
	ally.max_sp = 500
	ally.sp = 0
	p.skill_delay = 0
	sim.command_use_skill(p.id, "SH_BLESSING", ally.id)
	if ally.sp != 80 + int(p.stats.int) / 2:
		return "blessing restored %d SP" % ally.sp
	var far := _ally(sim, Vector2i(35, 35))
	p.skill_delay = 0
	return true if not sim.command_use_skill(p.id, "SH_COMFORT", far.id) else "healed out of range"


func test_protection_and_wrath(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 55)
	var p := _shaman(sim)
	var ally := _ally(sim)
	p.skills.SH_PROTECTION = 10
	p.skills.SH_WRATH = 10
	var def0 := ally.hard_def
	sim.command_use_skill(p.id, "SH_PROTECTION", ally.id)
	if ally.hard_def != def0 + 20 or ally.mdef != 20:
		return "protection should add 20 DEF/MDEF: %d %d" % [ally.hard_def, ally.mdef]
	var matk0 := p.matk()
	p.skill_delay = 0
	sim.command_use_skill(p.id, "SH_WRATH", 0)
	var matk1 := p.matk()
	if matk1.y != matk0.y * 130 / 100:
		return "wrath 10 should give +30%% MATK: %s -> %s" % [matk0, matk1]
	sim.tick(121000.0)
	return true if not ally.has_status("protection") and p.matk() == matk0 else "buffs did not expire"


func test_prayer_resurrection(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 56)
	var p := _shaman(sim)
	var ally := _ally(sim)
	p.skills.SH_PRAYER = 5
	if sim.command_use_skill(p.id, "SH_PRAYER", ally.id):
		return "resurrected a living player"
	sim._kill(ally, p)
	sim.command_use_skill(p.id, "SH_PRAYER", ally.id)
	if not p.is_casting():
		return "prayer should cast"
	_cast_to_end(sim, p)
	if ally.dead or ally.hp != ally.max_hp * 90 / 100:
		return "ally should revive with 90%% HP: dead=%s hp=%d/%d" % [ally.dead, ally.hp, ally.max_hp]
	return true if ally.walker.cell == Vector2i(12, 10) else "revived away from where they fell"


func test_mistletoe_enchant(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 57)
	var p := _shaman(sim)
	var ally := _ally(sim)
	p.skills.SH_MISTLETOE = 10
	if sim.command_use_skill(p.id, "SH_MISTLETOE", ally.id):
		return "enchanted a bare-handed ally"
	ally.job = "swordman"
	sim._recalc_player(ally)
	ally.inventory.add(1201, 1, sim.item_db, 99999)
	sim.command_equip(ally.id, ally.inventory.entries.size() - 1)
	p.skill_delay = 0
	sim.command_use_skill(p.id, "SH_MISTLETOE", ally.id)
	return true if ally.weapon_element() == "ghost" else "mistletoe did not set ghost element"


func test_rain_dance_and_southeast_wind(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 58)
	var p := _shaman(sim)
	p.skills.SH_RAINDANCE = 10
	p.skills.SH_SEWIND = 10
	sim.command_use_skill(p.id, "SH_RAINDANCE")
	p.skill_delay = 0
	sim.command_use_skill(p.id, "SH_SEWIND")
	if sim._element_bonus(p, "water") != 20 or sim._element_bonus(p, "wind") != 20:
		return "element bonuses wrong"
	return true if sim._element_bonus(p, "fire") == 0 else "rain dance boosted fire"


func test_spirits_damage_and_status(_t) -> Variant:
	var cases := [["SH_SUMMON", ""], ["SH_SPIRITFIRE", "confusion"], ["SH_SPIRITEARTH", "stone"],
		["SH_SPIRITWATER", "silence"], ["SH_SPIRITWIND", "sleep"]]
	for c in cases:
		var sim := FieldSimulation.new(_gat(), 59)
		var p := _shaman(sim)
		p.skills[c[0]] = 10
		var inflicted := false
		var m := _dummy(sim, Vector2i(14, 10))
		for i in 40:
			m.statuses.clear()
			p.sp = 2000
			p.skill_delay = 0
			var hp := m.hp
			if not sim.command_use_skill(p.id, c[0], m.id):
				return "%s refused" % c[0]
			_cast_to_end(sim, p)
			if m.hp >= hp:
				return "%s dealt no damage" % c[0]
			if c[1] != "" and m.has_status(c[1]):
				inflicted = true
				break
		if c[1] != "" and not inflicted:
			return "%s never inflicted %s" % [c[0], c[1]]
	return true


func test_divine_judgment_area(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 60)
	var p := _shaman(sim)
	p.skills.SH_DIVINE = 10
	var t := _dummy(sim, Vector2i(15, 10))
	var side := _dummy(sim, Vector2i(16, 12))
	var far := _dummy(sim, Vector2i(25, 25))
	sim.command_use_skill(p.id, "SH_DIVINE", t.id)
	_cast_to_end(sim, p)
	if t.hp == t.max_hp or side.hp == side.max_hp:
		return "divine judgment missed its area"
	return true if far.hp == far.max_hp else "divine judgment hit outside its area"


func test_silenced_cannot_cast(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 61)
	var p := _shaman(sim)
	p.skills.SH_COMFORT = 1
	sim.apply_status(p, "silence", 5000.0)
	return true if not sim.command_use_skill(p.id, "SH_COMFORT") else "silenced player healed"


func test_save_roundtrip(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 62)
	var p := _shaman(sim)
	p.skills.SH_COMFORT = 7
	var item_db := FieldSimulation._load_json(FieldSimulation.ITEM_DB)
	var r := SaveGame.validate(JSON.parse_string(JSON.stringify(SaveGame.capture(p, "prontera"))), item_db, ClassInsignia.classes())
	var q := FieldSimulation.new(_gat(), 63).add_player_from_save(r.character)
	return true if q.job == "shaman" and int(q.skills.get("SH_COMFORT", 0)) == 7 and not q.male else "shaman not restored"
