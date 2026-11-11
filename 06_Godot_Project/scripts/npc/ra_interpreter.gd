class_name RaInterpreter
extends RefCounted
## Runs one rAthena NPC script for one player (tree-walking, asynchronous:
## mes/next/select/menu/input await the host, so the dialog can wait for the
## player). Gameplay effects go through FieldSimulation helpers so the same
## rules apply offline and on a host / server. Unsupported commands are
## logged in `unsupported` and do nothing.

const MAX_STEPS := 400000

var world: RaWorld
var host: RaHost
var sim: FieldSimulation
var player: SimUnit
var npc: Dictionary = {}
var speaker := ""
var unsupported: Dictionary = {}   # command name -> count
var error := ""
var _frames: Array = []            # {locals, args, arg_nodes, arg_frame}
var _steps := 0
var _dialog_open := false


func _init(p_world: RaWorld, p_host: RaHost, p_sim: FieldSimulation, p_player: SimUnit, p_npc: Dictionary) -> void:
	world = p_world
	host = p_host
	sim = p_sim
	player = p_player
	npc = p_npc
	speaker = String(p_npc.get("display", ""))
	host.current_speaker = speaker
	_frames.append({"locals": {}, "args": [], "arg_nodes": [], "arg_frame": null})


## Runs the NPC from the top, or from an event label such as "OnInit".
func run(label := "") -> void:
	var body: Dictionary = npc.get("body", {})
	if body.is_empty():
		return
	var start := 0
	if label != "":
		start = RaWorld.label_index(body, label)
		if start < 0:
			return
		start += 1
	await _exec_list(body.body, start, true)
	if _dialog_open:
		host.finish()


# --- Statements ------------------------------------------------------------------

func _exec_list(list: Array, start: int, top := false) -> Variant:
	var i := start
	while i < list.size():
		var r: Variant = await _exec(list[i])
		if r != null:
			if r.sig == "goto":
				var idx := _label_in(list, String(r.label))
				if idx >= 0:
					i = idx + 1
					continue
				if top:
					_err("goto: label %s not found" % r.label)
					return {"sig": "end"}
			# A top-level label reached by falling through ends at the next event label.
			return r
		if top and list[i].k == "label" and String(list[i].name).begins_with("On") and i > start:
			return null
		i += 1
	return null


static func _label_in(list: Array, name: String) -> int:
	for j in list.size():
		if list[j].k == "label" and list[j].name == name:
			return j
	return -1


func _exec(s: Dictionary) -> Variant:
	_steps += 1
	if _steps > MAX_STEPS:
		_err("step limit reached (infinite loop?)")
		return {"sig": "end"}
	if error != "" or host.aborted:
		return {"sig": "end"}
	match String(s.k):
		"block":
			return await _exec_list(s.body, 0)
		"expr":
			var ev: Variant = await _eval(s.e)
			if ev is Dictionary and ev.has("sig"):
				return ev
			return null
		"if":
			if _truthy(await _eval(s.c)):
				return await _exec(s.then)
			elif s["else"] != null:
				return await _exec(s["else"])
			return null
		"while":
			while _truthy(await _eval(s.c)):
				var r: Variant = await _exec(s.body)
				if r != null:
					if r.sig == "break":
						break
					if r.sig != "continue":
						return r
			return null
		"do":
			while true:
				var r2: Variant = await _exec(s.body)
				if r2 != null:
					if r2.sig == "break":
						break
					if r2.sig != "continue":
						return r2
				if not _truthy(await _eval(s.c)):
					break
			return null
		"for":
			if s.init != null:
				await _eval(s.init)
			while s.c == null or _truthy(await _eval(s.c)):
				var r3: Variant = await _exec(s.body)
				if r3 != null:
					if r3.sig == "break":
						break
					if r3.sig != "continue":
						return r3
				if s.step != null:
					await _eval(s.step)
			return null
		"switch":
			var v: Variant = await _eval(s.e)
			if v is Dictionary and v.has("sig"):
				return v
			var at := -1
			for c in s.cases:
				if c.v == null:
					continue
				if _equal(v, await _eval(c.v)):
					at = int(c.at)
					break
			if at < 0:
				for c in s.cases:
					if c.v == null:
						at = int(c.at)
			if at < 0:
				return null
			var r4: Variant = await _exec_list(s.body, at)
			if r4 != null and r4.sig == "break":
				return null
			return r4
		"label", "nop", "func":
			return null
		"goto":
			return {"sig": "goto", "label": String(s.name)}
		"return":
			return {"sig": "return", "v": (await _eval(s.e)) if s.e != null else 0}
		"break":
			return {"sig": "break"}
		"continue":
			return {"sig": "continue"}
		"cmd":
			return await _command(String(s.name), s.args)
	return null


