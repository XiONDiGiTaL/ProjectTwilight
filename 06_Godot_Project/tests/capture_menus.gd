extends SceneTree
## Visual check of the title screen, character select and character creation.
## Uses a separate save folder so real saves are never touched.
##   godot --path 06_Godot_Project -s res://tests/capture_menus.gd

const DIR := "user://capture_saves/"


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String, settle := 30) -> void:
	for _f in settle:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := "user://captures/menu_%s.png" % name
	root.get_texture().get_image().save_png(out)
	print("saved ", ProjectSettings.globalize_path(out))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await _shot("title", 60)
	menu.queue_free()

	SaveGame.save_dir = DIR
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)
	var samples := [["Aurelia", false, 7, 4, [3, 8, 4], 12], ["Kaito", true, 4, 2, [9, 5, 2], 5]]
	for i in samples.size():
		var s: Array = samples[i]
		var ch := CharacterRules.new_character(s[0], s[1], s[2], s[3], CharacterRules.stats_from_pairs(s[4][0], s[4][1], s[4][2]))
		ch.cell = [ch.cell.x, ch.cell.y]
		ch.level = s[5]
		SaveGame.write("slot%d" % (i + 1), {"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "saved_at": 0, "character": ch})
	var sel: Node = load("res://scenes/ui/character_select.tscn").instantiate()
	root.add_child(sel)
	await _shot("select", 60)
	sel._select(2)  # empty slot -> creation form
	sel._name_edit.text = "Twilight"
	sel._male = false
	sel._hair_style = 10
	sel._hair_color = 6
	sel._refresh_look()
	for i in 3:
		sel._hexagon.raise("dex")
	sel._hexagon.raise("agi")
	await _shot("create", 40)
	sel.queue_free()
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)
	quit(0)
