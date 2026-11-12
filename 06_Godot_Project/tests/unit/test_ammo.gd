extends RefCounted
## Arrows and quivers: stackable ammo, unpacking, carry weight, bow consumption
## and elemental arrow damage.

const ARROW := 1750
const QUIVER := 1751
const FIRE_ARROW := 1752
const SILVER_ARROW := 1753
const BOW := 1701
const ARROW_PROJECTILE := preload("res://scripts/rendering/fx/arrow_projectile.gd")
const FIELD_SCENE := preload("res://scripts/game/field_scene.gd")


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
	if String(arrow.get("element", "")) != "neutral":
		return "Normal Arrow must be neutral"
	if not Inventory.is_stackable(arrow):
		return "Arrow must stack"
	for pair in [[FIRE_ARROW, "fire"], [SILVER_ARROW, "holy"]]:
		var tier: Dictionary = sim.item_db.get(str(pair[0]), {})
		if tier.is_empty() or String(tier.get("type", "")) != "ammo":
			return "Elemental arrow %d must be ammo" % pair[0]
		if String(tier.get("element", "")) != String(pair[1]):
			return "Elemental arrow %d has the wrong element" % pair[0]
		if int(tier.get("weight", 0)) != int(arrow.get("weight", 0)):
			return "Elemental arrow %d has the wrong weight" % pair[0]
		if int(tier.get("price", 0)) <= int(arrow.get("price", 0)):
			return "Elemental arrow %d should cost more than a normal arrow" % pair[0]
		if not Inventory.is_stackable(tier):
			return "Elemental arrow %d must stack" % pair[0]
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
	for id in [ARROW, FIRE_ARROW, SILVER_ARROW, QUIVER]:
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


static func _last_damage(sim: FieldSimulation) -> Dictionary:
	for i in range(sim.events.size() - 1, -1, -1):
		var ev: Dictionary = sim.events[i]
		if String(ev.get("type", "")) == "damage":
			return ev
	return {}


static func _hit_with_arrow(arrow_id: int, target_element: String) -> Dictionary:
	var sim := FieldSimulation.new(_gat(), 94)
	var p := _player(sim, Vector2i(10, 10))
	if not _equip(sim, p, BOW):
		return {"error": "could not equip bow"}
	var target := _dummy(sim, Vector2i(15, 10))
	target.element = target_element
	target.element_level = 1
	var carry := _carry(sim, p)
	if not p.inventory.add(arrow_id, 1, sim.item_db, carry):
		return {"error": "could not add arrow"}
	sim._attack(p, target)
	var ev := _last_damage(sim)
	return {"error": "", "damage": int(ev.get("amount", 0)), "element": String(ev.get("element", "")), "remaining": p.inventory.count(arrow_id)}


func test_bow_attacks_emit_visible_projectiles(_t) -> Variant:
	var sim := FieldSimulation.new(_gat(), 96)
	var p := _player(sim, Vector2i(10, 10))
	if not _equip(sim, p, BOW):
		return "Archer could not equip a bow"
	var target := _dummy(sim, Vector2i(15, 10))
	if not p.inventory.add(ARROW, 1, sim.item_db, _carry(sim, p)):
		return "Could not add an arrow for the projectile test"
	sim.drain_events()
	sim._attack(p, target)
	var normal := {}
	for ev in sim.events:
		if String(ev.get("type", "")) == "projectile":
			normal = ev
	if normal.is_empty() or int(normal.target) != target.id or int(normal.hits) != 1:
		return "Normal bow attack did not emit one projectile"
	if String(normal.element) != "neutral":
		return "Normal arrow projectile had the wrong element"

	p.skills["AC_DOUBLESTRAFE"] = 10
	if not p.inventory.add(FIRE_ARROW, 1, sim.item_db, _carry(sim, p)):
		return "Could not add a Fire Arrow for the skill projectile test"
	if not sim.command_use_skill(p.id, "AC_DOUBLESTRAFE", target.id):
		return "Double Strafe could not be queued for the projectile test"
	sim.drain_events()
	sim._attack(p, target)
	var skill := {}
	for ev in sim.events:
		if String(ev.get("type", "")) == "projectile":
			skill = ev
	if skill.is_empty() or int(skill.hits) != 2:
		return "Double Strafe did not emit two projectiles"
	return true if String(skill.element) == "fire" else "Skill projectile lost the arrow element"


