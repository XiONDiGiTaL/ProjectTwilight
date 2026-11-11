# Changelog

## [Unreleased] - 2026-11-10

### Added
- **Combat:** Pre-Renewal rules (hit/flee, critical, hard and soft DEF, ASPD) in `CombatRulesPreRenewal`; data-driven monsters (`data/prerenewal/monsters.json`) and EXP tables.
- **FieldSimulation:** deterministic and authoritative. Passive monster AI that retaliates, attack timing, damage-share EXP, base/job level-ups and respawns, all emitted as an event stream for presentation.
- **Twilight Glass UI:** frosted glass panels (backdrop blur, chamfered corners, hairline border, corner brackets, light sweep) and slanted glow bars whose HP colour shifts green, amber, red, with a lingering white damage chip.
  - Top-left status panel: fades when idle, wakes on HP/SP changes, collapsible and remembered.
  - Target frame, name-tagged world HP bars shown from first engagement until death, condensed glowing damage numbers, and a SYSTEM level-up notification.
- **Class insignia:** original generator (`tools/insignia`: emblem painter plus a shared render shader) producing 46 rank-consistent 512 px PNGs (wood, bronze, silver, wood/bronze with icy trim, gold). The insignia is shown beside the class title.
- **Sprites:** ACT layer tint and alpha applied in sprite composition, which fixes effects such as the Poring death splash.
- Walkable character: `GridPathfinder` (8-directional A* over GAT, no corner cutting, 64-step limit) and `GridWalker` (deterministic 150 ms/cell movement, 1.4× for diagonals, re-click finishes the current step). Both are pure gameplay logic.
- `CharacterSprite`: body and head composed through ACT anchors with hair palettes, shown as a camera-facing billboard that is depth-tested against the map.
- `PlayerAvatar` and the "Explore Prontera" offline prototype scene: click-to-walk, follow camera, target marker.
- Movement unit tests and a visual direction-ring capture.
- RSM/RSM2 model decoder (1.4, 1.5, 2.2, 2.3) and mesh baker. Maps now render their buildings, trees and props (for example, 1,303 instances in Prontera).
- Model shader with classic ambient/diffuse lighting. Synthetic RSM unit test and sampled client model test.

### Fixed
- RSW 2.7 model records: the extra f32 precedes the filename, so RSM2 references on 2.7 maps now resolve.

### Earlier
- GAT, GND (1.7/1.8/1.9) and RSW (1.9 to 2.7) decoders. All 3,366 map files in the reference client parse completely.
- Ground renderer: per-texture mesh surfaces, lightmap atlas, smoothed normals, classic sRGB lighting shader, and a water plane.
- `RoMap` node with cell/world conversion, `RoCamera` isometric camera, and a Map Viewer tool (added to the main menu).
- BMP/TGA/JPG/PNG texture loader with magenta colour keying.
- Map unit tests (synthetic fixtures) and an all-maps client integration test.
- Environment and repository audit (`PROJECT_AUDIT.md`).
- Godot 4.8 project in `06_Godot_Project`.
- GRF archive reader supporting versions 0x200 and 0x300, with a CP949 filename codec.
- SPR and ACT decoders, plus the `ActSprite` animated layer renderer.
- `RoResources` read-only virtual file system: loose files first, then GRFs in DATA.INI order.
- Main menu with client-folder mounting, and a Sprite Viewer developer tool.
- Pre-Renewal stat rules (status points, raise cost, HIT/FLEE, crit, status ATK, MATK).
- Private co-op `InvitationCode` (48-bit secret, CRC-16, versioned).
- Headless test runner: 16 unit tests and 5 client integration tests.
- Allow-list `.gitignore` so no game data reaches the public repository.
