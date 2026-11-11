extends SceneTree
## Visual check of the CPU adventurers and the corner minimap.
##   godot --path 06_Godot_Project -s res://tests/capture_bots.gd
## Output goes to user://captures and is never committed.


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for _f in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := "user://captures/bots_%s.png" % name
	root.get_texture().get_image().save_png(out)
	print("saved ", ProjectSettings.globalize_path(out))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/game/field.tscn").instantiate()
	scene.save_slot = ""   # no save: the capture never touches a character
	root.add_child(scene)
	await process_frame
	if scene.player == null:
		print("field failed to load")
		quit(1)
		return
	# One of each role nearby so the shot always shows every blip colour.
	var c: Vector2i = scene.player.walker.cell
	BotBrain.spawn(scene.sim, c + Vector2i(3, 0), 40, 0)    # melee
	BotBrain.spawn(scene.sim, c + Vector2i(-4, 2), 40, 5)   # caster
	BotBrain.spawn(scene.sim, c + Vector2i(2, 4), 40, 6)    # support
	scene.camera.distance = 190.0
	await create_timer(3.0).timeout
	var bots := 0
	for u in scene.sim.units.values():
		if u.is_bot:
			bots += 1
	print("units=%d bots=%d views=%d minimap=%s" % [scene.sim.units.size(), bots, scene.views.size(),
		str(scene.hud.minimap.size)])
	await _shot("field")
	# Now the camera pulled back over the portal area.
	scene.camera.distance = 260.0
	await create_timer(0.6).timeout
	await _shot("wide")
	quit(0)
