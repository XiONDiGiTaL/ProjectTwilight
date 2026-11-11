extends Node
## Virtual file system over a user-supplied Ragnarok client directory.
##
## Precedence:
##   0. Resource pack (Settings.resource_pack_path()): loose overlays found in
##      any "<pack>/<folder>/sprite|palette|texture/..." tree (stored with the
##      usual CP949-as-Latin-1 names), then the pack's *.grf files
##      (CorrectedSprites first, then alphabetical)
##   1. Loose files under <client>/data/...
##   2. GRF archives in DATA.INI order (lower number = higher priority)
## All access is read-only. Paths are Unicode with either separator, e.g.
##   "data/sprite/몬스터/poring.spr"

signal mounted(ok: bool, message: String)

var client_root: String = ""
var archives: Array[GrfArchive] = []
var is_mounted := false
var last_error: String = ""

var pack_root: String = ""
var pack_archives: Array[GrfArchive] = []
var _overlay: Dictionary = {}   # GRF key -> absolute path of a loose pack file
var _spr_cache: Dictionary = {}
var _act_cache: Dictionary = {}


## The Settings autoload, resolved through the tree so this script can also be
## used (and tested) without the project's autoload globals.
static func settings_node() -> Node:
	var loop := Engine.get_main_loop()
	return loop.root.get_node_or_null("Settings") if loop is SceneTree else null


## Mounts a client directory or a plain data folder. Safe to call again with a
## different path. A data folder needs no client executable: it may hold GRF
## archives (with or without DATA.INI) and/or a loose data/ tree.
func mount(root: String = "") -> bool:
	if root == "":
		var s := settings_node()
		root = s.client_path() if s != null else ""
	archives.clear()
	_spr_cache.clear()
	_act_cache.clear()
	is_mounted = false
	client_root = root
	if root == "" or not DirAccess.dir_exists_absolute(root):
		last_error = "No Ragnarok client directory configured."
		mounted.emit(false, last_error)
		return false
	_mount_pack()
	for grf_name in _grf_order(root):
		var grf := GrfArchive.new()
		var err := grf.open(root.path_join(grf_name))
		if err != OK:
			push_warning("Skipping %s: %s" % [grf_name, grf.last_error])
			continue
		archives.append(grf)
	is_mounted = not archives.is_empty() or DirAccess.dir_exists_absolute(root.path_join("data"))
	last_error = "" if is_mounted else "No readable GRF archives or data folder in %s" % root
	mounted.emit(is_mounted, last_error)
	return is_mounted


