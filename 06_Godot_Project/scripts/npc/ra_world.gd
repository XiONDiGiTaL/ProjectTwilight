class_name RaWorld
extends RefCounted
## Registry of loaded rAthena-format NPC scripts: NPC definitions (with
## duplicates resolved), global functions, warps, shops and the variable
## stores ($ globals, $@ temp globals, per-NPC "." variables, per-character
## "@" temp variables). Character permanent variables live on the SimUnit
## (script_vars) so they save with the character.
##
## Load list: data/npc/scripts.txt — one path per line; "res://..." for
## Project Twilight scripts, "pack:..." for files in the resource pack
## (e.g. pack:rathena/npc/custom/healer.txt). Missing files are skipped.

const LOAD_LIST := "res://data/npc/scripts.txt"
const GLOBALS_PATH := "user://npc_globals.json"

var npcs: Dictionary = {}        # full name -> def (see RaScriptFile) + "vars", "funcs", "labels"
var functions: Dictionary = {}   # global function name -> AST
var warps: Array = []
var shops: Array = []
var errors: Array = []
var loaded_files: Array = []
var globals: Dictionary = {}     # "$name" -> {idx: value}
var temp_globals: Dictionary = {}
var char_temp: Dictionary = {}   # unit id -> {"@name": {idx: value}}


## Loads every script in the load list. `res` resolves pack: paths.
func load_all(res: Node = null, list_path := LOAD_LIST) -> void:
	_load_globals()
	var list := FileAccess.get_file_as_string(list_path)
	for raw in list.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("//") or line.begins_with("#"):
			continue
		# "a || b": the first alternative that exists (rAthena file, else ours).
		for alt in line.split("||"):
			var entry := String(alt).strip_edges()
			var path := entry
			if entry.begins_with("pack:"):
				path = res.pack_file(entry.substr(5)) if res and res.has_method("pack_file") else ""
			if path != "" and FileAccess.file_exists(path):
				load_text(FileAccess.get_file_as_string(path), entry)
				break
	_resolve_duplicates()


func load_text(text: String, source: String) -> void:
	var f := RaScriptFile.parse(text, source)
	loaded_files.append(source)
	errors.append_array(f.errors)
	for k in f.functions:
		functions[k] = f.functions[k]
	for n in f.npcs:
		var def: Dictionary = n
		def.vars = {}
		def.funcs = {}
		if def.body != null:
			_collect_funcs(def.body, def.funcs)
		npcs[def.name] = def
	warps.append_array(f.warps)
	shops.append_array(f.shops)


## Duplicates share the source script's body and local functions.
func _resolve_duplicates() -> void:
	for name in npcs:
		var d: Dictionary = npcs[name]
		if d.body == null and String(d.duplicate_of) != "":
			var src: Dictionary = _find_npc(String(d.duplicate_of))
			if not src.is_empty():
				d.body = src.body
				d.funcs = src.funcs


func _find_npc(name: String) -> Dictionary:
	if npcs.has(name):
		return npcs[name]
	for k in npcs:
		if RaScriptFile.display_name(String(k)) == name or String(k).begins_with(name + "#") or String(k).begins_with(name + "::"):
			return npcs[k]
	return {}


func find_npc(name: String) -> Dictionary:
	return _find_npc(name)


static func _collect_funcs(node: Variant, out: Dictionary) -> void:
	if not (node is Dictionary):
		return
	if node.k == "func":
		out[node.name] = node.body
	if node.k == "block":
		for s in node.body:
			_collect_funcs(s, out)


## NPCs placed on a map (floating "-" NPCs have no map).
func npcs_on(map_name: String) -> Array:
	var out: Array = []
	for k in npcs:
		var d: Dictionary = npcs[k]
		if String(d.map) == map_name and d.body != null:
			out.append(d)
	return out


## Index of a top-level label in an NPC body, or -1.
static func label_index(body: Dictionary, label: String) -> int:
	var list: Array = body.body
	for i in list.size():
		if list[i].k == "label" and list[i].name == label:
			return i
	return -1


func char_vars_temp(unit_id: int) -> Dictionary:
	if not char_temp.has(unit_id):
		char_temp[unit_id] = {}
	return char_temp[unit_id]


func _load_globals() -> void:
	if FileAccess.file_exists(GLOBALS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GLOBALS_PATH))
		if parsed is Dictionary:
			for k in parsed:
				var arr := {}
				for idx in parsed[k]:
					arr[int(idx)] = parsed[k][idx]
				globals[k] = arr


func save_globals() -> void:
	var f := FileAccess.open(GLOBALS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(globals))
