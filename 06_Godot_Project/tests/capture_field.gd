extends SceneTree
## Visual check of the field scene: idle, walking east, and a ring of 8
## characters each facing outward (direction d placed at offset DIR_VECTORS[d]).
##   godot --path 06_Godot_Project -s res://tests/capture_field.gd
## Output goes to user://captures and is never committed.


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for _f in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := "user://captures/field_%s.png" % name
	var img := root.get_texture().get_image()
	img.save_png(out)
	var crop := img.get_region(Rect2i(440, 160, 400, 400))
	crop.resize(800, 800, Image.INTERPOLATE_NEAREST)
	crop.save_png(out.replace(".png", "_zoom.png"))
	print("saved ", ProjectSettings.globalize_path(out))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/game/field.tscn").instantiate()
	scene.save_slot = ""
	root.add_child(scene)
	await process_frame
	var walker: GridWalker = scene.walker
	if walker == null:
		print("field failed to load")
		quit(1)
		return
	scene.camera.distance = 160.0
	print("spawned at ", walker.cell)
	await _shot("idle")

	var start := walker.cell
	var ok: bool = scene.walk_to(start + Vector2i(12, 0))
	print("walk east ok=", ok)
	await create_timer(0.6).timeout
	print("walking: cell ", walker.cell, " dir ", walker.direction, " moving ", walker.is_moving())
	await _shot("walk_east")
	await create_timer(2.5).timeout
	print("after walk: cell ", walker.cell, " moving ", walker.is_moving())

	# Direction ring around the player.
	var res: Node = root.get_node("RoResources")
	var centre := start
	scene.camera.follow = null
	scene.camera.focus = scene.map.cell_to_world(centre.x, centre.y)
	scene.camera.distance = 110.0
	for d in 8:
		var w := GridWalker.new(centre + GridWalker.DIR_VECTORS[d] * 4)
		w.direction = d
		var a := PlayerAvatar.new()
		a.walker = w
		a.map = scene.map
		scene.add_child(a)
		a.build(res, "초보자", d % 2 == 0, 1 + d, d % 4)
	await _shot("direction_ring")
	scene.camera.yaw_deg = 90.0
	for a in scene.get_children():
		if a is PlayerAvatar:
			a.camera_yaw = 90.0
	await _shot("direction_ring_yaw90")
	quit(0)
