# Pre-Renewal Game Mechanics

**Target ruleset:** classic Pre-Renewal. The reference client is a 2025 Renewal-era kRO build and is **not** used as evidence for mechanics.

Implementation: `06_Godot_Project/scripts/gameplay/progression/stat_rules_prerenewal.gd`. Tests: `tests/unit/test_mechanics.gd`.

| Rule | Formula | Confidence | Evidence / golden value |
|---|---|---|---|
| Starting status points | 48 (all six stats start at 1) | High | iRO Wiki (classic), rAthena pre-re |
| Status points per level | floor(old_level / 5) + 3 | High | Produces the well-known 1,273 total at base level 99 (tested) |
| Stat raise cost (x → x+1) | floor((x − 1) / 10) + 2 | High | Produces the well-known 628 points for 1 → 99 (tested) |
| HIT | BaseLv + DEX + bonuses | High | iRO Wiki classic stats page |
| FLEE | BaseLv + AGI + bonuses | High | iRO Wiki classic stats page |
| Perfect dodge | 1 + floor(LUK / 10) | High | iRO Wiki classic |
| Critical rate | 1 + LUK × 0.3 (%) | High | iRO Wiki classic |
| Status ATK (melee) | STR + floor(STR/10)² + floor(DEX/5) + floor(LUK/5) | High | iRO Wiki classic. Ranged weapons swap STR and DEX. |
| MATK range | INT + floor(INT/7)² … INT + floor(INT/5)² | High | iRO Wiki classic |

## Combat

Implementation: `scripts/gameplay/combat/combat_rules_prerenewal.gd`, `scripts/gameplay/world/field_simulation.gd`. Tests: `tests/unit/test_combat.gd`.

| Rule | Formula | Confidence |
|---|---|---|
| Hit chance | 80 + HIT − FLEE, clamped to 5–95% | High |
| Critical chance | 1 + LUK × 0.3 % minus target LUK × 0.2 % (players only) | High |
| Critical damage | Maximum ATK; ignores FLEE and DEF; no × 1.4 multiplier (that is Renewal) | High |
| Hard DEF | Percentage reduction (`damage × (100 − DEF) / 100`) | High |
| Monster soft DEF | VIT + rnd(0, max(0, floor(VIT/20)² − 1)) | High |
| Player soft DEF | floor(VIT × 0.5) + rnd(floor(VIT × 0.3), max(floor(VIT × 0.3), floor(VIT²/150) − 1)) | Medium-high |
| Minimum damage | 1 | High |
| ASPD | 200 − (WD − (floor(WD × AGI / 25) + floor(WD × DEX / 100)) / 10), with WD = 50 × BTBA | High (formula) |
| Attack interval | (200 − ASPD) × 20 ms | High |
| Novice fist BTBA | 0.5 s | Medium |
| Novice max HP | (35 + 5 × level) × (1 + VIT/100) | Medium (other jobs need HP factors) |
| EXP distribution | Split by share of damage dealt | Medium |
| Passive monsters | Retaliate against their attacker; give up beyond 14 cells | Medium |
| Monster data | Poring, Fabre, Lunatic in `data/prerenewal/monsters.json` | High, pending Hercules cross-check |

## Movement

Implementation: `scripts/gameplay/world/grid_pathfinder.gd`, `grid_walker.gd`. Tests: `tests/unit/test_movement.gd`.

| Rule | Value | Confidence | Notes |
|---|---|---|---|
| Grid | GAT cells, 8 directions | Confirmed | GAT types 0 and 3 are walkable |
| Base walk speed | 150 ms per cell | High | Default speed shared by players and emulators (`DEFAULT_WALK_SPEED`) |
| Diagonal step | 1.4 × straight | High | Emulators use a 14/10 move cost |
| Corner cutting | Not allowed | High | A diagonal step needs both orthogonal neighbours walkable |
| Click-to-walk range | 64 steps | Medium | Typical client/emulator path limit; needs verification |
| Direction codes | 0 S, 1 SW, 2 W, 3 NW, 4 N, 5 NE, 6 E, 7 SE | Confirmed | Verified visually against the client's sprite directions |

## Still to research

Experience tables, job-based HP/SP, ASPD, cast time and after-cast delay, DEF/MDEF (hard and soft), the element table, size modifiers, the refine table, monster data, skills and drop rates.

Each one will be added with its source, cross-checked between the rAthena pre-re database and Hercules. Any disagreement will be listed under *Discrepancies*.

Emulator databases are GPL-licensed. Values are referenced as facts with provenance, and emulator code is never copied.
