extends SceneTree
## Visual check: rAthena / Project Twilight script NPCs in Prontera, the
## warper menu and the stylist.
##   godot --path 06_Godot_Project -s res://tests/capture_npcs.gd   (not headless)


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for _f in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://captures/%s.png" % name)
	print("saved ", ProjectSettings.globalize_path("user://captures/%s.png" % name))


func _talk(scene: Node, name_part: String) -> Dictionary:
	for id in scene.sim.npcs:
		var n: Dictionary = scene.sim.npcs[id]
		if String(n.get("script", "")).contains(name_part):
			return n
	return {}


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/game/field.tscn").instantiate()
	scene.save_slot = ""
	scene.map_name = "prontera"
	scene.start_cell = Vector2i(156, 180)
	root.add_child(scene)
	await _frames(40)
	var count := 0
	for id in scene.sim.npcs:
		if String(scene.sim.npcs[id].kind) == "script":
			count += 1
			print("NPC ", scene.sim.npcs[id].name, " at ", scene.sim.npcs[id].cell, " sprite ", scene.sim.npcs[id].sprite)
	print("script NPCs in prontera: ", count)
	scene.camera.distance = 230.0
	await _frames(30)
	await _shot("npc_prontera")
	# Warper: open, show the category menu, then Towns.
	var w := _talk(scene, "Warper")
	scene._run_npc_script(w)
	await _frames(20)
	await _shot("npc_warper_menu")
	scene.hud.dialog.chosen.emit(1)   # Towns (rAthena) / Towns (Twilight: after Next)
	await _frames(20)
	await _shot("npc_warper_towns")
	scene.hud.dialog.chosen.emit(-1)  # cancel
	await _frames(10)
	# Stylist.
	var s := _talk(scene, "Stylist")
	scene._run_npc_script(s)
	await _frames(15)
	scene.hud.dialog.chosen.emit(1)   # hairstyle (rAthena: "Cloth color" is 1)
	await _frames(15)
	scene.hud.dialog.chosen.emit(0)   # next style
	await _frames(25)
	await _shot("npc_stylist")
	scene.hud.dialog.chosen.emit(-1)
	await _frames(10)
	quit(0)
