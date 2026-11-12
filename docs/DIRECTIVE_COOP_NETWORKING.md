# Directive: private co-op networking

**Status (2026-11-12):** playable. The transport is wired into the game: HOST CO-OP and JOIN on the character select screen, the field scene runs as host or as client, and a session that ends returns to the title screen with the reason. Verified by two two-process tests on one PC (below). **Not verified:** a real LAN or internet link, more than one guest, and reconnects.

Read [`Directive.md`](../Directive.md) first for the project-wide rules.

## Design

Host-authoritative over ENet (`ENetMultiplayerPeer`, Godot high-level RPC on the `NetSession` node).

- **Host:** keeps one `FieldSimulation` per map that has players in it, built by `WorldBuilder`. It ticks them, runs every client command through the same `command_*` validation as offline play, and sends each client:
  - the changed units, ground items and events of its map (`_s_frame`; unit state at 10 Hz, events immediately);
  - its own private state when it changes (`_s_self`, checked every 250 ms): inventory, storage, equipment, skills, stats, open windows, guild record.
- **Client:** mirrors its map in a `RemoteSimulation`. This is a `FieldSimulation` subclass, so the field scene, HUD, minimap and windows can use it unchanged. Its `tick()` only interpolates walkers and timers, and every `command_*` is forwarded to the host.
- **Joining:** an `InvitationCode` carries the IPv4 address, port and a 48-bit secret. The host sends a random nonce and the client answers with HMAC-SHA256(secret, nonce); the secret never travels. Unauthenticated peers are dropped after 8 s.
- **Characters:** the client sends its own save. The host validates it with `SaveGame.validate` (the same clamping as loading a file) and refuses a duplicate name. The client keeps saving its own character locally from the replicated private state.
- **Commands:** only names in `NetCodec.CLIENT_COMMANDS` are accepted, with the argument types in `NetCodec.COMMAND_ARGS`. The host always supplies the unit id itself.
- **Map changes:** portals, script warps, `@warp` and save-point revives move the player between the host's map simulations (`NetSession._transfer`); the client then receives a fresh snapshot (`_s_enter`). A warp within the same map is a teleport and keeps the unit id.
- **NPC scripts:** they run on the host. `NetNpcHost` sends pages, menus and number inputs to the player and awaits the answer; a disconnect answers "cancel".
- **Chat:** plain lines are broadcast as `chat_received`; `@commands` run on the host through `ChatCommands`, and the answer goes only to the sender.
- **Guilds:** the host's maps share one `GuildStore`. A client's replica store is non-persistent (`GuildStore.new("")`), so it never touches the player's own `guilds.json`; it holds the player's guild record and pending invitations from the host.

## Files

| File | Role |
|---|---|
| `scripts/networking/net_session.gd` | Session node: host, join, auth, per-map sims, frames, transfers, chat. Must run as `/root/NetSession` on both sides. |
| `scripts/networking/net_codec.gd` | Unit / private state encoding, the client command whitelist and argument types |
| `scripts/networking/remote_simulation.gd` | Client replica (`FieldSimulation` subclass) |
| `scripts/networking/net_npc_host.gd` | `RaHost` that shows NPC dialogs on a remote player's screen |
| `scripts/networking/world_builder.gd` | Builds a map simulation: warps, spawns, script NPCs + `OnInit`, CPU adventurers |
| `scripts/gameplay/world/field_simulation.gd` | Added `remove_unit(id)` (emits `despawn`) |
| `scripts/gameplay/guilds/guild_store.gd` | Added `persistent`, `record_data()`, `install_record()` |
| `tests/net/coop_host.gd`, `tests/net/coop_client.gd` | Two-process test |

## Verified

Run the pair (host first; it writes the code to `user://coop_test_code.txt`):

```powershell
& "X:\Godot\Godot_v4.8-beta1_win64_console.exe" --headless --path 06_Godot_Project -s res://tests/net/coop_host.gd
& "X:\Godot\Godot_v4.8-beta1_win64_console.exe" --headless --path 06_Godot_Project -s res://tests/net/coop_client.gd
```

