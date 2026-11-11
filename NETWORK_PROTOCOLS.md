# Network Protocols

## Private co-op invitation codes (implemented, unit-tested)

Implementation: `06_Godot_Project/scripts/networking/invitation_code.gd`. Tests: `tests/unit/test_invitation_code.gd`.

Format: 24 Crockford base-32 characters shown as `XXXX-XXXX-XXXX-XXXX-XXXX-XXXX`, packing 120 bits:

| Bits | Field |
|---|---|
| 4 | format version (currently 1; reserved for IPv6 or relay payloads) |
| 32 | host IPv4 address |
| 16 | port |
| 48 | random session secret (`Crypto.generate_random_bytes`) |
| 16 | CRC-16/CCITT-FALSE over version + payload |
| 4 | zero padding (validated) |

Input is lenient: case, spaces and dashes are ignored, and I/L/O/U are read as 1/1/0/V. Tests confirm that every single-character typo is rejected.

### Compared with Shattered Marches `JoinCode`

| | Shattered Marches | Project Twilight |
|---|---|---|
| Key | 16-bit, **sent in clear** | 48-bit, **never sent** |
| Integrity check | 8-bit custom | CRC-16 |
| Versioning | none | 4-bit |
| Length | 15 chars | 24 chars |

### Planned join handshake (not yet implemented)

1. The client connects to the host.
2. The host sends a 32-byte random nonce.
3. The client replies with `HMAC-SHA256(secret, nonce ‖ player_id)`.
4. The host verifies the reply and then admits the player.

A 48-bit secret with a per-attempt nonce, plus host-side rate limiting, makes online guessing impractical.

## Real-time co-op transport (design, not implemented)

- **Transport:** ENet (UDP) through Godot's `ENetMultiplayerPeer`. Movement goes on unreliable-sequenced channels; combat results, inventory, chat and map changes go on reliable channels. Shattered Marches used WebSocket/TCP, which suits turn-based play but causes head-of-line blocking in real time.
- **Authority:** the host runs the same simulation as offline play. Clients send *intents* only (move to cell, attack target, use skill, pick up item). The host validates them against server-side rules and broadcasts the outcomes.
- **Tick:** a fixed simulation step (the classic client and emulators work on cell-based movement with a per-cell walk duration). The tick rate is to be decided by profiling.
- **Identity:** a persistent `player_id`, separate from the transport peer id, so reconnects restore the same character (an idea taken from Shattered Marches).
- **Connectivity:** LAN, direct IP, VPN and best-effort UPnP. When a connection fails the player gets a clear diagnostic. No promise of universal internet reachability. A relay is to be evaluated only if testing shows it is needed.

## eAthena / Hercules / rAthena client protocol

**Not yet researched.** Phase 7. See ROADMAP.md.
