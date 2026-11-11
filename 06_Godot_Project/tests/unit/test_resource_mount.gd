extends RefCounted
## Data-folder mounting: the game needs the player's data, not their executable.
## A folder of GRF archives (with or without DATA.INI) or a loose data/ tree
## must mount on its own.

## RoResources is an autoload without a class_name, so instantiate its script.
const RES_SCRIPT := preload("res://scripts/resources/ro_resources.gd")


static func _write(path: String, text := "") -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


func test_grf_folder_without_data_ini(_t) -> Variant:
	var root := ProjectSettings.globalize_path("user://mount_test_a")
	DirAccess.make_dir_recursive_absolute(root)
	_write(root.path_join("data.grf"))
	_write(root.path_join("patch.grf"))
	_write(root.path_join("extra.grf"))
	var res: Node = RES_SCRIPT.new()
	var order: PackedStringArray = res._grf_order(root)
	res.free()
	if order.size() != 3:
		return "expected 3 archives, got %s" % [order]
	return true if String(order[0]).to_lower() == "data.grf" else "data.grf should load first: %s" % [order]


func test_data_ini_order_then_extras(_t) -> Variant:
	var root := ProjectSettings.globalize_path("user://mount_test_b")
	DirAccess.make_dir_recursive_absolute(root.path_join("Data"))
	_write(root.path_join("DATA.INI"), "[Data]\n1=extra.grf\n")
	_write(root.path_join("extra.grf"))
	_write(root.path_join("data.grf"))
	_write(root.path_join("Data").path_join("patch.grf"))
	var res: Node = RES_SCRIPT.new()
	var order: PackedStringArray = res._grf_order(root)
	res.free()
	if order.is_empty() or String(order[0]) != "extra.grf":
		return "DATA.INI entry should load first: %s" % [order]
	if not order.has("data.grf") or not order.has("Data/patch.grf"):
		return "other archives in the folder and Data/ should still load: %s" % [order]
	return true


func test_mount_loose_data_folder(_t) -> Variant:
	var root := ProjectSettings.globalize_path("user://mount_test_c")
	DirAccess.make_dir_recursive_absolute(root.path_join("data/texture"))
	_write(root.path_join("data/texture/probe.bmp"), "x")
	var res: Node = RES_SCRIPT.new()
	var ok: bool = res.mount(root)
	var served: bool = res.exists("data/texture/probe.bmp")
	var bytes: int = res.read("data/texture/probe.bmp").size()
	res.free()
	if not ok:
		return "a folder with only data/ should mount"
	if not served or bytes != 1:
		return "loose data files should be readable"
	return true


func test_mount_rejects_missing_folder(_t) -> Variant:
	var res: Node = RES_SCRIPT.new()
	var ok: bool = res.mount(ProjectSettings.globalize_path("user://mount_test_missing"))
	res.free()
	return true if not ok else "a missing folder must not mount"
