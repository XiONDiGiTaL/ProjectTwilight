class_name GrfArchive
extends RefCounted
## Read-only reader for Gravity GRF archives (versions 0x200 and 0x300).
##
## The archive is opened read-only and never modified. File names are kept as
## lossless Latin-1 strings of the original CP949 bytes; use Cp949 to convert.
## See ASSET_FORMATS.md for the format description and evidence.

const HEADER_SIZE := 46
const FLAG_FILE := 0x01
const FLAG_MIXCRYPT := 0x02
const FLAG_DES_HEADER := 0x04

var path: String = ""
var version: int = 0
var signature: String = ""
var file_count: int = 0
var last_error: String = ""
## Number of distinct raw names that folded to the same lookup key.
var key_collisions: int = 0

# key (lowercase, backslash-separated, latin1) -> PackedInt64Array [offset, csize, asize, rsize, flags]
var _entries: Dictionary = {}
# key -> original latin1 name (case preserved)
var _names: Dictionary = {}
var _file: FileAccess
var _mutex := Mutex.new()


## Opens and indexes an archive. Returns OK or an error code; see last_error.
func open(archive_path: String) -> Error:
	path = archive_path
	_file = FileAccess.open(archive_path, FileAccess.READ)
	if _file == null:
		last_error = "Cannot open %s (%s)" % [archive_path, error_string(FileAccess.get_open_error())]
		return ERR_FILE_CANT_OPEN
	if _file.get_length() < HEADER_SIZE:
		last_error = "File too small to be a GRF"
		return ERR_FILE_CORRUPT
	var header := _file.get_buffer(HEADER_SIZE)
	signature = header.slice(0, 15).get_string_from_ascii()
	version = header.decode_u32(42)
	var table_offset: int
	match version:
		0x200:
			table_offset = header.decode_u32(30)
			var seed := header.decode_u32(34)
			file_count = header.decode_u32(38) - seed - 7
		0x300:
			table_offset = header.decode_u64(30)
			file_count = header.decode_u32(38)
		_:
			last_error = "Unsupported GRF version 0x%X" % version
			return ERR_FILE_UNRECOGNIZED
	var table_pos := table_offset + HEADER_SIZE
	if table_pos + 8 > _file.get_length():
		last_error = "File table offset beyond end of file"
		return ERR_FILE_CORRUPT
	_file.seek(table_pos)
	if version == 0x300:
		_file.get_32()  # Observed as 0 in kRO 2025 data.grf; purpose unknown.
	var csize := _file.get_32()
	var usize := _file.get_32()
	var table := _file.get_buffer(csize).decompress(usize, FileAccess.COMPRESSION_DEFLATE)
	if table.size() != usize:
		last_error = "File table failed to decompress"
		return ERR_FILE_CORRUPT
	return _parse_table(table)


func _parse_table(table: PackedByteArray) -> Error:
	var pos := 0
	var n := table.size()
	var offset_size := 8 if version == 0x300 else 4
	var record := 13 + offset_size
	var parsed := 0
	while pos < n:
		var end := table.find(0, pos)
		if end < 0 or end + 1 + record > n:
			last_error = "Truncated file table at entry %d" % parsed
			return ERR_FILE_CORRUPT
		var raw_name := table.slice(pos, end).get_string_from_ascii()
		var p := end + 1
		var csize := table.decode_u32(p)
		var asize := table.decode_u32(p + 4)
		var rsize := table.decode_u32(p + 8)
		var flags := table[p + 12]
		var offset := table.decode_u64(p + 13) if offset_size == 8 else table.decode_u32(p + 13)
		pos = p + record
		parsed += 1
		if (flags & FLAG_FILE) == 0:
			continue  # directory entry
		var key := normalize(raw_name)
		if _names.has(key) and _names[key] != raw_name:
			key_collisions += 1
		_entries[key] = PackedInt64Array([offset, csize, asize, rsize, flags])
		_names[key] = raw_name
	if parsed != file_count:
		push_warning("GRF %s: header says %d entries, table has %d" % [path, file_count, parsed])
	return OK


## Lookup key: lowercase, backslash separators. Works on latin1 or ASCII input.
static func normalize(name: String) -> String:
	return name.replace("/", "\\").to_lower()


## Convert a Unicode resource path (e.g. "data\\sprite\\인간족\\...") into a lookup key.
static func key_for(unicode_path: String) -> String:
	return normalize(Cp949.to_latin1(unicode_path))


func has_file(key: String) -> bool:
	return _entries.has(key)


func entry_count() -> int:
	return _entries.size()


## Raw latin1 names of all files (case preserved).
func list_raw_names() -> Array:
	return _names.values()


## Returns {"size": int, "compressed": int, "flags": int} or {} if absent.
func stat(key: String) -> Dictionary:
	if not _entries.has(key):
		return {}
	var e: PackedInt64Array = _entries[key]
	return {"size": e[3], "compressed": e[1], "flags": e[4]}


## Reads and decompresses a file. Returns an empty array and sets last_error on failure.
func read(key: String) -> PackedByteArray:
	if not _entries.has(key):
		last_error = "Not found: %s" % key
		return PackedByteArray()
	var e: PackedInt64Array = _entries[key]
	var flags := e[4]
	if flags & (FLAG_MIXCRYPT | FLAG_DES_HEADER):
		last_error = "DES-encrypted GRF entries are not supported yet: %s" % key
		return PackedByteArray()
	_mutex.lock()
	_file.seek(e[0] + HEADER_SIZE)
	var data := _file.get_buffer(e[1])
	_mutex.unlock()
	if data.size() != e[1]:
		last_error = "Short read for %s" % key
		return PackedByteArray()
	if e[3] == 0:
		return PackedByteArray()
	var out := data.decompress(e[3], FileAccess.COMPRESSION_DEFLATE)
	if out.size() != e[3]:
		if e[1] == e[3]:
			return data  # stored without compression
		last_error = "Decompression failed for %s" % key
		return PackedByteArray()
	return out


func close() -> void:
	_file = null
