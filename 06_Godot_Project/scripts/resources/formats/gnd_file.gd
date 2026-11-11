class_name GndFile
extends RefCounted
## Decoder for .gnd ground meshes (versions 1.7, 1.8, 1.9).
##
##   "GRGN" | u8 major | u8 minor | u32 width | u32 height | f32 zoom (cube size)
##   u32 texture_count | u32 name_length | texture_count * char[name_length]
##   u32 lightmap_count | u32 px | u32 py | u32 cells   (px*py*4 bytes each:
##       px*py shadow/intensity bytes, then px*py RGB colour triplets)
##   u32 surface_count | 40 bytes each: f32 u[4] | f32 v[4] | i16 texture | u16 lightmap | u8 BGRA
##   width*height cubes, 28 bytes: f32 h[4] (SW, SE, NW, NE) | i32 top | i32 front | i32 right
##   >= 1.8: water: f32 level | i32 type | f32 wave_height | f32 wave_speed | f32 wave_pitch
##           | i32 anim_speed | i32 split_w | i32 split_h
##           1.8: split_w*split_h f32 levels   1.9: split_w*split_h full 24-byte water records

var version: int = 0
var width: int = 0
var height: int = 0
var zoom: float = 10.0
var textures: PackedStringArray = []  # latin1 (CP949 bytes) paths relative to data/texture/
var lightmap_count: int = 0
var lightmap_px: int = 8
var lightmap_py: int = 8
var lightmaps: PackedByteArray  # raw, lightmap_count * px*py*4
## Surfaces: parallel arrays for speed.
var surf_uv: PackedVector2Array  # 4 per surface (corners SW, SE, NW, NE)
var surf_texture: PackedInt32Array
var surf_lightmap: PackedInt32Array
var surf_color: PackedColorArray
## Cubes
var cube_heights: PackedFloat32Array  # 4 per cube
var cube_top: PackedInt32Array
var cube_front: PackedInt32Array
var cube_right: PackedInt32Array
## Water (only for >= 1.8; for older maps the RSW carries water).
var water: Dictionary = {}
var last_error := ""


static func decode(data: PackedByteArray) -> GndFile:
	var g := GndFile.new()
	if not g._parse(data):
		push_warning("GND decode failed: %s" % g.last_error)
		return null
	return g


func _parse(d: PackedByteArray) -> bool:
	if d.size() < 26 or d.slice(0, 4).get_string_from_ascii() != "GRGN":
		last_error = "Missing GRGN signature"
		return false
	version = (d[4] << 8) | d[5]
	if version < 0x0107:
		last_error = "GND version %x not supported yet" % version
		return false
	width = d.decode_u32(6)
	height = d.decode_u32(10)
	zoom = d.decode_float(14)
	var tex_count := d.decode_u32(18)
	var name_len := d.decode_u32(22)
	var p := 26
	if tex_count > 4096 or name_len > 256 or p + tex_count * name_len > d.size():
		last_error = "Bad texture table"
		return false
	for i in tex_count:
		var raw := d.slice(p, p + name_len)
		var z := raw.find(0)
		textures.append((raw.slice(0, z) if z >= 0 else raw).get_string_from_ascii())
		p += name_len
	if p + 16 > d.size():
		last_error = "Truncated lightmap header"
		return false
	lightmap_count = d.decode_u32(p)
	lightmap_px = d.decode_u32(p + 4)
	lightmap_py = d.decode_u32(p + 8)
	p += 16
	var lm_size := lightmap_px * lightmap_py * 4
	if p + lightmap_count * lm_size > d.size():
		last_error = "Truncated lightmaps"
		return false
	lightmaps = d.slice(p, p + lightmap_count * lm_size)
	p += lightmap_count * lm_size
	var surf_count := d.decode_u32(p)
	p += 4
	if p + surf_count * 40 > d.size():
		last_error = "Truncated surfaces"
		return false
	surf_uv.resize(surf_count * 4)
	surf_texture.resize(surf_count)
	surf_lightmap.resize(surf_count)
	surf_color.resize(surf_count)
	for i in surf_count:
		for c in 4:
			surf_uv[i * 4 + c] = Vector2(d.decode_float(p + c * 4), d.decode_float(p + 16 + c * 4))
		surf_texture[i] = d.decode_s16(p + 32)
		surf_lightmap[i] = d.decode_u16(p + 34)
		surf_color[i] = Color8(d[p + 38], d[p + 37], d[p + 36], d[p + 39])  # stored B,G,R,A
		p += 40
	var cells := width * height
	if p + cells * 28 > d.size():
		last_error = "Truncated cubes (%dx%d)" % [width, height]
		return false
	cube_heights.resize(cells * 4)
	cube_top.resize(cells)
	cube_front.resize(cells)
	cube_right.resize(cells)
	for i in cells:
		for c in 4:
			cube_heights[i * 4 + c] = d.decode_float(p + c * 4)
		cube_top[i] = d.decode_s32(p + 16)
		cube_front[i] = d.decode_s32(p + 20)
		cube_right[i] = d.decode_s32(p + 24)
		p += 28
	if version >= 0x0108 and p + 32 <= d.size():
		water = {
			"level": d.decode_float(p), "type": d.decode_s32(p + 4),
			"wave_height": d.decode_float(p + 8), "wave_speed": d.decode_float(p + 12),
			"wave_pitch": d.decode_float(p + 16), "anim_speed": d.decode_s32(p + 20),
			"split_w": d.decode_s32(p + 24), "split_h": d.decode_s32(p + 28),
		}
	return true


func surface_count() -> int:
	return surf_texture.size()


## Builds an RGBA8 atlas: RGB = lightmap colour, A = shadow intensity.
## Returns {"image": Image, "per_row": int} (tiles are px x py texels).
func build_lightmap_atlas() -> Dictionary:
	var per_row := 256
	var w := per_row * lightmap_px
	var rows := maxi(1, ceili(float(lightmap_count) / per_row))
	var h := rows * lightmap_py
	var img_data := PackedByteArray()
	img_data.resize(w * h * 4)
	var texels := lightmap_px * lightmap_py
	for i in lightmap_count:
		var base := i * texels * 4
		var ox := (i % per_row) * lightmap_px
		var oy := (i / per_row) * lightmap_py
		for t in texels:
			var tx := t % lightmap_px
			var ty := t / lightmap_px
			var o := ((oy + ty) * w + ox + tx) * 4
			var c := base + texels + t * 3
			img_data[o] = lightmaps[c]
			img_data[o + 1] = lightmaps[c + 1]
			img_data[o + 2] = lightmaps[c + 2]
			img_data[o + 3] = lightmaps[base + t]
	return {"image": Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, img_data), "per_row": per_row}
