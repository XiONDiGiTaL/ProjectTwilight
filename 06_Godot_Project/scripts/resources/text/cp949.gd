class_name Cp949
extends RefCounted
## CP949 (Korean, superset of EUC-KR) <-> Unicode conversion.
##
## Ragnarok resource paths inside GRF archives are stored as CP949 bytes. The GRF
## index keeps names as lossless Latin-1 strings (one char per byte); this class
## converts those to readable Unicode and back for lookups.

const TABLE_PATH := "res://resources/encoding/cp949_to_unicode.bin"
const TRAIL_MIN := 0x41
const TRAIL_SPAN := 190  # 0x41..0xFE

static var _to_unicode: PackedInt32Array
static var _from_unicode: Dictionary = {}


static func _ensure_loaded() -> void:
	if not _to_unicode.is_empty():
		return
	var raw := FileAccess.get_file_as_bytes(TABLE_PATH)
	if raw.is_empty():
		push_error("Cp949: missing table %s" % TABLE_PATH)
		return
	_to_unicode.resize(raw.size() / 2)
	for i in _to_unicode.size():
		var cp := raw.decode_u16(i * 2)
		_to_unicode[i] = cp
		if cp != 0:
			_from_unicode[cp] = i


## Decode raw CP949 bytes to a Unicode String. Unmapped pairs become U+FFFD.
static func decode(bytes: PackedByteArray) -> String:
	_ensure_loaded()
	var out := ""
	var i := 0
	var n := bytes.size()
	while i < n:
		var b := bytes[i]
		if b < 0x80:
			out += char(b)
			i += 1
		elif b >= 0x81 and b <= 0xFE and i + 1 < n and bytes[i + 1] >= TRAIL_MIN and bytes[i + 1] <= 0xFE:
			var cp := _to_unicode[(b - 0x81) * TRAIL_SPAN + (bytes[i + 1] - TRAIL_MIN)]
			out += char(cp) if cp != 0 else char(0xFFFD)
			i += 2
		else:
			out += char(0xFFFD)
			i += 1
	return out


## Encode a Unicode String into CP949 bytes. Returns an empty array if a
## character has no CP949 representation.
static func encode(text: String) -> PackedByteArray:
	_ensure_loaded()
	var out := PackedByteArray()
	for i in text.length():
		var cp := text.unicode_at(i)
		if cp < 0x80:
			out.append(cp)
		elif _from_unicode.has(cp):
			var idx: int = _from_unicode[cp]
			out.append(0x81 + idx / TRAIL_SPAN)
			out.append(TRAIL_MIN + idx % TRAIL_SPAN)
		else:
			return PackedByteArray()
	return out


## Latin-1 (byte-per-char) string -> Unicode.
static func decode_latin1(raw: String) -> String:
	return decode(latin1_bytes(raw))


## Latin-1 string -> raw bytes (lossless inverse of get_string_from_ascii).
static func latin1_bytes(raw: String) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(raw.length())
	for i in raw.length():
		out[i] = raw.unicode_at(i) & 0xFF
	return out


## Unicode -> Latin-1 (byte-per-char) string, the GRF index key space.
static func to_latin1(text: String) -> String:
	var b := encode(text)
	if b.is_empty() and not text.is_empty():
		return ""
	return b.get_string_from_ascii()
