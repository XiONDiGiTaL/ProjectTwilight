# Reverse Engineering Log

| # | Date | Target | Tool | Finding | Evidence | Confidence | Open questions |
|---|---|---|---|---|---|---|---|
| 1 | 2026-11-10 | `kRO_Latest/data.grf` | Python struct probe, Godot `GrfArchive` | GRF 0x300 header: u64 table offset at byte 30, exact u32 file count at 38, signature `Event Horizon` | Header bytes `…9F 7F 06 E5 00 00 00 00 0D FD 03 00 00 03 00 00`; the parsed table gives 261,389 entries, matching the header | Confirmed | — |
| 2 | 2026-11-10 | same | same | The 0x300 file table starts with an extra u32 (value 0) before the compressed/uncompressed sizes. Entries use a u64 offset (21-byte record after the name). | Successful zlib inflate to exactly 19,084,889 bytes; all entries parse to the end of the table | Confirmed | What the leading u32 means |
| 3 | 2026-11-10 | same | Godot integration tests | No DES-flagged entries. 30 directory entries (flag 0). | Flag histogram {1: 261,359, 0: 30} | Confirmed | DES handling is still needed for older GRFs |
| 4 | 2026-11-10 | sampled `.spr`/`.act` | Godot bulk test | SPR 0x201 and ACT 0x201/0x203/0x204/0x205 layouts as documented in ASSET_FORMATS.md | 1,704 sampled files decode with 0 failures; rendered Poring and Novice frames look correct | Confirmed | Older SPR/ACT versions are only exercised by synthetic tests |
| 5 | 2026-11-10 | `2025-07-16_Ragexe…exe` | PowerShell VersionInfo | No PE version resource | Empty FileVersion/ProductName | Confirmed | Packet version: needs Ghidra analysis (Phase 7) |
| 7 | 2026-11-10 | all `.gat/.gnd/.rsw` | Python probes, Godot bulk test | GND surfaces are 40 bytes; GND 1.8/1.9 water trailers; RSW header grows a build byte (≥2.2) and a u32 (≥2.5); water moves from RSW to GND at RSW 2.6 | Section sizes sum exactly to end-of-file; 3,366 map files decode | Confirmed | — |
| 8 | 2026-11-10 | RSW 2.6/2.7 objects | Python stride analysis | Model record stride 252 (2.6 build 161), 253 (other 2.6), 257 (2.7: +u8 lead, +trailing f32). 2.7 inserts `u32 n + n*4` before objects | Distances between consecutive `.rsm` names; all object tables parse fully | Confirmed (layout) / Medium (build-wrap explanation) | Meaning of the 2.7 table and trailing float |
| 10 | 2026-11-11 | RSW 2.7 models | Python byte dump before `.rsm2` names | **Correction to #8:** the 2.7 extra f32 sits *before* the filename (after the u8), not after the scale | All 2.7 RSM2 references now resolve; 1,653 and 2,040 instances load on mu_fild02 and kindlbrk | Confirmed | Meaning of the f32 |
| 11 | 2026-11-11 | `.rsm/.rsm2` | Python trial parser, Godot bulk test | RSM 1.4/1.5/2.2/2.3 layouts (see ASSET_FORMATS) | 1,500-file Python sample plus a 740-file Godot sample: 0 failures, 0 empty meshes | Confirmed | RSM 2.0/2.1 layout (2 files) |
| 12 | 2026-11-11 | RSM baking | Visual comparison | roBrowser-style node chain and centring for 1.x; no centring for 2.x | Prontera, Izlude and field captures look correct; RSM2 rocks stand upright | High (1.x) / Medium (2.x) | 2.x keyframe semantics for animated models |
| 9 | 2026-11-10 | ground shading | Visual comparison | Smoothed vertex normals plus lightmap (shadow × colour + RGB) reproduces the classic look | Captures of prontera, prt_fild08 and izlude | High | Exact light-direction sign convention |
| 6 | 2026-11-10 | Eternal Love XAPK | Python zipfile (static) | Unity IL2CPP, SLua (encrypted), armeabi-v7a only; assets are Unity AssetBundles | Native library names, asset paths | Confirmed | Bundle encryption status; a Unity reader is needed |

## 2026-11-11 — Training Grounds map names in modern kRO

- **Finding:** the 2025 kRO client has no `new_1-1` … `new_5-4` files. It ships `new_zone01` … `new_zone04` (200×200).
- **Test:** I probed every NPC, spawn and portal coordinate that rAthena's `pre-re/jobs/novice/novice.txt` and `warps/other/jobquests.txt` use on `new_1-1` … `new_1-4` against the GAT files of `new_zone01` … `new_zone04`.
  - All spawn and portal cells were walkable.
  - Two non-walkable hits were an NPC standing spot and a room centre, and NPCs can stand on blocked cells.
- **Conclusion:** the zone maps are the classic training rooms under new names.
- **Implementation:** `MapAliases` loads `new_<copy>-<room>` from `new_zone0<room>` when the original is missing. Scripts, warps and saves keep the classic names.
