extends SceneTree
## Renders overview shots of maps to user://captures for visual review.
##   godot --path 06_Godot_Project -s res://tests/capture_maps.gd [-- map1 map2 ...]
## (Needs a rendering device, so do not pass --headless.) Output is never committed.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var res: Node = root.get_node("RoResources")
	if not res.mount():
		print("mount failed: ", res.last_error)
		quit(1)
		return
	var maps := OS.get_cmdline_user_args()
	if maps.is_empty():
		maps = PackedStringArray(["prontera", "prt_fild08", "izlude"])
	DirAccess.make_dir_recursive_absolute("user://captures")
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.6, 0.8)
	vp.add_child(env)
	var cam := RoCamera.new()
	vp.add_child(cam)
	for m in maps:
		var map := RoMap.new()
		vp.add_child(map)
		if not map.load_map(m):
			print("load failed ", m)
			map.queue_free()
			continue
		print("%s built in %d ms, models %s" % [m, map.load_ms, map.model_stats])
		var shots := [["overview", 0.0, 1100.0, 60.0], ["close", 45.0, 260.0, 50.0]]
		for s in shots:
			cam.focus = map.center()
			cam.yaw_deg = s[1]
			cam.distance = s[2]
			cam.pitch_deg = s[3]
			for _f in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var out := "user://captures/map_%s_%s.png" % [m, s[0]]
			vp.get_texture().get_image().save_png(out)
			print("saved ", ProjectSettings.globalize_path(out))
		map.queue_free()
		await process_frame
	quit(0)
