class_name WorldBuilder
extends RefCounted
## Builds the authoritative simulation of one map: walkability, rAthena warp
## portals and monster spawns, script NPCs (with their OnInit) and the CPU
## adventurers. Used by the offline field scene and by the co-op host, which
## keeps one simulation per map that has players in it.

static var npc_world: RaWorld


## The parsed NPC scripts, loaded once per session.
static func world(res: Node) -> RaWorld:
	if npc_world == null:
		npc_world = RaWorld.new()
		npc_world.load_all(res)
		for e in npc_world.errors:
			push_warning("NPC script: " + String(e))
		print("NPC scripts: %d files, %d NPCs, %d functions, %d errors" % [npc_world.loaded_files.size(),
			npc_world.npcs.size(), npc_world.functions.size(), npc_world.errors.size()])
	return npc_world


## Walkability of a map from the player's client (through MapAliases), or null.
static func load_gat(res: Node, map_name: String) -> GatFile:
	var data: PackedByteArray = res.read("data/%s.gat" % MapAliases.client_map(res, map_name))
	return GatFile.decode(data) if not data.is_empty() else null


## Creates the simulation for `map_name`. `gat` may be supplied by a scene
## that already loaded the map; `guilds` shares one guild registry between
## the host's maps.
static func build(res: Node, map_name: String, seed_value: int, gat: GatFile = null,
		with_bots := true, guilds: GuildStore = null) -> FieldSimulation:
	if gat == null:
		gat = load_gat(res, map_name)
	if gat == null:
		return null
	var sim := FieldSimulation.new(gat, seed_value)
	if guilds != null:
		sim.guilds = guilds
	var w := world(res)
	sim.setup_map(map_name, w.warps_on(map_name), w.monsters_on(map_name))
	spawn_script_npcs(res, sim, map_name)
	if with_bots:
		BotBrain.populate(sim, sim.rng.randi_range(2, 4), BotBrain.map_level(sim))
	return sim


## Places the map's script NPCs and runs each OnInit once per session.
static func spawn_script_npcs(res: Node, sim: FieldSimulation, map_name: String) -> void:
	var w := world(res)
	# OnInit sets NPC variables only; it runs against a detached unit.
	var nobody := SimUnit.new()
	nobody.kind = SimUnit.Kind.PLAYER
	nobody.walker = GridWalker.new(Vector2i.ZERO)
	for def in w.npcs_on(map_name):
		var sprite := NpcIdentity.sprite_for(res, String(def.sprite))
		if sprite == "":
			continue   # invisible NPCs (-1, 111, 139) are event / touch scripts
		sim.add_script_npc(def, sprite)
		if not bool(def.get("_inited", false)):
			def._inited = true
			RaInterpreter.new(w, RaHost.new(), sim, nobody, def).run("OnInit")
	for name in w.npcs:
		var d: Dictionary = w.npcs[name]
		if String(d.map) == "" and d.body != null and not bool(d.get("_inited", false)):
			d._inited = true
			RaInterpreter.new(w, RaHost.new(), sim, nobody, d).run("OnInit")
