extends SceneTree
## Captures the status panel in its states: expanded (hovered), idle-faded and collapsed.
##   godot --path 06_Godot_Project -s res://tests/capture_panel.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(900, 260)
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.35, 0.2)
	bg.size = Vector2(900, 260)
	root.add_child(bg)
	var u := SimUnit.new()
	u.name = "Adventurer"
	u.job = "novice"
	u.level = 3; u.job_level = 2; u.hp = 31; u.max_hp = 47; u.sp = 12; u.max_sp = 12; u.base_exp = 10; u.job_exp = 9
	var panels := []
	for i in 3:
		var host := Control.new()
		host.position = Vector2(i * 300, 0)
		host.size = Vector2(300, 260)
		root.add_child(host)
		var p := PlayerStatusPanel.new()
		host.add_child(p)
		panels.append(p)
	await process_frame
	for p in panels:
		p.update_unit(u, 25, 28, true)
	panels[2].set_collapsed(true, false)
	# Panel 1 stays awake (hover simulated by keeping the wake timer), panel 2 fades out.
	for t in 120:
		panels[0]._wake = 1.0
		panels[1]._wake = 0.0
		await process_frame
	panels[2]._wake = 1.0
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://captures/status_panel_states.png")
	print("saved ", ProjectSettings.globalize_path("user://captures/status_panel_states.png"))
	quit(0)
