# Directive: work in progress for AI agents

Read this first if you are picking up Project Twilight mid-task. It lists what
the project owner asked for, what is already done, and what still has to be
built, in order. Tick items off (`[x]`) as you finish them, and keep this file
current: it is the hand-off record between sessions.

> **Next session:** roster profiles and guild storage search/sort. See
> [docs/DIRECTIVE_GUILD_SOCIAL.md](docs/DIRECTIVE_GUILD_SOCIAL.md) and
> [TODO.md](TODO.md).

## Ground rules (never break these)

- **Never modify the original client** (`01_Client_Original`, the user's kRO folder). Read-only access only.
- **Never commit proprietary assets:** Gravity / DS / Eternal Love files, GRFs, SPR/ACT, extracted images, `Resources/` contents, `GRADIUS.ttf`, or `Shaman.jpg`.
  - The repo `.gitignore` is an allow-list. Before every push:
    - run `git diff --cached --name-only` and grep it for proprietary extensions;
    - then check the remote tree with `gh api repos/XiONDiGiTaL/ProjectTwilight/git/trees/main?recursive=1`.
- **`Resources/` is a user resource pack, loaded at runtime only:**
  - mounted by `RoResources._mount_pack()`;
  - the path comes from `Settings.resource_pack_path()`.
- **Pre-Renewal rules:** mechanics are Pre-Renewal-inspired. Ragnarok DS is a design reference for Dark Knight and Shaman, not a balance source. Document every number in `GAME_MECHANICS.md` or the class design doc, with a confidence level.
- **Tests:**
  - Command: `X:\Godot\Godot_v4.8-beta1_win64_console.exe --headless --path 06_Godot_Project -s res://tests/run_tests.gd`
  - Always run it via `Start-Process` plus `WaitForExit` with a timeout.
  - After adding new `class_name` scripts, run `--headless --import` once first.
  - Each test must `return true`.
  - Capture scripts (`tests/capture_*.gd`) must run **without** `--headless`.
- **Commits:** the owner pre-authorised commits and pushes to `main`. End each commit message with the Co-Authored-By line used in the history.
- **UI style:** every UI element follows the SAO / PSO2 / Solo Leveling translucent-glass look. The building blocks are:
  - `UiTheme`, `GlassPanel`, `GlassWindow`, `GlassBar`;
  - blue accent `UiTheme.ACCENT`.

## Current task: Dark Knight and Shaman second jobs (owner brief, 2026-11-11)

Full brief: Swordman → **Dark Knight**, female Acolyte → **Shaman**, with full skill trees, weapons, visuals, persistence and tests. The skill numbers and their rationale belong in `docs/design/CLASS_DARK_KNIGHT_SHAMAN.md`.

### Done

- [x] Resource pack mounting:
  - pack GRFs: `CorrectedSprites.grf` first, then `2025 Palettes.grf`;
  - loose overlay trees, e.g. `Resources/Dark knight Sprite/sprite/...`;
  - `RoResources.pack_file()`.
- [x] Battle font: `UiTheme.battle_font()` loads `GRADIUS.ttf` from the pack, with a fallback.
- [x] Data:
  - `jobs.json`: `dark_knight` and `shaman` (tier 2, parent, min_parent_job_level 40, Shaman female only, btba / weapon permissions, `pack_sprite`);
  - `skills.json`: `SM_TWOHAND` plus 13 `DK_*` and 15 `SH_*` skills, with a branch field on every skill;
  - `items.json`: Katana, Claymore, Axe, Battle Axe, Club, Rod, Book;
  - `shops.json`: Prontera Weapon Dealer;
  - `exp_tables.json`: `job_second`, provisional (job_first × 2);
  - `classes.json`: the two new classes.

### To do (in this order)

1. [x] **Simulation status framework**
   - Add `SimUnit.statuses` and per-tick expiry in `FieldSimulation`. Debuffs:
     - stun, sleep and stone block acting;
     - sleep breaks on damage;
     - silence blocks skills;
     - blind gives −25% HIT/FLEE;
     - confusion makes movement random.
   - Resistance by stat; events `{type: "status", id, status, on}`.
2. [x] **Buffs**:
   - `dark_breath`: ATK%, HP drain; ends before HP drops below 10%.
   - `shadow_quicken`: ASPD%, drain, cap 190.
   - `dark_weapon` / `mistletoe`: weapon element override; cleared on weapon change and on death.
   - `protection`: DEF/MDEF.
   - `wrath`: MATK%.
   - `rain_dance` / `se_wind`: element bonus on own magic.
   - `auto_counter`: stance.
3. [x] **Second job change**
   - `command_job_change` for tier 2: parent job, job level ≥ 40, sex rule.
   - `available_skills` includes the parent job's skills.
   - The Job Guide dialogue in `field_scene.gd` offers the second jobs. Knight, Crusader, Priest and Monk are listed as "not yet available".
4. [x] **Physical skill executor** (data-driven from `skills.json`):
   - fields: weapon requirement, `hits`, `splash` / `area`, `pierce`, `element` / weapon element, lifesteal, `inflict` status;
   - Hell Impact goes through the cast system (`cast_time` + `physical`).
   - Auto Counter hooks into monster melee attacks.
5. [x] **Support and magic extensions**:
   - target types `ally` / `dead_ally` / `self`; heal, SP, buff and resurrect effects;
   - Wrath MATK and element bonuses applied in `_release_spell`;
   - status inflict on spells;
   - a `fx` field drives the visuals (orbs / bolts / burst / spikes / judgment / wave / impact).
6. [x] **Masteries**:
   - `SM_TWOHAND` and `DK_AXEMASTERY` go through the existing `mastery_weapons` path;
   - `DK_CRITUP` adds a `crit_bonus` to the combat profile;
   - two-handed weapons block the shield slot.
7. [x] **Sprites**:
   - **Dark Knight:** body `운영자` from the pack overlay, with a sword weapon layer; fallback Knight `기사`.
   - **Shaman:** build a synthetic `SprFile` / `ActFile` from `Resources/Shaman.jpg`.
     - Frame rects and the action mapping go in `data/sprites/shaman_sheet.json`; key out the grey background.
     - Sheet layout:

       | Rows | View | Contents |
       |---|---|---|
       | 0, 2 | back | walk |
       | 1 | back | idle, sit, cast ×6, hurt, dead |
       | 3 | front | idle, sit, cast ×6, hurt, dead |
       | 4 | front | walk |
       | 5 | back | attack (11 frames) |
       | 6 | front | attack (11 frames) |

     - Fallback: Priest `프리스트`.
     - Head anchor near the top of the hood; calibrate visually.
8. [x] **Palettes**:
   - body palette support in `CharacterSprite`: cloth dye `data/palette/몸/<job>_<sex>_<n>.pal`, 700 per job;
   - hair colours up to 131: `머리<style>_<sex>_<n>.pal`;
   - creation UI steppers; saved as `cloth_color`.
9. [x] **Skill window**: group by `branch`; show SP, cast time, delay, duration, weapon restriction and type; block invalid allocation (the simulation already validates).
10. [x] **Damage numbers** in the new style:
    - blue gradient fill with a white outline in the battle font;
    - big hits and multi-hit totals in vibrant glowing blue;
    - small hits in a softer tone with a white outline.
11. [x] **Badges**: add `dark_knight` and `shaman` glyphs to `tools/insignia/emblem_painter.gd`, then rerun `generate_badges.gd` (non-headless).
12. [x] **Tests**: add `tests/unit/test_dark_knight.gd` and `tests/unit/test_shaman.gd`, covering every item in the brief's test list. Multiplayer is tested as two players in one authoritative simulation.
13. [x] **Visual captures**: add `tests/capture_classes.gd` and check the results.
14. [x] **Docs**:
    - write `docs/design/CLASS_DARK_KNIGHT_SHAMAN.md`, with a status per skill: implemented, partial, placeholder or planned;
    - update CHANGELOG, GAME_MECHANICS, ASSET_PROVENANCE (pack assets are not redistributed) and ROADMAP.
15. [x] Commit and push.

### Known gaps to state honestly

- **Networking:** there is no network transport yet. The co-op and dedicated-server paths do not exist in code. `FieldSimulation` commands are the authority layer and validate everything server-side. Report multiplayer as "authority logic ready, transport not implemented".
- **Persistence of buffs:** buffs and statuses are not saved; they end on logout, which is the classic behaviour.
- **Weapon layers:** the Dark Knight pack only ships a sword weapon layer, so axes have no weapon sprite.

### Follow-ups from this task (open)

- [x] **Design approval:** the owner chose separate branches; the Dark Knight sword, axe and dark lines are independent.
- [ ] **Spiritual Prayer vs the offline auto-revive (3 s):** add a "return to save point" choice so resurrection matters.
- [ ] Replace the provisional `job_second` EXP table with the cross-checked Pre-Renewal table.
- [ ] Custom icons for the DK_* / SH_* skills.
- [ ] Per-skill animations (the brief's animation list).
- [ ] A weapon layer for Dark Knight axes.
- [ ] Knight, Crusader, Priest and Monk.
- [ ] A network transport for co-op and dedicated servers. The authority logic is ready in `FieldSimulation`.

## Task: NPC scripts (owner brief, 2026-11-11) — done

- [x] The game is playable from the main scene; `tests/smoke_play.gd` checks the full flow.
- [x] rAthena script interpreter (`scripts/npc/`), loader (`data/npc/scripts.txt`) and the rAthena `npc` folder in `Resources/rathena` (sparse clone, never committed).
- [x] Healer, warper, job master, platinum skills, stylist, rental and reset NPCs: rAthena versions plus original fallbacks.
- [x] NPC sprites from the client's npcidentity / jobname `.lub` files.

### Follow-ups (open)

- [ ] Open rAthena `shop` NPCs in the shop window.
- [ ] `OnTouch` areas and NPC timers.
- [x] Load rAthena `npc/warps` so every map gets its portals; map spawns from `npc/pre-re/mobs` (done 2026-11-11).
- [ ] Draw falcon, cart and Peco; add Falconry, Pushcart and Riding to the classes that need them.
- [ ] Export presets: include `data/**/*.txt` in exported builds.

## Task: a living world — CPU adventurers and minimap (owner brief, 2026-11-11) — done

- [x] `BotBrain` (`scripts/gameplay/world/bot_brain.gd`) drives CPU players through the same `FieldSimulation` commands a human client sends. Roles: melee, caster (picks the element the target is weakest to), support Shaman (heal, buff, `SH_PRAYER` revive).
- [x] `FieldSimulation` ticks bots, keeps them off warp portals, and makes fallen bots wait `BOT_REVIVE_MS` (40 s) instead of the 3 s player revive.
- [x] `FieldScene` spawns 2–4 per map (`@export bots_enabled`, off for tools/captures) at `BotBrain.map_level`, away from the player.
- [x] Role-coloured `Label3D` name tags on bots only. `pixel_size * font_size` must stay around 1.5–2 world units to be readable.
- [x] `Minimap` (`scripts/ui/minimap.gd`): GAT walkability silhouette plus portal / monster / bot / player blips; `M` toggles it.
- [x] HUD guards: bot EXP and level-ups never write the player's save.
- [x] Tests: `tests/unit/test_bots.gd` (10 tests). Suite: 128 passed, 0 failed.
- [x] Diagnostics: `tests/diag_warps.gd` (2,999 portals from rAthena, 0 errors), `tests/capture_bots.gd`.

### Follow-ups (open)

- [ ] Bots should path to town shops and sell there; today junk is converted to Zeny abstractly.
- [ ] Party behaviour: spread across different monsters instead of stacking on one.
- [ ] Cleanse debuffs once a cure skill exists.
- [ ] Minimap: player facing arrow and click-to-walk.

## Task: data folder, server rules and command console (owner brief, 2026-11-11) — done

Owner brief: the game should run from the essential `.grf` data in a folder, without the ragexe/launcher, because Godot is the engine; add private-server quality of life; characters must move between offline, co-op and MMO; the MMO should read rAthena/Hercules server configuration.

- [x] `RoResources._grf_order`: `DATA.INI` order first, then every other `*.grf` in the folder and in `Data/`. A bare folder of archives mounts without an executable; a loose `data/` tree mounts too. `Settings` is resolved through the tree so the script is testable standalone.
- [x] `RuleConfig` (`scripts/gameplay/rules/rule_config.gd`): EXP / job / drop rates, autoloot, level cap. Sources: `data/config.json` → `user://server.cfg` → `<server>/conf/battle/{exp,drops,levels}.conf` (rAthena/Hercules). Unknown keys ignored, values clamped.
- [x] `FieldSimulation` applies the rules to EXP, drops, autoloot and the level cap; `FieldSimulation.new(gat, seed, rules)` accepts an injected rule set for tests and servers.
- [x] `ChatCommands` + `ChatConsole`: **Enter** opens the command line; `@go`, `@warp`, `@heal`, `@save`, `@die`, `@revive`, `@rates`, `@autoloot`, `@mobinfo`, `@who`, `@exp`, `@job`, `@where`, `@time`, `@help`. Plain text is local speech.
- [x] Tests: `test_rule_config.gd`, `test_chat_commands.gd`, `test_resource_mount.gd`. Suite: 145 passed, 0 failed.
- [x] `tests/capture_qol.gd` renders the console and command feedback.

### Follow-ups (open)

- [ ] Kafra storage, refine, cards and socketing — the private-server staples still missing.
- [ ] A real chat channel with speech bubbles and a party window (needs co-op transport).
- [ ] Character export/import UI so a save can be carried between offline, co-op and MMO servers.
- [ ] Read more rAthena conf groups (party, guild, PvP) once the corresponding systems exist.
- [ ] `@item`, `@jobchange` and other GM commands behind a permission flag for the MMO mode.

## Task: Kafra storage (owner brief, 2026-11-11) — done

- [x] `SimUnit.storage` (300 slots, no weight) plus `open_storage`; `Inventory.max_entries` makes the slot limit per bag.
- [x] `command_open_storage` / `command_storage_deposit` / `command_storage_withdraw`: open-storage, range, count, slot and carried-weight validation; `storage` events carry the result text.
- [x] `StorageWindow`: CARRIED / STORAGE tabs, quantity selector, capacity line, item rows with icons. Walking away or closing clears the server-side open storage.
- [x] Kafra NPC in Prontera at (150, 191) from `maps.json`; sprite `4_f_kafra1` exists in the client (verified).
- [x] Save v6 adds `storage`; v5 saves load with an empty bag. Restored storage keeps its 300 slots.
- [x] Tests: `test_storage.gd` (8). Suite: 153 passed, 0 failed. `tests/capture_storage.gd` renders both tabs.

### Follow-ups (open)

- [x] rAthena Kafra NPCs: `openstorage` (+ `storage` alias), `close3`, `implode` and `F_CanOpenStorage` are implemented; `kafras.txt` + `functions_kafras.txt` load by default. Their scripted fee is charged (40z in Prontera); Twilight's Kafra uses `kafra_fee` (0 by default). Tested against the real Prontera Kafra.
- [x] Guild storage: `GuildStore` (`user://guilds.json`) keeps one 300-slot bag per guild; `guildopenstorage` opens it, one member at a time; `@guild create` / `leave` manage membership; saves v7 keep the guild. Tests: `test_guild_storage.gd` (7), including the Prontera Guild Keeper.
- [x] Guild roster window (`G`): roster with leader, invite by name, accept / decline invitations, leader-only kick, leave with succession. Tests: `test_guild_roster.gd` (5).
- [x] Guild ranks and officer permissions (Milestone 1 of [docs/DIRECTIVE_GUILD_SOCIAL.md](docs/DIRECTIVE_GUILD_SOCIAL.md), done 2026-11-12):
  - `GuildStore` keeps a `ranks` map (name → leader / officer / member) next to the canonical `leader` field; `GuildStore.can(actor_rank, action, target_rank)` is the permission matrix.
  - `FieldSimulation` derives the actor's rank from the record and enforces it in `command_guild_invite` / `kick` / `promote` / `demote` / `transfer` / `disband`.
  - Design choices: a transfer makes the old leader an **officer**; a guild whose last member leaves is **removed** (with its storage); `@guild create <existing name>` still joins as a member.
  - Rank-less guild files migrate on load and are saved in the new shape on the next change.
  - `GuildWindow.actions_for(name)` is the single place that decides which row buttons appear.
  - Tests: `test_guild_ranks.gd` (10). Suite: 180 passed. Captures: `guild_window_leader`, `_leader_confirm`, `_officer`, `_member`.
- [x] Guild MOTD and guild chat (Milestone 2 of [docs/DIRECTIVE_GUILD_SOCIAL.md](docs/DIRECTIVE_GUILD_SOCIAL.md), done 2026-11-12):
  - `GuildStore` keeps a one-line `motd` (max 200) with `motd_of` / `clean_motd` / `set_motd`; old guild files migrate with an empty message.
  - `command_guild_set_motd` is leader/officer only; `command_guild_chat` emits one `chat` event per online guild member. `/g` and `/guild` route through `ChatCommands` into the feed.
  - `GuildWindow` shows the message to everyone; leaders/officers get an editable MOTD field with SET.
  - Tests: `test_guild_social.gd` (5). Suite: 185 passed. Captures: `guild_window_leader`, `_leader_confirm`, `_officer`, `_member`.
- [ ] Roster profiles (Milestone 3), guild storage search/sort (Milestone 4) — still open.
- [ ] `@storage` for VIP-style remote access behind a rule flag.

## Where the three play modes stand (2026-11-11)

| Mode | State |
|---|---|
| **Offline** | Playable: character creation → Training Grounds (or skip straight to Prontera) → field combat, loot, jobs, saves, warps, rAthena NPC scripts, CPU adventurers. |
| **Private co-op** | Authority logic exists (`FieldSimulation` validates every command) and invitation codes are implemented and tested. **No transport**: no ENet peer, no session, no sync. |
| **MMO** | **Not implemented.** rAthena and Hercules are read as script/data sources only; there is no packet adapter. Their protocols target the original client and specific `PACKETVER`s. `RuleConfig` now reads their `conf/battle` rates, which is the first piece of server-config loading. |

## Asset independence (still open)

The game still reads the player's kRO client for maps, sprites and models; `Resources/` only adds optional packs. There is no original replacement asset set yet, so a standalone distributable build is not possible. Replacing one asset class at a time (starting with tilesets and UI) is the honest path.

## Backlog after this task

- Archer, Merchant and Thief first-job skills, and Acolyte skills (Heal, Blessing, Holy Light).
- More maps and monsters; quests.
- The co-op host and dedicated server transport.
- Hercules-specific elements: nothing from Hercules is used yet. Its script language is close to rAthena's, so the interpreter is the place to add Hercules deviations — only against a concrete script that fails.
