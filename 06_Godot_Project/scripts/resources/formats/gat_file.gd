class_name GatFile
extends RefCounted
## Decoder for .gat altitude/attribute grids (versions 1.2, 1.3).
##
##   "GRAT" | u8 major | u8 minor | u32 width | u32 height
##   width*height cells of 20 bytes: f32 h[4] (SW, SE, NW, NE) | u32 type
## GAT cells are half a GND cube (5 world units). Heights grow downward
## (negative = higher), as in the GND.

enum CellType { WALKABLE = 0, BLOCKED = 1, WATER = 2, WALKABLE_WATER = 3, SNIPABLE = 5 }

var version: int = 0
var width: int = 0
var height: int = 0
var heights: PackedFloat32Array  # 4 per cell
var types: PackedByteArray
var last_error := ""


static func decode(data: PackedByteArray) -> GatFile:
	var g := GatFile.new()
	if not g._parse(data):
		push_warning("GAT decode failed: %s" % g.last_error)
		return null
	return g


func _parse(d: PackedByteArray) -> bool:
	if d.size() < 14 or d.slice(0, 4).get_string_from_ascii() != "GRAT":
		last_error = "Missing GRAT signature"
		return false
	version = (d[4] << 8) | d[5]
	width = d.decode_u32(6)
	height = d.decode_u32(10)
	var cells := width * height
	if width == 0 or height == 0 or 14 + cells * 20 > d.size():
		last_error = "Truncated or empty grid %dx%d" % [width, height]
		return false
	heights.resize(cells * 4)
	types.resize(cells)
	var p := 14
	for i in cells:
		heights[i * 4] = d.decode_float(p)
		heights[i * 4 + 1] = d.decode_float(p + 4)
		heights[i * 4 + 2] = d.decode_float(p + 8)
		heights[i * 4 + 3] = d.decode_float(p + 12)
		types[i] = d.decode_u32(p + 16) & 0xFF
		p += 20
	return true


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func cell_type(x: int, y: int) -> int:
	return types[x + y * width] if in_bounds(x, y) else CellType.BLOCKED


## Pre-Renewal walkability: types 0 and 3 are walkable.
func is_walkable(x: int, y: int) -> bool:
	var t := cell_type(x, y)
	return t == CellType.WALKABLE or t == CellType.WALKABLE_WATER


## Interpolated RO height (negative = up) at fractional position inside cell (x, y).
func height_at(x: int, y: int, fx: float = 0.5, fy: float = 0.5) -> float:
	if not in_bounds(x, y):
		return 0.0
	var i := (x + y * width) * 4
	var south := lerpf(heights[i], heights[i + 1], fx)
	var north := lerpf(heights[i + 2], heights[i + 3], fx)
	return lerpf(south, north, fy)
