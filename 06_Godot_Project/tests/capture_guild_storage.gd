extends SceneTree
## Visual check of the guild storage tab in Prontera.
##   godot --path 06_Godot_Project -s res://tests/capture_guild_storage.gd

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for _f in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := "user://captures/guild_storage_%s.png" % name
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
	if not scene.sim.command_create_guild(scene.player.id, "Twilight Guard"):
		print("could not found guild")
		quit(1)
		return
	var nid: int = scene.sim.add_kafra_npc(Vector2i(150, 191), "Kafra")
	scene.player.inventory.add(501, 12, scene.sim.item_db, scene.player.max_weight())
	scene.player.inventory.add(1201, 1, scene.sim.item_db, scene.player.max_weight())
	var bag: Inventory = scene.sim.guilds.storage_of(scene.player.guild_id)
	bag.add(909, 7, scene.sim.item_db, FieldSimulation.STORAGE_MAX_WEIGHT)
	bag.add(2301, 1, scene.sim.item_db, FieldSimulation.STORAGE_MAX_WEIGHT)
	bag.add(512, 3, scene.sim.item_db, FieldSimulation.STORAGE_MAX_WEIGHT)
	print("guild ", scene.player.guild_name, "  storage ", bag.entries.size(), " entries")
	scene.sim.command_open_guild_storage(scene.player.id, nid)
	scene.show_guild_storage()
	await create_timer(0.5).timeout
	await _shot("guild")
	quit(0)
