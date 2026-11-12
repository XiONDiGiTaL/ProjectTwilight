# Project Twilight — TODO

Updated 2026-11-12 after guild ranks (Milestone 1) · 180 tests passing.

The scoped hand-off is [`docs/DIRECTIVE_GUILD_SOCIAL.md`](docs/DIRECTIVE_GUILD_SOCIAL.md).
The project-wide rules and history are in [`Directive.md`](Directive.md).

## Now — guild social layer

- [x] **Ranks and officer permissions** (Milestone 1, done 2026-11-12; `test_guild_ranks.gd`, 10 tests)
  - [x] `ranks` map (`leader` / `officer` / `member`) in `GuildStore`, with migration for existing `user://guilds.json`
  - [x] Leader can promote, demote, transfer leadership and disband; only the leader can do these
  - [x] Officers can invite and kick ordinary members; members cannot
  - [x] `FieldSimulation` validates every action and emits guild events
  - [x] `GuildWindow` rank chips and permission-gated controls; transfer and disband ask for confirmation
  - [x] Leader leaving promotes an officer first, then a member
  - [x] Tests: migration, permissions, persistence, succession, disband cleanup
  - [x] Captured leader, officer and member views
  - [x] README, CHANGELOG, Directive and this file updated
- [ ] **Guild MOTD**
  - [ ] `motd` on the guild record, max 200 characters, no newlines
  - [ ] Leader/officer edit, all members read
  - [ ] Show in the guild window and on login/join
- [ ] **Guild chat**
  - [ ] Route through the existing chat/feed path with `channel: "guild"`
  - [ ] Members only; ephemeral, not persisted
  - [ ] Do not imply networked chat until co-op transport exists
- [ ] **Roster profiles**
  - [ ] Store level/job snapshots per member; derive online status from the simulation
  - [ ] Show level, job and OFFLINE in the roster
  - [ ] Test persistence and online/offline transitions
- [ ] **Guild storage polish**
  - [ ] Search by item name and sort by name/quantity in the GUILD tab
  - [ ] Recheck one-member-at-a-time state after kick/leave/disband

## Next — gameplay

- [ ] Archer, Acolyte, Merchant and Thief first-job skill trees
- [ ] Knight, Crusader, Priest and Monk second jobs
- [ ] Remaining Acolyte skills (Heal, Blessing, Holy Light)
- [ ] Party window and party EXP sharing
- [ ] Quests and quest log
- [ ] More maps, monsters and dungeon content
- [ ] Refine, cards and socketing
- [ ] Trade window
- [ ] Replace the provisional `job_second` EXP table with the cross-checked Pre-Renewal table
- [ ] Custom icons for the DK_* / SH_* skills
- [ ] Per-skill animations for Dark Knight and Shaman
- [ ] Dark Knight axe weapon layer

## Multiplayer and server

- [ ] Co-op transport (ENet) behind the existing `FieldSimulation` authority layer
  - [ ] Host/session lifecycle and invitation-code handshake
  - [ ] Snapshot + command replication, reconnect and late join
  - [ ] Server-authoritative guild and storage actions
- [ ] Dedicated server mode
- [ ] MMO packet adapter for rAthena/Hercules (not started; version-specific)
- [ ] Read more rAthena/Hercules conf groups (party, guild, PvP) as systems land
- [ ] GM commands behind a permission flag (`@item`, `@jobchange`, …)
- [ ] Character export/import UI for carrying saves between offline, co-op and MMO

## QoL / private-server staples

- [x] Kafra storage and rAthena Kafra scripts
- [x] Guild storage and guild window
- [ ] `@storage` remote access behind a rule flag
- [ ] Storage search/sort
- [ ] Bots path to town shops and sell junk there
- [ ] Party behaviour: spread across monsters instead of stacking
- [ ] Minimap player-facing arrow and click-to-walk

## Assets and release

- [ ] Original tileset and UI replacement assets (standalone build is not possible yet)
- [ ] Local importer that converts the player's own client into `user://` Godot resources
- [ ] Export presets that include `data/**/*.txt`
- [ ] Validate an exported build on a machine without the original client folder

## Engineering / docs

- [ ] Keep `Directive.md`, `TODO.md` and `ROADMAP.md` current at every hand-off
- [ ] Add tests for any new save migration
- [ ] Keep capture scripts out of `--headless`
- [ ] Audit for proprietary assets before every push
- [ ] CI-style headless test command for Windows and Linux
