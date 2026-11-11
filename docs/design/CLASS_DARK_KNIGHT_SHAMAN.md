# Dark Knight and Shaman

Project Twilight second jobs that branch from Swordman and Acolyte. They are adapted from **Ragnarok Online DS** class concepts. The numbers below are Project Twilight balance values for a Pre-Renewal-style ruleset, not RO DS data.

Status legend:
- **Implemented** — works in the simulation and has tests.
- **Partial** — works, but with a gap that is listed.
- **Placeholder** — a stand-in exists.
- **Planned** — not started.

## Progression

```text
Novice ── Swordman ──┬── Knight      (planned; not in this build)
                     ├── Crusader    (planned)
                     └── Dark Knight (implemented)
Novice ── Acolyte  ──┬── Priest      (planned)
                     ├── Monk        (planned)
                     └── Shaman      (implemented, female only)
```

**Advancement** goes through the Job Guide NPC in Prontera.

| Rule | Details |
|---|---|
| Requirement | The parent first job at Job Level 40 or higher (`min_parent_job_level`). Shaman is female only, because the supplied sprite is female only. |
| What changes | The job resets to Job Level 1. Unspent skill points carry over (classic Pre-Renewal behaviour). First-job and Novice skills are kept. Weapons the new class cannot use go back to the inventory. |
| Where the rules live | `FieldSimulation.job_change_unmet()` / `command_job_change()`, and `jobs.json` (`tier: 2`, `parent`, `sex`). |
| Job EXP | `job_second` is **provisional** (the first-job table × 2) until the real second-class table is cross-checked. |

## Shared systems added

**Status effects** (`StatusRules`, `SimUnit.statuses`). All of these run on timers.

| Status | Effect |
|---|---|
| Stun, Sleep, Stone | Cannot move, attack, cast or use skills. FLEE drops to 0. |
| Sleep | Ends when the target takes damage. |
| Stone | The target's defence element becomes Earth 1. |
| Silence | No skills. |
| Blind | HIT and FLEE × 0.75. |
| Confusion | Players walk to a random nearby cell; monsters stagger about instead of chasing. |

- **Resistance:** each status is resisted by a stat. Chance and duration are both reduced by the resist stat as a percentage:

  | Stat | Resists |
  |---|---|
  | VIT | Stun, Silence |
  | INT | Sleep |
  | MDEF | Stone |
  | (INT+VIT)/2 | Blind |
  | (STR+INT)/2 | Confusion |

  Confidence: Medium.
- **Buffs** are statuses too: Dark Breath, Shadow Quicken, Dark Weapon, Mistletoe, Auto Counter, Protection, Wrath, Rain Dance and Southeast Wind.
- **Death** clears all of them.
- **Not saved:** buffs and statuses end on logout, as in the classic game.
- **Data-driven skill executors** read their settings from `skills.json`:
  - `target`: `enemy` / `self` / `self_area` / `ally` / `dead_ally`;
  - `physical`, `magic`, `weapon` (required types), `hits`, `splash`, `area`, `pierce`, `element`, `lifesteal_pct`;
  - `inflict` (status + chance), `status` + `duration`, `effect` (`heal` / `sp` / `buff` / `resurrect`), and `fx` (visual).
- **Weapons:**
  - New types: two-handed sword, one- and two-handed axe, mace, rod and book.
  - Two-handed weapons remove and block the shield.
  - New items: Katana, Claymore, Axe, Battle Axe, Club, Rod (MATK +15%) and Book, sold by the Prontera Weapon Dealer.

## Dark Knight

**Identity:** aggressive dark-energy melee with a sword or an axe.

**Weapons:** fist, dagger, one- and two-handed swords, one- and two-handed axes.

**Base factors:** HP like the Knight (A 1.5), SP factor 3, weight +800.

**BTBA:**

| Weapon | BTBA |
|---|---|
| Dagger | 0.6 |
| One-handed sword | 0.7 |
| Two-handed sword | 0.6 |
| Axe | 0.75 |
| Two-handed axe | 0.85 |

