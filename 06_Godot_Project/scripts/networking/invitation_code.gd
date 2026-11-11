class_name InvitationCode
extends RefCounted
## Shareable private co-op invitation codes, e.g. "4D2K-9QXF-T0M3-AB7C-ZZ1P-H8V2".
##
## Adapted from the Shattered Marches JoinCode concept (IPv4 + port + key in
## Crockford base-32) with stronger parameters, because a real-time co-op host is
## reachable on the internet for long sessions:
##   * 48-bit session secret instead of a 16-bit key (not brute-forceable online)
##   * CRC-16/CCITT check instead of an 8-bit check (catches typos reliably)
##   * 4-bit format version for future IPv6 / relay payloads
## The secret is never sent over the wire: the host authenticates joiners with an
## HMAC challenge (see ConnectionValidator). Layout, most significant bit first:
##   version:4 | ipv4:32 | port:16 | secret:48 | crc16:16  = 116 bits -> 24 chars

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const FORMAT_VERSION := 1
const SECRET_BYTES := 6
const CHARS := 24


## Returns "" if ip is not a valid IPv4 address or port/secret are out of range.
static func encode(ip: String, port: int, secret: PackedByteArray) -> String:
	var ip_bytes := _parse_ipv4(ip)
	if ip_bytes.is_empty() or port < 1 or port > 65535 or secret.size() != SECRET_BYTES:
		return ""
	var payload := PackedByteArray()
	payload.append_array(ip_bytes)
	payload.append((port >> 8) & 0xFF)
	payload.append(port & 0xFF)
	payload.append_array(secret)
	var crc := crc16(PackedByteArray([FORMAT_VERSION]) + payload)
	# Bit stream: version nibble, payload, crc, then 4 bits of zero padding (120 bits).
	var bits := _bits(FORMAT_VERSION, 4)
	for b in payload:
		bits += _bits(b, 8)
	bits += _bits(crc, 16) + "0000"
	var out := ""
	for i in CHARS:
		out += ALPHABET[bits.substr(i * 5, 5).bin_to_int()]
		if i % 4 == 3 and i < CHARS - 1:
			out += "-"
	return out


## Returns {"ok": bool, "ip": String, "port": int, "secret": PackedByteArray, "error": String}
static func decode(code: String) -> Dictionary:
	var clean := code.strip_edges().to_upper().replace("-", "").replace(" ", "")
	clean = clean.replace("I", "1").replace("L", "1").replace("O", "0").replace("U", "V")
	if clean.length() != CHARS:
		return _fail("An invitation code has %d letters and digits." % CHARS)
	var bits := ""
	for ch in clean:
		var v := ALPHABET.find(ch)
		if v < 0:
			return _fail("The code contains an invalid character '%s'." % ch)
		bits += _bits(v, 5)
	var version := bits.substr(0, 4).bin_to_int()
	if version != FORMAT_VERSION:
		return _fail("This invitation was made by an incompatible version of Project Twilight.")
	var payload := PackedByteArray()
	for i in 12:
		payload.append(bits.substr(4 + i * 8, 8).bin_to_int())
	var crc := bits.substr(100, 16).bin_to_int()
	if crc16(PackedByteArray([version]) + payload) != crc or bits.substr(116, 4) != "0000":
		return _fail("That code is not valid. Check it for typos.")
	var ip := "%d.%d.%d.%d" % [payload[0], payload[1], payload[2], payload[3]]
	var port := (payload[4] << 8) | payload[5]
	if port == 0:
		return _fail("That code contains an invalid port.")
	return {"ok": true, "ip": ip, "port": port, "secret": payload.slice(6, 12), "error": ""}


static func new_secret() -> PackedByteArray:
	return Crypto.new().generate_random_bytes(SECRET_BYTES)


## CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF).
static func crc16(data: PackedByteArray) -> int:
	var crc := 0xFFFF
	for b in data:
		crc ^= b << 8
		for _i in 8:
			crc = ((crc << 1) ^ 0x1021) if (crc & 0x8000) else (crc << 1)
			crc &= 0xFFFF
	return crc


static func _parse_ipv4(ip: String) -> PackedByteArray:
	var parts := ip.strip_edges().split(".")
	if parts.size() != 4:
		return PackedByteArray()
	var out := PackedByteArray()
	for p in parts:
		if not p.is_valid_int() or int(p) < 0 or int(p) > 255:
			return PackedByteArray()
		out.append(int(p))
	return out


static func _bits(v: int, width: int) -> String:
	var s := ""
	for i in range(width - 1, -1, -1):
		s += "1" if (v >> i) & 1 else "0"
	return s


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "ip": "", "port": 0, "secret": PackedByteArray(), "error": msg}
