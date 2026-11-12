class_name SprFile
extends RefCounted
## Decoder for Ragnarok .spr sprite sheets (versions 0x100 - 0x201).
##
## Layout (little-endian), see ASSET_FORMATS.md:
##   "SP" | u8 minor | u8 major | u16 indexed_count | [u16 rgba_count if >= 0x200]
##   indexed images: u16 w, u16 h, then
##       >= 0x201: u16 encoded_size + RLE (0x00 followed by run length of zeros)
##       else    : w*h raw palette indices
##   rgba images: u16 w, u16 h, w*h*4 bytes (A,B,G,R), rows stored bottom-up
##   palette (>= 0x101): last 1024 bytes, 256 x (R,G,B,unused). Index 0 is transparent.

var version: int = 0
var palette: PackedByteArray  # 1024 bytes
## Each entry: {"w": int, "h": int, "indices": PackedByteArray}
var indexed_frames: Array = []
## Each entry: Image (RGBA8), already flipped upright.
var rgba_frames: Array[Image] = []
var last_error: String = ""
## Frames whose RLE data was short and was padded with transparent pixels.
var repaired_frames := 0


static func decode(data: PackedByteArray) -> SprFile:
	var spr := SprFile.new()
	if not spr._parse(data):
		push_warning("SPR decode failed: %s" % spr.last_error)
		return null
	return spr


func _parse(data: PackedByteArray) -> bool:
	if data.size() < 6 or data[0] != 0x53 or data[1] != 0x50:  # "SP"
		last_error = "Missing SP signature"
		return false
	version = data[2] | (data[3] << 8)
	var pos := 4
	var indexed_count := data.decode_u16(pos); pos += 2
	var rgba_count := 0
	if version >= 0x200:
		rgba_count = data.decode_u16(pos); pos += 2
	for i in indexed_count:
		if pos + 4 > data.size():
			last_error = "Truncated indexed frame header %d" % i
			return false
		var w := data.decode_u16(pos)
		var h := data.decode_u16(pos + 2)
		pos += 4
		var pixels := w * h
		var indices := PackedByteArray()
		if version >= 0x201:
			if pos + 2 > data.size():
				last_error = "Truncated RLE size %d" % i
				return false
			var enc_size := data.decode_u16(pos); pos += 2
			if pos + enc_size > data.size():
				last_error = "Truncated RLE frame %d" % i
				return false
			indices = _decode_rle(data, pos, enc_size, pixels)
			pos += enc_size
		else:
			if pos + pixels > data.size():
				last_error = "Truncated raw frame %d" % i
				return false
			indices = data.slice(pos, pos + pixels)
			pos += pixels
		if indices.size() != pixels:
			# Some shipped sprites have a frame whose RLE data ends early. The
			# original client draws the rest transparent, so do the same
			# instead of rejecting the whole sprite.
			indices.resize(pixels)
			repaired_frames += 1
		indexed_frames.append({"w": w, "h": h, "indices": indices})
	for i in rgba_count:
		if pos + 4 > data.size():
			last_error = "Truncated RGBA frame header %d" % i
			return false
		var w := data.decode_u16(pos)
		var h := data.decode_u16(pos + 2)
		pos += 4
		var size := w * h * 4
		if pos + size > data.size():
			last_error = "Truncated RGBA frame %d" % i
			return false
		rgba_frames.append(_abgr_to_image(data, pos, w, h))
		pos += size
	if version >= 0x101 and data.size() >= 1024:
		palette = data.slice(data.size() - 1024)
	else:
		palette = PackedByteArray()
		palette.resize(1024)
	return true


static func _decode_rle(data: PackedByteArray, start: int, length: int, expected: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(expected)
	var o := 0
	var i := start
	var end := start + length
	while i < end and o < expected:
		var c := data[i]
		i += 1
		if c == 0:
			var run := data[i] if i < end else 0
			i += 1
			if run == 0:
				run = 1  # "00 00" encodes a single zero in some encoders
			for _k in run:
				if o >= expected:
					break
				out[o] = 0
				o += 1
		else:
			out[o] = c
			o += 1
	if o != expected:
		out.resize(o)
	return out


static func _abgr_to_image(data: PackedByteArray, pos: int, w: int, h: int) -> Image:
	var rgba := PackedByteArray()
	rgba.resize(w * h * 4)
	for y in h:
		var src_row := pos + (h - 1 - y) * w * 4
		var dst_row := y * w * 4
		for x in w:
			var s := src_row + x * 4
			var d := dst_row + x * 4
			rgba[d] = data[s + 3]
			rgba[d + 1] = data[s + 2]
			rgba[d + 2] = data[s + 1]
			rgba[d + 3] = data[s]
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)


func frame_count() -> int:
	return indexed_frames.size() + rgba_frames.size()


## Builds an RGBA image for an indexed frame, optionally with a replacement
## 1024-byte palette (e.g. from a .pal file for hair/cloth dyes).
func indexed_image(index: int, override_palette: PackedByteArray = PackedByteArray()) -> Image:
	var f: Dictionary = indexed_frames[index]
	var pal := override_palette if override_palette.size() >= 1024 else palette
	var w: int = f.w
	var h: int = f.h
	var idx: PackedByteArray = f.indices
	var rgba := PackedByteArray()
	rgba.resize(w * h * 4)
	for p in idx.size():
		var c := idx[p]
		if c == 0:
			continue  # transparent; buffer is zero-initialised
		var d := p * 4
		var s := c * 4
		rgba[d] = pal[s]
		rgba[d + 1] = pal[s + 1]
		rgba[d + 2] = pal[s + 2]
		rgba[d + 3] = 255
	if w == 0 or h == 0:
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)


## Image for a layer reference: type 0 = indexed, 1 = rgba.
func image_for(sprite_index: int, sprite_type: int, override_palette: PackedByteArray = PackedByteArray()) -> Image:
	if sprite_type == 1:
		if sprite_index < 0 or sprite_index >= rgba_frames.size():
			return null
		return rgba_frames[sprite_index]
	if sprite_index < 0 or sprite_index >= indexed_frames.size():
		return null
	return indexed_image(sprite_index, override_palette)
