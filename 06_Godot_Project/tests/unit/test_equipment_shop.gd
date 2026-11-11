extends RefCounted
## Equipment rules, weapon damage model and NPC shop trading.


static func _open_gat(w: int, h: int) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


static func _setup() -> Array:
	var sim := FieldSimulation.new(_open_gat(40, 40), 21)
	var p := sim.add_player("Tester", Vector2i(10, 10), {"str": 5, "agi": 5, "vit": 5, "int": 1, "dex": 5, "luk": 5})
	return [sim, p]


static func _add_shop_npc(sim: FieldSimulation, cell: Vector2i) -> int:
	sim.npcs[77] = {"id": 77, "name": "Merchant", "sprite": "1_m_merchant", "cell": cell, "direction": 0,
		"shop": "prt_fild08_merchant", "greeting": ""}
	return 77


func test_size_modifier_and_weapon_range(_t) -> Variant:
	if CombatRulesPreRenewal.size_modifier("dagger", "medium") != 75 or CombatRulesPreRenewal.size_modifier("fist", "large") != 100:
		return "size table wrong"
	var r := CombatRulesPreRenewal.weapon_atk_range(17, 1, 5)  # min(17, floor(5*1.0)) = 5
	return true if r == Vector2i(5, 17) else "weapon range wrong: %s" % r


func test_equip_knife(_t) -> Variant:
	var s := _setup()
	var sim: FieldSimulation = s[0]
	var p: SimUnit = s[1]
	var fist_interval := p.attack_interval
	p.inventory.add(1201, 1, sim.item_db, p.max_weight())
	if not sim.command_equip(p.id, p.inventory.entries.size() - 1):
		return "equip failed"
	if p.equipment.get("weapon", 0) != 1201 or p.inventory.count(1201) != 0:
		return "knife not moved to the weapon slot"
	if p.weapon_type != "dagger" or p.atk_min != p.batk + 5 or p.atk_max != p.batk + 17:
		return "ATK not updated: %d~%d (batk %d)" % [p.atk_min, p.atk_max, p.batk]
	if p.attack_interval <= fist_interval:
		return "dagger should be slower than fists for a Novice (BTBA 0.65 vs 0.5)"
	# Damage against a medium target uses 75% of weapon ATK.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var target := {"hit": 1, "flee": -500, "luk": 0, "vit": 0, "def": 0, "is_player": false, "can_crit": false, "size": "medium"}
	var prof := p.combat_profile()
	prof.can_crit = false
	for i in 30:
		var res := CombatRulesPreRenewal.resolve_attack(prof, target, rng)
		if res.miss:
			continue  # 5% minimum miss chance
		if res.damage < p.batk + 5 * 75 / 100 or res.damage > p.batk + 17 * 75 / 100:
			return "damage %d outside medium-size range" % res.damage
	return true


func test_armor_def_and_swap(_t) -> Variant:
	var s := _setup()
	var sim: FieldSimulation = s[0]
	var p: SimUnit = s[1]
	p.inventory.add(2301, 1, sim.item_db, p.max_weight())
	p.inventory.add(2401, 1, sim.item_db, p.max_weight())
	sim.command_equip(p.id, 0)
	sim.command_equip(p.id, 0)
	if p.hard_def != 2:
		return "DEF should be 2 with shirt + sandals, got %d" % p.hard_def
	p.inventory.add(1201, 1, sim.item_db, p.max_weight())
	p.inventory.add(1207, 1, sim.item_db, p.max_weight())
	sim.command_equip(p.id, 0)
	sim.command_equip(p.id, 0)  # Main Gauche replaces Knife
	if p.equipment.weapon != 1207 or p.inventory.count(1201) != 1:
		return "swap did not return the knife to the inventory"
	if not sim.command_unequip(p.id, "weapon") or p.weapon_type != "fist" or p.inventory.count(1207) != 1:
		return "unequip failed"
	var potion_index := p.inventory.entries.size()
	p.inventory.add(501, 1, sim.item_db, p.max_weight())
	return true if not sim.command_equip(p.id, potion_index) else "equipped a potion"


func test_shop_flow(_t) -> Variant:
	var s := _setup()
	var sim: FieldSimulation = s[0]
	var p: SimUnit = s[1]
	if sim.command_buy(p.id, 501, 1):
		return "bought without an open shop"
	var nid := _add_shop_npc(sim, Vector2i(18, 10))
	sim.command_talk(p.id, nid)
	var opened := false
	for i in 200:
		sim.tick(50.0)
		for ev in sim.drain_events():
			opened = opened or ev.type == "npc_open"
		if opened:
			break
	if not opened:
		return "walking to the NPC did not open the shop"
	p.zeny = 120
	if not sim.command_buy(p.id, 501, 2) or p.zeny != 20 or p.inventory.count(501) != 2:
		return "buy failed: zeny %d" % p.zeny
	if sim.command_buy(p.id, 501, 1):
		return "bought without enough zeny"
	if sim.command_buy(p.id, 909, 1):
		return "bought an item the shop does not sell"
	var idx := 0
	if not sim.command_sell(p.id, idx, 2) or p.zeny != 70 or p.inventory.count(501) != 0:
		return "sell failed (half price): zeny %d" % p.zeny
	p.walker = GridWalker.new(Vector2i(35, 35))
	p.inventory.add(909, 1, sim.item_db, p.max_weight())
	return true if not sim.command_sell(p.id, 0, 1) else "traded from across the map"


func test_save_v2_equipment_and_v1_compat(_t) -> Variant:
	var s := _setup()
	var sim: FieldSimulation = s[0]
	var p: SimUnit = s[1]
	p.inventory.add(1201, 1, sim.item_db, p.max_weight())
	sim.command_equip(p.id, 0)
	var data: Variant = JSON.parse_string(JSON.stringify(SaveGame.capture(p, "prt_fild08")))
	var r := SaveGame.validate(data, sim.item_db, ClassInsignia.classes())
	var q := FieldSimulation.new(_open_gat(40, 40), 1).add_player_from_save(r.character)
	if q.equipment.get("weapon", 0) != 1201 or q.weapon_type != "dagger":
		return "equipment not restored"
	data.version = 1
	data.character.erase("equipment")
	var r1 := SaveGame.validate(data, sim.item_db, ClassInsignia.classes())
	return true if r1.ok and (r1.character.equipment as Dictionary).is_empty() else "v1 save rejected"
