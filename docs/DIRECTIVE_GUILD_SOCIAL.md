# Directive: guild social layer (next session)

**Status:** hand-off after commit `9e899a5` · **Suite:** 170 passed, 0 failed, 0 skipped
**Scope:** turn the guild window into a complete social layer: ranks, officer
permissions, a message of the day, guild chat, richer roster rows and guild
storage search/sort.

Read [`Directive.md`](../Directive.md) first for project-wide rules, then
[`TODO.md`](../TODO.md) for the checklist. This file scopes the guild work; it
does not replace the main directive.

## Current state (verified)

- `GuildStore` (`06_Godot_Project/scripts/gameplay/guilds/guild_store.gd`) is the
  shared registry, persisted to `user://guilds.json`. A record contains
  `id`, `name`, `leader`, `members`, `invites` and one 300-slot `storage` bag.
- `FieldSimulation` owns every guild mutation and validates it:
  `command_create_guild`, `command_guild_invite`, `command_guild_accept`,
  `command_guild_decline`, `command_guild_kick`, `command_leave_guild`,
  `command_open_guild_storage`, `command_guild_deposit` and
  `command_guild_withdraw`.
- `GuildWindow` (`G`) shows the roster, leader/member badges, leader-only invite
  and kick, leave with succession, and accept/decline for guildless characters.
  It only emits intents; it never edits `GuildStore` directly.
- `StorageWindow` has a GUILD tab; the Prontera Guild Keeper and rAthena
  `guildopenstorage` both open it. One member may use the bag at a time.
- Character saves (v7) keep only `guild_id` / `guild_name`; the guild record is
  authoritative for membership.
- Tests: `tests/unit/test_guild_roster.gd` (5) and
  `tests/unit/test_guild_storage.gd` (7). `tests/capture_guild_window.gd` is the
  visual capture.
- **Guilds are local-only today.** There is no co-op transport or MMO packet
  adapter; do not present guild features as networked.

## Milestone 1 (do next): ranks and officer permissions

### Goal

A guild has a leader, officers and members. Officers can invite and kick
ordinary members; only the leader can promote, demote, transfer leadership or
disband. Every rule is enforced by `FieldSimulation`, and the window only shows
the controls the acting player is allowed to use.

### Data model

- Add a `ranks` dictionary to each guild record: character name → `"leader"`,
  `"officer"` or `"member"`.
- Keep the existing `leader` field as the canonical leader name for
  compatibility; it must always agree with the single `"leader"` entry in
  `ranks`.
- New members join as `"member"`. Kicking or leaving removes the rank entry.
- The record is still name-keyed; invites remain name strings so offline
  characters can be invited.

### Permission matrix

| Action | Leader | Officer | Member |
|---|---|---|---|
| Invite | yes | yes | no |
| Kick a member | yes | yes | no |
| Kick an officer | yes | no | no |
| Promote / demote | yes | no | no |
| Edit MOTD (later milestone) | yes | yes | no |
| Transfer leadership | yes | no | no |
| Disband | yes | no | no |
| Use guild storage | yes | yes | yes |

The leader cannot kick themselves. An officer cannot kick another officer or the
leader. The leader can kick an officer, which also removes that officer's rank.

### Behaviour

- Add `GuildStore` helpers for rank lookup and rank changes, but route every
  user action through `FieldSimulation` commands so a future host/server
  validates the same way.
- Promotion and demotion apply to existing members only. Unknown names and
  non-members are rejected with a guild event, not a silent no-op.
- Leadership transfer makes the target `"leader"`, makes the old leader a
  `"member"` (or `"officer"` if you prefer; document the choice), and updates
  the `leader` field atomically. Only the leader can transfer.
- Disband is leader-only and irreversible. Remove the guild record, clear the
  guild fields and open guild-storage state of every online member, and save.
  The UI must ask for confirmation before emitting the intent.
- Preserve the current leader-leaves behaviour: if the leader leaves, promote
  the first officer if one exists, otherwise the first member. If the guild is
  empty, remove it.
- The guild window should show a rank chip per row and expose:
  - `PROMOTE` / `DEMOTE` for the leader;
  - `TRANSFER` for the leader, with a confirmation and a target choice;
  - `DISBAND` for the leader, with a confirmation;
  - existing `INVITE` and `KICK` controls gated by the matrix.
- Officer controls must be visually distinct from member controls and must not
  appear when the local player lacks the permission.

### Migration

Existing `user://guilds.json` records have no `ranks`. On load:

- the recorded `leader` becomes `"leader"`;
- every other member becomes `"member"`;
- missing/unknown rank values fall back to `"member"` (except the leader);
- the record is saved in the new shape the next time it changes.

Add a regression test that loads a legacy record with no `ranks` and verifies
the leader and members are usable immediately.

### Tests

Extend `tests/unit/test_guild_roster.gd` (or add `test_guild_ranks.gd` and
register it in `tests/run_tests.gd`) with at least:

1. legacy migration: no `ranks` field still yields one leader and members;
2. leader promotes a member to officer, and it survives a reload;
3. officer can invite and kick an ordinary member;
4. member cannot invite, kick, promote or disband;
5. officer cannot kick an officer or the leader;
6. leader can kick an officer and the rank entry disappears;
7. leadership transfer updates `leader`, `ranks` and persistence;
8. disband removes the record and clears online members' guild state;
9. leader leaving promotes an officer first, then a member;
10. rejected actions do not mutate `GuildStore` or save the file.

