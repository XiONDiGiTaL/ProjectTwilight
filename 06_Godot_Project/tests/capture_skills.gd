extends SceneTree
## Visual check: skill window, hotkey bar with a skill and potions, sitting.
##   godot --path 06_Godot_Project -s res://tests/capture_skills.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/game/field.tscn").instantiate()
	scene.save_slot = ""
	root.add_child(scene)
	await process_frame
	var sim: FieldSimulation = scene.sim
	var p: SimUnit = scene.player
	scene.camera.distance = 150.0
	sim._gain_exp(p, 0, 120)  # a few job levels -> skill points
	for i in 3:
		sim.command_learn_skill(p.id, "NV_BASIC")
	scene.hud.hotkeys.set_entry(0, {"type": "skill", "id": "NV_FIRSTAID"})
	scene.hud.hotkeys.set_entry(1, {"type": "skill", "id": "NV_TRICKDEAD"})
	scene.hud.hotkeys.set_entry(2, {"type": "item", "id": 501})
	sim.command_sit(p.id)
	scene.hud.skill_window.toggle(true)
	scene.hud.skill_window.position = Vector2(860, 170)
	for _f in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://captures/skills.png")
	print("saved ", ProjectSettings.globalize_path("user://captures/skills.png"), " basic ", p.skills.NV_BASIC, " sitting ", p.sitting)
	quit(0)
