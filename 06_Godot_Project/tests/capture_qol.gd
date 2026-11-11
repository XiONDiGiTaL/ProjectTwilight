extends SceneTree
## Visual check of the private-server layer: command console, HUD notices.
##   godot --path 06_Godot_Project -s res://tests/capture_qol.gd
## Output goes to user://captures and is never committed.


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for _f in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := "user://captures/qol_%s.png" % name
	root.get_texture().get_image().save_png(out)
	print("saved ", ProjectSettings.globalize_path(out))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/game/field.tscn").instantiate()
	scene.save_slot = ""
	root.add_child(scene)
	await process_frame
	if scene.player == null:
		print("field failed to load")
		quit(1)
		return
	scene.hud.map_banner("", "")
	scene.hud.chat.open("@rates")
	await create_timer(0.4).timeout
	await _shot("console")
	scene.hud.chat.close()
	for line in ["@rates", "@autoloot on", "@mobinfo poring", "@where"]:
		scene._on_chat_submit(line)
	await create_timer(0.8).timeout
	await _shot("commands")
	print("rules: ", scene.sim.rules.describe())
	quit(0)