# --- Expressions ----------------------------------------------------------------

func _eval(e: Variant) -> Variant:
	if e == null:
		return 0
	match String(e.k):
		"num":
			return int(e.v)
		"str":
			return String(e.v)
		"dash":
			return "-"
		"var":
			return _get_var(String(e.name), (await _eval(e.idx)) if e.idx != null else 0)
		"call":
			return await _call(String(e.name), e.args)
		"seq":
			var last: Variant = 0
			for it in e.items:
				last = await _eval(it)
			return last
		"un":
			var u: Variant = await _eval(e.e)
			match String(e.op):
				"!": return 0 if _truthy(u) else 1
				"-": return -_num(u)
				"~": return ~_num(u)
			return _num(u)
		"tern":
			return (await _eval(e.a)) if _truthy(await _eval(e.c)) else (await _eval(e.b))
		"bin":
			var op := String(e.op)
			if op == "&&":
				return 1 if _truthy(await _eval(e.a)) and _truthy(await _eval(e.b)) else 0
			if op == "||":
				return 1 if _truthy(await _eval(e.a)) or _truthy(await _eval(e.b)) else 0
			return _binop(op, await _eval(e.a), await _eval(e.b))
		"assign":
			var t: Dictionary = e.target
			var idx: Variant = (await _eval(t.idx)) if t.idx != null else 0
			var val: Variant = await _eval(e.e)
			if String(e.op) != "=":
				val = _binop(String(e.op).trim_suffix("="), _get_var(String(t.name), idx), val)
			_set_var(String(t.name), idx, val)
			return val
		"incdec":
			var tt: Dictionary = e.target
			var i2: Variant = (await _eval(tt.idx)) if tt.idx != null else 0
			var old := _num(_get_var(String(tt.name), i2))
			var nv := old + (1 if String(e.op) == "++" else -1)
			_set_var(String(tt.name), i2, nv)
			return old if e.post else nv
	return 0


func _binop(op: String, a: Variant, b: Variant) -> Variant:
	if a is String or b is String:
		match op:
			"+": return _str(a) + _str(b)
			"==": return 1 if _str(a) == _str(b) else 0
			"!=": return 1 if _str(a) != _str(b) else 0
			"<": return 1 if _str(a) < _str(b) else 0
			">": return 1 if _str(a) > _str(b) else 0
	var x := _num(a)
	var y := _num(b)
	match op:
		"+": return x + y
		"-": return x - y
		"*": return x * y
		"/": return x / y if y != 0 else 0
		"%": return x % y if y != 0 else 0
		"==": return 1 if x == y else 0
		"!=": return 1 if x != y else 0
		"<": return 1 if x < y else 0
		">": return 1 if x > y else 0
		"<=": return 1 if x <= y else 0
		">=": return 1 if x >= y else 0
		"&": return x & y
		"|": return x | y
		"^": return x ^ y
		"<<": return x << y
		">>": return x >> y
	return 0


static func _num(v: Variant) -> int:
	if v is int:
		return v
	if v is float:
		return int(v)
	if v is String:
		return int(v) if String(v).strip_edges().is_valid_int() else 0
	return 0


static func _str(v: Variant) -> String:
	return v if v is String else str(_num(v))


