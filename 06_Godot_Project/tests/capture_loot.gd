extends SceneTree
## Visual check of loot: kill a Poring, show dropped items, pick them up,
## then open the inventory and status windows.
##   godot --path 06_Godot_Project -s res://tests/capture_loot.gd


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var out := "user://captures/loot_%s.png" % name
	root.get_texture().get_image().save_png(out)
	print("saved ", ProjectSettings.globalize_path(out))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/game/field.tscn").instantiate()
	scene.save_slot = ""
	root.add_child(scene)
	await process_frame
	var sim: FieldSimulation = scene.sim
	var player: SimUnit = scene.player
	scene.camera.distance = 150.0
	# Guarantee a visible drop: make the next Poring drop Jellopy and an Apple.
	var poring: SimUnit = null
	for u in sim.units.values():
		if u.mob_id == "1002":
			poring = u
			break
	poring.walker = GridWalker.new(sim.pathfinder.nearest_walkable(player.walker.cell + Vector2i(2, 0), 4))
	poring.data = poring.data.duplicate(true)
	poring.data.drops = [[909, 10000], [512, 10000], [713, 10000]]
	poring.hp = 8
	scene.attack(poring.id)
	var t0 := Time.get_ticks_msec()
	while not poring.dead and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	await create_timer(0.6).timeout
	print("ground items: ", sim.ground_items.size())
	await _shot("drops")
	for gid in sim.ground_items.keys():
		sim.command_pickup(player.id, gid)
		var t1 := Time.get_ticks_msec()
		while sim.ground_items.has(gid) and Time.get_ticks_msec() - t1 < 5000:
			await process_frame
	print("inventory: ", player.inventory.entries)
	scene.hud.inventory.toggle(true)
	scene.hud.inventory._select_tab(2)
	scene.hud.status_window.toggle(true)
	scene.hud.status_window.position = Vector2(420, 380)
	scene.hud.inventory.position = Vector2(880, 300)
	for _f in 6:
		await process_frame
	await _shot("windows")
	quit(0)
