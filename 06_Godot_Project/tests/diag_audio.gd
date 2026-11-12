extends SceneTree
## Lists the client's sound effects (data/wav) by folder and probes the names
## the game uses, plus the map -> BGM table.
##   godot --headless --path 06_Godot_Project -s res://tests/diag_audio.gd [filter]


func _initialize() -> void:
	var res := root.get_node("RoResources")
	if not res.is_mounted:
		res.mount()
	var filter := ""
	for a in OS.get_cmdline_user_args():
		filter = a
	var groups := {}
	var top := []
	for g in res.archives:
		for raw in g.list_raw_names():
			var u := Cp949.decode_latin1(String(raw)).replace("\\", "/").to_lower()
			if not u.begins_with("data/wav/"):
				continue
			var rel := u.trim_prefix("data/wav/")
			var folder := rel.get_base_dir()
			groups[folder] = int(groups.get(folder, 0)) + 1
			if folder == "" or (filter != "" and rel.contains(filter)):
				top.append(rel)
	for k in groups:
		print("%6d  %s" % [groups[k], k])
	top.sort()
	print(" | ".join(top))
	var table := Cp949.decode(res.read("data/mp3nametable.txt")) if res.exists("data/mp3nametable.txt") else ""
	print("mp3nametable lines: ", table.split("\n").size())
	print(table.left(400))
	quit(0)
