extends SceneTree
## Diagnostic: mount a folder of GRF archives that has no DATA.INI and no
## client executable, then read real files out of it.
##   TWILIGHT_DATA_FOLDER=<folder> godot --headless --path 06_Godot_Project \
##       -s res://tests/diag_datafolder.gd

const RES_SCRIPT := preload("res://scripts/resources/ro_resources.gd")


func _initialize() -> void:
	var folder := OS.get_environment("TWILIGHT_DATA_FOLDER")
	if folder == "" or not DirAccess.dir_exists_absolute(folder):
		print("TWILIGHT_DATA_FOLDER is not set to a folder")
		quit(1)
		return
	var res: Node = RES_SCRIPT.new()
	var ok: bool = res.mount(folder)
	print("folder: ", folder)
	print("mounted=", ok, "  archives=", res.archives.size(), "  error=", res.last_error)
	for a in res.archives:
		print("  archive entries: ", a.entry_count())
	for p in ["data\\sprite\\인간족\\몸통\\남\\초보자_남.spr", "data/sprite/몬스터/poring.spr",
			"data\\palette\\머리\\머리1_남_0.pal"]:
		var data: PackedByteArray = res.read(p)
		print("  read ", p, " -> ", data.size(), " bytes  (", res.last_error, ")")
	res.free()
	quit(0 if ok else 1)
