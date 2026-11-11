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

## Still to research

Experience tables, job-based HP/SP, ASPD, cast time and after-cast delay, DEF/MDEF (hard and soft), the element table, size modifiers, the refine table, monster data, skills and drop rates.

Each one will be added with its source, cross-checked between the rAthena pre-re database and Hercules. Any disagreement will be listed under *Discrepancies*.

Emulator databases are GPL-licensed. Values are referenced as facts with provenance, and emulator code is never copied.
