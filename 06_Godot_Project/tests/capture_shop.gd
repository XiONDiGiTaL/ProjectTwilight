extends SceneTree
## Visual check: talk to the merchant, open the shop, buy and equip a Knife,
## then show the equipment window and the weapon on the character.
##   godot --path 06_Godot_Project -s res://tests/capture_shop.gd


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var out := "user://captures/shop_%s.png" % name
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
	scene.camera.distance = 170.0
	player.zeny = 3000
	var nid: int = sim.npcs.keys()[0]
	sim.command_talk(player.id, nid)
	var t0 := Time.get_ticks_msec()
	while not scene.hud.shop.visible and Time.get_ticks_msec() - t0 < 10000:
		await process_frame
	print("shop open: ", scene.hud.shop.visible)
	scene.hud.shop._selected = 3  # Knife row in the catalog
	scene.hud.shop.refresh()
	for _f in 4:
		await process_frame
	await _shot("open")
	sim.command_buy(player.id, 1201, 1)
	sim.command_buy(player.id, 2301, 1)
	sim.command_buy(player.id, 2401, 1)
	for _f in 3:
		await process_frame
	for item in [1201, 2301, 2401]:
		for i in player.inventory.entries.size():
			if int(player.inventory.entries[i].id) == item:
				sim.command_equip(player.id, i)
				break
	scene.hud.shop.toggle(false)
	scene.hud.equipment_window.toggle(true)
	scene.hud.equipment_window.position = Vector2(870, 140)
	print("equipment: ", player.equipment, " atk ", player.atk_min, "~", player.atk_max, " def ", player.hard_def, " zeny ", player.zeny)
	# Fight a Poring with the knife for the weapon-in-hand shot.
	var poring: SimUnit = null
	for u in sim.units.values():
		if u.mob_id == "1002":
			poring = u
			break
	poring.walker = GridWalker.new(sim.pathfinder.nearest_walkable(player.walker.cell + Vector2i(2, 0), 4))
	scene.attack(poring.id)
	await create_timer(1.3).timeout
	await _shot("equipped")
	quit(0)
