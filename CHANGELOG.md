# Changelog

## [Unreleased] - 2026-11-10

### Added
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
