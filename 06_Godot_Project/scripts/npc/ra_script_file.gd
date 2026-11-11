class_name RaScriptFile
extends RefCounted
## Splits an rAthena NPC script file into its top-level declarations:
##   <map>,<x>,<y>,<dir>\tscript\t<Name>\t<sprite>[,<tx>,<ty>],{ ...body... }
##   -\tscript\t<Name>\t-1,{ ... }                 (floating NPC)
##   function\tscript\t<Name>\t{ ... }             (global function)
##   <map>,<x>,<y>,<dir>\tduplicate(<Src>)\t<Name>\t<sprite>
##   <map>,<x>,<y>,<dir>\twarp\t<Name>\t<spanx>,<spany>,<to map>,<tx>,<ty>
##   <map>,<x>,<y>,<dir>\tshop\t<Name>\t<sprite>,<item>:<price>,...
## Monsters, mapflags and other declarations are skipped (reported).

var npcs: Array = []         # {name, display, map, x, y, dir, sprite, body, duplicate_of, trigger, source}
var functions: Dictionary = {}  # name -> body AST
var warps: Array = []        # {map, cell, span, to_map, to_cell, name}
var shops: Array = []        # {name, display, map, x, y, dir, sprite, items: [[id, price]]}
var errors: Array = []
var skipped := 0


static func parse(text: String, source := "") -> RaScriptFile:
	var f := RaScriptFile.new()
	f._parse(text, source)
	return f


static func display_name(full: String) -> String:
	var n := full
	var cut := n.find("::")
	if cut >= 0:
		n = n.substr(0, cut)
	cut = n.find("#")
	if cut >= 0:
		n = n.substr(0, cut)
	return n.strip_edges()


func _parse(text: String, source: String) -> void:
	var i := 0
	var n := text.length()
	while i < n:
		# Skip whitespace and comments at the top level.
		var c := text[i]
		if c == " " or c == "\t" or c == "\r" or c == "\n":
			i += 1
			continue
		if text.substr(i, 2) == "//":
			i = _line_end(text, i)
			continue
		if text.substr(i, 2) == "/*":
			var e := text.find("*/", i + 2)
			i = n if e < 0 else e + 2
			continue
		var line_end := _line_end(text, i)
		var brace := text.find("{", i)
		var header := text.substr(i, line_end - i)
		var cols := header.split("\t", false)
		var kind := String(cols[1]).strip_edges() if cols.size() > 1 else ""
		if (kind == "script" or kind.begins_with("script")) and brace >= 0:
			var close := _match_brace(text, brace)
			if close < 0:
				errors.append("%s: unbalanced braces after '%s'" % [source, header.left(60)])
				return
			var head := text.substr(i, brace - i)
			var body_src := text.substr(brace + 1, close - brace - 1)
			_add_script(head.split("\t", false), body_src, source)
			i = close + 1
			continue
		if kind.begins_with("duplicate(") and cols.size() >= 3:
			var src_name := kind.substr(10, kind.length() - 11)
			var pos := _pos(String(cols[0]))
			var spr := String(cols[3]).split(",")[0] if cols.size() > 3 else "-1"
			npcs.append({"name": String(cols[2]).strip_edges(), "display": display_name(String(cols[2])), "map": pos.map,
				"x": pos.x, "y": pos.y, "dir": pos.dir, "sprite": spr.strip_edges(), "body": null,
				"duplicate_of": src_name, "trigger": _trigger(String(cols[3]) if cols.size() > 3 else ""), "source": source})
		elif kind == "warp" or kind == "warp2":
			if cols.size() >= 4:
				var pw := _pos(String(cols[0]))
				var a := String(cols[3]).split(",")
				if a.size() >= 5:
					warps.append({"map": pw.map, "cell": Vector2i(pw.x, pw.y), "span": Vector2i(int(a[0]), int(a[1])),
						"to_map": String(a[2]).strip_edges(), "to_cell": Vector2i(int(a[3]), int(a[4])), "name": String(cols[2])})
		elif kind == "shop" and cols.size() >= 4:
			var ps := _pos(String(cols[0]))
			var parts := String(cols[3]).split(",")
			var items: Array = []
			for k in range(1, parts.size()):
				var ip := String(parts[k]).split(":")
				if ip.size() == 2 and String(ip[0]).strip_edges().is_valid_int():
					items.append([int(ip[0]), int(ip[1])])
			shops.append({"name": String(cols[2]), "display": display_name(String(cols[2])), "map": ps.map, "x": ps.x,
				"y": ps.y, "dir": ps.dir, "sprite": String(parts[0]).strip_edges(), "items": items})
		else:
			skipped += 1
		i = line_end
	return


func _add_script(cols: PackedStringArray, body_src: String, source: String) -> void:
	var ast := RaParser.parse_body(body_src)
	var name := String(cols[2]).strip_edges() if cols.size() > 2 else "?"
	if String(ast.get("error", "")) != "":
		errors.append("%s: %s: %s" % [source, name, ast.error])
	if String(cols[0]).strip_edges() == "function":
		functions[name] = ast
		return
	var pos := _pos(String(cols[0]))
	var sprite_col := String(cols[3]) if cols.size() > 3 else "-1"
	npcs.append({"name": name, "display": display_name(name), "map": pos.map, "x": pos.x, "y": pos.y, "dir": pos.dir,
		"sprite": sprite_col.split(",")[0].strip_edges(), "body": ast, "duplicate_of": "",
		"trigger": _trigger(sprite_col), "source": source})


static func _pos(s: String) -> Dictionary:
	var p := s.strip_edges().split(",")
	if p.size() < 3 or p[0] == "-":
		return {"map": "", "x": 0, "y": 0, "dir": 0}
	return {"map": String(p[0]), "x": int(p[1]), "y": int(p[2]), "dir": int(p[3]) if p.size() > 3 else 0}


## "<sprite>,<tx>,<ty>" -> touch area half-size (OnTouch), or (-1, -1).
static func _trigger(s: String) -> Vector2i:
	var p := s.split(",")
	if p.size() >= 3 and String(p[1]).strip_edges().is_valid_int() and String(p[2]).strip_edges().is_valid_int():
		return Vector2i(int(p[1]), int(p[2]))
	return Vector2i(-1, -1)


static func _line_end(text: String, i: int) -> int:
	var e := text.find("\n", i)
	return text.length() if e < 0 else e + 1


## Index of the brace closing the one at `open`, skipping strings and comments.
static func _match_brace(text: String, open: int) -> int:
	var depth := 0
	var i := open
	var n := text.length()
	while i < n:
		var c := text[i]
		if c == "\"":
			i += 1
			while i < n and text[i] != "\"":
				if text[i] == "\\":
					i += 1
				i += 1
		elif c == "/" and i + 1 < n and text[i + 1] == "/":
			i = _line_end(text, i) - 1
		elif c == "/" and i + 1 < n and text[i + 1] == "*":
			var e := text.find("*/", i + 2)
			i = n if e < 0 else e + 1
		elif c == "{":
			depth += 1
		elif c == "}":
			depth -= 1
			if depth == 0:
				return i
		i += 1
	return -1
