"""Generate the CP949 -> Unicode lookup table used by the GRF filename decoder.

Output: little-endian uint16 array indexed by (lead - 0x81) * 190 + (trail - 0x41),
lead in 0x81..0xFE, trail in 0x41..0xFE. 0 = unmapped. Derived from Python's
standard 'cp949' codec (Microsoft code page 949, a superset of KS X 1001 / EUC-KR).
"""
import struct, sys
out = sys.argv[1] if len(sys.argv) > 1 else "06_Godot_Project/resources/encoding/cp949_to_unicode.bin"
buf = bytearray()
for lead in range(0x81, 0xFF):
    for trail in range(0x41, 0xFF):
        try:
            ch = bytes([lead, trail]).decode("cp949")
            cp = ord(ch) if len(ch) == 1 and ord(ch) <= 0xFFFF else 0
        except UnicodeDecodeError:
            cp = 0
        buf += struct.pack("<H", cp)
open(out, "wb").write(buf)
print(out, len(buf))
