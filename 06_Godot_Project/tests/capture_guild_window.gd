extends SceneTree
## Visual check of the guild roster window (G) in Prontera.
##   godot --path 06_Godot_Project -s res://tests/capture_guild_window.gd

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for _f in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := "user://captures/guild_window_%s.png" % name
	root.get_texture().get_image().save_png(out)
	print("saved ", ProjectSettings.globalize_path(out))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/game/field.tscn").instantiate()
	scene.save_slot = ""
	scene.map_name = "prontera"
	scene.start_cell = Vector2i(152, 191)
	root.add_child(scene)
	await process_frame
	if scene.player == null:
		print("field failed to load")
		quit(1)
		return
	scene.sim.guilds = GuildStore.new("user://captures/guilds_capture.json", scene.sim.item_db)
	scene.player.guild_id = ""
	scene.player.guild_name = ""
	if not scene.sim.command_create_guild(scene.player.id, "Twilight Guard"):
		print("could not found guild")
		quit(1)
		return
	var gid: String = scene.player.guild_id
	scene.sim.command_guild_invite(scene.player.id, "Aria")
	var aria: SimUnit = scene.sim.add_player("Aria", Vector2i(154, 191), {"str": 5, "agi": 5, "vit": 5, "int": 5, "dex": 5, "luk": 5})
	scene.sim.command_guild_accept(aria.id, gid)
	var bag: Inventory = scene.sim.guilds.storage_of(gid)
	bag.add(501, 3, scene.sim.item_db, FieldSimulation.STORAGE_MAX_WEIGHT)
	print("guild storage ", bag.entries.size())
	scene.hud.guild_window.open(scene.sim.guilds, scene.player)
	print("guild roster: ", (scene.sim.guilds.get_guild(gid).members as Array))
	await create_timer(0.5).timeout
	await _shot("roster")
	quit(0)
