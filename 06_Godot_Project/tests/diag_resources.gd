extends SceneTree
## Lists what the optional resource-pack GRFs contain (by folder), plus
## palette counts for a few looks.
##   godot --headless --path 06_Godot_Project -s res://tests/diag_resources.gd


func _initialize() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../Resources").simplify_path()
	for f in DirAccess.get_files_at(dir):
		if not f.to_lower().ends_with(".grf"):
			continue
		var g := GrfArchive.new()
		if g.open(dir.path_join(f)) != OK:
			print(f, ": ", g.last_error)
			continue
		var groups := {}
		var pal_counts := {}
		var bodies := []
		for raw in g.list_raw_names():
			var u := Cp949.decode_latin1(String(raw)).replace("\\", "/")
			var parts := u.split("/")
			var k := "/".join(parts.slice(0, mini(parts.size() - 1, 4)))
			groups[k] = int(groups.get(k, 0)) + 1
			if u.contains("palette/") and parts[-1].ends_with(".pal"):
				var stem := parts[-1].get_basename()
				var cut := stem.rfind("_")
				var base := parts[-2] + "/" + stem.substr(0, cut)
				pal_counts[base] = int(pal_counts.get(base, 0)) + 1
			elif u.contains("몸통") and u.ends_with(".spr"):
				bodies.append(parts[-1])
		print("== %s: %d files" % [f, g.entry_count()])
		for k in groups:
			print("  %6d  %s" % [groups[k], k])
		for probe in ["머리/머리2_남", "머리/머리2_여", "머리/머리10_여", "몸/초보자_남", "몸/초보자_여", "몸/검사_남", "몸/성직자_여", "몸/기사_남", "몸/프리스트_여"]:
			if pal_counts.has(probe):
				print("  palettes %s: %d" % [probe, pal_counts[probe]])
		if not bodies.is_empty():
			print("  bodies: ", ", ".join(bodies.slice(0, 40)))
	quit(0)
