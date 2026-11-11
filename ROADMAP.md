# Roadmap

Status keys: ✅ Implemented and tested · 🔧 In development · 📋 Planned · 🔍 Under investigation

## Phase 1: Audit ✅
Workspace, tools, client, Eternal Love package and Shattered Marches audited. See PROJECT_AUDIT.md.

## Phase 2: Research foundation 🔧
- ✅ ASSET_FORMATS (GRF, SPR, ACT) · ✅ REVERSE_ENGINEERING_LOG · 🔧 GAME_MECHANICS (stat core) · ✅ NETWORK_PROTOCOLS (co-op design) · ✅ ASSET_PROVENANCE
- 📋 VISUAL_REFERENCE_COMPARISON (needs a Unity bundle reader for Eternal Love) · 📋 SERVER_COMPATIBILITY · 📋 Clone rAthena, Hercules and the eAthena archive into `03_Reference_Sources`

## Phase 3: Architecture and prototypes 🔧
1. ✅ GRF indexing and extraction (0x200/0x300)
2. ✅ Sprite decoding (SPR) with palettes
3. ✅ Sprite previewing (Sprite Viewer tool)
4. ✅ Animation playback (ACT, ActSprite)
5. ✅ Map decoding (GAT, GND, RSW; all 3,366 client map files)
6. ✅ Isometric map rendering: ground, lightmaps, water plane, camera, RSM/RSM2 models (static first frame) · 📋 model animation, animated water, model translucency
7. ✅ Character composition (body + head via ACT anchors, hair palettes, 8 directions with camera-yaw correction)
8. ✅ Cell-based movement on GAT walkability (A*, no corner cutting, 150 ms/cell, click-to-walk)
9. 📋 Versioned local save/load

## Asset independence 📋
The engine never runs Gravity code; only *content* comes from the client. Two complementary paths:
- **Local importer** (near term): convert the player's own client once into Godot-native resources under `user://`, so the GRF is no longer read at runtime. Nothing is redistributed.
- **Original replacement assets** (long term): independently created sprites, maps, models and music in the classic style. This is required for any publicly distributable standalone build. The resource layer already treats assets as replaceable.

## Phase 4: First playable (offline) 🔧
✅ map · ✅ movement · ✅ monsters (Poring/Fabre/Lunatic) · ✅ combat · ✅ EXP and levels · ✅ combat HUD · 📋 character creation · ✅ inventory and drops · ✅ save/load · ✅ stat allocation window · ✅ equipment · ✅ NPC shop

## Phases 5–8 📋
Core gameplay → private co-op (ENet, invitation codes ✅ already) → server integration and MMO → modernisation.
