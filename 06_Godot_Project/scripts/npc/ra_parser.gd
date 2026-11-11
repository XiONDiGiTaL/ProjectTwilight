class_name RaParser
extends RefCounted
## Lexer + parser for the rAthena NPC script language (script bodies), written
## from the language's public documentation (doc/script_commands.txt). It
## builds a small AST of Dictionaries consumed by RaInterpreter.
##
## Statements: {k: block|expr|if|while|do|for|switch|label|goto|cmd|return|
##   break|continue|func|nop}
## Expressions: {k: num|str|var|call|un|bin|tern|assign|incdec|dash}
## Variables keep their full rAthena name (".@i", "@menu$", "$global", "Zeny").

const KEYWORDS := ["if", "else", "for", "while", "do", "switch", "case", "default", "goto", "return", "break", "continue", "function"]
const ASSIGN_OPS := ["=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>="]
const OPS3 := ["<<=", ">>="]
const OPS2 := ["==", "!=", "<=", ">=", "&&", "||", "++", "--", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<", ">>", "::"]
const BIN_PREC := {
	"||": 1, "&&": 2, "|": 3, "^": 4, "&": 5, "==": 6, "!=": 6,
	"<": 7, ">": 7, "<=": 7, ">=": 7, "<<": 8, ">>": 8, "+": 9, "-": 9, "*": 10, "/": 10, "%": 10,
}

var tokens: Array = []
var pos := 0
var error := ""


# --- Lexer ---------------------------------------------------------------------

static func tokenize(src: String) -> Array:
	var out: Array = []
	var i := 0
	var n := src.length()
	var line := 1
	while i < n:
		var c := src[i]
		if c == "\n":
			line += 1
			i += 1
			continue
		if c == " " or c == "\t" or c == "\r":
			i += 1
			continue
		if c == "/" and i + 1 < n and src[i + 1] == "/":
			while i < n and src[i] != "\n":
				i += 1
			continue
		if c == "/" and i + 1 < n and src[i + 1] == "*":
			i += 2
			while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
				if src[i] == "\n":
					line += 1
				i += 1
			i += 2
			continue
		if c == "\"":
			var s := ""
			i += 1
			while i < n and src[i] != "\"":
				if src[i] == "\\" and i + 1 < n:
					i += 1
					match src[i]:
						"n": s += "\n"
						"t": s += "\t"
						_: s += src[i]
				else:
					if src[i] == "\n":
						line += 1
					s += src[i]
				i += 1
			i += 1
			out.append({"t": "str", "v": s, "line": line})
			continue
		# Identifiers (with rAthena scope prefixes and $ suffix); also names
		# that start with a digit such as 4_F_KAFRA1.
		var start := i
		var prefix := ""
		if c == "." and i + 1 < n and src[i + 1] == "@":
			prefix = ".@"
		elif c == "." and i + 1 < n and _is_ident_char(src[i + 1]) and not src[i + 1].is_valid_int():
			prefix = "."
		elif c == "$" and i + 1 < n and src[i + 1] == "@":
			prefix = "$@"
		elif c == "$" and i + 1 < n and _is_ident_char(src[i + 1]):
			prefix = "$"
		elif c == "@" and i + 1 < n and _is_ident_char(src[i + 1]):
			prefix = "@"
		elif c == "#" and i + 1 < n and src[i + 1] == "#":
			prefix = "##"
		elif c == "#" and i + 1 < n and _is_ident_char(src[i + 1]):
			prefix = "#"
		elif c == "'" and i + 1 < n and _is_ident_char(src[i + 1]):
			prefix = "'"
		if prefix != "" or _is_ident_start(c) or (c.is_valid_int() and _digit_ident(src, i)):
			i += prefix.length()
			while i < n and _is_ident_char(src[i]):
				i += 1
			if i < n and src[i] == "$":
				i += 1
			out.append({"t": "id", "v": src.substr(start, i - start), "line": line})
			continue
		if c.is_valid_int():
			if c == "0" and i + 1 < n and (src[i + 1] == "x" or src[i + 1] == "X"):
				i += 2
				while i < n and src[i].is_valid_hex_number():
					i += 1
				out.append({"t": "num", "v": src.substr(start + 2, i - start - 2).hex_to_int(), "line": line})
			else:
				while i < n and src[i].is_valid_int():
					i += 1
				out.append({"t": "num", "v": int(src.substr(start, i - start)), "line": line})
			continue
		var three := src.substr(i, 3)
		var two := src.substr(i, 2)
		if three in OPS3:
			out.append({"t": "op", "v": three, "line": line})
			i += 3
		elif two in OPS2:
			out.append({"t": "op", "v": two, "line": line})
			i += 2
		else:
			out.append({"t": "op", "v": c, "line": line})
			i += 1
	out.append({"t": "eof", "v": "", "line": line})
	return out


static func _is_ident_start(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"


static func _is_ident_char(c: String) -> bool:
	return _is_ident_start(c) or c.is_valid_int()


## "4_F_KAFRA1": digits followed by an underscore and letters is a name.
static func _digit_ident(src: String, i: int) -> bool:
	var j := i
	while j < src.length() and src[j].is_valid_int():
		j += 1
	return j < src.length() and src[j] == "_" and j + 1 < src.length() and _is_ident_char(src[j + 1])


# --- Parser ----------------------------------------------------------------------

## Parses a script body (the text between the NPC's outer braces).
static func parse_body(src: String) -> Dictionary:
	var p := RaParser.new()
	p.tokens = tokenize(src)
	var body: Array = []
	while not p._at("eof") and p.error == "":
		body.append(p._statement())
	return {"k": "block", "body": body, "error": p.error}


## Parses a standalone expression (used for header values and tests).
static func parse_expression(src: String) -> Dictionary:
	var p := RaParser.new()
	p.tokens = tokenize(src)
	return p._expr()


func _peek(o := 0) -> Dictionary:
	return tokens[mini(pos + o, tokens.size() - 1)]


func _at(t: String, v: Variant = null) -> bool:
	var tk := _peek()
	return tk.t == t and (v == null or tk.v == v)


func _at_op(v: String, o := 0) -> bool:
	var tk := _peek(o)
	return tk.t == "op" and tk.v == v


func _next() -> Dictionary:
	var tk := _peek()
	pos = mini(pos + 1, tokens.size() - 1)
	return tk


func _expect_op(v: String) -> void:
	if _at_op(v):
		_next()
	elif error == "":
		error = "line %d: expected '%s' near '%s'" % [_peek().line, v, str(_peek().v)]
		pos = tokens.size() - 1


func _statement() -> Dictionary:
	if error != "":
		return {"k": "nop"}
	var tk := _peek()
	if tk.t == "op":
		match String(tk.v):
			"{":
				_next()
				var body: Array = []
				while not _at_op("}") and not _at("eof") and error == "":
					body.append(_statement())
				_expect_op("}")
				return {"k": "block", "body": body}
			";":
				_next()
				return {"k": "nop"}
		var e := _expr()
		_semi()
		return {"k": "expr", "e": e}
	if tk.t == "id":
		var w := String(tk.v)
		# Label "Name:" (not "Name::").
		if _at_op(":", 1) and not (w in KEYWORDS) and w != "case" and w != "default":
			_next()
			_next()
			return {"k": "label", "name": w}
		match w:
			"if":
				_next()
				_expect_op("(")
				var c := _expr()
				_expect_op(")")
				var then_s := _statement()
				var else_s: Variant = null
				if _at("id", "else"):
					_next()
					else_s = _statement()
				return {"k": "if", "c": c, "then": then_s, "else": else_s}
			"while":
				_next()
				_expect_op("(")
				var c2 := _expr()
				_expect_op(")")
				return {"k": "while", "c": c2, "body": _statement()}
			"do":
				_next()
				var body2 := _statement()
				if _at("id", "while"):
					_next()
				_expect_op("(")
				var c3 := _expr()
				_expect_op(")")
				_semi()
				return {"k": "do", "c": c3, "body": body2}
			"for":
				_next()
				_expect_op("(")
				var init: Variant = null if _at_op(";") else _expr_list()
				_expect_op(";")
				var cond: Variant = null if _at_op(";") else _expr()
				_expect_op(";")
				var step: Variant = null if _at_op(")") else _expr_list()
				_expect_op(")")
				return {"k": "for", "init": init, "c": cond, "step": step, "body": _statement()}
			"switch":
				_next()
				_expect_op("(")
				var se := _expr()
				_expect_op(")")
				_expect_op("{")
				var body3: Array = []
				var cases: Array = []
				while not _at_op("}") and not _at("eof") and error == "":
					if _at("id", "case"):
						_next()
						var v := _expr()
						_expect_op(":")
						cases.append({"v": v, "at": body3.size()})
					elif _at("id", "default"):
						_next()
						_expect_op(":")
						cases.append({"v": null, "at": body3.size()})
					else:
						body3.append(_statement())
				_expect_op("}")
				return {"k": "switch", "e": se, "cases": cases, "body": body3}
			"goto":
				_next()
				var lbl := String(_next().v)
				_semi()
				return {"k": "goto", "name": lbl}
			"return":
				_next()
				var rv: Variant = null if _at_op(";") else _expr()
				_semi()
				return {"k": "return", "e": rv}
			"break":
				_next()
				_semi()
				return {"k": "break"}
			"continue":
				_next()
				_semi()
				return {"k": "continue"}
			"function":
				_next()
				var fname := String(_next().v)
				if _at_op(";"):
					_next()
					return {"k": "nop"}
				var fbody := _statement()
				return {"k": "func", "name": fname, "body": fbody}
		# Expression statement (assignment / ++ / --) or a command call.
		var nxt := _peek(1)
		if nxt.t == "op" and (String(nxt.v) in ASSIGN_OPS or nxt.v == "[" or nxt.v == "++" or nxt.v == "--"):
			var e2 := _expr()
			_semi()
			return {"k": "expr", "e": e2}
		_next()
		var args: Array = []
		if _at_op("(") and _paren_then_semi():
			_next()
			if not _at_op(")"):
				args = _arg_list()
			_expect_op(")")
		elif not _at_op(";"):
			args = _arg_list()
		_semi()
		return {"k": "cmd", "name": w, "args": args}
	var e3 := _expr()
	_semi()
	return {"k": "expr", "e": e3}


## True when the parenthesis at the cursor closes right before a ';'.
func _paren_then_semi() -> bool:
	var depth := 0
	var j := pos
	while j < tokens.size():
		var tk: Dictionary = tokens[j]
		if tk.t == "op" and tk.v == "(":
			depth += 1
		elif tk.t == "op" and tk.v == ")":
			depth -= 1
			if depth == 0:
				var after: Dictionary = tokens[mini(j + 1, tokens.size() - 1)]
				return after.t == "op" and after.v == ";"
		elif tk.t == "eof":
			return false
		j += 1
	return false


func _semi() -> void:
	if _at_op(";"):
		_next()


func _arg_list() -> Array:
	var args: Array = []
	while error == "":
		if _at_op("-") and (_at_op(",", 1) or _at_op(";", 1) or _at_op(")", 1)):
			_next()
			args.append({"k": "dash"})
		else:
			args.append(_expr())
		if _at_op(","):
			_next()
		else:
			break
	return args


func _expr_list() -> Dictionary:
	# for (set .@i, 0; ...; set .@i, .@i + 1) uses the "set" command form.
	if _at("id", "set") and not _at_op("(", 1):
		_next()
		var target := _primary()
		_expect_op(",")
		return {"k": "assign", "op": "=", "target": target, "e": _expr()}
	var items: Array = [_expr()]
	while _at_op(","):
		_next()
		items.append(_expr())
	return {"k": "seq", "items": items} if items.size() > 1 else items[0]


func _expr() -> Dictionary:
	return _assign()


func _assign() -> Dictionary:
	var left := _ternary()
	if _peek().t == "op" and String(_peek().v) in ASSIGN_OPS and (left.k == "var"):
		var op := String(_next().v)
		var right := _assign()
		return {"k": "assign", "op": op, "target": left, "e": right}
	return left


func _ternary() -> Dictionary:
	var c := _binary(1)
	if _at_op("?"):
		_next()
		var a := _assign()
		_expect_op(":")
		var b := _assign()
		return {"k": "tern", "c": c, "a": a, "b": b}
	return c


func _binary(min_prec: int) -> Dictionary:
	var left := _unary()
	while error == "":
		var tk := _peek()
		if tk.t != "op" or not BIN_PREC.has(tk.v) or int(BIN_PREC[tk.v]) < min_prec:
			break
		var op := String(_next().v)
		var right := _binary(int(BIN_PREC[op]) + 1)
		left = {"k": "bin", "op": op, "a": left, "b": right}
	return left


func _unary() -> Dictionary:
	if _at_op("!") or _at_op("-") or _at_op("~") or _at_op("+"):
		var op := String(_next().v)
		return {"k": "un", "op": op, "e": _unary()}
	if _at_op("++") or _at_op("--"):
		var op2 := String(_next().v)
		return {"k": "incdec", "op": op2, "target": _unary(), "post": false}
	var e := _primary()
	if _at_op("++") or _at_op("--"):
		return {"k": "incdec", "op": String(_next().v), "target": e, "post": true}
	return e


func _primary() -> Dictionary:
	var tk := _next()
	match tk.t:
		"num":
			return {"k": "num", "v": int(tk.v)}
		"str":
			return {"k": "str", "v": String(tk.v)}
		"id":
			var name := String(tk.v)
			if _at_op("("):
				_next()
				var args: Array = []
				if not _at_op(")"):
					args = _arg_list()
				_expect_op(")")
				return {"k": "call", "name": name, "args": args}
			var idx: Variant = null
			if _at_op("["):
				_next()
				idx = _expr()
				_expect_op("]")
			return {"k": "var", "name": name, "idx": idx}
		"op":
			if tk.v == "(":
				var e := _expr()
				_expect_op(")")
				return e
	if error == "":
		error = "line %d: unexpected '%s'" % [tk.line, str(tk.v)]
	pos = tokens.size() - 1
	return {"k": "num", "v": 0}
