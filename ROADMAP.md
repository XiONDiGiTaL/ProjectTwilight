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
5. 📋 Map decoding (GAT, GND, RSW) ← **next**
6. 📋 Isometric map rendering (ground plus lightmaps, then RSM models)
7. 📋 Character composition (body + head via ACT anchors, hair palettes)
8. 📋 Cell-based movement on GAT walkability
9. 📋 Versioned local save/load

## Phase 4: First playable (offline) 📋
Main menu → character creation → one classic map → movement → one monster → basic combat → EXP → inventory → save/load.

## Phases 5–8 📋
Core gameplay → private co-op (ENet, invitation codes ✅ already) → server integration and MMO → modernisation.
