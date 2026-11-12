# Dark Knight, Shaman and the advanced job paths

Project Twilight began with the Dark Knight and Shaman second jobs that branch from Swordman and Acolyte, adapted from **Ragnarok Online DS** class concepts. It now also covers the canonical second, transcendent and third-job paths for every first job. The numbers below are Project Twilight balance values for a Pre-Renewal-style ruleset, not RO DS data.

Status legend:
- **Implemented** — works in the simulation and has tests.
- **Partial** — works, but with a gap that is listed.
- **Placeholder** — a stand-in exists.
- **Planned** — not started.

## Progression

```text
Novice ── Swordman ──┬── Knight ── Lord Knight ── Rune Knight
                     ├── Crusader ── Paladin ── Royal Guard
                     └── Dark Knight ── Dread Knight ── Abyss Knight
Novice ── Mage ──────┬── Wizard ── High Wizard ── Warlock
                     └── Sage ── Professor ── Sorcerer
Novice ── Archer ────┬── Hunter ── Sniper ── Ranger
                     ├── Bard ── Clown ── Minstrel
                     └── Dancer ── Gypsy ── Wanderer
Novice ── Acolyte ───┬── Priest ── High Priest ── Arch Bishop
                     ├── Monk ── Champion ── Sura
                     └── Shaman (female) ── Oracle ── Spirit Sage
Novice ── Merchant ──┬── Blacksmith ── Whitesmith ── Mechanic
                     └── Alchemist ── Creator ── Genetic
Novice ── Thief ─────┬── Assassin ── Assassin Cross ── Guillotine Cross
                     └── Rogue ── Stalker ── Shadow Chaser
```

**Advancement** goes through the Job Guide NPC in Prontera.

| Rule | Details |
|---|---|
| Second job | Parent first job at Job Level 40 or higher (`min_parent_job_level`). Bard/Clown are male only; Dancer/Gypsy female only. |
| Transcendence | Parent second job at Base Level 99 / Job Level 50. Custom lines use Dread Knight and Oracle. |
| Third job | Parent transcendent class at Base Level 99 / Job Level 70. Custom lines use Abyss Knight and Spirit Sage. |
| What changes | The job resets to Job Level 1. Unspent skill points carry over (classic Pre-Renewal behaviour). Every earlier skill is kept. Weapons the new class cannot use go back to the inventory. |
| Where the rules live | `FieldSimulation.job_change_unmet()` / `command_job_change()`, and `jobs.json` (`tier`, `parent`, `min_parent_base_level`, `min_parent_job_level`, `sex`). |
| Job EXP | `job_second` is **provisional** (the first-job table × 2) until the real second-class table is cross-checked. Transcendent and third jobs use `job_third`, the documented 70-level advanced table. |
| Base Level cap | Third jobs 150; every earlier class 99. The server's `RuleConfig.max_level` can lower the ceiling. |

## First-job skill trees

All six first jobs now have dedicated skills, so a character has a class tree from the first job onward. Swordman and Mage keep their existing trees; Archer, Acolyte, Merchant and Thief gained the following skills.

| First job | Skills |
|---|---|
| Swordman | Sword Mastery, Two-Handed Sword Mastery, Increase HP Recovery, Bash, Magnum Break |
| Mage | Increase SP Recovery, Napalm Beat, Soul Strike, Cold Bolt, Fire Bolt, Lightning Bolt |
| Archer | Double Strafe, Charge Arrow, Arrow Shower |
| Acolyte | Heal, Holy Light, Ruwach, Mace Mastery |
| Merchant | Mammonite, Cart Revolution, Hammer Fall, Axe Mastery |
| Thief | Envenom, Sand Attack, Back Slash, Dagger Mastery |

Mace Mastery, Axe Mastery and Dagger Mastery use the existing weapon-specific `mastery_atk` path. The active skills use the same physical, magic, healing, area and debuff paths as the advanced trees.

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
  - New types: two-handed sword, one- and two-handed axe, mace, rod, book, bow, instrument and whip.
  - Two-handed weapons remove and block the shield.
  - New items: Katana, Claymore, Axe, Battle Axe, Club, Rod (MATK +15%), Book, Short Bow, Hunter Bow, Great Bow, Lute, Harp, Whip and Chain Whip, sold by the Prontera Weapon Dealer.
  - Bows give 9-cell normal attack range; instruments and whips give 2 cells. Archer/Hunter/Sniper/Ranger skills require a bow, Bard/Clown/Minstrel skills an instrument, and Dancer/Gypsy/Wanderer skills a whip.
  - The Prontera Weapon Dealer also sells Arrows (weight 1, 3 Zeny), Fire Arrows (5 Zeny), Silver Arrows (8 Zeny) and Quivers (weight 100, 250 Zeny). A normal bow attack or bow skill consumes one Arrow; using a Quiver unpacks 100 normal Arrows within the carry limit.
  - Fire Arrows make a bow shot fire-element and Silver Arrows make it holy-element, so they exploit earth and undead targets. Weapon enchantments take priority over the arrow element.

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

- **Tabs and layout:** one tab per job in the ancestry (Novice, first job, second job, transcendent class and third job where present), opening on the current job. Skills are grouped by `branch` in two columns:

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

## Canonical paths and custom continuations

Every canonical first job now reaches a second job, a transcendent class and a third job. The Dark Knight and Shaman lines keep their own continuations, so their ids do not collide with canonical Lord Knight / High Priest. All steps use the Job Guide NPC in Prontera.

