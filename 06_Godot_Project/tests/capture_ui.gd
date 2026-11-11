extends SceneTree
## Renders the glass UI components over a game screenshot for visual review.
##   godot --path 06_Godot_Project -s res://tests/capture_ui.gd
## Uses user://captures/map_prt_fild08_close.png as the backdrop when available.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var bg := TextureRect.new()
	bg.size = Vector2(1280, 720)
	var shot := Image.load_from_file(ProjectSettings.globalize_path("user://captures/map_prt_fild08_close.png")) \
		if FileAccess.file_exists("user://captures/map_prt_fild08_close.png") else null
	if shot:
		bg.texture = ImageTexture.create_from_image(shot)
	root.add_child(bg)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var panel := GlassPanel.new()
	panel.position = Vector2(700, 40)
	layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(UiTheme.label("HP STATES", 12, UiTheme.ACCENT, 600, 3))
	for f in [0.95, 0.75, 0.5, 0.25, 0.05]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		col.add_child(row)
		var b := GlassBar.new()
		b.custom_minimum_size = Vector2(360, 16)
		row.add_child(b)
		b.snap(f * 100.0, 100.0)
		row.add_child(UiTheme.label("%d%%" % roundi(f * 100), 12, UiTheme.TEXT, 600))
	col.add_child(UiTheme.label("DECLINE (CHIP)", 12, UiTheme.ACCENT, 600, 3))
	var declining := GlassBar.new()
	declining.custom_minimum_size = Vector2(360, 16)
	col.add_child(declining)
	declining.snap(90, 100)
	for st in [GlassBar.Style.SP, GlassBar.Style.BASE_EXP, GlassBar.Style.JOB_EXP]:
		var b := GlassBar.new()
		b.style = st
		b.custom_minimum_size = Vector2(360, 12)
		col.add_child(b)
		b.snap(60, 100)
	var status := PlayerStatusPanel.new()
	layer.add_child(status)
	var u := SimUnit.new()
	u.name = "Adventurer"
	u.level = 3; u.job_level = 2; u.hp = 31; u.max_hp = 47; u.sp = 9; u.max_sp = 12; u.base_exp = 10; u.job_exp = 9
	await process_frame
	status.update_unit(u, 25, 28, true)
	declining.set_value(45, 100)
	for _f in 10:
		status._wake = 1.0
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("user://captures/ui_glass.png")
	for r in [[Rect2i(0, 0, 420, 200), "left"], [Rect2i(680, 20, 460, 320), "right"]]:
		var crop := img.get_region(r[0])
		crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
		crop.save_png("user://captures/ui_glass_zoom_%s.png" % r[1])
	print("saved ", ProjectSettings.globalize_path("user://captures/ui_glass.png"))
	quit(0)
