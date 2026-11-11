extends RefCounted
## Kafra storage: deposit / withdraw validation, the Prontera Kafra and the
## storage field in the character save.

const FLAT := {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5}


static func _gat(w := 400, h := 400) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


func _field() -> FieldSimulation:
	var sim := FieldSimulation.new(_gat(), 23, RuleConfig.new())
	sim.map_name = "prontera"
	sim.map_info = sim.map_db.get("prontera", {})
	sim.respawn_cell = Vector2i(60, 60)
	return sim


static func _index_of(bag: Inventory, item_id: int) -> int:
	for i in bag.entries.size():
		if int(bag.entries[i].id) == item_id:
			return i
	return -1


func test_deposit_and_withdraw(_t) -> Variant:
	var sim := _field()
	var p := sim.add_player("Keeper", Vector2i(50, 50), FLAT)
	var kafra := sim.add_kafra_npc(Vector2i(50, 52))
	if not sim.command_open_storage(p.id, kafra):
		return "storage should open next to the Kafra"
	if not p.inventory.add(501, 10, sim.item_db, p.max_weight()):
		return "could not stock the inventory"
	if not sim.command_storage_deposit(p.id, _index_of(p.inventory, 501), 4):
		return "deposit failed"
	if p.storage.count(501) != 4 or p.inventory.count(501) != 6:
		return "deposit counts wrong: stored %d, carried %d" % [p.storage.count(501), p.inventory.count(501)]
	if not sim.command_storage_withdraw(p.id, _index_of(p.storage, 501), 2):
		return "withdraw failed"
	if p.storage.count(501) != 2 or p.inventory.count(501) != 8:
		return "withdraw counts wrong: stored %d, carried %d" % [p.storage.count(501), p.inventory.count(501)]
	return true


func test_moves_report_through_events(_t) -> Variant:
	var sim := _field()
	var p := sim.add_player("Keeper", Vector2i(50, 50), FLAT)
	var kafra := sim.add_kafra_npc(Vector2i(50, 51))
	sim.command_open_storage(p.id, kafra)
	p.inventory.add(501, 2, sim.item_db, p.max_weight())
	sim.drain_events()
	sim.command_storage_deposit(p.id, _index_of(p.inventory, 501), 1)
	for ev in sim.drain_events():
		if ev.type == "storage" and ev.id == p.id and ev.ok and String(ev.text).contains("Stored"):
			return true
	return "a deposit should emit a storage event"


func test_requires_an_open_kafra_in_range(_t) -> Variant:
	var sim := _field()
	var p := sim.add_player("Keeper", Vector2i(50, 50), FLAT)
	var kafra := sim.add_kafra_npc(Vector2i(50, 52))
	p.inventory.add(501, 2, sim.item_db, p.max_weight())
	if sim.command_storage_deposit(p.id, _index_of(p.inventory, 501), 1):
		return "storage must not work before it is opened"
	sim.command_open_storage(p.id, kafra)
	p.walker = GridWalker.new(Vector2i(70, 70))   # walk away
	if sim.command_storage_deposit(p.id, _index_of(p.inventory, 501), 1):
		return "storage must refuse a player who walked away"
	return true


func test_only_kafra_npcs_open_storage(_t) -> Variant:
	var sim := _field()
	var p := sim.add_player("Keeper", Vector2i(50, 50), FLAT)
	var guide := sim.add_script_npc({"name": "Guide#tw", "display": "Guide", "x": 50, "y": 51, "dir": 0}, "4_m_01")
	return true if not sim.command_open_storage(p.id, guide) else "a plain script NPC is not a Kafra"


func test_capacity_limits(_t) -> Variant:
	var sim := _field()
	var p := sim.add_player("Keeper", Vector2i(50, 50), FLAT)
	var kafra := sim.add_kafra_npc(Vector2i(50, 52))
	sim.command_open_storage(p.id, kafra)
	p.inventory.add(501, 5, sim.item_db, p.max_weight())
	p.storage.max_entries = 0
	if sim.command_storage_deposit(p.id, _index_of(p.inventory, 501), 1):
		return "a full Kafra must refuse deposits"
	p.storage.max_entries = SimUnit.STORAGE_SLOTS
	p.storage.add(2301, 1, sim.item_db, FieldSimulation.STORAGE_MAX_WEIGHT)
	p.inventory.max_entries = p.inventory.entries.size()
	return true if not sim.command_storage_withdraw(p.id, _index_of(p.storage, 2301), 1) else "a full bag must refuse withdrawals"


func test_storage_persists_with_the_character(_t) -> Variant:
	var sim := _field()
	var p := sim.add_player("Keeper", Vector2i(50, 50), FLAT)
	var kafra := sim.add_kafra_npc(Vector2i(50, 52))
	sim.command_open_storage(p.id, kafra)
	p.inventory.add(501, 6, sim.item_db, p.max_weight())
	sim.command_storage_deposit(p.id, _index_of(p.inventory, 501), 4)
	var captured := SaveGame.capture(p, "prontera")
	var valid := SaveGame.validate(captured, sim.item_db, ClassInsignia.classes())
	if not valid.ok:
		return "save validation failed: %s" % valid.error
	var restored := sim.add_player_from_save(valid.character)
	if restored.storage.count(501) != 4 or restored.inventory.count(501) != 2:
		return "storage did not survive the save: stored %d, carried %d" % [restored.storage.count(501), restored.inventory.count(501)]
	if restored.storage.max_entries != SimUnit.STORAGE_SLOTS:
		return "restored storage should keep its 300 slots"
	return true


func test_older_saves_load_without_storage(_t) -> Variant:
	var sim := _field()
	var p := sim.add_player("Keeper", Vector2i(50, 50), FLAT)
	var captured := SaveGame.capture(p, "prontera")
	captured.version = 5
	captured.character.erase("storage")
	var valid := SaveGame.validate(captured, sim.item_db, ClassInsignia.classes())
	if not valid.ok:
		return "a v5 save should still load"
	return true if (valid.character.storage as Array).is_empty() else "v5 saves start with empty storage"


func test_prontera_has_a_kafra(_t) -> Variant:
	var sim := _field()
	sim.setup_map("prontera")
	for nid in sim.npcs:
		var npc: Dictionary = sim.npcs[nid]
		if String(npc.get("kind", "")) == "kafra":
			return true
	return "Prontera should spawn a Kafra NPC from maps.json"
