extends RefCounted
## Bow, instrument and whip weapons: data, class permissions, range and skill gates.

const BOW := 1701
const ARROW := 1750
const INSTRUMENT := 1901
const WHIP := 1951


static func _gat(w := 40, h := 40) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


static func _player(sim: FieldSimulation, job: String, cell: Vector2i) -> SimUnit:
	var p := sim.add_player("Tester", cell, {"str": 20, "agi": 10, "vit": 20, "int": 20, "dex": 20, "luk": 10})
	p.job = job
	p.level = 40
	p.max_sp = 2000
	p.sp = 2000
	return p


static func _equip(sim: FieldSimulation, p: SimUnit, item_id: int) -> bool:
	p.inventory.add(item_id, 1, sim.item_db, 99999)
	return sim.command_equip(p.id, p.inventory.entries.size() - 1)


static func _dummy(sim: FieldSimulation, cell: Vector2i) -> SimUnit:
	var m := sim.add_monster("1002", cell)
	m.walker.walk_speed = 1e9
	m.max_hp = 100000
	m.hp = m.max_hp
	m.stats.vit = 0
	m.stats.int = 0
	m.stats.agi = 0
	return m


func test_weapon_data_and_permissions(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 81)
	for id in [BOW, 1702, 1703, INSTRUMENT, 1902, WHIP, 1952]:
		var def: Dictionary = sim.item_db.get(str(id), {})
		if def.is_empty() or String(def.get("equip", "")) != "weapon":
			return "missing weapon %d" % id
		if int(def.get("atk", 0)) <= 0 or int(def.get("weapon_level", 0)) <= 0:
			return "weapon %d has no attack data" % id
		if not (String(def.weapon_type) in ["bow", "instrument", "whip"]):
			return "weapon %d has the wrong type" % id
		if int(def.get("range", 0)) <= 0 or not bool(def.get("two_handed", false)):
			return "weapon %d needs an attack range and two-handed flag" % id
	for id in [BOW, INSTRUMENT, WHIP]:
		if not sim.shop_db.get("prontera_weapon_dealer", {}).get("items", []).has(id):
			return "%d is not sold by the Prontera weapon dealer" % id

	var archer := _player(sim, "archer", Vector2i(10, 10))
	if not _equip(sim, archer, BOW):
		return "Archer could not equip a bow"
	archer.inventory.add(2101, 1, sim.item_db, 99999)
	if sim.command_equip(archer.id, archer.inventory.entries.size() - 1):
		return "A two-handed bow allowed a shield"
	if _equip(sim, archer, INSTRUMENT):
		return "Archer equipped an instrument"
	if _equip(sim, archer, WHIP):
		return "Archer equipped a whip"

	var bard := _player(sim, "bard", Vector2i(10, 20))
	if not _equip(sim, bard, INSTRUMENT):
		return "Bard could not equip an instrument"
	if _equip(sim, bard, BOW):
		return "Bard equipped a bow"

	var dancer := _player(sim, "dancer", Vector2i(10, 30))
	if not _equip(sim, dancer, WHIP):
		return "Dancer could not equip a whip"
	if _equip(sim, dancer, BOW):
		return "Dancer equipped a bow"
	if _equip(sim, dancer, INSTRUMENT):
		return "Dancer equipped an instrument"
	return true


func test_ranges_and_skill_requirements(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 82)
	var archer := _player(sim, "archer", Vector2i(10, 10))
	archer.skills["AC_DOUBLESTRAFE"] = 10
	var target := _dummy(sim, Vector2i(15, 10))
	if sim.command_use_skill(archer.id, "AC_DOUBLESTRAFE", target.id):
		return "Double Strafe worked without a bow"
	if not _equip(sim, archer, BOW):
		return "Archer could not equip a bow"
	if archer.attack_range != 9:
		return "bow should give attack range 9, got %d" % archer.attack_range
	archer.inventory.add(ARROW, 2, sim.item_db, 99999)
	if not sim.command_use_skill(archer.id, "AC_DOUBLESTRAFE", target.id):
		return "Double Strafe was rejected with a bow"
	var hp := target.hp
	sim._attack(archer, target)
	if target.hp >= hp:
		return "Double Strafe dealt no damage with a bow"

	var bard := _player(sim, "bard", Vector2i(10, 20))
	bard.skills["BA_DISSONANCE"] = 10
	if sim.command_use_skill(bard.id, "BA_DISSONANCE", target.id):
		return "Bard skill worked without an instrument"
	if not _equip(sim, bard, INSTRUMENT):
		return "Bard could not equip an instrument"
	if bard.attack_range != 2:
		return "instrument should give attack range 2, got %d" % bard.attack_range
	if not sim.command_use_skill(bard.id, "BA_DISSONANCE", target.id):
		return "Bard skill was rejected with an instrument"

	var dancer := _player(sim, "dancer", Vector2i(10, 30))
	dancer.skills["DC_SLINGARROW"] = 10
	if sim.command_use_skill(dancer.id, "DC_SLINGARROW", target.id):
		return "Dancer skill worked without a whip"
	if not _equip(sim, dancer, WHIP):
		return "Dancer could not equip a whip"
	if dancer.attack_range != 2:
		return "whip should give attack range 2, got %d" % dancer.attack_range
	return true if sim.command_use_skill(dancer.id, "DC_SLINGARROW", target.id) else "Dancer skill was rejected with a whip"
