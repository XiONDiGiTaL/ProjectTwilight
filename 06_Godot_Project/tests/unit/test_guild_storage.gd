extends RefCounted
## Guild membership and the shared guild storage: moves, one member at a
## time, persistence across characters and the guildopenstorage command.

const FLAT := {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5}
const TEST_PATH := "user://test_guild_storage.json"


static func _gat(w := 400, h := 400) -> GatFile:
	var g := GatFile.new()
	g.width = w
	g.height = h
	g.heights.resize(w * h * 4)
	g.types.resize(w * h)
	return g


func _clean() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _field(path := TEST_PATH) -> FieldSimulation:
	var sim := FieldSimulation.new(_gat(), 41, RuleConfig.new(), path)
	sim.map_name = "prontera"
	sim.map_info = sim.map_db.get("prontera", {})
	sim.respawn_cell = Vector2i(60, 60)
	return sim


func _kafra(sim: FieldSimulation) -> int:
	return sim.add_script_npc({"name": "Guild Kafra#tw", "display": "Guild Kafra", "x": 50, "y": 52, "dir": 0}, "4_f_kafra1")


func test_create_and_move_items(_t) -> Variant:
	_clean()
	var sim := _field()
	var p := sim.add_player("Leader", Vector2i(50, 50), FLAT)
	if not sim.command_create_guild(p.id, "Twilight Guard"):
		return "could not found a guild"
	if p.guild_id == "" or p.guild_name != "Twilight Guard":
		return "guild membership not set"
	var npc := _kafra(sim)
	if not sim.command_open_guild_storage(p.id, npc):
		return "guild storage did not open"
	p.inventory.add(501, 4, sim.item_db, p.max_weight())
	if not sim.command_guild_deposit(p.id, 0, 3):
		return "guild deposit failed"
	if sim.guilds.storage_of(p.guild_id).count(501) != 3:
		return "guild storage count wrong"
	if not sim.command_guild_withdraw(p.id, 0, 1):
		return "guild withdraw failed"
	if sim.guilds.storage_of(p.guild_id).count(501) != 2 or p.inventory.count(501) != 2:
		return "guild withdraw counts wrong"
	return true


func test_storage_is_shared_and_persisted(_t) -> Variant:
	_clean()
	var sim := _field()
	var p := sim.add_player("Leader", Vector2i(50, 50), FLAT)
	sim.command_create_guild(p.id, "Twilight Guard")
	var npc := _kafra(sim)
	sim.command_open_guild_storage(p.id, npc)
	p.inventory.add(501, 5, sim.item_db, p.max_weight())
	sim.command_guild_deposit(p.id, 0, 2)
	var store := GuildStore.new(TEST_PATH, sim.item_db)
	if store.storage_of(p.guild_id).count(501) != 2:
		return "guild storage did not survive the file"
	var sim2 := _field()
	var p2 := sim2.add_player("Member", Vector2i(50, 50), FLAT)
	if not sim2.command_create_guild(p2.id, "Twilight Guard"):
		return "a second character could not join the guild"
	if p2.guild_id != p.guild_id:
		return "members landed in different guilds"
	var npc2 := _kafra(sim2)
	if not sim2.command_open_guild_storage(p2.id, npc2):
		return "member could not open the shared storage"
	return true if sim2.guilds.storage_of(p2.guild_id).count(501) == 2 else "shared storage count wrong"


func test_one_member_at_a_time(_t) -> Variant:
	_clean()
	var sim := _field()
	var p1 := sim.add_player("Leader", Vector2i(50, 50), FLAT)
	var p2 := sim.add_player("Member", Vector2i(51, 50), FLAT)
	sim.command_create_guild(p1.id, "Twilight Guard")
	sim.command_create_guild(p2.id, "Twilight Guard")
	var npc := _kafra(sim)
	if not sim.command_open_guild_storage(p1.id, npc):
		return "leader could not open the storage"
	if sim.command_open_guild_storage(p2.id, npc):
		return "a second member must be refused while it is in use"
	sim.close_guild_storage(p1.id)
	return true if sim.command_open_guild_storage(p2.id, npc) else "storage did not free up"


