extends RefCounted

static var SECRET := PackedByteArray([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02])


func test_roundtrip(_t) -> Variant:
	var code := InvitationCode.encode("192.168.1.42", 6900, SECRET)
	if code.length() != 29:
		return "unexpected code shape: %s" % code
	var d := InvitationCode.decode(code)
	if not d.ok or d.ip != "192.168.1.42" or d.port != 6900 or d.secret != SECRET:
		return "decode mismatch: %s" % d
	return true


func test_lenient_input(_t) -> Variant:
	var code := InvitationCode.encode("10.0.0.5", 7000, SECRET)
	var messy := " " + code.to_lower().replace("-", " ").replace("0", "o").replace("1", "l") + " "
	var d := InvitationCode.decode(messy)
	return true if d.ok and d.ip == "10.0.0.5" else "lenient decode failed: %s" % d.error


func test_single_typo_rejected(_t) -> Variant:
	var code := InvitationCode.encode("203.0.113.9", 6901, SECRET)
	for i in code.length():
		if code[i] == "-":
			continue
		var swapped := "2" if code[i] != "2" else "3"
		var bad := code.substr(0, i) + swapped + code.substr(i + 1)
		if InvitationCode.decode(bad).ok:
			return "typo at %d accepted" % i
	return true


func test_invalid_inputs(_t) -> Variant:
	if InvitationCode.encode("300.1.1.1", 6900, SECRET) != "":
		return "bad ip accepted"
	if InvitationCode.encode("1.2.3.4", 0, SECRET) != "":
		return "port 0 accepted"
	if InvitationCode.decode("ABC").ok:
		return "short code accepted"
	if InvitationCode.decode("!!!!-!!!!-!!!!-!!!!-!!!!-!!!!").ok:
		return "garbage accepted"
	return true