Use temporary guild paths (`user://test_guild_*.json`) and clean up as the
existing guild tests do.

### Done when

- The permission matrix is enforced in `FieldSimulation`, not only in the UI.
- `GuildWindow` shows the correct controls for leader, officer and member.
- Legacy guild files load without losing membership.
- The new tests pass and the full suite is green.
- `CHANGELOG.md`, `README.md` and `Directive.md` mention ranks and permissions.
- A capture (or an updated `capture_guild_window.gd`) shows a leader view and an
  officer view; inspect both before claiming the UI works.

## Milestone 2: MOTD and guild chat

After ranks are stable:

- Add `motd` (max 200 characters, no newlines) to the guild record; leader and
  officers can edit it, members can read it. Show it in `GuildWindow` and in the
  system feed on login/join.
- Add a guild chat channel through the existing chat/feed path. Emit a
  `{type: "chat", channel: "guild", ...}` event from the simulation; do not build
  a parallel chat UI. Only members can send or receive.
- Keep chat ephemeral. Do not persist messages, and do not imply that guild chat
  crosses the network until the co-op transport exists.
- Test with two `SimUnit` players in one authoritative simulation: member
  receives, non-member does not, muted/non-member send fails.

## Milestone 3: roster profiles

The roster currently shows names only. Add a small per-member profile snapshot
(level, job, maybe last-seen) to the guild record:

- update it when a character joins and when their level or job changes while
  online;
- derive online status from `FieldSimulation.units`, never store an `online`
  boolean in the guild file;
- show `Lv`, job and an `OFFLINE` label in the roster;
- test persistence and the online/offline transition.

## Milestone 4: guild storage polish

- Add search by item name and sort by name / quantity in the GUILD tab.
- Keep all members able to deposit and withdraw; do not tie storage access to
  rank in this pass unless the owner asks for it.
- Re-check the one-member-at-a-time rule and stale open-storage state after a
  kick, leave or disband.

## Architecture map

| File | Responsibility |
|---|---|
| `scripts/gameplay/guilds/guild_store.gd` | Persistent guild records, ranks, invitations, storage, save/load |
| `scripts/gameplay/world/field_simulation.gd` | Authority layer; validates guild commands and emits guild events |
| `scripts/ui/guild_window.gd` | Roster/management UI; emits intents only |
| `scripts/game/field_scene.gd` | Wires window signals to simulation, `G` key, refresh on guild events |
| `scripts/ui/storage_window.gd` | CARRIED / STORAGE / GUILD tabs and quantity controls |
| `scripts/npc/ra_interpreter.gd` + `ra_host.gd` | `guildopenstorage` script command |
| `tests/unit/test_guild_roster.gd` | Invite/accept/kick/leave/succession tests |
| `tests/unit/test_guild_storage.gd` | Shared-bag and one-user-at-a-time tests |
| `tests/capture_guild_window.gd` | Visual capture; run **without** `--headless` |

## Constraints

- Never modify `01_Client_Original`; never commit Gravity/DS/EL assets, GRFs,
  extracted images or `Resources/` contents. The `.gitignore` is an allow-list.
- Keep the Twilight Glass look: `GlassWindow`, `UiTheme`, blue `ACCENT`.
- Do not add a network transport in this session. `FieldSimulation` is the
  authority layer; keep it that way.
- Do not use client-supplied permissions. The simulation derives the actor's
  rank from the guild record.
- Preserve old saves and old guild files. Add migration, do not bump versions
  just for the sake of it.

## Verification

```powershell
# Once after adding a new class_name
& "X:\Godot\Godot_v4.8-beta1_win64_console.exe" --headless --path 06_Godot_Project --import

# Full suite (use Start-Process + WaitForExit with a timeout)
& "X:\Godot\Godot_v4.8-beta1_win64_console.exe" --headless --path 06_Godot_Project -s res://tests/run_tests.gd

# Visual check (no --headless)
& "X:\Godot\Godot_v4.8-beta1_win64_console.exe" --path 06_Godot_Project -s res://tests/capture_guild_window.gd
```

Each test must `return true`. Report the exact passed/failed/skipped counts.
Check the capture at `user://captures/` before saying the UI is verified.

## Commit

Commit the code, tests, capture and docs together. End the message with the
repository's existing attribution line:

```text
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

Do not push unless the owner asks. Leave the tree clean.

## Prompt for Claude

```text
Continue Project Twilight, a Godot 4.8 Pre-Renewal Ragnarok Online reimplementation at E:\ProjectTwilight.

Read docs/DIRECTIVE_GUILD_SOCIAL.md, TODO.md and Directive.md first, then inspect the current guild code. Implement Milestone 1 only: guild ranks (leader / officer / member), officer permissions, promotion/demotion, leadership transfer and leader-only disband. Persist ranks in GuildStore with migration for existing guild files, enforce every rule in FieldSimulation, and update GuildWindow so it only shows the controls the acting player may use. Do not start MOTD, chat, roster profiles or network transport in this session.

Follow the repository rules: never modify 01_Client_Original or commit Gravity/DS/EL assets, GRFs or Resources/ contents; preserve the Twilight Glass UI; keep old saves and guild files loadable. Add focused tests for migration, permissions and persistence, register any new test file in tests/run_tests.gd, run --headless --import if you add a class_name, run the full suite, and capture the leader and officer views without --headless. Update CHANGELOG.md, README.md, Directive.md and TODO.md. Commit with the existing Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com> footer and report the exact test counts and any limitations honestly.
```
