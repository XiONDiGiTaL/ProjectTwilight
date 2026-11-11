class_name RsmFile
extends RefCounted
## Decoder for .rsm / .rsm2 models (versions 1.4, 1.5, 2.2, 2.3 observed in kRO 2025).
##
## Header: "GRSM" | u8 major | u8 minor | i32 anim_length | i32 shade_type
##   [>= 1.4: u8 alpha] then
##   1.x : 16 reserved | i32 n + n * char[40] textures | char[40] root | i32 node_count
##   2.x : f32 fps | [2.2 only: i32 n + n * lenstr textures] | i32 n + n * lenstr roots | i32 node_count
## Node:
##   name, parent (char[40] in 1.x, length-prefixed in 2.x)
##   i32 n texture refs: 1.x/2.2 = i32 indices into the global list, 2.3 = lenstr names
##   f32 offset[9] (3x3) | f32 position[3]
##   1.x only: f32 translation[3] | f32 rot_angle | f32 rot_axis[3] | f32 scale[3]
##   i32 n vertices (f32 x3) | i32 n tex coords ([>=1.2: u32 colour] f32 u, v)
##   i32 n faces: [2.x: i32 record length] u16 v[3] | u16 t[3] | u16 tex | u16 pad
##                | i32 two_sided | [>=1.2: i32 smooth_group] (+ extra groups in 2.x)
##   [>= 1.6: scale keys (i32 frame, f32 xyz, f32 data)]
##   rotation keys (i32 frame, f32 quat xyzw)
##   [>= 2.2: position keys (i32 frame, f32 xyz, i32 data)]
##   [>= 2.3: texture animations]
## A few trailing bytes (volume boxes) follow the nodes and are ignored.

enum Shade { NONE = 0, FLAT = 1, SMOOTH = 2 }

var version: int = 0
var anim_length: int = 0
var shade_type: int = Shade.FLAT
var alpha: int = 255
var textures: PackedStringArray = []  # latin1 paths relative to data/texture/
var root_names: PackedStringArray = []
## Node = {name, parent, textures: PackedStringArray (resolved names),
##         offset: Basis, position: Vector3, translation: Vector3, rot_angle: float,
##         rot_axis: Vector3, scale: Vector3, rot_key: Quaternion|null,
##         scale_key: Vector3|null, pos_key: Vector3|null,
##         vertices: PackedVector3Array, uvs: PackedVector2Array,
##         faces: PackedInt32Array (8 per face: v0 v1 v2 t0 t1 t2 tex two_sided),
##         smooth: PackedInt32Array}
var nodes: Array = []
var last_error := ""

var _d: PackedByteArray
var _p := 0
var _bad := false


static func decode(data: PackedByteArray) -> RsmFile:
	var r := RsmFile.new()
	if not r._parse(data):
		push_warning("RSM decode failed: %s" % r.last_error)
		return null
	return r


func _need(n: int) -> bool:
	if _bad or _p + n > _d.size():
		_bad = true
		return false
	return true

func _i32() -> int:
	if not _need(4): return 0
	_p += 4
	return _d.decode_s32(_p - 4)

func _f32() -> float:
	if not _need(4): return 0.0
	_p += 4
	return _d.decode_float(_p - 4)

func _v3() -> Vector3:
	return Vector3(_f32(), _f32(), _f32())

func _fixed(n: int) -> String:
	if not _need(n): return ""
	var raw := _d.slice(_p, _p + n)
	_p += n
	var z := raw.find(0)
	return (raw.slice(0, z) if z >= 0 else raw).get_string_from_ascii()

func _lenstr() -> String:
	var n := _i32()
	if n < 0 or n > 1024:
		_bad = true
		return ""
	return _fixed(n)

func _count(limit: int) -> int:
	var n := _i32()
	if n < 0 or n > limit:
		_bad = true
		return 0
	return n


