extends SceneTree
## Diagnostic: prints ACT layer data for one action of a sprite.
##   godot --headless --path 06_Godot_Project -s res://tests/diag_act.gd -- <sprite path> <action>


func _initialize() -> void:
	var res: Node = root.get_node("RoResources")
	res.mount()
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "data/sprite/몬스터/poring"
	var action := int(args[1]) if args.size() > 1 else 32
	var act := ActFile.decode(res.read(path + ".act"))
	var spr := SprFile.decode(res.read(path + ".spr"))
	print("act v%x actions %d ; spr indexed %d rgba %d" % [act.version, act.actions.size(), spr.indexed_frames.size(), spr.rgba_frames.size()])
	var a: Dictionary = act.actions[action]
	print("action %d frames %d interval %.1f" % [action, a.frames.size(), a.interval])
	for f in a.frames.size():
		for l in a.frames[f].layers:
			var dims := ""
			if l.sprite >= 0:
				var img := spr.image_for(l.sprite, l.type)
				dims = "%dx%d" % [img.get_width(), img.get_height()] if img else "missing"
			print("  f%d spr %d type %d pos %s scale %s mirror %s rot %d %s" % [f, l.sprite, l.type, l.pos, l.scale, l.mirror, l.rotation, dims])
	quit(0)