## Regression for the capture bug: the HUD must drop a player's plate when the
## owning view is torn down, otherwise the next frame calls a freed anchor.
func test_double_strafe_stagger_and_player_plate_cleanup(t: SceneTree) -> Variant:
	var field := Node3D.new()
	t.root.add_child(field)
	ARROW_PROJECTILE.volley(field, Vector3.ZERO, Vector3(60, 0, 0), "fire", 2)
	var arrows := field.get_children()
	if arrows.size() != 2:
		field.queue_free()
		return "Double Strafe volley did not create exactly two arrows"
	var first = arrows[0]
	var second = arrows[1]
	if not is_equal_approx(first.delay, 0.0):
		field.queue_free()
		return "The first Double Strafe arrow should not be delayed"
	if not is_equal_approx(second.delay, ARROW_PROJECTILE.HIT_STAGGER):
		field.queue_free()
		return "The second Double Strafe arrow lost its stagger delay"
	if ARROW_PROJECTILE.HIT_STAGGER < 0.1:
		field.queue_free()
		return "Double Strafe arrows need enough stagger to read separately"
	await t.process_frame
	first.set_process(false)
	second.set_process(false)
	if not first.visible or second.visible:
		field.queue_free()
		return "Only the leading Double Strafe arrow should be visible at launch"
	# Advance both arrows deterministically instead of relying on wall-clock frames.
	first._process(0.1)
	second._process(0.1)
	if second.visible:
		field.queue_free()
		return "The trailing arrow became visible before its stagger elapsed"
	for _i in 3:
		first._process(0.1)
		second._process(0.1)
	if not first.visible or not second.visible:
		field.queue_free()
		return "Both Double Strafe arrows should be visible after the stagger"
	if first.global_position.distance_to(second.global_position) < 2.0:
		field.queue_free()
		return "The two Double Strafe arrows are too close to read separately"

	var hud := CombatHud.new()
	t.root.add_child(hud)
	await t.process_frame
	hud.add_player_plate(9001, "Capture Archer", 100, 100, func(): return Vector3.ZERO)
	var plate: Dictionary = hud._player_plates.get(9001, {})
	if plate.is_empty():
		hud.queue_free()
		field.queue_free()
		return "Player nameplate was not registered"
	var plate_node: Node = plate.node
	hud.remove_player_plate(9001)
	var cleanup_ok: bool = not hud._player_plates.has(9001) and plate_node.is_queued_for_deletion()
	hud.queue_free()
	field.queue_free()
	return true if cleanup_ok else "Removing a player view left its nameplate registered"


## The capture tool and the live despawn handler must share the teardown path;
## this exercises that path without loading a rendered map.
func test_capture_view_teardown_uses_field_cleanup(t: SceneTree) -> Variant:
	var field = FIELD_SCENE.new()
	var hud := CombatHud.new()
	t.root.add_child(hud)
	await t.process_frame
	field.hud = hud
	var view := UnitView.new()
	t.root.add_child(view)
	field.views[9002] = view
	hud.add_player_plate(9002, "Capture Archer", 100, 100, func(): return Vector3.ZERO)
	field.remove_view(9002)
	var cleanup_ok: bool = not field.views.has(9002) and not hud._player_plates.has(9002) and view.is_queued_for_deletion()
	hud.queue_free()
	field.free()
	return true if cleanup_ok else "Field view teardown left its view or nameplate behind"


func test_elemental_arrows_change_bow_damage(_t) -> Variant:
	var normal_earth := _hit_with_arrow(ARROW, "earth")
	var fire_earth := _hit_with_arrow(FIRE_ARROW, "earth")
	for h in [normal_earth, fire_earth]:
		if String(h.get("error", "")) != "":
			return String(h.error)
	if String(normal_earth.element) != "neutral":
		return "Normal Arrow should deal neutral damage"
	if String(fire_earth.element) != "fire":
		return "Fire Arrow should deal fire damage"
	if int(fire_earth.damage) <= int(normal_earth.damage):
		return "Fire Arrow should beat neutral damage against earth"
	if int(fire_earth.remaining) != 0:
		return "Fire Arrow was not consumed"

	var normal_undead := _hit_with_arrow(ARROW, "undead")
	var silver_undead := _hit_with_arrow(SILVER_ARROW, "undead")
	for h in [normal_undead, silver_undead]:
		if String(h.get("error", "")) != "":
			return String(h.error)
	if String(silver_undead.element) != "holy":
		return "Silver Arrow should deal holy damage"
	if int(silver_undead.damage) <= int(normal_undead.damage):
		return "Silver Arrow should beat neutral damage against undead"

	var sim := FieldSimulation.new(_gat(), 95)
	var p := _player(sim, Vector2i(10, 10))
	if not _equip(sim, p, BOW):
		return "Archer could not equip a bow"
	var target := _dummy(sim, Vector2i(15, 10))
	target.element = "earth"
	target.element_level = 1
	p.skills["AC_DOUBLESTRAFE"] = 10
	if not p.inventory.add(FIRE_ARROW, 1, sim.item_db, _carry(sim, p)):
		return "Could not add a Fire Arrow for Double Strafe"
	if not sim.command_use_skill(p.id, "AC_DOUBLESTRAFE", target.id):
		return "Double Strafe could not be queued with a Fire Arrow"
	var hp := target.hp
	sim._attack(p, target)
	var ev := _last_damage(sim)
	if target.hp >= hp:
		return "Double Strafe with a Fire Arrow dealt no damage"
	if String(ev.get("element", "")) != "fire":
		return "Double Strafe did not use the Fire Arrow element"
	return true if p.inventory.count(FIRE_ARROW) == 0 else "Double Strafe did not consume the Fire Arrow"