func _parse(d: PackedByteArray) -> bool:
	_d = d
	if d.size() < 6 or d.slice(0, 4).get_string_from_ascii() != "GRSM":
		last_error = "Missing GRSM signature"
		return false
	version = (d[4] << 8) | d[5]
	if version >= 0x0200 and version < 0x0202:
		# RSM 2.0/2.1: only 2 files in kRO 2025 (engine/biggear*), layout unverified.
		last_error = "RSM version %x not supported yet" % version
		return false
	_p = 6
	anim_length = _i32()
	shade_type = _i32()
	if version >= 0x0104:
		if _need(1):
			alpha = d[_p]
			_p += 1
	var node_count := 0
	if version >= 0x0202:
		_f32()  # fps
		if version < 0x0203:
			for i in _count(4096):
				textures.append(_lenstr())
		for i in _count(256):
			root_names.append(_lenstr())
		node_count = _count(4096)
	else:
		_p += 16
		for i in _count(4096):
			textures.append(_fixed(40))
		root_names.append(_fixed(40))
		node_count = _count(4096)
	if _bad or node_count == 0:
		last_error = "Bad header (v%x)" % version
		return false
	for n in node_count:
		var node := _parse_node()
		if _bad:
			last_error = "Truncated in node %d (v%x)" % [n, version]
			return false
		nodes.append(node)
	return true


func _parse_node() -> Dictionary:
	var node := {}
	var v2 := version >= 0x0202
	node.name = _lenstr() if v2 else _fixed(40)
	node.parent = _lenstr() if v2 else _fixed(40)
	var tex := PackedStringArray()
	for i in _count(4096):
		if version >= 0x0203:
			tex.append(_lenstr())
		else:
			var idx := _i32()
			tex.append(textures[idx] if idx >= 0 and idx < textures.size() else "")
	node.textures = tex
	var m := []
	for i in 9:
		m.append(_f32())
	# Stored row-major as used by roBrowser/BrowEdit (m[0..2] = first column of the GL mat3).
	node.offset = Basis(Vector3(m[0], m[1], m[2]), Vector3(m[3], m[4], m[5]), Vector3(m[6], m[7], m[8]))
	node.position = _v3()
	node.translation = Vector3.ZERO
	node.rot_angle = 0.0
	node.rot_axis = Vector3.UP
	node.scale = Vector3.ONE
	if not v2:
		node.translation = _v3()
		node.rot_angle = _f32()
		node.rot_axis = _v3()
		node.scale = _v3()
	var verts := PackedVector3Array()
	var nv := _count(500000)
	if _need(nv * 12):
		verts.resize(nv)
		for i in nv:
			verts[i] = Vector3(_d.decode_float(_p), _d.decode_float(_p + 4), _d.decode_float(_p + 8))
			_p += 12
	node.vertices = verts
	var uvs := PackedVector2Array()
	var nt := _count(500000)
	var tstride := 12 if version >= 0x0102 else 8
	var toff := 4 if version >= 0x0102 else 0
	if _need(nt * tstride):
		uvs.resize(nt)
		for i in nt:
			uvs[i] = Vector2(_d.decode_float(_p + toff), _d.decode_float(_p + toff + 4))
			_p += tstride
	node.uvs = uvs
	var faces := PackedInt32Array()
	var smooth := PackedInt32Array()
	var nf := _count(500000)
	for i in nf:
		var flen := _i32() if v2 else (24 if version >= 0x0102 else 20)
		if flen < 20 or not _need(flen):
			_bad = true
			break
		var q := _p
		faces.append_array([_d.decode_u16(q), _d.decode_u16(q + 2), _d.decode_u16(q + 4),
			_d.decode_u16(q + 6), _d.decode_u16(q + 8), _d.decode_u16(q + 10),
			_d.decode_u16(q + 12), _d.decode_s32(q + 16)])
		smooth.append(_d.decode_s32(q + 20) if flen >= 24 else 0)
		_p += flen
	node.faces = faces
	node.smooth = smooth
	node.scale_key = null
	node.rot_key = null
	node.pos_key = null
	if version >= 0x0106:
		var n := _count(100000)
		for i in n:
			_i32()
			var s := _v3()
			_f32()
			if i == 0:
				node.scale_key = s
	var nr := _count(100000)
	for i in nr:
		_i32()
		var q := Quaternion(_f32(), _f32(), _f32(), _f32())
		if i == 0:
			node.rot_key = q
	if v2:
		var npos := _count(100000)
		for i in npos:
			_i32()
			var pp := _v3()
			_i32()
			if i == 0:
				node.pos_key = pp
	if version >= 0x0203:
		for t in _count(4096):
			_i32()
			for a in _count(64):
				_i32()
				var frames := _count(100000)
				if _need(frames * 8):
					_p += frames * 8
	return node