These are design values.

| Skill | Max | Prerequisites | Behaviour (Project Twilight values) | Status |
|---|---:|---|---|---|
| Sword Mastery (`SM_SWORD`, inherited) | 10 | none | +4 ATK per level with daggers and one-handed swords; mastery ATK ignores DEF. | Implemented |
| Two-Handed Sword Mastery (`SM_TWOHAND`) | 10 | Sword Mastery 1 | +4 ATK per level with two-handed swords only. A Swordman skill, as in Pre-Renewal. | Implemented |
| Axe Mastery (`DK_AXEMASTERY`) | 10 | Sword Mastery 3, Two-Handed Sword Mastery 3 | +3 ATK per level with one- and two-handed axes only. Dark Knight only. | Implemented |
| Critical Rate Up | 10 | Sword Mastery 5, Two-Handed Sword Mastery 5 | +1% crit per level on normal attacks. The target's LUK shield still applies. | Implemented |
| Auto Counter | 5 | Two-Handed Sword Mastery 5 | 0.4 s per level. The first melee normal attack from an attacker with range 2 or less is blocked and answered with a guaranteed crit. Ranged attacks and skills are not countered. | Implemented |
| Dark Breath | 10 | Bloody Crash 3 | Physical damage +(5 + 3 × level)% for 60 s. Drains 1 HP + 0.6% Max HP every 2 s. Ends by itself before HP would reach 10%, so it never kills. | Implemented |
| Shadow Quicken | 10 | Dark Breath 3, Critical Rate Up 3 | Attack delay −3% per level for 60 s, capped at ASPD 190 (200 ms). Same drain and safety floor as Dark Breath. | Implemented |
| Dark Weapon | 5 | none | Weapon element becomes Shadow for 60 s per level. Ends on weapon change or death; recasting refreshes it. Needs a weapon. | Implemented |
| Bloody Crash | 10 | none | ATK (150 + 30 × level)%. Heals 2% per level of the damage actually applied (not on a miss). | Implemented |
| Guillotine | 10 | Bloody Crash 3 | Axe only. ATK (200 + 40 × level)%, with a 3% per level chance to Stun. | Implemented |
| Genocide | 10 | Bloody Crash 5 | Shadow-element hit on everything in the 5×5 area around the caster: ATK (100 + 30 × level)%, 4% per level chance to Blind. | Implemented |
| Chaos | 10 | Genocide 5 | Weapon-element hit on the 5×5 area (7×7 from level 6): ATK (120 + 30 × level)%, 4% per level chance to Confuse. | Implemented |
| Blind Wave | 10 | Sword Mastery 5, Two-Handed Sword Mastery 5, Bloody Crash 3 | Sword only. A Shadow blade with range 7 that pierces every monster on the line: ATK (150 + 30 × level)%. | Implemented (visual uses orbs) |
| Death Blade | 10 | Sword Mastery 5, Two-Handed Sword Mastery 5, Blind Wave 5 | Sword only. 2 + level/3 hits (5 at level 10), each ATK (80 + 12 × level)% and each rolled separately for hit. | Implemented |
| Hell Impact | 10 | Axe Mastery 5, Dark Weapon 5, Guillotine 5 | Axe only. A 1 s wind-up (moving or being hit interrupts), then a 5×5 ground smash at the target: ATK (300 + 50 × level)% in the weapon element. | Implemented |

