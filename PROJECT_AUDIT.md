# Project Audit

Audit date: 2026-11-10. Everything below was checked on the development machine. Nothing in this report is assumed.

## 1. Repository

| Item | Finding |
|---|---|
| GitHub repository | `XiONDiGiTaL/ProjectTwilight`, **public**, default branch `main`, empty when the audit began (no commits, no license). |
| Local workspace | `E:\ProjectTwilight` was not a Git repository. It held a research folder layout (`00_Source_Inventory` … `09_Ragnarok_Eternal_Love`) containing only `.gitkeep`/`README.txt` placeholders, plus `Logo.png` (1024×768), `README_FIRST.md` and `Inventory-ROClient.ps1`. |
| Existing implementation | None. `06_Godot_Project` was empty. |
| Build status | Nothing to build at the start. The Godot project now imports cleanly and the test suite passes (see §8). |

**Decision:** the Git repository root is `E:\ProjectTwilight`, and `.gitignore` is an **allow-list**. Only the docs, `tools/` and `06_Godot_Project/` are tracked. Client files, the APK, extracted assets and local research output stay out of the public repository even if someone runs `git add -A` by accident. Game data extensions (`*.grf`, `*.spr`, `*.act`, …) are also blocked inside allowed folders.

`README_FIRST.md` says "no gameplay implementation until the inventory is approved". The later project brief overrides that and asks for implementation right after the audit, so I followed the brief.

## 2. Development tools

| Tool | Location | Status |
|---|---|---|
| Godot | `X:\Godot\Godot_v4.8-beta1_win64(.exe/_console.exe)` | **Verified**: `4.8.beta1.official.4d10419ca`. Vulkan Forward+ on an AMD Radeon RX 7900 XT. This is a beta, so check engine-level bugs against the stable release when it ships. A GodotSteam 4.7.2 editor build is also present but unused. |
| Ghidra | `D:\ghidra_12.2_PUBLIC` (another copy at `X:\REA\ghidra`) | Present. JDK 21 is bundled at `X:\REA\jdk21`. Not yet used for analysis. |
| REA | `X:\REA` (`rea-agents` v6.7.0, built locally) | Present. Use it through the `X:\REA\rea.cmd` / `rea.sh` wrappers, which keep all state on X:. `rea setup` was deliberately never run because it writes to C:. |
| Python | 3.14.7 | Used for offline probes and to generate the CP949 table. |
| Java | system JRE on PATH | Present. |
| Git / GitHub CLI | git 2.55, gh 2.102 | Authenticated. Can read the private `shattered-marches` repository. |
| JADX / Apktool / 7-Zip | — | **Not installed.** I inspected the APK with Python `zipfile` (read-only), which was enough for a structural survey. |

## 3. Original kRO client

Location: `01_Client_Original\Client_Files\kRO_Latest` (treated as read-only; nothing was written there).

