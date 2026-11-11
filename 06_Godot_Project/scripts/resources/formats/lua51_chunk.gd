class_name Lua51Chunk
extends RefCounted
## Minimal reader for compiled Lua 5.1 chunks (.lub) used by the client's data
## tables (npcidentity.lub, jobname.lub, ...). It does not run Lua: it decodes
## the main function and replays the handful of opcodes that table files use
## (LOADK / GETGLOBAL / GETTABLE / NEWTABLE / SETTABLE / SETGLOBAL / MOVE /
## SETLIST), which is enough to rebuild `name = { key = value, ... }` tables.
## Format: Lua 5.1 header (12 bytes) + function prototype. See ASSET_FORMATS.md.

const OP_MOVE := 0
const OP_LOADK := 1
const OP_GETGLOBAL := 5
const OP_GETTABLE := 6
const OP_SETGLOBAL := 7
const OP_SETTABLE := 9
const OP_NEWTABLE := 10
const OP_SETLIST := 34

var code: PackedInt64Array = []
var constants: Array = []
var last_error := ""
var _data: PackedByteArray
var _pos := 0
var _size_t := 4


static func decode(data: PackedByteArray) -> Lua51Chunk:
	var c := Lua51Chunk.new()
	if data.size() < 12 or data[0] != 0x1B or data[1] != 0x4C or data[4] != 0x51:
		c.last_error = "Not a Lua 5.1 chunk"
		return c
	c._data = data
	c._size_t = data[8]
	c._pos = 12
	c._read_function()
	return c


func _u8() -> int:
	var v := _data[_pos]
	_pos += 1
	return v


func _int() -> int:
	var v := _data.decode_s32(_pos)
	_pos += 4
	return v


func _sizet() -> int:
	var v: int = _data.decode_u32(_pos) if _size_t == 4 else _data.decode_u64(_pos)
	_pos += _size_t
	return v


func _string() -> String:
	var n := _sizet()
	if n == 0:
		return ""
	var raw := _data.slice(_pos, _pos + n - 1)   # drop the trailing NUL
	_pos += n
	return Cp949.decode(raw)


## Reads one prototype; only the main one's code and constants are kept.
func _read_function(main := true) -> void:
	_string()          # source
	_int(); _int()     # line defined / last line
	_u8(); _u8(); _u8(); _u8()   # upvalues, params, vararg, max stack
	var n := _int()
	var ins := PackedInt64Array()
	for i in n:
		ins.append(_data.decode_u32(_pos))
		_pos += 4
	var k: Array = []
	n = _int()
	for i in n:
		match _u8():
			0: k.append(null)
			1: k.append(_u8() != 0)
			3:
				k.append(_data.decode_double(_pos))
				_pos += 8
			4: k.append(_string())
			_:
				last_error = "Unknown constant type"
				return
	if main:
		code = ins
		constants = k
	n = _int()
	for i in n:
		_read_function(false)
	n = _int()          # line info
	_pos += n * 4
	n = _int()          # locals
	for i in n:
		_string(); _int(); _int()
	n = _int()          # upvalue names
	for i in n:
		_string()


## Replays the table-building opcodes. Returns the globals it assigned;
## tables are Dictionaries. `env` supplies globals defined by earlier chunks.
func run_tables(env: Dictionary = {}) -> Dictionary:
	var globals := env.duplicate()
	var regs := {}
	for ins in code:
		var op := ins & 0x3F
		var a := (ins >> 6) & 0xFF
		var c := (ins >> 14) & 0x1FF
		var b := (ins >> 23) & 0x1FF
		var bx := ins >> 14
		match op:
			OP_MOVE:
				regs[a] = regs.get(b)
			OP_LOADK:
				regs[a] = constants[bx] if bx < constants.size() else null
			OP_GETGLOBAL:
				regs[a] = globals.get(constants[bx])
			OP_GETTABLE:
				var t: Variant = regs.get(b)
				regs[a] = (t as Dictionary).get(_rk(regs, c)) if t is Dictionary else null
			OP_NEWTABLE:
				regs[a] = {}
			OP_SETTABLE:
				var t2: Variant = regs.get(a)
				var key: Variant = _rk(regs, b)
				if t2 is Dictionary and key != null:
					(t2 as Dictionary)[_norm(key)] = _rk(regs, c)
			OP_SETGLOBAL:
				globals[constants[bx]] = regs.get(a)
			OP_SETLIST:
				var t3: Variant = regs.get(a)
				if t3 is Dictionary:
					var block := c if c > 0 else 1
					for i in range(1, b + 1):
						(t3 as Dictionary)[(block - 1) * 50 + i] = regs.get(a + i)
	return globals


func _rk(regs: Dictionary, x: int) -> Variant:
	if x >= 256:
		var i := x - 256
		return _norm(constants[i]) if i < constants.size() else null
	return regs.get(x)


## Lua numbers are doubles; integral ones become ints so they work as keys.
static func _norm(v: Variant) -> Variant:
	if v is float and is_equal_approx(v, roundf(v)):
		return int(v)
	return v