static func _truthy(v: Variant) -> bool:
	return String(v) != "" if v is String else _num(v) != 0


func _equal(a: Variant, b: Variant) -> bool:
	return _binop("==", a, b) == 1


# --- Variables ------------------------------------------------------------------

## The dictionary that stores `name` (an rAthena variable), by scope prefix.
func _store(name: String) -> Dictionary:
	if name.begins_with(".@"):
		return _frames[-1].locals
	if name.begins_with("."):
		return npc.vars
	if name.begins_with("$@"):
		return world.temp_globals
	if name.begins_with("$"):
		return world.globals
	if name.begins_with("@"):
		return world.char_vars_temp(player.id)
	if name.begins_with("'"):
		return npc.vars
	return player.script_vars


func _get_var(name: String, idx: Variant) -> Variant:
	var i := _num(idx)
	if not name.begins_with(".") and not name.begins_with("@") and not name.begins_with("$") and not name.begins_with("#") and not name.begins_with("'"):
		if i == 0:
			var special: Variant = _char_param(name)
			if special != null:
				return special
			if RaConstants.has(name):
				return RaConstants.value(name)
	var st := _store(name)
	var arr: Dictionary = st.get(name, {})
	var v: Variant = arr.get(i, "" if name.ends_with("$") else 0)
	if v is float:
		v = int(v)
	return v


func _set_var(name: String, idx: Variant, value: Variant) -> void:
	var i := _num(idx)
	if i == 0 and _set_char_param(name, value):
		return
	var st := _store(name)
	if not st.has(name):
		st[name] = {}
	st[name][i] = _str(value) if name.ends_with("$") else _num(value)
	if name.begins_with("$") and not name.begins_with("$@"):
		world.save_globals()


func _array_size(name: String) -> int:
	var arr: Dictionary = _store(name).get(name, {})
	var hi := -1
	var empty: Variant = "" if name.ends_with("$") else 0
	for k in arr:
		if arr[k] != empty and int(k) > hi:
			hi = int(k)
	return hi + 1


## Resolves a variable reference for array builtins: a var node, or getarg(n)
## pointing at a caller's variable. Returns [name, frame_index, start_idx].
func _ref(node: Dictionary) -> Array:
	if node.k == "var":
		return [String(node.name), _frames.size() - 1, (await _eval(node.idx)) if node.idx != null else 0]
	if node.k == "call" and String(node.name) == "getarg":
		var n := _num(await _eval(node.args[0]))
		var f: Dictionary = _frames[-1]
		if n < f.arg_nodes.size() and f.arg_nodes[n] is Dictionary and f.arg_nodes[n].k == "var":
			var an: Dictionary = f.arg_nodes[n]
			return [String(an.name), _frames.size() - 2, 0]
	if node.k == "call" and String(node.name) == "getelementofarray":
		var inner: Array = await _ref(node.args[0])
		inner[2] = _num(await _eval(node.args[1]))
		return inner
	return ["", -1, 0]


## Temporarily makes the frame that owns a referenced variable the top one
## (array builtins called on getarg(n) references). Returns what to restore.
func _enter(frame_index: int) -> Array:
	if frame_index < 0 or frame_index >= _frames.size() - 1:
		return []
	var saved := _frames.slice(frame_index + 1)
	_frames = _frames.slice(0, frame_index + 1)
	return saved


func _leave(saved: Array) -> void:
	_frames.append_array(saved)


# --- Character parameters ----------------------------------------------------------

