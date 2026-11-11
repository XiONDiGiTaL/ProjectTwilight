extends SceneTree
## Diagnostic: is the menu backdrop viewport sized and rendering a map?


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var b := MenuBackdrop.new()
	host.add_child(b)
	for _f in 10:
		await process_frame
	print("container size ", b.size, " vp size ", b._vp.size, " map ", b._map != null,
		" ground ", b._map.ground != null if b._map else false, " cam pos ", b._cam.global_position,
		" focus ", b._cam.focus, " cam current ", b._cam.current)
	quit(0)
