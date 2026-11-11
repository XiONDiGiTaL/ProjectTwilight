extends SceneTree
## Visual check of the Kafra storage window in Prontera.
##   godot --path 06_Godot_Project -s res://tests/capture_storage.gd
## Output goes to user://captures and is never committed.


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for _f in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := "user://captures/storage_%s.png" % name
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
	var kafra := 0
	for nid in scene.sim.npcs:
		if String(scene.sim.npcs[nid].get("kind", "")) == "kafra":
			kafra = nid
	if kafra == 0:
		print("Prontera has no Kafra NPC")
		quit(1)
		return
	scene.player.inventory.add(501, 12, scene.sim.item_db, scene.player.max_weight())
	scene.player.inventory.add(1201, 1, scene.sim.item_db, scene.player.max_weight())
	scene.player.storage.add(909, 7, scene.sim.item_db, FieldSimulation.STORAGE_MAX_WEIGHT)
	scene.player.storage.add(2301, 1, scene.sim.item_db, FieldSimulation.STORAGE_MAX_WEIGHT)
	scene.player.storage.add(512, 3, scene.sim.item_db, FieldSimulation.STORAGE_MAX_WEIGHT)
	print("kafra npc ", kafra, "  storage ", scene.player.storage.entries.size(), " entries")
	scene.sim.command_open_storage(scene.player.id, kafra)
	scene.hud.storage.open("Kafra", scene.player, scene.sim.item_db)
	await create_timer(0.5).timeout
	await _shot("carried")
	scene.hud.storage._set_mode(true)
	await create_timer(0.3).timeout
	await _shot("stored")
	quit(0)
