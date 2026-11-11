extends Node
## Virtual file system over a user-supplied Ragnarok client directory.
##
## Precedence (matches the original client with "read folder" enabled):
##   1. Loose files under <client>/data/...
##   2. GRF archives in DATA.INI order (lower number = higher priority)
## All access is read-only. Paths are Unicode with either separator, e.g.
##   "data/sprite/몬스터/poring.spr"

signal mounted(ok: bool, message: String)

var client_root: String = ""
var archives: Array[GrfArchive] = []
var is_mounted := false
var last_error: String = ""

var _spr_cache: Dictionary = {}
var _act_cache: Dictionary = {}


## Mounts the client directory. Safe to call again with a different path.
func mount(root: String = "") -> bool:
	if root == "":
		root = Settings.client_path()
	archives.clear()
	_spr_cache.clear()
	_act_cache.clear()
	is_mounted = false
	client_root = root
	if root == "" or not DirAccess.dir_exists_absolute(root):
		last_error = "No Ragnarok client directory configured."
		mounted.emit(false, last_error)
		return false
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


## Reads DATA.INI ([Data] N=file.grf). Falls back to data.grf.
func _grf_order(root: String) -> PackedStringArray:
	var out := PackedStringArray()
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
			out.append(entries[k])
	if out.is_empty() and FileAccess.file_exists(root.path_join("data.grf")):
		out.append("data.grf")
	return out


func exists(path: String) -> bool:
	if FileAccess.file_exists(_loose_path(path)):
		return true
	var key := GrfArchive.key_for(path)
	for a in archives:
		if a.has_file(key):
			return true
	return false


## Returns file bytes or an empty array (last_error set).
func read(path: String) -> PackedByteArray:
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