func _char_param(name: String) -> Variant:
	match name:
		"Zeny": return player.zeny
		"BaseLevel": return player.level
		"JobLevel": return player.job_level
		"Class": return RaConstants.class_of(player.job)
		"BaseClass":
			return RaConstants.roclass(RaConstants.eaclass_of(RaConstants.class_of(player.job)) & 0xFF)
		"BaseJob":
			return RaConstants.roclass(RaConstants.eaclass_of(RaConstants.class_of(player.job)) & 0xFFF)
		"Upper": return 1 if RaConstants.eaclass_of(RaConstants.class_of(player.job)) & 0x1000 else 0
		"Sex": return 1 if player.male else 0
		"SkillPoint": return player.skill_points
		"StatusPoint": return player.status_points
		"Hp": return player.hp
		"MaxHp": return player.max_hp
		"Sp": return player.sp
		"MaxSp": return player.max_sp
		"Weight": return player.inventory.weight(sim.item_db) + player.equipment_weight(sim.item_db)
		"MaxWeight": return player.max_weight()
		"Hair": return player.hair_style
		"HairColor": return player.hair_color
		"ClothesColor": return player.cloth_color
	return null


func _set_char_param(name: String, value: Variant) -> bool:
	match name:
		"Zeny":
			player.zeny = clampi(_num(value), 0, 1000000000)
			sim.events.append({"type": "inventory", "id": player.id})
			return true
		"SkillPoint":
			player.skill_points = maxi(0, _num(value))
			sim.events.append({"type": "skills", "id": player.id})
			return true
		"StatusPoint":
			player.status_points = maxi(0, _num(value))
			sim.events.append({"type": "stats", "id": player.id})
			return true
	return false


# --- Calls -----------------------------------------------------------------------

## Commands at statement level. Returns a control signal or null.
func _command(name: String, args: Array) -> Variant:
	match name:
		"mes":
			var parts: Array = []
			for a in args:
				parts.append(_str(await _eval(a)))
			_dialog_open = true
			host.mes(speaker, RaHost.plain("\n".join(parts)))
			return null
		"next":
			await host.next()
			return null
		"close":
			await host.close_dialog()
			_dialog_open = false
			return {"sig": "end"}
		"close2":
			await host.close_dialog()
			_dialog_open = false
			return null
		"end":
			return {"sig": "end"}
		"menu":
			var labels: Array = []
			var opts: Array = []
			for i in range(0, args.size(), 2):
				opts.append(_str(await _eval(args[i])))
				labels.append(args[i + 1] if i + 1 < args.size() else {"k": "dash"})
			# Each menu string may hold several ":"-separated options for one label.
			var flat: Array = []
			var owner: Array = []
			for i in opts.size():
				for o in String(opts[i]).split(":"):
					flat.append(o)
					owner.append(i)
			var choice := await _ask(flat)
			if choice == 255 or choice < 1:
				return {"sig": "end"}
			_set_var("@menu", 0, choice)
			var lab: Dictionary = labels[owner[choice - 1]]
			if lab.k == "dash":
				return null
			return {"sig": "goto", "label": String(lab.name)}
		"callsub":
			var lname := _label_name(args[0])
			await _call_label(lname, args.slice(1))
			return null
		"goto":
			return {"sig": "goto", "label": _label_name(args[0])}
		"return":
			return {"sig": "return", "v": (await _eval(args[0])) if not args.is_empty() else 0}
	var r: Variant = await _call(name, args)
	if r is Dictionary and r.has("sig"):
		return r
	if String(name) == "warp" or String(name) == "warpparty":
		return {"sig": "end"}
	return null


static func _label_name(node: Dictionary) -> String:
	return String(node.get("name", node.get("v", "")))


func _ask(options: Array) -> int:
	_dialog_open = true
	var clean: Array = []
	for o in options:
		clean.append(RaHost.plain(String(o)))
	var c: int = await host.select(speaker, clean)
	return c


func _call_label(label: String, arg_nodes: Array) -> Variant:
	var body: Dictionary = npc.body
	var at := RaWorld.label_index(body, label)
	if at < 0:
		_err("callsub: label %s not found" % label)
		return 0
	var vals: Array = []
	for a in arg_nodes:
		vals.append(await _eval(a))
	_frames.append({"locals": {}, "args": vals, "arg_nodes": arg_nodes, "arg_frame": _frames.size() - 1})
	var r: Variant = await _exec_list(body.body, at + 1)
	_frames.pop_back()
	if r is Dictionary and r.sig == "end":
		return r
	return r.v if r is Dictionary and r.sig == "return" else 0


