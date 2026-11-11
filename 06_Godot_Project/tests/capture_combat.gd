extends SceneTree
## Visual check of combat UI: engaged HP bar, damage numbers, target frame,
## player panel and a level-up. Output: user://captures/combat_*.png
##   godot --path 06_Godot_Project -s res://tests/capture_combat.gd


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var out := "user://captures/combat_%s.png" % name
	root.get_texture().get_image().save_png(out)
	print("saved ", ProjectSettings.globalize_path(out))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/game/field.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var sim: FieldSimulation = scene.sim
	var player: SimUnit = scene.player
	if sim == null:
		print("field failed")
		quit(1)
		return
	# Move the nearest Poring right next to the player so the fight is on screen.
	var poring: SimUnit = null
	for u in sim.units.values():
		if u.mob_id == "1002" and (poring == null or _d(u, player) < _d(poring, player)):
			poring = u
	poring.walker = GridWalker.new(sim.pathfinder.nearest_walkable(player.walker.cell + Vector2i(2, 1), 4))
	poring.walker.walk_speed = 400.0
	player.base_exp = 8  # next kill levels up (9 EXP needed for level 2)
	scene.camera.distance = 150.0
	print("player ", player.walker.cell, " hp ", player.hp, "/", player.max_hp, " atk ", player.atk_min,
		" interval ", player.attack_interval, " ; poring ", poring.walker.cell, " hp ", poring.hp)
	scene.attack(poring.id)
	var shots_taken := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		await process_frame
		var elapsed := Time.get_ticks_msec() - t0
		if shots_taken == 0 and poring.hp < poring.max_hp * 0.7:
			await _shot("fight")
			shots_taken = 1
		if poring.dead and shots_taken == 1:
			await create_timer(0.35).timeout
			await _shot("kill_levelup")
			shots_taken = 2
			break
	print("poring dead=", poring.dead, " player lv ", player.level, " exp ", player.base_exp, " hp ", player.hp)
	await create_timer(1.5).timeout
	await _shot("after")
	quit(0)


static func _d(a: SimUnit, b: SimUnit) -> int:
	return maxi(absi(a.walker.cell.x - b.walker.cell.x), absi(a.walker.cell.y - b.walker.cell.y))
