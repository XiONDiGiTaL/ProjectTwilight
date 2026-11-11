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

## Items and inventory

Implementation: `scripts/gameplay/items/inventory.gd`, `field_simulation.gd`, `data/prerenewal/items.json`. Tests: `tests/unit/test_items.gd`.

| Rule | Value | Confidence |
|---|---|---|
| Weight limit | 2000 + STR × 30 (+ job bonus; Novice 0) | High |
| Inventory entries | 100 | Medium |
| Stacking | Etc and usable items stack; equipment takes one entry per piece | High |
| Loot priority | Top damage dealer gets an exclusive 3 s window | Medium |
| Ground item lifetime | 60 s | Medium |
| Drop placement | Death cell, then its neighbours | Medium |
| Drop rates | Per 10,000; Poring/Fabre/Lunatic tables from Pre-Renewal sources | Medium (cards omitted) |
| Red Potion / Apple / Carrot | Heal 45–65 / 16–18 / 18–24 HP | High |
| Overweight penalties (50% no regen, 90% no attack) | Not yet implemented | — |

## Equipment and trading

| Rule | Value | Confidence |
|---|---|---|
| Player ATK | StatusATK + WeaponATK × size modifier | High (model) |
| Weapon ATK range | [min(WATK, floor(DEX × (0.8 + 0.2 × weapon level))), WATK] | Medium |
| Size modifiers | e.g. dagger 100/75/50 against small/medium/large; fists 100 for all sizes | High |
| Critical with a weapon | StatusATK + max WATK × size modifier, ignoring DEF | Medium-high |
| Armor | Equipment DEF is summed into hard DEF (percentage reduction) | High |
| Novice BTBA | Fist 0.5 s, dagger 0.65 s | Medium |
| NPC prices | Buy at the item price; sell at floor(price / 2) | High (without Discount/Overcharge) |
| Interaction range | Talk within 2 cells; trades rejected beyond 6 cells | Medium |

## Character creation

Implementation: `scripts/gameplay/character/character_rules.gd`. Tests: `tests/unit/test_character.gd`.

| Rule | Value | Confidence |
|---|---|---|
| Stat hexagon | STR/INT, AGI/LUK and VIT/DEX pairs; each stat 1–9; each pair sums to 10 | High |
| Starting points | Every legal hexagon spends exactly 48 (each pair costs 16 at 2 points per raise), leaving 0 | High |
| Names | 4–23 characters (local rule; server rules may differ) | Medium |
| Starting gear | Knife and Cotton Shirt equipped, plus 3 Red Potions | Medium |
| Start location | prt_fild08 (170, 200) for now; classic start points come with more maps | — |

## Skills and regeneration

Implementation: `field_simulation.gd`, `scripts/gameplay/skills/regen_rules_prerenewal.gd`, `data/prerenewal/skills.json`. Tests: `tests/unit/test_skills.gd`.

| Rule | Value | Confidence |
|---|---|---|
| Novice skill points | 1 per job level above 1 (9 at job level 10) | High |
| Basic Skill | Levels 1–9; level 3 allows sitting; level 9 is required for a job change | High |
| First Aid | +5 HP for 3 SP; quest skill | High (the 1 s delay is Medium) |
| Play Dead | 5 SP toggle; monsters lose and cannot acquire you; no moving or attacking; getting up is free | High |
| HP regen | max(1, floor(MaxHP / 200)) + floor(VIT / 5) every 6 s, or 3 s while sitting | Medium-high |
| SP regen | 1 + floor(MaxSP / 100) + floor(INT / 6) every 8 s, or 4 s while sitting | Medium-high |
| Weight | No natural regeneration at 50% weight or more | High |
| Quest skills | Granted at creation until the quests are implemented | Simplification |

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
