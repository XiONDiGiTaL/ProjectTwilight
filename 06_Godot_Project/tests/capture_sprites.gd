extends SceneTree
## Renders a contact sheet of sprite frames to user://captures for visual review.
##   godot --path 06_Godot_Project -s res://tests/capture_sprites.gd
## (Needs a rendering device, so do not pass --headless.)
## Output stays in the user data folder and is never committed.

const TARGETS := [
	["data/sprite/몬스터/poring", [0, 8, 16, 24]],
	["data/sprite/인간족/몸통/남/초보자_남", [0, 8, 16, 32]],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var res: Node = root.get_node("RoResources")
	if not res.mount():
		print("mount failed: ", res.last_error)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("user://captures")
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 200)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new(); bg.color = Color(0.16, 0.2, 0.17); bg.size = Vector2(640, 200)
	vp.add_child(bg)
	for t in TARGETS:
		var base: String = t[0]
		var spr: SprFile = res.load_spr(base + ".spr")
		var act: ActFile = res.load_act(base + ".act")
		if spr == null or act == null:
			print("load failed ", base, ": ", res.last_error)
			continue
		var nodes: Array = []
		var acts: Array = t[1]
		for i in acts.size():
			var s := ActSprite.new()
			s.setup(spr, act)
			s.action = acts[i]
			s.set_process(false)
			s.scale = Vector2(2, 2)
			s.position = Vector2(80 + i * 160, 150)
			vp.add_child(s)
			nodes.append(s)
		for _f in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var out := "user://captures/%s.png" % base.get_file()
		img.save_png(out)
		print("saved ", ProjectSettings.globalize_path(out))
		for n in nodes:
			n.queue_free()
	quit(0)
