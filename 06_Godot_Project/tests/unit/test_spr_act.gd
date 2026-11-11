extends RefCounted
## Synthetic SPR/ACT fixtures built byte-by-byte from the documented layout.


static func _u16(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xFF); b.append((v >> 8) & 0xFF)


static func _u32(b: PackedByteArray, v: int) -> void:
	for i in 4:
		b.append((v >> (8 * i)) & 0xFF)


static func _f32(b: PackedByteArray, v: float) -> void:
	var t := PackedByteArray(); t.resize(4); t.encode_float(0, v); b.append_array(t)


func _make_spr_201() -> PackedByteArray:
	var b := PackedByteArray([0x53, 0x50, 0x01, 0x02])  # SP v2.1
	_u16(b, 1)  # indexed
	_u16(b, 1)  # rgba
	# indexed 3x2: pixels [0,0,5, 7,0,0] -> RLE: 00 02 05 07 00 02
	_u16(b, 3); _u16(b, 2)
	var rle := PackedByteArray([0x00, 0x02, 0x05, 0x07, 0x00, 0x02])
	_u16(b, rle.size()); b.append_array(rle)
	# rgba 1x2, stored bottom-up as A,B,G,R. Bottom row red, top row blue.
	_u16(b, 1); _u16(b, 2)
	b.append_array(PackedByteArray([255, 0, 0, 255]))  # bottom: R=255
	b.append_array(PackedByteArray([255, 255, 0, 0]))  # top: B=255
	var pal := PackedByteArray(); pal.resize(1024)
	pal[5 * 4] = 10; pal[5 * 4 + 1] = 20; pal[5 * 4 + 2] = 30
	pal[7 * 4] = 200
	b.append_array(pal)
	return b


func test_spr_rle_and_rgba(_t) -> Variant:
	var spr := SprFile.decode(_make_spr_201())
	if spr == null:
		return "decode returned null"
	if spr.version != 0x201 or spr.frame_count() != 2:
		return "version/frames wrong: %x %d" % [spr.version, spr.frame_count()]
	var idx: PackedByteArray = spr.indexed_frames[0].indices
	if idx != PackedByteArray([0, 0, 5, 7, 0, 0]):
		return "rle decoded %s" % str(idx)
	var img := spr.indexed_image(0)
	if img.get_pixel(0, 0).a != 0.0:
		return "index 0 must be transparent"
	var c := img.get_pixel(2, 0)
	if c.r8 != 10 or c.g8 != 20 or c.b8 != 30 or c.a8 != 255:
		return "palette colour wrong: %s" % c
	var rgba := spr.rgba_frames[0]
	if rgba.get_pixel(0, 0).b8 != 255 or rgba.get_pixel(0, 1).r8 != 255:
		return "rgba not flipped / channel order wrong"
	return true


func test_spr_truncated_fails_cleanly(_t) -> Variant:
	var b := _make_spr_201().slice(0, 12)
	var spr := SprFile.new()
	if spr._parse(b):
		return "truncated data should fail"
	return true


func _make_act_205() -> PackedByteArray:
	var b := PackedByteArray([0x41, 0x43, 0x05, 0x02])  # AC v2.5
	_u16(b, 1)  # one action
	b.append_array(PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	_u32(b, 1)  # one frame
	b.resize(b.size() + 32)
	_u32(b, 1)  # one layer
	_u32(b, -3 & 0xFFFFFFFF); _u32(b, 4)  # pos
	_u32(b, 0)  # sprite index
	_u32(b, 1)  # mirror
	b.append_array(PackedByteArray([255, 128, 0, 255]))
	_f32(b, 1.5); _f32(b, 2.0)
	_u32(b, 90)  # rotation
	_u32(b, 0)  # type
	_u32(b, 3); _u32(b, 2)  # w, h
	_u32(b, 0xFFFFFFFF)  # sound -1
	_u32(b, 1)  # anchors
	_u32(b, 0); _u32(b, 7); _u32(b, -9 & 0xFFFFFFFF); _u32(b, 0)
	_u32(b, 1)  # events
	var ev := "atk.wav".to_ascii_buffer(); ev.resize(40); b.append_array(ev)
	_f32(b, 6.0)  # interval
	return b


func test_act_205(_t) -> Variant:
	var act := ActFile.decode(_make_act_205())
	if act == null:
		return "decode returned null"
	var fr: Dictionary = act.actions[0].frames[0]
	var l: Dictionary = fr.layers[0]
	if l.pos != Vector2i(-3, 4) or not l.mirror or l.rotation != 90:
		return "layer fields wrong: %s" % l
	if not is_equal_approx(l.scale.x, 1.5) or not is_equal_approx(l.scale.y, 2.0):
		return "scale wrong"
	if fr.anchors.size() != 1 or fr.anchors[0] != Vector2i(7, -9):
		return "anchor wrong: %s" % str(fr.anchors)
	if act.events[0] != "atk.wav":
		return "event wrong: %s" % act.events
	if not is_equal_approx(act.actions[0].interval, 150.0):
		return "interval wrong: %f" % act.actions[0].interval
	return true