func test_requires_a_guild(_t) -> Variant:
	_clean()
	var sim := _field()
	var p := sim.add_player("Loner", Vector2i(50, 50), FLAT)
	var npc := _kafra(sim)
	return true if not sim.command_open_guild_storage(p.id, npc) else "a guildless player must be refused"


func test_guild_membership_persists_with_the_character(_t) -> Variant:
	_clean()
	var sim := _field()
	var p := sim.add_player("Leader", Vector2i(50, 50), FLAT)
	sim.command_create_guild(p.id, "Twilight Guard")
	var captured := SaveGame.capture(p, "prontera")
	var valid := SaveGame.validate(captured, sim.item_db, ClassInsignia.classes())
	if not valid.ok:
		return "save validation failed: %s" % valid.error
	if String(valid.character.guild_id) != p.guild_id or String(valid.character.guild_name) != "Twilight Guard":
		return "guild membership missing from the save"
	var restored := sim.add_player_from_save(valid.character)
	if restored.guild_id != p.guild_id or restored.guild_name != "Twilight Guard":
		return "guild membership did not survive the save"
	captured.version = 6
	captured.character.erase("guild_id")
	captured.character.erase("guild_name")
	var legacy := SaveGame.validate(captured, sim.item_db, ClassInsignia.classes())
	return true if legacy.ok and String(legacy.character.guild_id) == "" else "older saves should load guildless"


func test_guild_keeper_npc(_t) -> Variant:
	_clean()
	var world := RaWorld.new()
	world.load_all(null)
	if not world.errors.is_empty():
		return "script errors: %s" % [world.errors.slice(0, 3)]
	var def := world.find_npc("Guild Keeper#tw")
	if def.is_empty():
		return "Guild Keeper#tw is not loaded"
	var sim := _field()
	var p := sim.add_player("Leader", Vector2i(50, 50), FLAT)
	sim.command_create_guild(p.id, "Twilight Guard")
	p.walker = GridWalker.new(Vector2i(int(def.x), int(def.y)))
	sim.add_script_npc(def, "4_f_kafra1")
	var host := RaHost.new()
	host.answers = [1]   # Open the guild storage
	var vm := RaInterpreter.new(world, host, sim, p, def)
	await vm.run()
	if vm.error != "":
		return vm.error
	if host.guild_storages != [true]:
		return "the keeper did not open storage: %s / %s" % [host.transcript, vm.unsupported]
	return true if not sim._open_guild_storage_of(p).is_empty() else "guild storage not open in the simulation"


func test_guildopenstorage_script_command(_t) -> Variant:
	_clean()
	var sim := _field()
	var p := sim.add_player("Leader", Vector2i(50, 50), FLAT)
	sim.command_create_guild(p.id, "Twilight Guard")
	var src := "prontera,50,50,0\tscript\tGuild Kafra Test\t4_F_KAFRA1,{\n" + \
		"\tif (guildopenstorage()) {\n\t\tmes \"busy\";\n\t\tclose;\n\t}\n" + \
		"\tmes \"opened\";\n\tclose;\n}\n"
	var world := RaWorld.new()
	world.load_text(src, "test")
	world._resolve_duplicates()
	var def := world.find_npc("Guild Kafra Test")
	sim.add_script_npc(def, "4_f_kafra1")
	var host := RaHost.new()
	var vm := RaInterpreter.new(world, host, sim, p, def)
	await vm.run()
	if vm.error != "":
		return vm.error
	if host.guild_storages != [true]:
		return "guildopenstorage was not recorded: %s" % [host.guild_storages]
	return true if not sim._open_guild_storage_of(p).is_empty() else "guild storage not open in the simulation"