| Item | Finding |
|---|---|
| Executable | `2025-07-16_Ragexe_175220998_clientinfo.exe` (16,143,872 bytes, SHA-256 `AE630E35E8592D8A…`). It has no PE version resource. The build date comes from the filename only. |
| Archive | One `data.grf` (3,845,198,853 bytes, SHA-256 `04E7ED042187E35F…`). `DATA.INI` lists only `1=data.grf`. |
| GRF format | Signature `Event Horizon`, **version 0x300** (64-bit offsets). 261,389 table entries, of which 261,359 are files and 30 are directories. No entry uses DES encryption. |
| Content by type (count) | act 100,726 · spr 64,615 · bmp 57,314 · tga 11,440 · rsm 7,078 · pal 4,522 · str 3,873 · wav 3,578 · rsm2 2,548 · gat/rsw 1,131 · gnd 1,104 · png 789 · lub 547 · jpg 417 · imf 317 · ezv 91 · gr2 21 |
| Loose files | `data\` 927 files (loose maps such as `prontera`/`izlude`/`morocc` `.gat/.gnd/.rsw`, `clientinfo.xml`, message tables); `System\` 40 (`.lub`); `SystemEN\` 19; `BGM\` 208 mp3; `AI\` 51; `Skin\` 5,126; `.warpgate\` 10 |
| Service | `clientinfo.xml`: `servicetype=korea`, `langtype=0`, `version=55` |
| Other binaries | `opensetup.exe`, Miles audio (`Mss32.dll`), Bink, Granny2, WebView2 loader, `BaseSDK.dll`/`IAPSDK.dll` |
| Empty archival folders | `01_Client_Original\{BGM,Data,GRF,System}` contain only `.gitkeep` |

**Important:** this is a **2025 Renewal-era client**. It is a valid source of *assets* (sprites, maps, models, sounds), but it is **not** evidence of Pre-Renewal *mechanics*. The gameplay ruleset must come from Pre-Renewal sources (emulator pre-re databases and historical documentation, cross-checked). See GAME_MECHANICS.md.

**Preservation:** every Project Twilight reader opens client files with `FileAccess.READ` only. The game resolves the client folder at runtime from user settings, so no copy is ever required.

## 4. Ragnarok M: Eternal Love package

`09_Ragnarok_Eternal_Love\Ragnarok+M_+Eternal+Love_1.4.7_APKPure.xapk`, 1,047,108,127 bytes. This is an **XAPK bundle, not a single APK**. It was inspected statically only and never installed or run.

| Item | Finding |
|---|---|
| Package | `com.gravity.romg`, version name 1.4.7, version code 2057 |
| SDK | min 26, target 36 |
| Bundle parts | `com.gravity.romg.apk` (37.6 MB base: 3 dex files, 106 layouts, `assets/bin/Data`) · `config.armeabi_v7a.apk` (113.8 MB native libs) · `UnityDataAssetPack.apk` (895 MB, 3,879 entries) · `icon.png` · `manifest.json` |
| Engine | **Unity with IL2CPP** (`libunity.so`, `libil2cpp.so`, `lib_burst_generated.so`). Scripting is Lua via SLua (`libslua_encrypt.so`, which suggests encrypted Lua). Video uses AVPro. Voice uses iFlytek/GME. |
| Largest asset groups | `resources/gui` 261 MB (1,512 bundles) · `art/scene` 260 MB · `art/role` 141 MB (1,051) · `art/model` 78 MB · `resources/script2` 75 MB · `art/fx` 2.7 MB (271) · `scene/pronteraneo`, `scene/bigworld`, character select scenes |
| Asset format | Unity AssetBundles plus `assetcfg_*.txt` / `ExtAssetBundleInfo.xml` manifests. A Unity bundle reader (e.g. AssetRipper/UnityPy) would be needed to go further. None is installed. |
| Native libs | 28 libraries, all **armeabi-v7a (32-bit ARM)**. No x86/arm64 split is included. |

**Conclusions:**
- Eternal Love is a full 3D Unity game. Its resources are **not format-compatible** with classic RO sprites or maps. Their value is as visual reference (lighting, effects, UI layout, character proportions), not as drop-in content.
- Some content is likely downloaded after install (`assetcfg_patch.txt`, `assetcfg_yun.txt`). The bundle should not be treated as complete.
- None of these files may be committed or redistributed. Use is limited to internal reference (see ASSET_PROVENANCE.md).

## 5. Shattered Marches networking (source-verified)

Repository: `C:\GitHub\shattered-marches` (origin `XiONDiGiTaL/shattered-marches`, HEAD `2f20495`). Godot 4.8, GDScript.

| Concern | Actual source | Behaviour |
|---|---|---|
| Transport | `scripts/net/net_manager.gd` (autoload `Net`) | `WebSocketMultiplayerPeer` on TCP, default port 7777, plain `ws://` (unencrypted). |
| Invitation code | `scripts/net/join_code.gd` | 9 bytes: IPv4(4) + port(2) + **16-bit key** + 8-bit check. 15 Crockford base-32 characters `XXXXX-XXXXX-XXXXX`. Lenient input (I/L→1, O→0, dashes and case ignored). |
| Authentication | `net_manager._register_player` | The client sends the key **in clear** via RPC to the host. The host compares it, sends back a rejection message and disconnects after 0.5 s. A player cap is enforced. |
| Identity | `net_manager` | Persistent `player_id` UUID, separate from the transport peer id, which allows reconnection. |
| Public address | `net_manager.discover_public_address` | UPnP discovery plus TCP port mapping on a thread. Falls back to `https://api.ipify.org` (a third-party service). |
| Session / lobby | `scripts/net/mp_session.gd` (1,312 lines) | Slots (human/AI), ready states, countdown, AI takeover on disconnect, reconnect restore keyed by `player_id`, battle id for event cursors. |
| State sync | `scripts/net/mp_sync.gd` | Turn-based full/delta **snapshots** of units plus an event log with a cursor. |

**What carries over to Project Twilight:** a persistent player identity separate from the peer id, host authority, lenient Crockford codes, UPnP as best effort with clear fallbacks, and reconnect keyed by identity.

**What does not carry over:** the turn snapshot model (RO is real-time), the 16-bit cleartext key, and the 8-bit checksum. Real-time play needs unreliable/sequenced channels (ENet/UDP) for movement, plus a challenge-response join. See NETWORK_PROTOCOLS.md.

## 6. Licensing concerns

- The repository is public, so allow-list ignoring is mandatory (done).
- Gravity's client and APK content may not be redistributed. The game is designed as **bring-your-own-client**: it reads the user's own installation at runtime.
- rAthena, Hercules and eAthena are GPL. Their *code* must not be copied into Apache-licensed Project Twilight code. Their databases are used only as research references, recorded with provenance.
- `resources/encoding/cp949_to_unicode.bin` is generated from Python's standard codec (a public character-set standard) by `tools/gen_cp949_table.py`.

## 7. Risks

| Risk | Severity | Notes |
|---|---|---|
| Pre-Renewal accuracy from a Renewal-era client | High | Mechanics must come from separately verified pre-re sources. Every formula records its evidence and confidence. |
| eAthena/Hercules protocol compatibility | High | Their packet sets target specific `PACKETVER`s and the original client. A native client needs a protocol adapter. Nothing is claimed until a test connects. |
| Real-time co-op over direct internet | High | NAT and CGNAT will block some hosts. UPnP is best effort. A relay may become necessary. |
| Map rendering fidelity (GND lightmaps, RSM/RSM2 models, water) | Medium | Formats are documented by the community and are next on the roadmap. |
| Eternal Love assets | Medium | These are Unity bundles: reference only, with no direct use. |
| Godot 4.8 beta | Low | Pin to stable 4.8 when it is released. |

## 8. Verification at the end of this session

`godot --headless --path 06_Godot_Project -s res://tests/run_tests.gd`, with the kRO client configured:

```
21 passed, 0 failed, 0 skipped
[grf]  indexed 261359 files in 787 ms (v0x300, collisions=0)
[bulk] decoded 1704 sampled spr/act, failures=0,
       versions={act205: 994, spr201: 676, act204: 27, act203: 5, act201: 2}
```

Visual check: `tests/capture_sprites.gd` rendered Poring (idle/walk/attack/hurt) and the male Novice body with correct palettes, transparency and layer offsets.