With the real game scenes (two windows, not headless; screenshots go to `user://captures/coop_*.png`):

```powershell
& "X:\Godot\Godot_v4.8-beta1_win64_console.exe" --path 06_Godot_Project -s res://tests/net/coop_scene_host.gd
& "X:\Godot\Godot_v4.8-beta1_win64_console.exe" --path 06_Godot_Project -s res://tests/net/coop_scene_client.gd
```

Result on 2026-11-12: host 10 checks and client 10 checks, 0 failed: the host scene presents and walks a map ticked by NetSession; the guest joins through the character select code path, plays on a replica, sees the host, damages a monster, chats, follows a host-ordered transfer to Prontera, opens a remote NPC dialog and keeps its own save; the host follows by a real map travel and both meet in Prontera.

Transport only (headless) — result on 2026-11-12: `CLIENT RESULT: 16 passed, 0 failed`, with no errors on either side. The checks cover:

- a malformed code is refused locally; join and HMAC handshake; snapshot (own unit, the host player, monsters);
- private state (starter potions and gear);
- chat both ways; an `@command` answered privately;
- movement decided by the host; combat damage events;
- map transfer to Prontera with script NPCs in the new snapshot;
- a remote NPC dialog round trip (Stylist menu → answer → next page → cancel).

**Not verified:** more than one client, a real LAN or internet link (only localhost) and reconnects.

## How the game uses it

- `project.godot` registers `NetSession` as an autoload; offline play never touches it (`mode == OFFLINE`).
- `character_select.gd`: **HOST CO-OP** calls `NetSession.host(port, advertised_ip)` (both from `[coop]` in `user://settings.cfg`) and enters the field; **JOIN** sends the slot's save with `NetSession.join(code, save)` and enters the field on `map_entered` (12 s timeout).
- `field_scene.gd` has three modes, chosen in `_ready`:
  - **Offline** (`_build_offline_world`): the scene owns and ticks the simulation, as before.
  - **Host** (`_enter_session`): `NetSession.host_enter()` on first entry, `host_sim()` / `host_unit()` after a travel. The scene does not tick; it reads `NetSession.take_local_events()`. Views for what already exists are built directly, and the `spawn` / `npc_spawn` / `drop` handlers skip duplicates. Travel goes through `NetSession.host_travel()`.
  - **Client**: `sim` is a `RemoteSimulation`; the scene never travels or runs NPC scripts on its own. It reloads on `map_entered`, shows `dialog_received` in the glass dialog and answers with `answer_dialog()` (walking away answers 255 = cancel).
- New events handled by the scene: `despawn` (free the view) and `appearance` (rebuild the sprite).
- Chat in a session goes through `NetSession.say()`; `@code`, `@who` and `@leave` are handled locally.

## To do

1. [ ] Verify on a real LAN and over the internet (forwarded port), and with three or more players.
2. [ ] Port / advertised-IP fields in the Settings window (today: `[coop] port` and `advertised_ip` in `user://settings.cfg`).
3. [ ] Reconnect after a dropped connection (today the guest returns to the title screen and joins again).
4. [ ] Party window, speech bubbles, player-to-player trade.
5. [ ] Host-side rate presets apply only to the host's current map simulation; make them session-wide.
6. [ ] Measure bandwidth on a slow link; send unit deltas instead of whole unit states if needed.

## Known limits

- **IPv4 only**, direct connection: internet play needs the host's port forwarded and the public address put in the code. There is no relay or NAT traversal.
- **Trust model** is private co-op: the host validates commands and characters, but a joining character's level and items are whatever its save says (after clamping).
- **Guild window on a client** shows only the player's own guild and invitations.
- **Buffs and statuses** are lost on a map change (the character is re-created from its save shape), as when re-logging.
- **Bandwidth:** unit state is sent whole when any field of a unit changes. That is fine on a LAN; it has not been measured on a slow link.