func _call_user(fn_body: Dictionary, arg_nodes: Array, pre_values: Variant = null) -> Variant:
	var vals: Array = []
	if pre_values is Array:
		vals = pre_values
	else:
		for a in arg_nodes:
			vals.append(await _eval(a))
	_frames.append({"locals": {}, "args": vals, "arg_nodes": arg_nodes, "arg_frame": _frames.size() - 1})
	var r: Variant = await _exec(fn_body)
	_frames.pop_back()
	if r is Dictionary and r.sig == "end":
		return r
	return r.v if r is Dictionary and r.sig == "return" else 0


## Function calls in expressions (and the non-flow commands).
func _call(name: String, args: Array) -> Variant:
	if npc.funcs.has(name):
		return await _call_user(npc.funcs[name], args)
	var a: Array = []
	match name:
		# Flow / arguments ------------------------------------------------
		"getarg":
			var n := _num(await _eval(args[0]))
			var f: Dictionary = _frames[-1]
			if n < f.args.size():
				return f.args[n]
			return (await _eval(args[1])) if args.size() > 1 else 0
		"getargcount":
			return (_frames[-1].args as Array).size()
		"callfunc":
			var fname := _str(await _eval(args[0]))
			if world.functions.has(fname):
				return await _call_user(world.functions[fname], args.slice(1))
			return await _builtin_function(fname, args.slice(1))
		"select", "prompt":
			var opts: Array = []
			for x in args:
				opts.append_array(_str(await _eval(x)).split(":"))
			var c := await _ask(opts)
			_set_var("@menu", 0, c)
			if c == 255 and name == "select":
				return {"sig": "end"}
			return c
		"input":
			var ref: Array = await _ref(args[0])
			var lo := _num(await _eval(args[1])) if args.size() > 1 else 0
			var hi := _num(await _eval(args[2])) if args.size() > 2 else 2147483647
			if String(ref[0]).ends_with("$"):
				var txt := await host.input_text(speaker)
				_set_var(String(ref[0]), ref[2], txt)
			else:
				var num := await host.input_number(speaker, lo, hi)
				_set_var(String(ref[0]), ref[2], num)
			return 0
		"set":
			var r0: Array = await _ref(args[0])
			var val: Variant = await _eval(args[1])
			if args.size() > 2:   # set .@x, value, "NPC" is not supported
				pass
			_set_var(String(r0[0]), r0[2], val)
			return val
		"setarray":
			var r1: Array = await _ref(args[0])
			var vals: Array = []
			for x in args.slice(1):
				vals.append(await _eval(x))
			var sv1 := _enter(int(r1[1]))
			for k in vals.size():
				_set_var(String(r1[0]), int(r1[2]) + k, vals[k])
			_leave(sv1)
			return 0
		"cleararray":
			var r2: Array = await _ref(args[0])
			var cv: Variant = await _eval(args[1])
			var cn := _num(await _eval(args[2]))
			var sv2 := _enter(int(r2[1]))
			for k in cn:
				_set_var(String(r2[0]), int(r2[2]) + k, cv)
			_leave(sv2)
			return 0
		"deletearray":
			var r3: Array = await _ref(args[0])
			var dn: int = _num(await _eval(args[1])) if args.size() > 1 else -1
			var sv3 := _enter(int(r3[1]))
			var vname := String(r3[0])
			var st := _store(vname)
			var arr: Dictionary = st.get(vname, {})
			var from := int(r3[2])
			var cnt := (_array_size(vname) - from) if dn < 0 else dn
			var keep := {}
			for k in arr:
				if int(k) < from:
					keep[int(k)] = arr[k]
				elif int(k) >= from + cnt:
					keep[int(k) - cnt] = arr[k]
			st[vname] = keep
			_leave(sv3)
			return 0
		"getarraysize":
			var r4: Array = await _ref(args[0])
			var sv4 := _enter(int(r4[1]))
			var size := _array_size(String(r4[0]))
			_leave(sv4)
			return size
		"getelementofarray":
			var r5: Array = await _ref(args[0])
			var ei := _num(await _eval(args[1]))
			var sv5 := _enter(int(r5[1]))
			var ev: Variant = _get_var(String(r5[0]), ei)
			_leave(sv5)
			return ev
	# Everything else: evaluate the arguments first.
	for x in args:
		a.append(await _eval(x))
	return await _builtin(name, a)


