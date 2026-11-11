extends SceneTree
## Visual check: Job Guide dialogue in Prontera and the change to Swordman.
##   godot --path 06_Godot_Project -s res://tests/capture_jobchange.gd

const DIR := "user://capture_saves/"


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var out := "user://captures/job_%s.png" % name
	root.get_texture().get_image().save_png(out)
	print("saved ", ProjectSettings.globalize_path(out))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	SaveGame.save_dir = DIR
	DirAccess.make_dir_recursive_absolute(DIR)
	var ch := CharacterRules.new_character("Ready Novice", true, 6, 3, CharacterRules.stats_from_pairs(8, 5, 6))
	ch.map = "prontera"
	ch.cell = [151, 50]
	ch.job_level = 10
	ch.skills = {"NV_BASIC": 9, "NV_FIRSTAID": 1, "NV_TRICKDEAD": 1}
	ch.skill_points = 0
	SaveGame.write("cap2", {"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "saved_at": 0, "character": ch})
	root.get_node("GameSession").slot = "cap2"
	change_scene_to_file("res://scenes/game/field.tscn")
	await create_timer(2.5).timeout
	var field: Node = current_scene
	field.camera.distance = 160.0
	var nid := 0
	for id in field.sim.npcs:
		if field.sim.npcs[id].kind == "job_guide":
			nid = id
	field.sim.command_talk(field.player.id, nid)
	var t0 := Time.get_ticks_msec()
	while not field.hud.dialog.visible and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	await create_timer(0.3).timeout
	await _shot("dialog")
	field._on_dialog_choice(0)  # Swordman
	await create_timer(0.2).timeout
	field._on_dialog_choice(0)  # confirm
	await create_timer(0.9).timeout
	print("job now ", field.player.job, " sprite ", field.player.sprite, " hp ", field.player.max_hp)
	await _shot("swordman")
	SaveGame.delete("cap2")
	quit(0)