| Family | Path | Third-job signature skills |
|---|---|---|
| Swordman | Knight → Lord Knight → Rune Knight | Rune Mastery, Hundred Spear, Dragon Breath, Rune Shield |
| Swordman | Crusader → Paladin → Royal Guard | Shield Press, Earth Drive |
| Mage | Wizard → High Wizard → Warlock | Comet, Soul Drain |
| Mage | Sage → Professor → Sorcerer | Psychic Wave, Diamond Dust |
| Archer | Hunter → Sniper → Ranger | Arrow Storm, Warg Strike |
| Archer | Bard → Clown → Minstrel | Arrow Vulcan, Severe Rainstorm |
| Archer | Dancer → Gypsy → Wanderer | Arrow Vulcan, Metallic Sound |
| Acolyte | Priest → High Priest → Arch Bishop | High Heal, Assumptio, Holy Light, Judgement |
| Acolyte | Monk → Champion → Sura | Gates of Hell, Tiger Strike |
| Merchant | Blacksmith → Whitesmith → Mechanic | Power Swing, Axe Boomerang |
| Merchant | Alchemist → Creator → Genetic | Cart Cannon, Acid Bomb |
| Thief | Assassin → Assassin Cross → Guillotine Cross | Cross Impact, Dark Claw |
| Thief | Rogue → Stalker → Shadow Chaser | Fatal Menace, Feint Bomb |
| Custom | Dark Knight → Dread Knight → Abyss Knight | Abyss Strike, Nightmare |
| Custom | Shaman → Oracle → Spirit Sage | Spirit Storm, Soul Bind |

**Gates and caps.** A second job needs the first job at Job Level 40. Transcendence needs the second job at Base Level 99 / Job Level 50. A third job needs the transcendent class at Base Level 99 / Job Level 70. Third jobs raise the Base Level cap to **150** and keep the Job Level cap at **70**; every earlier class stays at Base Level 99. `jobs.json` stores `max_base_level: 150` only on third jobs, and `FieldSimulation.base_level_cap()` takes the lower of the server's `RuleConfig.max_level` and the class cap. `SaveGame.validate()` reads the class registry's `max_base_level`, so a third-job save at level 120 loads while a transcendent save at 120 is clamped to 99.

**What changes on promotion.** The job resets to Job Level 1, unspent skill points carry over, and every skill learned in the ancestry stays learned. `available_skills()` walks the whole parent chain, so a Rune Knight keeps Swordman and Knight skills, and an Abyss Knight keeps Dark Knight skills. The skill window builds one tab per job in that chain.

**Second-job and transcendent skill trees.** Every canonical second job and transcendent class now has two dedicated active skills, and Dread Knight and Oracle have two each (56 skills total). They reuse the existing physical, magic, healing, area, multi-hit and debuff paths; no new combat subsystem was added. All six first jobs also have their own trees (15 new skills for Archer, Acolyte, Merchant and Thief; Swordman and Mage retain theirs).

| Rank | Skills |
|---|---|
| Knight | Spear Stab, Bowling Bash |
| Crusader | Shield Charge, Holy Cross |
| Wizard | Frost Nova, Meteor Storm |
| Sage | Earth Spike, Heaven's Drive |
| Hunter | Arrow Shower, Blitz Beat |
| Bard | Dissonance, Musical Strike |
| Dancer | Ugly Dance, Sling Arrow |
| Priest | Heal, Holy Light |
| Monk | Iron Fist, Asura Strike |
| Blacksmith | Mammonite, Hammer Fall |
| Alchemist | Acid Terror, Potion Pitcher |
| Assassin | Sonic Blow, Grimtooth |
| Rogue | Back Stab, Raid |
| Lord Knight | Spiral Pierce, Spear Boomerang |
| Paladin | Shield Chain, Grand Cross |
| High Wizard | Meteor Storm, Ganbantein |
| Professor | Earth Strain, Fire Wall |
| Sniper | Falcon Assault, Sharpshooting |
| Clown | Melody Strike, Pang Voice |
| Gypsy | Slinging Arrow, Dazzler |
| High Priest | Sanctuary, Magnus Exorcismus |
| Champion | Palm Strike, Asura Strike |
| Whitesmith | Cart Termination, Hammer Fall |
| Creator | Acid Demonstration, Bomb |
| Assassin Cross | Soul Destroyer, Meteor Assault |
| Stalker | Back Stab, Raid |
| Dread Knight | Death Strike, Soul Reap |
| Oracle | Fate Seal, Starfall |

**Third-job skill trees.** Every third job has its own data-driven signature skills (two to four each, listed above). Rune Mastery uses the existing `mastery_atk` path; Rune Shield and Assumptio use the status/`def_bonus` path, and `_recalc_player()` now sums DEF bonuses from every active buff.

**Art.** Third-job class registry entries have no dedicated emblem yet, so `ClassInsignia` draws the `third`-tier shield fallback (teal body, gold rim). Canonical jobs reuse their first-job body sprite, and the custom lines reuse the Knight / Priest bodies, until dedicated class art exists.

**Tests.** `tests/unit/test_third_jobs.gd` (6 cases) covers all 13 canonical paths plus both custom paths, third-job data, caps, skill trees, EXP and save validation. `tests/unit/test_rank_skills.gd` (2 cases) verifies every second-job, transcendent and custom transcendent rank exposes two matching skills and exercises physical, magic and healing skills. `tests/unit/test_first_job_skills.gd` (2 cases) covers the Archer, Acolyte, Merchant and Thief trees, learning and representative use, `tests/unit/test_weapon_types.gd` (2 cases) covers bow/instrument/whip data, permissions, range and skill gates, and `tests/unit/test_ammo.gd` (4 cases) covers arrows, quivers, carry weight, bow ammunition and elemental arrow damage. The full suite is 229 passed, 0 failed, 0 skipped.
