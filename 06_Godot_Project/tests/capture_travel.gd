extends SceneTree
## End-to-end map travel: field -> warp -> Prontera, using a temporary save slot.
##   godot --path 06_Godot_Project -s res://tests/capture_travel.gd

const DIR := "user://capture_saves/"


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var out := "user://captures/travel_%s.png" % name
	root.get_texture().get_image().save_png(out)
	print("saved ", ProjectSettings.globalize_path(out))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	SaveGame.save_dir = DIR
	DirAccess.make_dir_recursive_absolute(DIR)
	var ch := CharacterRules.new_character("Wanderer", true, 4, 1, CharacterRules.stats_from_pairs(6, 6, 6))
	ch.cell = [170, 366]
	SaveGame.write("cap1", {"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "saved_at": 0, "character": ch})
	root.get_node("GameSession").slot = "cap1"
	change_scene_to_file("res://scenes/game/field.tscn")
	await create_timer(2.5).timeout
	var field: Node = current_scene
	field.camera.distance = 220.0
	await _shot("field_portal")
	field.walk_to(Vector2i(170, 376))
	var t0 := Time.get_ticks_msec()
	while current_scene == field and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	await create_timer(1.2).timeout
	var town: Node = current_scene
	print("now on ", town.map_name, " at ", town.player.walker.cell)
	await _shot("prontera_arrival")
	SaveGame.delete("cap1")
	quit(0)
