# Project Twilight — TODO

Updated 2026-11-12 after guild MOTD and chat (Milestone 2) · 185 tests passing.

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
- [x] **Guild MOTD** (Milestone 2, done 2026-11-12)
  - [x] `motd` on the guild record, max 200 characters, no newlines
  - [x] Leader/officer edit, all members read
  - [x] Show in the guild window and on login/join
- [x] **Guild chat** (Milestone 2, done 2026-11-12)
  - [x] Route through the existing chat/feed path with `channel: "guild"`
  - [x] Members only; ephemeral, not persisted
  - [x] Do not imply networked chat until co-op transport exists
- [ ] **Roster profiles**
  - [ ] Store level/job snapshots per member; derive online status from the simulation
  - [ ] Show level, job and OFFLINE in the roster
  - [ ] Test persistence and online/offline transitions
- [ ] **Guild storage polish**
  - [ ] Search by item name and sort by name/quantity in the GUILD tab
  - [ ] Recheck one-member-at-a-time state after kick/leave/disband

## Next — gameplay

- [x] Archer, Acolyte, Merchant and Thief first-job skill trees
- [x] Knight, Crusader, Priest and Monk second jobs
- [x] Canonical second, transcendent and third-job paths for all six families (plus custom Dread Knight / Abyss Knight and Oracle / Spirit Sage)
- [x] Core Pre-Renewal stat formulas: ranged weapons use DEX status ATK; status window shows formula-based soft DEF and soft MDEF
- [ ] Acolyte Blessing and other supportive buffs
- [ ] Party window and party EXP sharing
- [ ] Quests and quest log
- [x] First rAthena world batch: Hornet, Pupa, Creamy, Poporing, Thief Bug, Rocker and Drops, plus connected `prt_fild00`, `prt_fild04` and `prt_fild05` spawn tables
- [ ] More maps, monsters and dungeon content
- [ ] Refine, cards and socketing
- [ ] Trade window
- [ ] Replace the provisional `job_second` EXP table with the cross-checked Pre-Renewal table
- [ ] Custom icons for the DK_* / SH_* skills
- [ ] Per-skill animations for Dark Knight and Shaman
- [ ] Dark Knight axe weapon layer

## Multiplayer and server

- [x] Co-op transport (ENet) behind the existing `FieldSimulation` authority layer (playable; see `docs/DIRECTIVE_COOP_NETWORKING.md`)
- [ ] Co-op: verify on a real LAN and over the internet, with three or more players; reconnect after a drop; port / advertised-IP fields in the Settings window (they are read from `user://settings.cfg` today)
- [ ] Co-op: party window, speech bubbles, trading between players, PvP rules
- [ ] Audio: positional panning, per-map ambient sounds from RSW sound sources, ACT-embedded sound events
- [ ] More monster species: `monsters.json` now has ten Classic species; the remaining fields, dungeons and boss encounters still need data
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