**Branches are independent** (owner decision, 2026-11-11; this replaces the brief's single chain):

| Branch | Path |
|---|---|
| Sword | Sword Mastery 5 + Two-Handed Sword Mastery 5 → Critical Rate Up and Blind Wave (also Bloody Crash 3) → Death Blade; Shadow Quicken needs Critical Rate Up 3 + Dark Breath 3 |
| Axe | Sword Mastery 3 + Two-Handed Sword Mastery 3 → Axe Mastery → Guillotine (Bloody Crash 3) → Hell Impact (also Dark Weapon 5) |
| Dark (shared) | Bloody Crash → Dark Breath; Bloody Crash 5 → Genocide → Chaos. Dark Weapon and Bloody Crash are open to both builds. |

Each specialist reaches its top skill without touching the other weapon family; `test_branches_are_independent` checks this. Sword Mastery 3 and Two-Handed Sword Mastery 3 stay the entry for Axe Mastery, since they are inherited Swordman basics.

**Build directions:**
- **Sword specialist:** Critical Rate Up, Shadow Quicken, Death Blade and Blind Wave.
- **Axe specialist:** Axe Mastery, Guillotine (stun) and Hell Impact.
- **Hybrid:** both mastery lines and Dark Weapon, with weaker specialisation.

## Shaman

**Identity:** spiritual support plus an elemental spirit caster.

**Weapons:** fist, mace, rod and book.

**Base factors:** HP A 0.75, SP factor 8, weight +600 (Priest-like).

| Skill | Max | Prerequisites | Behaviour | Status |
|---|---:|---|---|---|
| Auto Heal | 10 | none | Natural SP regeneration +10% per level, plus 1 SP per level on each tick. | Implemented |
| Spiritual Comfort | 10 | none | Heals self or an ally within 9 cells: ⌊(BaseLv + INT)/8⌋ × (4 + 8 × level), the classic Heal formula. | Implemented (Undead damage not applied) |
| Spiritual Blessing | 10 | Comfort 3 | Restores 8 × level + INT/2 SP to another player (cannot target self). | Implemented |
| Spiritual Protection | 10 | Blessing 3 | Hard DEF and MDEF +2 per level for 120 s, on self or an ally. | Implemented |
| Spiritual Prayer | 5 | Auto Heal 5, Blessing 5 | 2 s cast. Revives a fallen player in place at 10 / 30 / 50 / 70 / 90% HP. Living targets are rejected. Range 9, SP 60, 3 s delay. | Partial (offline auto-revive after 3 s limits the window) |
| Spiritual Wrath | 10 | Protection 5 | MATK +3% per level for 120 s, on self or an ally. | Implemented |
| Mistletoe | 10 | Wrath 3 | Ghost ("Spirit") weapon element for (30 + 30 × level) s on any non-fist weapon. | Implemented |
| Rain Dance | 10 | Auto Heal 5 | The caster's own Water magic +2% per level for 180 s. | Implemented |
| Southeast Wind | 10 | Rain Dance 3 | The caster's own Wind magic +2% per level for 180 s. | Implemented |
| Summon | 10 | none | Ghost wisp: MATK (100 + 10 × level)%, cast 0.5 + 0.1 × level s. | Implemented |
| Spirit of Fire | 10 | Summon 5 | Fire bolt: MATK (120 + 20 × level)%, 3% per level chance to Confuse. | Implemented |
| Spirit of Earth | 10 | Summon 5 | Earth eruption: MATK (110 + 20 × level)%, 2% per level chance to Petrify. | Implemented |
| Spirit of Water | 10 | Summon 3, Rain Dance 3 | Water hit on a 3×3 area, 1 + level/3 waves of (60 + 8 × level)% each, 3% per level chance to Silence. | Implemented |
| Spirit of Wind | 10 | Summon 3, Southeast Wind 3 | Wind bolt: MATK (110 + 20 × level)%, 3% per level chance to Sleep. | Implemented |
| Divine Judgment | 10 | all four spirits 5 | 3 s cast. 3 + level/2 Ghost strikes on a 5×5 area, each (80 + 10 × level)% MATK on everything inside. | Implemented |

"Spirit" maps to the Pre-Renewal **Ghost** element, so the existing element table applies unchanged.

**Build directions:**
- **Support:** Comfort, Blessing, Protection and Prayer.
- **Elemental:** Rain Dance, Southeast Wind, the spirits and Divine Judgment.
- **Hybrid:** Wrath and Mistletoe for the party, plus a couple of spirits.

## Skill tree UI

- **Tabs and layout:** one tab per job in the chain (Novice, first job, second job), opening on the current job. Skills are grouped by `branch` in two columns:

  | Class | Branches |
  |---|---|
  | Dark Knight | Sword / Axe / Shared / Dark |
  | Shaman | Support / Spirit buffs / Elemental / Spirits / Ultimate |

- **Each node** shows the icon (the client's, when one exists), name, type, level and max level, level pips, and LOCKED when prerequisites are unmet.
- **The tooltip** adds the description, SP, cast time, delay, duration, range, required weapons and prerequisites.
- **Invalid allocations are blocked twice:** the UI disables the + button, and the simulation (`command_learn_skill`) rejects them anyway (max level, points, prerequisites, other classes' skills). Unlearned skills cannot be used.
- **Missing:** custom icons for the new skills. They show the generic icon until art exists.

## Visuals

**Dark Knight sprite:** comes from the resource pack (`Resources/Dark knight Sprite`; GungHo art edited by FXFreitas, packaged as a replacement for the GM sprite 운영자).
- It is mounted at runtime as an overlay and never committed. Male and female bodies are included, plus a one-handed sword weapon layer.
- **Without the pack**, the Knight body is shown as a placeholder.
- **Axes have no weapon layer** (none was supplied).

**Shaman sprite:** sliced at runtime from `Resources/Shaman.jpg` using `data/sprites/shaman_sheet.json`.
- The JSON holds frame rects and the action map: idle, walk, sit, cast, attack, hurt and dead, across 8 directions with mirroring.
- The background is removed by a border flood-fill key. The head layer attaches at the neck.
- **Without the pack**, the Priest body is shown as a placeholder.
- **Known limits:** JPEG fringe on the edges; the sheet has no dedicated heal or summon poses, so casting reuses the cast frames.

**Skill visuals:**
- **Ground circles:** casting circles per element; Hell Impact and spells use these.
- **Release effects:** bolts, orbs, bursts, Hell Impact's double ring plus a falling strike, and Divine Judgment's strikes over the area.
- **Statuses:** a floating status label, and a sprite tint for Stone, Stun/Sleep, Blind and Dark buffs.

**Badges:** new original badges for Dark Knight (crossed sword and axe, horned crest, crimson-violet tile) and Shaman (staff in a ring with four elemental gems, teal tile).

**Still needed:** dedicated per-skill animations (the brief's animation list). Skills currently reuse the attack and cast animations.

## Multiplayer

- **Authority:** every validation runs inside `FieldSimulation` commands: skill ownership and level, SP, delays, weapon requirements, target validity, range, damage, healing, statuses, drains and resurrection. That is the code a co-op host or dedicated server runs.
- **Tests:** ally skills (heal, SP, buffs, Mistletoe, resurrection) are tested with two players in one simulation.
- **Not built yet:** the network transport (co-op host / dedicated server sessions, reconnects). "Multiplayer support" is therefore **authority logic ready, transport not implemented**. Clients will send only commands; they never submit results.

## Tests

The tests are `tests/unit/test_dark_knight.gd` (14 cases) and `tests/unit/test_shaman.gd` (13 cases). Together they cover:
- advancement and the sex rule, weapon permissions, masteries per weapon type, prerequisites and points;
- crit rate, Auto Counter (melee only, expiry), drains with the floor and the ASPD cap;
- Dark Weapon (weapon change, death);
- Bloody Crash life steal, Guillotine (axe, stun), Genocide and Chaos (area, statuses), Blind Wave pierce, Death Blade's 5 hits, Hell Impact (axe, wind-up, area);
- Auto Heal, Comfort / Blessing (no self, range), Protection / Wrath expiry, Prayer, Mistletoe, Rain Dance / Southeast Wind isolation;
- every spirit's damage and status, Divine Judgment's area, silence;
- save round trips.

## Decisions needing approval

1. **Spiritual Blessing** cannot target the caster. That makes it pure party support; solo Shamans rely on Auto Heal instead.
2. **The second-job EXP table** is provisional.
3. **Spiritual Prayer** competes with the offline 3 s auto-revive. A "return to save point" button would make resurrection more meaningful.
