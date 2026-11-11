class_name ActFile
extends RefCounted
## Decoder for Ragnarok .act animation files (versions 0x100 - 0x205).
##
## An ACT file holds actions; each action holds frames; each frame holds sprite
## layers that reference images in the matching .spr file. Character and monster
## actions are grouped in blocks of 8 directions (action = type * 8 + direction).
## See ASSET_FORMATS.md for the layout and evidence.

const DEFAULT_INTERVAL := 4.0  # in 25 ms units, used when the file has no timing table

var version: int = 0
## Array of actions. Action = {"frames": Array[frame], "interval": float (ms per frame)}
## Frame = {"layers": Array[layer], "sound": int, "anchors": Array[Vector2i]}
## Layer = {"pos": Vector2i, "sprite": int, "mirror": bool, "color": Color,
##          "scale": Vector2, "rotation": int, "type": int}
var actions: Array = []
var events: PackedStringArray = []
var last_error: String = ""


static func decode(data: PackedByteArray) -> ActFile:
	var act := ActFile.new()
	if not act._parse(data):
		push_warning("ACT decode failed: %s" % act.last_error)
		return null
	return act


func _parse(data: PackedByteArray) -> bool:
	if data.size() < 16 or data[0] != 0x41 or data[1] != 0x43:  # "AC"
		last_error = "Missing AC signature"
		return false
	version = data[2] | (data[3] << 8)
	var action_count := data.decode_u16(4)
	var r := _Reader.new(data, 16)  # 10 reserved bytes after the count
	for a in action_count:
		var frame_count := r.u32()
		if r.failed or frame_count > 4096:
			last_error = "Bad frame count in action %d" % a
			return false
		var frames: Array = []
		for f in frame_count:
			r.skip(32)  # two unused bounding rectangles
			var layer_count := r.u32()
			if r.failed or layer_count > 1024:
				last_error = "Bad layer count (action %d frame %d)" % [a, f]
				return false
			var layers: Array = []
			for l in layer_count:
				var layer := {}
				layer.pos = Vector2i(r.i32(), r.i32())
				layer.sprite = r.i32()
				layer.mirror = r.i32() != 0
				layer.color = Color.WHITE
				layer.scale = Vector2.ONE
				layer.rotation = 0
				layer.type = 0
				if version >= 0x200:
					layer.color = Color8(r.u8(), r.u8(), r.u8(), r.u8())
					if version >= 0x204:
						layer.scale = Vector2(r.f32(), r.f32())
					else:
						var s := r.f32()
						layer.scale = Vector2(s, s)
					layer.rotation = r.i32()
					layer.type = r.i32()
					if version >= 0x205:
						r.skip(8)  # explicit width/height of the referenced image
				layers.append(layer)
			var sound := -1
			if version >= 0x200:
				sound = r.i32()
			var anchors: Array[Vector2i] = []
			if version >= 0x203:
				var anchor_count := r.u32()
				if anchor_count > 64:
					last_error = "Bad anchor count"
					return false
				for _k in anchor_count:
					r.skip(4)
					anchors.append(Vector2i(r.i32(), r.i32()))
					r.skip(4)
			frames.append({"layers": layers, "sound": sound, "anchors": anchors})
		actions.append({"frames": frames, "interval": DEFAULT_INTERVAL * 25.0})
		if r.failed:
			last_error = "Truncated in action %d" % a
			return false
	if version >= 0x201 and not r.at_end():
		var event_count := r.u32()
		for _e in event_count:
			events.append(r.fixed_string(40))
	if version >= 0x202:
		for a in actions.size():
			if r.remaining() < 4:
				break
			actions[a].interval = r.f32() * 25.0
	if r.failed:
		last_error = "Truncated event/timing table"
		return false
	return true


class _Reader:
	var d: PackedByteArray
	var p: int
	var failed := false

	func _init(data: PackedByteArray, start: int) -> void:
		d = data
		p = start

	func _need(n: int) -> bool:
		if p + n > d.size():
			failed = true
			return false
		return true

	func u8() -> int:
		if not _need(1): return 0
		p += 1
		return d[p - 1]

	func u32() -> int:
		if not _need(4): return 0
		p += 4
		return d.decode_u32(p - 4)

	func i32() -> int:
		if not _need(4): return 0
		p += 4
		return d.decode_s32(p - 4)

	func f32() -> float:
		if not _need(4): return 0.0
		p += 4
		return d.decode_float(p - 4)

	func skip(n: int) -> void:
		if _need(n):
			p += n

	func fixed_string(n: int) -> String:
		if not _need(n): return ""
		var s := d.slice(p, p + n)
		p += n
		var z := s.find(0)
		return (s.slice(0, z) if z >= 0 else s).get_string_from_ascii()

	func remaining() -> int:
		return d.size() - p

	func at_end() -> bool:
		return p >= d.size()
