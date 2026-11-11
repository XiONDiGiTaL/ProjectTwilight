extends SceneTree
## Renders the ornate bars on their own for visual review.
##   godot --path 06_Godot_Project -s res://tests/capture_ui.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.12, 0.2)
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	var fracs := [0.95, 0.75, 0.5, 0.25, 0.01, 0.0]
	for i in fracs.size():
		var big := OrnateBar.new()
		big.position = Vector2(40 + (i % 2) * 620, 30 + (i / 2) * 90)
		big.size = Vector2(560, 64)
		root.add_child(big)
		big.snap(fracs[i] * 100.0, 100.0)
		var l := Label.new()
		l.text = "%d%%" % roundi(fracs[i] * 100)
		l.position = big.position + Vector2(260, 62)
		root.add_child(l)
	# Small in-world size, a decline in progress, and the other styles.
	var small := OrnateBar.new()
	small.position = Vector2(40, 330)
	small.size = Vector2(110, 18)
	root.add_child(small)
	small.snap(70, 100)
	var declining := OrnateBar.new()
	declining.position = Vector2(200, 320)
	declining.size = Vector2(300, 36)
	root.add_child(declining)
	declining.snap(90, 100)
	await process_frame
	declining.set_value(45, 100)
	var styles := [OrnateBar.Style.SP, OrnateBar.Style.BASE_EXP, OrnateBar.Style.JOB_EXP]
	for i in styles.size():
		var b := OrnateBar.new()
		b.style = styles[i]
		b.show_diamond = false
		b.position = Vector2(560, 320 + i * 40)
		b.size = Vector2(300, 30)
		root.add_child(b)
		b.snap(60, 100)
	for _f in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("user://captures/ui_bars.png")
	print("saved ", ProjectSettings.globalize_path("user://captures/ui_bars.png"))
	quit(0)
