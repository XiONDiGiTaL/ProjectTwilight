# NPC scripts

Project Twilight runs NPCs written in the **rAthena script language**. The interpreter is original code in `06_Godot_Project/scripts/npc/`, written from the language's public documentation. No emulator code is used.

- **rAthena's own scripts** (GPL-3.0) are loaded only from the player's resource pack at runtime and are never committed.
- **Project Twilight's equivalents** in `data/npc/twilight/` are original and Apache-2.0.

## Loading

`data/npc/scripts.txt` lists the files, one per line:

| Line | Meaning |
|---|---|
| `res://data/npc/twilight/prontera_services.txt` | A Project Twilight script |
| `pack:rathena/npc/custom/healer.txt` | A file in the resource pack (`Resources/rathena/...`) |
| `a \|\| b` | The first alternative that exists, e.g. rAthena's healer, otherwise ours |

The **Global_Functions** pack file provides `F_InsertComma`, `F_GetPlatinumSkills` and others. When it is missing, `F_InsertComma` is built in.

To fetch rAthena's NPC folder:

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/rathena/rathena.git Resources/rathena
git -C Resources/rathena sparse-checkout set npc
```

## What is loaded by default

| Service | rAthena file (if present) | Project Twilight fallback |
|---|---|---|
| Free healer in every town | `npc/custom/healer.txt` (over 30 towns) | `twilight/healer.txt` (18 towns) |
| Warper (fast travel) | `npc/custom/warper.txt` (towns, fields, dungeons, …) | `twilight/warper.txt` (towns, fields, dungeons) |
| Job changer | `npc/custom/jobmaster.txt` | `twilight/prontera_services.txt` Job Master. Always loaded; the only one that offers Dark Knight and Shaman. |
| Platinum skills | `npc/custom/platinum_skills.txt` | Job Master area, Prontera south gate |
| Stylist (hair style, hair colour, cloth dye) | `npc/custom/stylist.txt` | Prontera south gate |
| Rental (falcon, cart, Peco) | `npc/custom/breeder.txt` | Prontera south gate |
| Skill and stat reset | `npc/custom/resetnpc.txt` | Prontera south gate |
| Kafra save / storage / teleport | `npc/kafras/kafras.txt` (with `functions_kafras.txt`) | `maps.json` Kafra in Prontera |
| Guild storage | — | `twilight/guild_keeper.txt` (Prontera, `guildopenstorage`) |

**Sprites:** NPC sprite ids (`909`) and names (`4_F_KAFRA1`) are resolved through the player's own client tables, `npcidentity.lub` and `jobname.lub`. They are read by `Lua51Chunk`, a small Lua 5.1 bytecode table reader. Invisible ids (`-1`, `111`, `139`) are not drawn.

**Maps:** warps to any map in the player's client work, including maps without Project Twilight map data. The town or field loads from the client; monsters only spawn on maps that `maps.json` describes.

## Supported language

| Area | Supported |
|---|---|
| Top level | `script` NPCs (map-placed, floating `-`, OnTouch area), `duplicate(...)`, `function script`, `warp` and `shop` lines (parsed), `/* */` and `//` comments |
| Statements | `if / else`, `for`, `while`, `do … while`, `switch / case / default`, `break`, `continue`, labels, `goto`, `callsub`, `return`, local `function Name {}` with forward declarations, `close3`, `end` |
| Expressions | Integers, strings, `+ - * / %`, comparisons, `&& \|\| !`, bit operators, `?:`, assignments (`= += -= …`), `++` / `--`, arrays `name[i]` |
| Variables | `.@` (script), `.` (NPC), `@` (character, temporary), plain (character, **saved with the character**), `$` (global, saved in `user://npc_globals.json`), `$@` (global temporary), `#` / `##` (saved as character variables offline) |
| Dialog | `mes`, `next`, `close`, `close2`, `select`, `prompt`, `menu` (with labels and `-`), `input` (numbers) |
| Character | `Zeny`, `BaseLevel`, `JobLevel`, `Class`, `BaseClass`, `BaseJob`, `Sex`, `SkillPoint`, `StatusPoint`, `Hp`, `MaxHp`, `Sp`, `MaxSp`, `Weight`, `MaxWeight` |
| Commands | `percentheal`, `heal`, `warp`, `jobchange`, `jobname`, `eaclass`, `roclass`, `skill`, `getskilllv`, `resetskill`, `resetstatus`, `getitem`, `delitem`, `countitem`, `openstorage`, `guildopenstorage`, `implode`, `getguildname`, `getlook`, `setlook`, `getbattleflag`, `set`, `setarray`, `cleararray`, `deletearray`, `getarraysize`, `getelementofarray`, `getarg`, `getargcount`, `callfunc`, `rand`, `strcharinfo`, `sprintf`, `getstrlen`, `gettimetick`, `message`, `dispbottom`, `announce`, `specialeffect(2)`, falcon / cart / Peco checks and setters |
| Effects | `checkre()` is 0 (Pre-Renewal). Visual-only commands (`emotion`, `cutin`, `soundeffect`, …) do nothing. |

Unsupported commands do nothing and are listed in the console, e.g. `NPC Warper used unsupported commands: …`. Third- and fourth-class constants resolve to a value no Pre-Renewal class has, so rAthena's job master offers only the classic paths that exist in this build.

## Authority and multiplayer

- **Where effects apply:** script effects go through `FieldSimulation` helpers (`script_heal`, `script_job_change`, `script_grant_skill`, `script_reset_*`, `script_get_item` / `script_del_item`), so a co-op host or dedicated server would apply them with the same rules.
- **Hosts:** `RaHost` is the headless host (tests, server); `FieldNpcHost` drives the glass dialog.
- **Not built yet:** the network transport.

## Kafra storage

`openstorage` (and its `storage` alias) opens the same glass storage window as Twilight's own Kafra. The official rAthena Kafra scripts are loaded from the resource pack, so their menus (save, storage, teleport, pushcart) work; their storage fee is the per-NPC argument in `kafras.txt` (40 zeny in Prontera), charged by the script itself. Twilight's own Kafra uses `kafra_fee` from `data/config.json` / `user://server.cfg` (0 = free). Both paths go through `command_open_storage`, so range, slots, weight and the open-storage state stay server-validated.

`guildopenstorage` uses `command_open_guild_storage` and opens one shared bag for every member of the player's guild. It returns 1 while another member has it open (the rAthena contract), and 0 on success. Moves go through `command_guild_deposit` / `command_guild_withdraw`, which validate the open state, range, counts, slots and the withdrawing member's carried weight, then persist the guild bag.

## Known limits

- **Rental:** falcons, carts and Peco Pecos are stored as character options but not drawn yet. No class in this build has Falconry, Pushcart or Riding.
- **Shops:** `shop` lines are parsed but not opened yet. The Project Twilight shops in `shops.json` are used instead.
- **Guild Kafra:** `guildopenstorage` opens the shared guild storage (one member at a time). Membership comes from `@guild create <name>` / `@guild leave`; guilds and their bag live in `user://guilds.json`.
- **Not yet handled:** NPC timers, `OnTouch` areas, `waitingroom` and `query_sql`.
