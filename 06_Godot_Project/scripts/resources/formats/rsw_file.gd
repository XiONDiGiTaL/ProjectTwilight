class_name RswFile
extends RefCounted
## Decoder for .rsw world descriptors (versions 1.9 - 2.7 observed in kRO 2025).
##
##   "GRSW" | u8 major | u8 minor | [>= 2.2: u8 build] | [>= 2.5: u32 unknown]
##   char[40] ini | char[40] gnd | char[40] gat | char[40] source
##   water (only < 2.6; moved to GND 1.8+): f32 level | i32 type | f32 wave_height
##        | f32 wave_speed | f32 wave_pitch | i32 anim_speed
##   light: i32 longitude | i32 latitude | f32 diffuse[3] | f32 ambient[3] | f32 opacity
##   ground bounds: i32 top, bottom, left, right
##   >= 2.7: u32 n | n * 4 bytes (purpose unknown)
##   u32 object_count | objects (type 1 model, 2 light, 3 sound, 4 effect)

var version: int = 0
var build: int = 0
var gnd_file := ""
var gat_file := ""
var water: Dictionary = {}
var light := {
	"longitude": 45, "latitude": 45,
	"diffuse": Color(1, 1, 1), "ambient": Color(0.3, 0.3, 0.3), "opacity": 1.0,
}
var models: Array = []   # {name, file (latin1), pos, rot, scale, anim_type, anim_speed, block_type}
var lights: Array = []
var sounds: Array = []
var effects: Array = []
## True when every object record parsed; false if an unknown layout stopped parsing early.
var objects_complete := false
var last_error := ""


static func decode(data: PackedByteArray) -> RswFile:
	var r := RswFile.new()
	if not r._parse(data):
		push_warning("RSW decode failed: %s" % r.last_error)
		return null
	return r


func _str(d: PackedByteArray, p: int, n: int) -> String:
	var raw := d.slice(p, p + n)
	var z := raw.find(0)
	return (raw.slice(0, z) if z >= 0 else raw).get_string_from_ascii()


func _vec3(d: PackedByteArray, p: int) -> Vector3:
	return Vector3(d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8))


func _parse(d: PackedByteArray) -> bool:
	if d.size() < 6 or d.slice(0, 4).get_string_from_ascii() != "GRSW":
		last_error = "Missing GRSW signature"
		return false
	version = (d[4] << 8) | d[5]
	var p := 6
	if version >= 0x0202:
		build = d[p]
		p += 1
	if version >= 0x0205:
		p += 4
	if p + 160 > d.size():
		last_error = "Truncated header"
		return false
	gnd_file = _str(d, p + 40, 40)
	gat_file = _str(d, p + 80, 40)
	p += 160
	if version < 0x0206:
		if p + 24 > d.size():
			last_error = "Truncated water block"
			return false
		water = {
			"level": d.decode_float(p), "type": d.decode_s32(p + 4),
			"wave_height": d.decode_float(p + 8), "wave_speed": d.decode_float(p + 12),
			"wave_pitch": d.decode_float(p + 16), "anim_speed": d.decode_s32(p + 20),
		}
		p += 24
	if p + 36 + 16 > d.size():
		last_error = "Truncated light block"
		return false
	var dif := _vec3(d, p + 8)
	var amb := _vec3(d, p + 20)
	light = {
		"longitude": d.decode_s32(p), "latitude": d.decode_s32(p + 4),
		"diffuse": Color(dif.x, dif.y, dif.z), "ambient": Color(amb.x, amb.y, amb.z),
		"opacity": d.decode_float(p + 32),
	}
	p += 36 + 16  # light + ground bounds
	if version >= 0x0207:
		# Unknown table: u32 n + n * 4 bytes (n = 16 in every kRO 2025 map).
		if p + 4 > d.size():
			last_error = "Truncated 2.7 block"
			return false
		p += 4 + d.decode_u32(p) * 4
	_parse_objects(d, p)
	return true


func _parse_objects(d: PackedByteArray, p: int) -> void:
	if p + 4 > d.size():
		return
	var count := d.decode_u32(p)
	p += 4
	if count > 100000:
		last_error = "Implausible object count %d" % count
		return
	for i in count:
		if p + 4 > d.size():
			last_error = "Truncated at object %d" % i
			return
		var type := d.decode_s32(p)
		p += 4
		match type:
			1:
				# Extra leading byte in model records: all 2.7; 2.6 from build 162 on.
				# Builds 8 and 18 also carry it, so the u8 build counter appears to
				# wrap past 255 (medium confidence; only build 161 lacks it in kRO 2025).
				var extra := version >= 0x0207 or (version == 0x0206 and (build >= 162 or build < 100))
				var lead := 1 if extra else 0
				# 2.7 appends an unknown f32 (observed -1.0) after the scale.
				var size := 248 + lead + (4 if version >= 0x0207 else 0)
				if p + size > d.size():
					last_error = "Truncated model %d" % i
					return
				var q := p + lead
				models.append({
					"name": _str(d, p, 40), "anim_type": d.decode_s32(p + 40),
					"anim_speed": d.decode_float(p + 44), "block_type": d.decode_s32(p + 48),
					"file": _str(d, q + 52, 80),
					"pos": _vec3(d, q + 212), "rot": _vec3(d, q + 224), "scale": _vec3(d, q + 236),
				})
				p += size
			2:
				if p + 108 > d.size():
					return
				lights.append({"name": _str(d, p, 80), "pos": _vec3(d, p + 80),
					"color": Color(d.decode_float(p + 92), d.decode_float(p + 96), d.decode_float(p + 100)),
					"range": d.decode_float(p + 104)})
				p += 108
			3:
				var size := 192 if version >= 0x0200 else 188
				if p + size > d.size():
					return
				sounds.append({"name": _str(d, p, 80), "file": _str(d, p + 80, 80), "pos": _vec3(d, p + 160)})
				p += size
			4:
				if p + 116 > d.size():
					return
				effects.append({"name": _str(d, p, 80), "pos": _vec3(d, p + 80), "id": d.decode_s32(p + 92)})
				p += 116
			_:
				last_error = "Unknown object type %d at index %d" % [type, i]
				return
	objects_complete = true


## Unit vector pointing from the ground toward the light, in Godot space
## (x east, y up, -z north). Medium confidence; see ASSET_FORMATS.md.
func light_direction() -> Vector3:
	var lng := deg_to_rad(float(light.longitude))
	var lat := deg_to_rad(float(light.latitude))
	return Vector3(sin(lat) * sin(lng), cos(lat), -sin(lat) * cos(lng)).normalized()
