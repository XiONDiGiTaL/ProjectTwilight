extends SceneTree
## Diagnostic: how many warp portals and spawns RaWorld loads, per map.
##   godot --headless --path 06_Godot_Project -s res://tests/diag_warps.gd
## Needs the rAthena npc folder in the resource pack (Resources/rathena).

const MAPS := ["prontera", "prt_fild08", "new_1-1", "geffen", "izlude", "payon", "morocc", "alberta"]


func _initialize() -> void:
	var res: Node = root.get_node("RoResources")
	if not res.is_mounted:
		res.mount()
	var world := RaWorld.new()
	world.load_all(res)
	print("files=%d warps=%d npcs=%d shops=%d monsters=%d errors=%d" % [world.loaded_files.size(),
		world.warps.size(), world.npcs.size(), world.shops.size(), world.monsters.size(), world.errors.size()])
	for m in MAPS:
		var ws: Array = world.warps_on(m)
		var targets := {}
		for w in ws:
			targets[String(w.to_map)] = true
		print("%-12s %3d portals  %3d spawn lines  -> %s" % [m, ws.size(), world.monsters_on(m).size(),
			", ".join(targets.keys())])
	var sample: Array = world.warps_on("prt_fild08")
	print("prt_fild08 sample: ", sample.slice(0, 3))
	quit(0)
