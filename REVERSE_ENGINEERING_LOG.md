# Reverse Engineering Log

| # | Date | Target | Tool | Finding | Evidence | Confidence | Open questions |
|---|---|---|---|---|---|---|---|
| 1 | 2026-11-10 | `kRO_Latest/data.grf` | Python struct probe, Godot `GrfArchive` | GRF 0x300 header: u64 table offset at byte 30, exact u32 file count at 38, signature `Event Horizon` | Header bytes `…9F 7F 06 E5 00 00 00 00 0D FD 03 00 00 03 00 00`; the parsed table gives 261,389 entries, matching the header | Confirmed | — |
| 2 | 2026-11-10 | same | same | The 0x300 file table starts with an extra u32 (value 0) before the compressed/uncompressed sizes. Entries use a u64 offset (21-byte record after the name). | Successful zlib inflate to exactly 19,084,889 bytes; all entries parse to the end of the table | Confirmed | What the leading u32 means |
| 3 | 2026-11-10 | same | Godot integration tests | No DES-flagged entries. 30 directory entries (flag 0). | Flag histogram {1: 261,359, 0: 30} | Confirmed | DES handling is still needed for older GRFs |
| 4 | 2026-11-10 | sampled `.spr`/`.act` | Godot bulk test | SPR 0x201 and ACT 0x201/0x203/0x204/0x205 layouts as documented in ASSET_FORMATS.md | 1,704 sampled files decode with 0 failures; rendered Poring and Novice frames look correct | Confirmed | Older SPR/ACT versions are only exercised by synthetic tests |
| 5 | 2026-11-10 | `2025-07-16_Ragexe…exe` | PowerShell VersionInfo | No PE version resource | Empty FileVersion/ProductName | Confirmed | Packet version: needs Ghidra analysis (Phase 7) |
| 6 | 2026-11-10 | Eternal Love XAPK | Python zipfile (static) | Unity IL2CPP, SLua (encrypted), armeabi-v7a only; assets are Unity AssetBundles | Native library names, asset paths | Confirmed | Bundle encryption status; a Unity reader is needed |