## GRF load order: DATA.INI [Data] entries first (lower number = higher
## priority), then any other *.grf in the folder and in <folder>/Data, so a
## bare folder of archives works without DATA.INI or a client executable.
func _grf_order(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	var ini := FileAccess.open(root.path_join("DATA.INI"), FileAccess.READ)
	if ini:
		var entries := {}
		var in_data := false
		while not ini.eof_reached():
			var line := ini.get_line().strip_edges()
			if line.begins_with("["):
				in_data = line.to_lower() == "[data]"
			elif in_data and "=" in line:
				var kv := line.split("=", true, 1)
				if kv[0].strip_edges().is_valid_int():
					entries[int(kv[0])] = kv[1].strip_edges()
		var keys := entries.keys()
		keys.sort()
		for k in keys:
			var name := String(entries[k]).replace("\\", "/")
			out.append(name)
			seen[name.to_lower()] = true
	for dir in [root, root.path_join("Data")]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var files := Array(DirAccess.get_files_at(dir)).filter(func(f): return String(f).to_lower().ends_with(".grf"))
		files.sort()
		# data.grf is the main archive, so it loads before optional patches.
		files.sort_custom(func(a, b): return String(a).to_lower() == "data.grf" and String(b).to_lower() != "data.grf")
		for f in files:
			if seen.has(String(f).to_lower()):
				continue
			var name := String(f) if dir == root else "Data/" + String(f)
			out.append(name)
			seen[String(f).to_lower()] = true
	return out


## Mounts the optional resource pack: loose overlays and extra GRFs.
func _mount_pack() -> void:
	pack_archives.clear()
	_overlay.clear()
	var s := settings_node()
	pack_root = s.resource_pack_path() if s != null else ""
	if pack_root == "":
		return
	var grfs := Array(DirAccess.get_files_at(pack_root)).filter(func(f): return String(f).to_lower().ends_with(".grf"))
	grfs.sort_custom(func(a, b): return (String(a).to_lower().contains("correct") and not String(b).to_lower().contains("correct")) or (String(a).to_lower().contains("correct") == String(b).to_lower().contains("correct") and String(a) < String(b)))
	for f in grfs:
		var g := GrfArchive.new()
		if g.open(pack_root.path_join(f)) == OK:
			pack_archives.append(g)
		else:
			push_warning("Resource pack: skipping %s: %s" % [f, g.last_error])
	for sub in DirAccess.get_directories_at(pack_root):
		_index_overlay(pack_root.path_join(sub), "")


func _index_overlay(dir: String, rel: String) -> void:
	for d in DirAccess.get_directories_at(dir):
		var r := (rel + "/" + d) if rel != "" else d
		var lower := d.to_lower()
		if rel == "" and not (lower in ["sprite", "palette", "texture", "data"]):
			_index_overlay(dir.path_join(d), "")   # descend until the data-tree root
			continue
		_index_overlay(dir.path_join(d), r)
	if rel == "":
		return
	for f in DirAccess.get_files_at(dir):
		var key := GrfArchive.normalize(("data/" + rel.replace("\\", "/") + "/" + f).replace("data/data/", "data/"))
		_overlay[key] = dir.path_join(f)


## True when a path is served by the resource pack (overlay or pack GRF).
func from_pack(path: String) -> bool:
	var key := GrfArchive.key_for(path)
	if _overlay.has(key):
		return true
	for a in pack_archives:
		if a.has_file(key):
			return true
	return false


## Absolute path of a file inside the pack folder (fonts, sheets), or "".
func pack_file(relative: String) -> String:
	if pack_root == "":
		var s := settings_node()
		pack_root = s.resource_pack_path() if s != null else ""
	var p := pack_root.path_join(relative) if pack_root != "" else ""
	return p if p != "" and FileAccess.file_exists(p) else ""


func exists(path: String) -> bool:
	if from_pack(path):
		return true
	if FileAccess.file_exists(_loose_path(path)):
		return true
	var key := GrfArchive.key_for(path)
	for a in archives:
		if a.has_file(key):
			return true
	return false


## Returns file bytes or an empty array (last_error set).
func read(path: String) -> PackedByteArray:
	var pkey := GrfArchive.key_for(path)
	if _overlay.has(pkey):
		return FileAccess.get_file_as_bytes(_overlay[pkey])
	for a in pack_archives:
		if a.has_file(pkey):
			return a.read(pkey)
	var loose := _loose_path(path)
	if FileAccess.file_exists(loose):
		return FileAccess.get_file_as_bytes(loose)
	var key := GrfArchive.key_for(path)
	if key == "":
		last_error = "Path not representable in CP949: %s" % path
		return PackedByteArray()
	for a in archives:
		if a.has_file(key):
			var data := a.read(key)
			if data.is_empty():
				last_error = a.last_error
			return data
	last_error = "Not found: %s" % path
	return PackedByteArray()


func load_spr(path: String) -> SprFile:
	if _spr_cache.has(path):
		return _spr_cache[path]
	var data := read(path)
	var spr := SprFile.decode(data) if not data.is_empty() else null
	_spr_cache[path] = spr
	return spr


func load_act(path: String) -> ActFile:
	if _act_cache.has(path):
		return _act_cache[path]
	var data := read(path)
	var act := ActFile.decode(data) if not data.is_empty() else null
	_act_cache[path] = act
	return act


func _loose_path(path: String) -> String:
	return client_root.path_join(path.replace("\\", "/"))
