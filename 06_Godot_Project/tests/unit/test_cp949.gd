extends RefCounted


func test_ascii_roundtrip(_t) -> Variant:
	var b := Cp949.encode("data\\sprite\\poring.spr")
	if Cp949.decode(b) != "data\\sprite\\poring.spr":
		return "ascii roundtrip failed"
	return true


func test_korean_known_bytes(_t) -> Variant:
	# "몬스터" (monster) in CP949 is B8 F3 BD BA C5 CD
	var b := Cp949.encode("몬스터")
	if b != PackedByteArray([0xB8, 0xF3, 0xBD, 0xBA, 0xC5, 0xCD]):
		return "encode gave %s" % b.hex_encode()
	if Cp949.decode(b) != "몬스터":
		return "decode mismatch"
	return true


func test_latin1_key_roundtrip(_t) -> Variant:
	var key := Cp949.to_latin1("인간족")
	if key.length() != 6:
		return "expected 6 latin1 chars, got %d" % key.length()
	if Cp949.decode_latin1(key) != "인간족":
		return "latin1 roundtrip failed"
	return true


func test_unrepresentable_returns_empty(_t) -> Variant:
	if not Cp949.encode("emoji 😀").is_empty():
		return "expected empty for unmappable char"
	return true
