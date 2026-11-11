<p align="center">
  <img src="Logo.png" alt="Project Twilight" width="520">
</p>

<p align="center">
  <b>Classic Ragnarok's soul, modern presentation, native PC.</b><br>
  A standalone reimplementation of Pre-Renewal Ragnarok Online, built in Godot 4.8.
</p>

---

## What is Project Twilight?

Project Twilight is a native Windows reimplementation of **classic Pre-Renewal Ragnarok Online**. It is not a launcher, a wrapper around the original executable or another emulator. It is a new game client and simulation, written from scratch, that recreates the classic experience and adds modern rendering and usability.

It is planned to support three ways to play, all sharing one gameplay core:

| Mode | Description |
|---|---|
| **Offline single-player** | The full game locally, with no account, server or internet connection |
| **Private co-op** | Host a session and share an invitation code with friends over LAN, VPN or direct internet |
| **Persistent MMO** | Dedicated servers with persistent worlds, with configurable eAthena/Hercules integration as a goal |

### Bring your own client

Project Twilight **contains no Gravity game data**. On first launch you point it at your own Ragnarok Online client folder. Sprites, maps and sounds are then decoded directly from that installation, which is opened read-only and never modified or copied.

## Development status

> Early development. The resource pipeline is working; the playable game is not there yet.

| Area | Status |
|---|---|
| GRF archive reading (v0x200, v0x300) | ✅ Implemented and tested |
| Korean (CP949) resource paths | ✅ Implemented and tested |
| SPR sprites, palettes and ACT animations | ✅ Implemented and tested |
| Animated sprite rendering and Sprite Viewer tool | ✅ Implemented |
| Pre-Renewal stat formulas (core) | 🔧 In development |
| Co-op invitation codes | ✅ Implemented and tested · networking 📋 planned |
| Map decoding (GAT/GND/RSW) and ground rendering | ✅ Implemented and tested |
| Map models (RSM/RSM2: buildings, trees, props) | ✅ Implemented and tested (static) |
| Character sprites (body + head, hair dyes) and click-to-walk movement | ✅ Implemented and tested |
| Combat (Pre-Renewal hit/flee/crit/DEF/ASPD), monsters, EXP and levels | ✅ Implemented and tested (first monsters) |
| Twilight Glass HUD: status panel, target frame, HP bars, combat text | ✅ Implemented |
| Original class insignia for all 46 classes | ✅ Generated (polish ongoing) |
| Loot, inventory, item use, stat allocation | ✅ Implemented and tested |
| Local save/load (versioned, validated) | ✅ Implemented and tested |
| Equipment (weapon damage model, armor DEF, weapon sprites) | ✅ Implemented and tested |
| NPC merchant and shop (buy/sell, Zeny) | ✅ Implemented and tested |
| Character select and creation (classic stat hexagon, live preview) | ✅ Implemented and tested |
| Novice skills, skill window, F1–F9 hotkey bar, sitting and regen | ✅ Implemented and tested |
| Warps and more maps, job change, first-job skills | 📋 Next |
| First offline playable (character, map, monster, combat, save) | 📋 Planned |
| Private co-op sessions | 📋 Planned |
| eAthena / Hercules compatibility | 🔍 Under investigation, not claimed |
| Persistent MMO server | 📋 Planned |

The detailed plan is in [ROADMAP.md](ROADMAP.md).

## Classes

The Pre-Renewal target covers these classes:

| First job | Second jobs | Transcendent |
|---|---|---|
| Swordman | Knight / Crusader | Lord Knight / Paladin |
| Mage | Wizard / Sage | High Wizard / Professor |
| Archer | Hunter / Bard / Dancer | Sniper / Clown / Gypsy |
| Acolyte | Priest / Monk | High Priest / Champion |
| Merchant | Blacksmith / Alchemist | Whitesmith / Creator |
| Thief | Assassin / Rogue | Assassin Cross / Stalker |

Expanded classes (Super Novice, Taekwon, Star Gladiator, Soul Linker) are tracked separately. Renewal third jobs and Renewal mechanics are out of scope for the classic ruleset.

## Interface

Project Twilight's HUD uses its own **Twilight Glass** design language, a sleek holographic "system window" style:
- frosted panels with chamfered corners and hairline borders
- slanted glowing resource bars
- condensed, letter-spaced typography

Classic information stays where veterans expect it: the status window is top-left. It fades when you aren't using it, wakes up when your HP or SP changes, and can be collapsed.

## Visual direction

The classic isometric camera, sprite characters and original map layouts stay. Lighting, effects, animation smoothness and UI are modernised on top of them, and each enhancement can be switched off independently of gameplay. Ragnarok M: Eternal Love is studied as a visual *reference* only. Its 3D Unity assets are not compatible with, or used in, this project.

## Getting started (development)

Requirements:
- Godot **4.8** (currently developed on 4.8-beta1)
- Your own Ragnarok Online client installation
- Python 3 (only to regenerate the encoding table)

```bash
git clone https://github.com/XiONDiGiTaL/ProjectTwilight.git
```

1. Open `06_Godot_Project/project.godot` in Godot.
2. Run it, enter your client folder on the title screen and press **Mount**. Alternatively, set the `TWILIGHT_RO_CLIENT` environment variable, or create `06_Godot_Project/twilight.local.cfg` (git-ignored) containing:
   ```ini
   [resources]
   client_path="D:/Games/RagnarokOnline"
   ```
3. Choose **PLAY**, create a character, then fight Porings, Lunatics and Fabres on prt_fild08. Left-click to walk, attack or pick up loot; press **I** for the inventory, **S** for status, **Q** for equipment, **K** for skills, **F1–F9** for hotkeys, **Insert** to sit and **F12** to save. Click the Field Merchant to buy and sell. Progress also saves automatically. to walk around as a Novice, or open **Map Viewer** to fly around any classic map, or **Sprite Viewer** to browse animated sprites from your client.

### Tests

```bash
godot --headless --path 06_Godot_Project -s res://tests/run_tests.gd
```

Unit tests use synthetic fixtures and need no game data. Client integration tests run automatically when a client folder is configured, and are skipped otherwise.

## Repository structure

```text
06_Godot_Project/    Godot project (scripts, scenes, tests)
tools/               Offline helper scripts
*.md                 Architecture, research and format documentation
```

The workspace also has local-only research folders (`01_Client_Original`, `09_Ragnarok_Eternal_Love`, …). These are excluded from the repository by an allow-list `.gitignore`.

## Documentation

[ARCHITECTURE](ARCHITECTURE.md) · [PROJECT_AUDIT](PROJECT_AUDIT.md) · [ASSET_FORMATS](ASSET_FORMATS.md) · [GAME_MECHANICS](GAME_MECHANICS.md) · [NETWORK_PROTOCOLS](NETWORK_PROTOCOLS.md) · [REVERSE_ENGINEERING_LOG](REVERSE_ENGINEERING_LOG.md) · [ASSET_PROVENANCE](ASSET_PROVENANCE.md) · [ROADMAP](ROADMAP.md) · [CHANGELOG](CHANGELOG.md)

## License

Original Project Twilight code is licensed under the [Apache License 2.0](LICENSE). This license grants no rights to Gravity's intellectual property. Project Twilight is not affiliated with or endorsed by Gravity Co., Ltd. See [NOTICE](NOTICE) and [LICENSES.md](LICENSES.md).