func _builtin_function(fname: String, arg_nodes: Array) -> Variant:
	var a: Array = []
	for x in arg_nodes:
		a.append(await _eval(x))
	match fname:
		"F_InsertComma":
			return _comma(_num(a[0]) if not a.is_empty() else 0)
	_unsupported("callfunc " + fname)
	return 0


static func _comma(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _builtin(name: String, a: Array) -> Variant:
	match name:
		# Text ---------------------------------------------------------------
		"rand":
			if a.size() >= 2:
				return sim.rng.randi_range(mini(_num(a[0]), _num(a[1])), maxi(_num(a[0]), _num(a[1])))
			return sim.rng.randi_range(0, maxi(0, _num(a[0]) - 1))
		"strcharinfo":
			match _num(a[0]):
				0: return player.name
				3: return sim.map_name
			return ""
		"getcharid":
			return player.id if _num(a[0]) == 0 else 0
		"getstrlen":
			return _str(a[0]).length()
		"strtolower":
			return _str(a[0]).to_lower()
		"strtoupper":
			return _str(a[0]).to_upper()
		"charat":
			var s0 := _str(a[0])
			var ci := _num(a[1])
			return s0[ci] if ci >= 0 and ci < s0.length() else ""
		"substr":
			return _str(a[0]).substr(_num(a[1]), _num(a[2]) - _num(a[1]) + 1)
		"sprintf":
			return _sprintf(_str(a[0]), a.slice(1))
		"implode":
			return ""
		"gettimetick":
			return int(Time.get_unix_time_from_system()) if _num(a[0]) == 2 else Time.get_ticks_msec()
		"gettime":
			return 0
		"jobname":
			var cid := _num(a[0])
			var job := RaConstants.job_of(cid)
			return String(sim.job_db.get(job, {}).get("name", RaConstants.class_name_of(cid)))
		"eaclass":
			return RaConstants.eaclass_of(_num(a[0]) if not a.is_empty() else RaConstants.class_of(player.job))
		"roclass":
			return RaConstants.roclass(_num(a[0]), (_num(a[1]) == 1) if a.size() > 1 else player.male)
		"checkre":
			return 0      # Pre-Renewal
		"getbattleflag":
			match _str(a[0]):
				"max_hair_style": return CharacterRules.HAIR_STYLES
				"max_hair_color": return 131
				"max_cloth_color": return 699
			return 0
		"getgmlevel", "getgroupid", "getnpcid", "getmapusers", "getwaitingroomstate", "query_sql", "checkvending", "checkchatting":
			return 0
		"playerattached", "isloggedin":
			return 1
		"checkweight":
			return 1
		"getvariableofnpc":
			return 0
		# Dialog-free feedback --------------------------------------------
		"message", "dispbottom":
			host.notify(RaHost.plain(_str(a[a.size() - 1] if name == "message" else a[0])))
			return 0
		"announce", "mapannounce":
			host.notify(RaHost.plain(_str(a[0] if name == "announce" else a[1])))
			return 0
		"specialeffect", "specialeffect2", "misceffect":
			host.effect(_str(a[0]) if not a.is_empty() else "")
			return 0
		"emotion", "cutin", "soundeffect", "soundeffectall", "navigateto", "naviregisterwarp", "initnpctimer", "stopnpctimer", "donpcevent", "waitingroom", "delwaitingroom", "progressbar", "setnpcdisplay", "hideonnpc", "hideoffnpc":
			return 0
		# Character --------------------------------------------------------
		"percentheal":
			sim.script_heal(player, player.max_hp * _num(a[0]) / 100, player.max_sp * _num(a[1]) / 100 if a.size() > 1 else 0)
			return 0
		"heal", "itemheal":
			sim.script_heal(player, _num(a[0]), _num(a[1]) if a.size() > 1 else 0)
			return 0
		"warp":
			host.warp(_str(a[0]), _num(a[1]) if a.size() > 1 else 0, _num(a[2]) if a.size() > 2 else 0)
			return 0
		"getlook":
			match _num(a[0]):
				1: return player.hair_style
				6: return player.hair_color
				7: return player.cloth_color
			return 0
		"setlook", "changelook":
			match _num(a[0]):
				1: player.hair_style = clampi(_num(a[1]), 1, CharacterRules.HAIR_STYLES)
				6: player.hair_color = clampi(_num(a[1]), 0, 131)
				7: player.cloth_color = clampi(_num(a[1]), 0, 699)
			host.appearance_changed()
			return 0
		"jobchange":
			var job2 := RaConstants.job_of(_num(a[0]))
			if job2 == "" or not sim.job_db.has(job2):
				host.notify("%s is not available in this build yet." % RaConstants.class_name_of(_num(a[0])))
				return 0
			sim.script_job_change(player, job2)
			host.appearance_changed()
			return 0
		"getskilllv":
			var code := _skill_code(a[0])
			return int(player.skills.get(code, 0))
		"skill", "addtoskill":
			var code2 := _skill_code(a[0])
			sim.script_grant_skill(player, code2, _num(a[1]) if a.size() > 1 else 1)
			return 0
		"resetskill":
			sim.script_reset_skills(player)
			return 0
		"resetstatus":
			sim.script_reset_stats(player)
			return 0
		"getitem":
			sim.script_get_item(player, _num(a[0]), _num(a[1]) if a.size() > 1 else 1)
			return 0
		"delitem":
			return 1 if sim.script_del_item(player, _num(a[0]), _num(a[1]) if a.size() > 1 else 1) else 0
		"countitem":
			return player.inventory.count(_num(a[0]))
		"sc_start", "sc_start2", "sc_start4", "sc_end", "skilleffect", "npcskilleffect":
			return 0
		# Mounts, carts and falcons (cosmetic options) ----------------------
		"checkfalcon": return 1 if player.options.get("falcon", false) else 0
		"checkcart": return 1 if player.options.get("cart", false) else 0
		"checkriding": return 1 if player.options.get("peco", false) else 0
		"checkdragon", "checkwug", "checkmadogear", "ismounting", "checkwugrider": return 0
		"setfalcon":
			player.options["falcon"] = a.is_empty() or _num(a[0]) != 0
			host.appearance_changed()
			return 0
		"setcart":
			player.options["cart"] = a.is_empty() or _num(a[0]) != 0
			host.appearance_changed()
			return 0
		"setriding":
			player.options["peco"] = a.is_empty() or _num(a[0]) != 0
			host.appearance_changed()
			return 0
		"setdragon", "setmadogear":
			return 0
	_unsupported(name)
	return 0


func _skill_code(v: Variant) -> String:
	if v is String:
		return String(v)
	for code in sim.skill_db:
		if int(sim.skill_db[code].get("id", -1)) == _num(v):
			return code
	return ""


static func _sprintf(fmt: String, vals: Array) -> String:
	var out := ""
	var vi := 0
	var i := 0
	while i < fmt.length():
		if fmt[i] == "%" and i + 1 < fmt.length():
			var c := fmt[i + 1]
			if c == "%":
				out += "%"
			else:
				out += _str(vals[vi]) if vi < vals.size() else ""
				vi += 1
			i += 2
			continue
		out += fmt[i]
		i += 1
	return out


func _unsupported(name: String) -> void:
	unsupported[name] = int(unsupported.get(name, 0)) + 1


func _err(msg: String) -> void:
	if error == "":
		error = "%s: %s" % [npc.get("name", "?"), msg]
		push_warning("NPC script " + error)
