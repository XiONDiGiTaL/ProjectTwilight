extends RefCounted
## Arrows and quivers: stackable ammo, unpacking, carry weight and bow consumption.

const ARROW := 1750
const QUIVER := 1751
const BOW := 1701


static func _gat(w := 40, h := 40) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


static func _player(sim: FieldSimulation, cell: Vector2i) -> SimUnit:
	var p := sim.add_player("Tester", cell, {"str": 5, "agi": 10, "vit": 20, "int": 10, "dex": 20, "luk": 10})
	p.job = "archer"
	p.level = 40
	p.max_sp = 2000
	p.sp = 2000
	return p


static func _carry(sim: FieldSimulation, p: SimUnit) -> int:
	return p.max_weight() - p.equipment_weight(sim.item_db)


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


func test_ammo_data_stacking_and_stock(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 91)
	var arrow: Dictionary = sim.item_db.get(str(ARROW), {})
	if arrow.is_empty() or String(arrow.get("type", "")) != "ammo":
		return "Arrow must be an ammo item"
	if int(arrow.get("weight", 0)) <= 0 or int(arrow.get("price", 0)) <= 0:
		return "Arrow needs a weight and price"
	if not Inventory.is_stackable(arrow):
		return "Arrow must stack"
	var inv := Inventory.new()
	if not inv.add(ARROW, 200, sim.item_db, 500):
		return "Arrows should stack under the weight limit"
	if inv.entries.size() != 1 or inv.count(ARROW) != 200:
		return "Arrow stack is wrong: %s" % str(inv.entries)
	if inv.weight(sim.item_db) != 200:
		return "200 arrows should weigh 200, got %d" % inv.weight(sim.item_db)
	if inv.add(ARROW, 301, sim.item_db, 500):
		return "Arrows exceeded the carry weight"

	var quiver: Dictionary = sim.item_db.get(str(QUIVER), {})
	if quiver.is_empty() or String(quiver.get("type", "")) != "usable":
		return "Quiver must be a usable item"
	if String(quiver.get("use_effect", "")) != "ammo" or int(quiver.get("ammo_item", 0)) != ARROW:
		return "Quiver must unpack into arrows"
	var amount := int(quiver.get("ammo_amount", 0))
	if amount != 100:
		return "Quiver should contain 100 arrows, got %d" % amount
	if int(quiver.get("weight", 0)) != int(arrow.get("weight", 0)) * amount:
		return "Quiver weight must match its 100 arrows"
	if not Inventory.is_stackable(quiver):
		return "Quiver must stack"
	var stock: Array = sim.shop_db.get("prontera_weapon_dealer", {}).get("items", [])
	for id in [ARROW, QUIVER]:
		if not stock.has(id):
			return "%d is not sold by the Prontera weapon dealer" % id
	return true


func test_quiver_unpack_respects_carry_weight(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 92)
	var p := _player(sim, Vector2i(10, 10))
	if not _equip(sim, p, BOW):
		return "Archer could not equip a bow"
	var carry := _carry(sim, p)
	if not p.inventory.add(ARROW, carry - 100, sim.item_db, carry):
		return "Could not fill the inventory with arrows"
	if not p.inventory.add(QUIVER, 1, sim.item_db, carry):
		return "Could not add a quiver at the exact carry limit"
	var qindex := -1
	for i in p.inventory.entries.size():
		if int(p.inventory.entries[i].id) == QUIVER:
			qindex = i
	if qindex < 0:
		return "Quiver was not in the inventory"
	if not sim.command_use_item(p.id, qindex):
		return "Quiver use failed at the exact carry limit"
	if p.inventory.count(QUIVER) != 0:
		return "Quiver was not consumed"
	if p.inventory.count(ARROW) != carry:
		return "Quiver did not unpack 100 arrows"
	if p.inventory.weight(sim.item_db) != carry:
		return "Unpacked arrows should fill the carry limit exactly"
	if p.inventory.add(ARROW, 1, sim.item_db, carry):
		return "Arrow was accepted beyond the carry limit"
	return true


func test_bow_attacks_and_skills_consume_arrows(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 93)
	var p := _player(sim, Vector2i(10, 10))
	if not _equip(sim, p, BOW):
		return "Archer could not equip a bow"
	var target := _dummy(sim, Vector2i(15, 10))
	var hp := target.hp
	sim._attack(p, target)
	if target.hp != hp:
		return "A bow attack dealt damage without arrows"
	if p.inventory.count(ARROW) != 0:
		return "A failed bow attack changed the arrow count"

	var carry := _carry(sim, p)
	if not p.inventory.add(ARROW, 2, sim.item_db, carry):
		return "Could not add arrows"
	hp = target.hp
	sim._attack(p, target)
	if target.hp >= hp:
		return "A bow attack with an arrow dealt no damage"
	if p.inventory.count(ARROW) != 1:
		return "A bow attack did not consume exactly one arrow"
	sim._attack(p, target)
	if p.inventory.count(ARROW) != 0:
		return "The second bow attack did not consume the last arrow"

	p.skills["AC_DOUBLESTRAFE"] = 10
	if sim.command_use_skill(p.id, "AC_DOUBLESTRAFE", target.id):
		return "Double Strafe was accepted without arrows"

	if not p.inventory.add(ARROW, 1, sim.item_db, carry):
		return "Could not add an arrow for Double Strafe"
	if not sim.command_use_skill(p.id, "AC_DOUBLESTRAFE", target.id):
		return "Double Strafe could not be queued with an arrow"
	for i in p.inventory.entries.size():
		if int(p.inventory.entries[i].id) == ARROW:
			p.inventory.remove_at(i, 1)
			break
	hp = target.hp
	sim._attack(p, target)
	if target.hp != hp:
		return "Double Strafe dealt damage after the last arrow was removed"

	if not p.inventory.add(ARROW, 1, sim.item_db, carry):
		return "Could not add an arrow for the second Double Strafe"
	if not sim.command_use_skill(p.id, "AC_DOUBLESTRAFE", target.id):
		return "Double Strafe could not be queued with an arrow"
	hp = target.hp
	sim._attack(p, target)
	if target.hp >= hp:
		return "Double Strafe with an arrow dealt no damage"
	return true if p.inventory.count(ARROW) == 0 else "Double Strafe did not consume an arrow"
