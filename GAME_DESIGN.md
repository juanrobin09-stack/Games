# EMBERFALL: LAST LIGHT — Game Design Document

## 1. Pillars

1. **Playability first.** Every system must work end-to-end before it gets more content.
2. **Readable combat.** Every hit — dealt or received — is telegraphed and confirmed with layered feedback (flash, particles, sound, number, knockback).
3. **Short, replayable runs.** A full run (three zones + boss) targets **10–20 minutes**. Death is never a full reset: Soul Ash always carries forward.

## 2. Core Loop

```
 ┌─────────────┐     ┌──────────┐     ┌────────┐     ┌───────────┐     ┌────────────┐
 │  Explore a  │ ──▶ │  Fight   │ ──▶ │  Loot  │ ──▶ │  Upgrade   │ ──▶ │ Push toward │
 │    room     │     │ enemies  │     │(Embers)│     │ (choose 1  │     │ the zone's  │
 └─────────────┘     └──────────┘     └────────┘     │  of 3)     │     │   heart     │
        ▲                                              └───────────┘     └──────┬──────┘
        │                                                                        │
        └────────────────────────── next room ◀────────────────────────────────┘
```

A run ends when the player either falls (**Defeat**) or destroys **The Ashen Colossus** in the Ember Citadel (**Victory**). Both outcomes grant **Soul Ash** for permanent progression, so no run is wasted.

### First five minutes (onboarding)

1. Main menu → **Play** → (loadout picker only appears once something is unlocked; first-ever run skips straight in).
2. Contextual toast: movement, then attack, on first input of each.
3. First kill drops Ember pickups automatically homed toward the player once in range.
4. Clearing the first combat-capable room offers a **choice of 3 upgrades**.
5. Exploration reveals a **shop**, **event**, **chest**, or **rest** room — each has its own one-time onboarding hint the first time it's found.
6. Reaching the zone's **heart** room (a tougher guardian fight) grants a bigger reward and unlocks the portal to the next zone.

All hints are shown at most once, ever, tracked per-hint key via `hintsShown` in the save (a legacy save with the old single `tutorialSeen` flag migrates to every hint marked seen, so returning players aren't hint-flooded); a completed first run silences onboarding for good.

## 3. Progression Layers

| Layer | Currency | Resets each run? | Where |
|---|---|---|---|
| Player Level | **XP** (from kills) | Yes | 7 stat rows in the Character screen (`I`) |
| In-run power | **Embers** | Yes | Upgrade choices, shop purchases, chest rewards |
| Meta progression | **Soul Ash** | No (persists forever) | Main Menu → Upgrades (stat nodes) / Armory (unlocks) |

The full stacking order, base to final: permanent Soul Ash stat nodes → `createBaseStats()` → Player Level's stat-point bonuses (`Player.addBonusModifier`, same ratio-preserving path world events use) → owned in-run upgrades (`Player.upgrades`, each stacked to its own level) → live `StatBlock`.

### Embers

Dropped by nearly every kill (`emberValue` on the enemy definition, ±15% variance, split into 1–5 pickups), found in event/shrine choices, and spent on:

- Shop upgrade offers (22–145 Embers depending on rarity)
- Healing at the shop (30 Embers → 35% of missing HP)
- Rerolling the shop's offers (15 Embers)
- A few event choices (see §8)

### Soul Ash

Earned at the end of every run: `floor(kills × 0.6 + eliteKills × 4 + (victory ? 70 : 0) + embersCarried × 0.08)`, plus any Soul Ash granted mid-run by the **Ember Well** event. Spent between runs on:

- **Upgrades menu** — 10 permanent stat nodes (see §7)
- **Armory menu** — 6 unlocks: 2 weapons, 2 abilities, 1 enemy, 1 upgrade-rarity gate (see §7)

### Player Level & Stat Points

A run-scoped character sheet, entirely separate from (and layered underneath) the in-run upgrade pool — resets to Level 1 every run, same as upgrades do, and caps at **Level 30** (`MAX_PLAYER_LEVEL`): XP still accumulates harmlessly past it, but the bar just reads MAX rather than banking XP it can never spend. Every enemy kill grants XP (`data/playerProgression.ts`'s `getEnemyXpValue`, built on the existing `xpWeight` field already authored per enemy — an Ash Crawler, `xpWeight` 1, gives exactly 5 XP; deeper zones' enemies are worth more at the same `xpWeight`, +25% per zone index, a placeholder curve). Reaching the level's XP threshold (`xpRequiredForLevel`: 25 to reach Level 2, ×1.35 per level after — a real ramp, not a flat repeat) grants 1 stat point and rolls over any leftover XP; a single large grant resolves every level it crosses in one synchronous loop, so nothing desyncs. Open the character sheet with **I** (or Pause → Your Build) to spend points across 6 stats — HP, Stamina, Ability Damage, Range, Move Speed, Attack Speed — each with its own independent level and a modest per-level bonus (`PLAYER_STATS` in the same file). All of it is placeholder magnitude by design, meant to be retuned from that one file without touching call sites.

M1 Damage was removed from this list entirely — base weapon damage is now a fixed, unupgradeable number (see §7). Attack Speed and Ability Damage stay in the list but start **locked**: a row shows a lock badge and its unlock condition instead of a spend button, and `Game.spendStatPoint` refuses the same way server-side (`isPlayerStatLocked`, `data/playerProgression.ts`) so the lock can't be bypassed by any path other than the UI. Attack Speed unlocks the moment the Bow is picked up; Ability Damage unlocks on reaching Zone 2 (the Hollow Ruins) — see §7 and §9.

### Upgrade Levels

In-run upgrades (§8) can now stack: `Player.addUpgrade` already tracked `stacks`/`maxStacks` per owned upgrade, but reward/shop offer generation used to exclude anything already owned outright, so no upgrade had ever actually re-offered itself. It now re-offers an owned upgrade up to its effective cap — the tighter of its own `maxStacks` (most upgrades don't set one) and the current zone's cap (`ZONE_UPGRADE_LEVEL_CAP`: Ashen Woods caps every upgrade at Level 2, Hollow Ruins at 3, Ember Citadel at 4 — extend the array for future zones). Every chest, reward-choice, and shop card shows the level the upgrade would become if picked.

## 4. Player Stats

The player's live `StatBlock` (see `data/types.ts`) is built as `base → + permanent Soul Ash modifiers → + owned in-run upgrades`, using one consistent formula everywhere:

- `flat` modifiers add their raw value.
- `mult` modifiers multiply the stat's *current* value by `(1 + value)` — this lets `*Mult` fields (base `1.0`) compound predictably, and lets reduction fields (like dodge cooldown) shrink safely toward zero via negative values.

Base stats: 130 HP (clamped 10–180 — the 180 ceiling is a hard ceiling, not a starting value: Player Level HP points and the Hearty Vigor/Phoenix Heart upgrades climb toward it, nothing starts there), 0.4 HP/s regen, 190 move speed, 5% crit chance, 1.5× crit damage, 100 stamina, 100 energy (6/s regen), 70 pickup range. All other multipliers start at `1.0`; all other flat bonuses (armor, lifesteal, burn chance, shield charges, projectile count, rarity luck) start at `0`. Stamina's own regen (45/s after a 0.55s pause — a full 0→100 refill takes ~2.2s) is a fixed constant rather than a stat — only its max is upgradeable, see §5 and §7.

## 5. Combat

- **Stamina** gates both M1 and dodge from one shared 100-point pool, regenerating at 45/s once 0.55s has passed since the last time either spent from it (a full 0→100 refill takes ~2.2s). M1 costs a uniform 10 stamina per swing regardless of weapon (10 swings deep before forcing a breather, ≈4.5s of sustained attacking); dodge costs 15. Upgradeable via `staminaMax` (in-run chest/reward upgrades and the Endless Vigor permanent node). An action blocked purely by low stamina (not by its own attack/dodge cooldown) pulses the HUD stamina bar red so the denial always reads as "no stamina," never as an unresponsive input — a held M1 keeps the pulse lit continuously, a single denied dodge flashes it briefly. One notable interaction: dodge's own ~0.95s cooldown already paces it slower than the ~0.4s of open regen window between two max-rate dodges regenerates (~18), so pure dodge-spam alone never actually drains the pool — stamina mainly bites when dodging is mixed with M1, or under repeated ability/movement pressure that outpaces the pause needed for regen to kick in.
- **Melee weapons** hit *every* enemy inside an arc out to `range × rangeMult` the instant the swing starts — an intentional design choice for crowd-clearing game feel over single-target precision. The hit-detection arc itself is checked at 75% of the weapon's full `arcDegrees` (`HIT_ARC_COVERAGE` in `CombatSystem.ts`): since the hit lands the instant the swing starts but the blade sprite only reaches its full arc by sweeping across it over the swing's duration, checking the full nominal arc would land hits on its far edge before the blade is anywhere near it. The visual blade length itself is derived directly from the weapon's actual range (`rendering/draw/drawPlayer.ts`) rather than a fixed constant, so a longer-reaching weapon (e.g. Void Scythe) always looks like it reaches further, too.
- **Ranged weapons** fire `1 + projectileCount` projectiles that pierce `pierce` targets before expiring.
- **Crits** roll at `critChance` (stat + weapon bonus) and multiply damage by `critDamage`. A crit landed on an enemy mid-windup **interrupts** its attack (except elites/boss) — a skill reward for aggressive, well-timed play.
- **Dodge** grants full invulnerability for its duration (~0.22s, scaled by `dodgeCooldownMult`) and a directional burst of speed, at a 15-stamina cost from the same pool M1 draws from (see above). A **perfect dodge** (avoiding a real hit) always triggers a distinct particle flash and chime so skilled timing is immediately readable regardless of build; the **Shadow & Dodge** synergy additionally grants +35% damage for 3s on top of that universal feedback.
- **Contact damage**: non-telegraphed touch damage from a chasing enemy, capped to once per 0.6s per enemy, so standing in a crowd chips rather than melts you — the *real* threat is always the telegraphed attack.
- **Hit-stop**: crits, Ember Burst, elite kills, and boss-phase/death beats briefly slow the whole simulation (not just the visuals) to a crawl for 45–140ms — a classic "hitlag" trick layered on top of screen shake and hit-flash so the heaviest moments read as heavier than routine hits, without ever fully freezing input.
- **Danger vignette**: a full-screen ember-red vignette fades in once HP drops below 35% and breaks into an urgent pulse below 15%, so mortal danger is readable at a glance instead of requiring a glance at the corner HP bar mid-fight.

## 6. Enemies

| Enemy | Behavior | HP | Damage | Speed | Notes |
|---|---|---|---|---|---|
| Ash Crawler | Chaser | 200 | 8 | 255 | Fast, hunts in numbers |
| Hollow | Tank | 200 | 8 | 85 | Slow, heavy telegraph |
| Flame Wisp | Ranged | 200 | 8 | 125 | Flying, kites at range, fireballs |
| Gravebound | Heavy | 58 | 20 | 105 | Big telegraphed slam |
| Shadow Stalker | Stalker | 30 | 14 | 235 | Vanishes and repositions to ambush |
| Ember Devourer | Elite | 230 | 22 | 145 | Hybrid melee/ranged, appears in elite/heart rooms |
| Cinder Wraith *(unlockable)* | Ranged/phasing | 36 | 12 | 155 | Vanish-and-reposition ranged attacker |
| Blightbloat *(Hollow Ruins)* | Bloat | 30 | 18 | 82 | Plants itself in reach, swells for 0.85s, then bursts (96 radius) and leaves a lingering **spore cloud** (84 radius, 5s DoT). Killed early it still ruptures into a smaller cloud — *where* it dies matters. A crit during the swell staggers it. |
| Hollow Warden *(Hollow Ruins)* | Warden | 88 | 19 | 92 | Door-sized stone shield turns aside 85% of damage inside its frontal ±66° arc (no knockback/stagger/burn); turns at 3.1 rad/s while hunting an angle (fast enough to actually catch up to a circling player, with a light lead on their velocity so holding a steady orbit no longer stalls it indefinitely), engages its bash from 195px; bashes along its facing (540 px/s lunge, telegraphed as a lane — the *committed* turn during windup/bash is throttled back to its original, pre-rework rate so a sidestep still beats it), then its guard drops for 1.4s — the punish window. |
| **The Sunken Warden** *(champion)* | Warden | 290 | 23 | 104 | Level 2's conclusion. Phase 1: the shield line above (turns at 2.7 rad/s, engages from 235px), wider arc. At 50% HP the shield **shatters** (hard stagger, two Blightbloats crawl out of the flanks), and phase 2 is a faster double bash that leaves a spore cloud where it lands. Gets the boss HP bar. |

Zone 1's three starting enemies (Ash Crawler, Hollow, Flame Wisp) were leveled to a uniform 200 HP / 8 damage as part of the Level-30 rebalance — a deliberate simplification of what were previously three differentiated HP/damage tiers (16–22 HP, 6–9 damage) into one shared baseline for the player's very first fights, chosen over re-differentiating three new numbers per archetype since the brief specified a single Level-1 mob baseline; their behavior, speed, and role (fast chaser / slow tank / kiting ranged) are untouched, so the *feel* of each still differs even though the numbers now don't. All values are base; see §9 for zone/time scaling. Every enemy can be spawned as an **elite instance** (empowered ×2.1 HP / ×1.35 damage, named `Empowered <Name>`) in elite rooms, or as a **zone heart guardian** (×3.2 HP / ×1.5 damage) at the end of zone 1. Zone 2's heart guardian is instead a purpose-built **champion** (The Sunken Warden) whose numbers are authored for the role — it only takes the zone/time scaling, not the ×3.2 promotion.

The two Level 2 archetypes were designed around *new situations* rather than bigger numbers: the Warden is a **positioning** problem (its front is a wall, its back is a target, its bash is a committed line you sidestep and punish — Stormstep's dash-through puts you behind it for free), and the Blightbloat is a **space-denial** problem (it makes the floor itself the enemy, and turns "kill it fast" into "kill it *there*"). Together — a Warden advancing behind its shield while a Bloat waddles up beside it — they force the flank and the retreat to happen at the same time.

## 7. Weapons, Abilities & Permanent Progression

### Weapons (4)

| Weapon | Type | Damage | Cooldown | Stamina | Notes | Unlock |
|---|---|---|---|---|---|---|
| Ember Blade | Melee | 17 | 0.45s | 10 | Balanced, wide-ish arc | Default |
| Void Scythe | Melee | 34 | 0.85s | 10 | Slow, huge arc, +8% crit | 150 Soul Ash |
| Solar Spear | Ranged | 14 | 0.55s | 10 | Pierces 2 targets | 220 Soul Ash |
| Warden's Bow | Ranged | 16 | 0.5s | 10 | Pierces 1 target, 420 range | Zone 2 elite room (in-run) |

Ember Blade's base damage is fixed at 17 with **no in-run upgrade able to raise it any more** — the old Weathered Grip / Honed Edge upgrades and the `m1Damage` Player-Level stat that used to scale it were removed outright as part of the Level-30 rebalance (still fully absent from chests, shop, room-clear rewards and the character sheet; verified by sampling the live upgrade pool hundreds of rolls deep with every gate state reachable). Reducing raw M1 output made room for a real early cadence to matter: Attack Speed itself is Level-1-locked (see §3) precisely so the *fixed* ~2.2 hits/s cadence stays the balance point for a while, rather than immediately drifting upward.

The **Warden's Bow** is the run's one in-run weapon pickup: clearing Zone 2's (the Hollow Ruins') single guaranteed elite room grants it directly and auto-equips it, stacked on top of that room's normal upgrade-choice reward exactly the way the Drowned Sanctum's bonus stacks with its own room-clear roll (§3's "Upgrade Levels", §9). It reuses the same ranged-attack path Solar Spear already exercises (`kind:'ranged'`, a pierce-1 projectile), so nothing new had to be built for it to fire correctly. Attack Speed's three upgrades — Brisk Hands (+3%), Shadow Step (+6%), Quickdraw (+9%) — are gated `requiresUnlock:'bow'` and only enter the pool once the Bow is owned (`Game.currentGateIds()` merges the player's in-run `unlockedWeapons` into the same gate-id set `requiresUnlock` already checks for permanent Soul-Ash unlocks and zone-progress — see §8).

### Abilities (3)

Right-click abilities spend a single dedicated **energy** resource rather than a partial cost: usable only once it's at a full 100%, a cast drains it entirely to 0%, and it then recharges progressively back to full over the ability's own recharge time below (scaled by `energyRegen`, e.g. the Second Wind permanent node — at the default regen rate an ability always takes exactly its listed recharge time to go from empty to full). The HUD's top-left bar and the bottom-left icon's cooldown sweep both track this same underlying value and light up together once it's actually usable, so what's on screen always matches what you can actually do.

| Ability | Recharge | Effect | Unlock |
|---|---|---|---|
| Ember Burst | 8.7s | AoE nova, knockback | Default |
| Stormstep | 7.2s | Dash-blink that damages everything in its path + brief invuln | 140 Soul Ash |
| Warding Sigil | 15.7s | Planted totem: damages nearby enemies and heals the player over 5s | 190 Soul Ash |

### Permanent upgrades (11 stat nodes, Soul Ash)

Warden's Resolve (+10 HP), Ember Edge (+5% dmg), Swift Boots (+12 move speed), Fortune's Favor (+5% rarity luck), Ember Hoard (+8% Ember gain), Second Wind (+1.2 energy regen), Iron Skin (+3% armor), Keen Eye (+3% crit chance), Vital Embers (+0.3 HP regen), Endless Vigor (+8 max stamina), Deep Pockets (+20 pickup range & +1 shield) — each has 3–5 levels with `cost = baseCost × growth^level`.

### Unlocks (6, Soul Ash) — the Armory

Void Scythe (weapon), Solar Spear (weapon), Stormstep (ability), Warding Sigil (ability), **Awaken the Deep** (adds Cinder Wraith to zones 2–3's enemy pool), **Ember Sight** (allows Legendary-rarity upgrades to appear at all).

## 8. Upgrades, Rarities & Synergies

28 in-run upgrades across 5 rarities (weights: Common 40, Uncommon 30, Rare 18, Epic 9, Legendary 3 — biased upward by `rarityLuck` via an exponential roll transform). `requiresUnlock` gates an upgrade behind any id in `Game.currentGateIds()`, which merges three independent sources into the one set — permanent Soul-Ash unlocks (`meta.getUnlockedGateIds()`, persists across runs), weapons found this run (`player.unlockedWeapons`), and synthetic zone-progress ids (`'zone1'`, `'zone2'` once `run.zoneIndex` reaches them) — so an upgrade can gate on any of them through the exact same mechanism `UpgradePool` already had, with no changes to its own logic. Legendary upgrades are gated behind the **Ember Sight** unlock so they never appear for a save that hasn't earned them; the four ability-range upgrades (Keen Aim +5%, Far Reach +10%, Wide Blast +15%, Eagle Eye +17%, one per rarity tier from Common to Epic) are ungated; the three attack-speed upgrades (Brisk Hands +3%, Shadow Step +6%, Quickdraw +9%) are gated `'bow'`; Embered Veins (ability damage) is gated `'zone1'`; Steady Breath and Iron Lungs (stamina) are gated behind an id nothing currently grants (`'staminaUpgrades'`) — kept in code per the brief rather than deleted, but permanently unreachable as a drop until that changes. Every `StatBlock` field has in-run coverage except `rarityLuck` itself (permanent-only, to keep luck-stacking from spiraling within a single run) — **Ember Wellspring** (Uncommon, +18% ability energy regen) closes the one gap that used to exist between `embered-veins` (ability *damage*) and no in-run lever at all for ability *cooldown*.

### Synergies (5)

Detected automatically from the *tags* on owned upgrades — no separate synergy currency, they just activate. The instant one does, a banner names it over a distinct chime so the moment reads as a discovery rather than a silent stat change; the pause menu's "Your Build" screen also lists every synergy currently active alongside every upgrade collected so far this run.

- **Ember & Critical** — crits have a 35% chance to detonate a small Ember explosion.
- **Ash & Fire** — burning enemies take +40% damage from all sources.
- **Shadow & Dodge** — a dodge that avoids a real hit ("perfect dodge") grants +35% damage for 3s.
- **Light & Healing** — killing a burning/warded enemy has a chance to drop a healing mote.
- **Wrath of the Warden** — damage scales up to +50% as your HP drops toward zero (needs 2 Wrath-tagged upgrades).

### World Events (7)

The Old Shrine (Embers vs. full heal), The Forgotten Merchant (buy a guaranteed upgrade at a floor rarity), The Dying Flame (sacrifice 25% HP for a guaranteed Rare+), The Whisper (50/50 double-or-halve your Embers), The Ember Well (spend Embers for immediate Soul Ash). Each event is seen at most once per run.

Two events are **bound to the Hollow Ruins** (`zoneId` on the definition) — they never appear elsewhere, and are picked first there while unused, so Level 2 tells its own stories: **The Warden's Oath** (take up the oath for an extra shield charge, pry the shield loose for 55 Embers at the cost of 15% max HP, or leave it) and **The Spore Mother** (breathe deep for +15 max HP for the run — a run-scoped stat bonus outside the upgrade system, `Player.addBonusModifier` — or cut it open for a Rare+ upgrade at 20% HP).

## 9. Zones & Difficulty Curve

| Zone | Rooms | Enemy pool | Heart guardian | Ambient |
|---|---|---|---|---|
| 1 — Ashen Woods | 8 | Ash Crawler, Hollow, Flame Wisp | Gravebound | Falling ash |
| 2 — The Hollow Ruins | 10 | + Gravebound, Shadow Stalker, **Blightbloat, Hollow Warden**, (Cinder Wraith if unlocked) | **The Sunken Warden** (champion, 2 phases) | Drifting spores, teal and violet |
| 3 — Ember Citadel | 7 | Gravebound, Shadow Stalker, Flame Wisp, Ember Devourer, Cinder Wraith | **The Ashen Colossus** | Rising embers |

### Level 2 — The Hollow Ruins

*"Stone remembers what flesh forgets."* Level 2 is the same world, further down: a buried city of the same ruined masonry as the woods above, colder, damper, darker (ambient darkness 0.5 vs 0.4), lit not by fire but by what grows on the dead — clusters of **bioluminescent fungus** cast a cold teal light, spirit **crystals** a violet one, and the only warm light down here is the Warden's own ember. The floor and walls come from the same reference photos as Level 1, but the zone's `material` block (`ZoneDefinition.material`) makes the stone *further gone*: cold blue-green moss at 2.6× density, more rubble and cracking, damp seepage down the walls, and large dried tide-line stains across the flagstones. The air is thicker — twice the spore density of the woods' ash, in two colours.

**Structure and progression.** Ten rooms: the arrival stairwell, a guaranteed elite / shop / chest, the **Drowned Sanctum** (see below, always present, always at least two rooms from the entrance), two combat rooms, an event, a rest, and the heart. Combat rooms are *composed*, not rolled: each is one of five encounter templates (shield wall, bloat field, vanguard, ambush, phalanx) weighted by the room's distance from the entrance, so the two new mechanics are met one at a time before they combine, and the deepest rooms field two Wardens at once. Difficulty therefore rises through *what you are asked to do* — flank, retreat, do both — not only through the zone multiplier.

**The Drowned Sanctum** is the zone's memorable set-piece: a ritual chamber with a carved sunken circle ringed by six dead candles and four kneeling stone wardens. It is opt-in — *Kneel at the Circle* seals the doors and raises three waves in turn (bodies; both new mechanics; a proper shield line with stalkers behind it), each wave lighting two more candles cold-teal. Wave enemies carry their own rite-only bump on top of the zone's normal scaling (+12% HP, +18% damage — biased toward damage so the rite reads as genuinely more dangerous rather than merely spongier), and once **Awaken the Deep** is unlocked the climactic third wave swaps a Blightbloat for a Cinder Wraith, so a returning player doesn't always face the exact same fight. Survive all three and every candle turns warm: a 30% heal, 35 Embers, and a choice of three **Rare-or-better** blessings (+0.3 rarity luck, `minRarity: 'rare'`). Dying mid-rite is a normal defeat; leaving isn't possible until it's done.

**The conclusion** is The Sunken Warden in the heart room (§6): a readable, telegraphed two-phase fight rather than a scaled-up regular enemy, with the boss HP bar and phase dots. The sealed stairwell down to the Ember Citadel sits *behind* it, on the far side of the room from the one door — visible over the guardian's shoulder from the moment you walk in.

**The transition — stairs.** Every zone change is a physical stairwell, never a teleport. A heart room's stairwell starts **sealed** under a rune-carved lid; once the guardian falls and the blessing is chosen, the lid grinds aside (stone chips, a toast, the ruins' cold light climbing out of the well) and the prompt *Descend to The Hollow Ruins* appears at its foot. Pressing it starts a scripted ~2.5s moment: input is suspended, the Warden walks down into the well while the screen goes to black and spores rise from it (`stairsDescend`), the zone switches at the bottom of the fade (`zoneArrive`: a reverberant boom, the zone banner, then the subtitle), and the screen comes back up on the new zone with the player stepping off the **arrival stairwell** — a matching well against a doorless wall, lit faintly warm from above by the world just left. Stairs descend because the fiction descends (woods → buried ruins → the citadel's depths), because the existing "Descend to…" wording already said so, and because a top-down camera reads a hole in the floor instantly. The music follows: the drone glides to a semitone-lower chord set with a lowered fifth, plucks thin out, and water drips somewhere in the dark (`MusicEngine.setMood`).

### Level 3 — The Ember Citadel

Combat rooms here are composed the same way the Ruins' are (§10's "not only through the zone multiplier" principle applies just as much at the top of the run, where it matters most before the Colossus): four templates — **crossfire** (Flame Wisps focus-firing at range), **vanguard** (a Gravebound anchoring a fast Shadow Stalker flank), **ambush** (Stalker/Cinder Wraith vanish-heavy pressure, once Awaken the Deep is unlocked), and **siege** (twin Gravebounds) — weighted by distance the same way, so the Citadel's difficulty comes from what a room asks of you too, not just bigger numbers on the same random roll. Each template's filler slots cycle round-robin (reshuffled once per lap) rather than being re-rolled independently, so a small filler set can't randomly stack the same enemy three or four times and quietly turn, say, a ranged crossfire room into a pile of melee stalkers. The Ember Devourer is deliberately excluded from every template's core and filler — it stays exclusive to the dedicated elite room (1 leader + 2 escorts), the scale it's actually balanced for; an earlier pass gave it its own rare composed template, but padding a full-strength elite-tier enemy up to a normal room's 5-7 count made a plain combat room tougher than the elite room itself, caught in live combat testing.

A rare **mutated variant** — "*Name*, Ember-Marked" — can replace a regular enemy in a Citadel combat or elite-escort slot (~10% per eligible enemy, elite/champion enemies excluded): noticeably tougher (+35% HP, +25% damage, a slightly larger frame) and visibly distinct (a cold violet ring and glow, the game's existing visual language for "something otherworldly," reused rather than invented) with its own floating name tag — enough that a player thinks "that one's different," without a new behavior/AI system or becoming a second elite tier.



```
hpMult      = 1 + zoneIndex × 0.32 + corruption × 0.55
damageMult  = 1 + zoneIndex × 0.22 + corruption × 0.35
extraEnemies = floor(zoneIndex × 0.6 + corruption × 1.6)
```

`corruption = min(1, runMinutes / 14)` — the **darkness pressure** meter shown in the HUD, reinforced by a slow-fading shadow-toned screen vignette so the pressure is felt ambiently, not just read off a corner bar. It never insta-kills the player; it just makes dawdling progressively more dangerous, giving a soft push toward the zone's heart rather than a hard timer.

## 10. Level Generation

A randomized-growth spanning tree starting from the entry room guarantees every room is reachable (no cycles, no unreachable rooms, no unsolvable seed). The single farthest room from the entrance becomes the zone's **heart** (zones 1–2) or **boss** room (zone 3). The remaining rooms are assigned in two passes rather than fixed counts. First, one **elite** (never adjacent to the entrance), one **shop**, and one **chest** are reserved unconditionally — these three are guaranteed in every zone regardless of how small or unlucky its layout turns out, since a zone with no shop or no chest would silently starve the player of upgrades. In the Hollow Ruins one **sanctum** (the rite arena) is reserved the same way, at least two rooms from the entrance. Whatever rooms remain are then split roughly in half between a guaranteed **combat** minimum and secondary specials (**event**, **rest**, then a bonus second **event**/**chest** for bigger zones); any leftover defaults to combat. Rooms with enemies **lock** their doors until cleared (the sanctum only once its rite has begun); every other room type is always open. Because the layout is a spanning tree grown outward from the entrance, the farthest room is always a leaf with exactly one door — which is what lets the heart room place its exit stairwell on the far side from the way in. Scattered obstacles keep clear of every door's approach lane, of each other, and of landmarks (the stairwells, the arrival foot), and enemy spawns keep clear of obstacles; a crowded room simply places one fewer obstacle rather than ever stacking one into a doorway. Every wall's stonework is sourced from a single real reference painting of ancient dungeon masonry (`assets/textures/ancient-wall.png`), not a procedural color fill: small hand-picked regions of it — a run of coursed ashlar, the corner pilaster block, a door jamb with its mounted torch — are resampled as material swatches (`rendering/StoneAsset.ts`). Each block draws a randomly-positioned, sometimes-mirrored window of that one source photo, seeded per room, so neither neighboring blocks nor different rooms ever read as an obvious repeat of the same tile despite there being only one source image. A zone's palette is then applied on top with the canvas `'color'` composite mode, which shifts only the swatch's hue/saturation toward the zone's tone (olive Ashen Woods, cold violet Hollow Ruins, ember-brown Ember Citadel) while preserving the photo's own shading and depth — so the three zones stay visually distinct without burying the real stone detail under a flat tint. Each block fills its full rect edge-to-edge rather than sitting inset within a gap — an earlier version inset every block a couple of pixels to let the strip's own flat dark base color show through as a mortar groove, which read as an actual void once the blocks around it were real, detailed photo material rather than flat gradients; the joint is now suggested purely by a thin stroke drawn on top, never by leaving anything unpainted. A second, compounding problem was the source photo itself: it's a scene lit almost entirely by its own torches, so most of the frame — including where these crop regions sample from — sits far below a legible brightness by the artist's own design, not because detail is missing there. Left alone, that scene-specific darkness baked straight into the tiled result as another kind of void; a per-region levels stretch (`rendering/ImageLevels.ts`), computed once from each region's actually-observed brightness range and reused for every block cut from it, remaps that range back up to something legible, revealing the real relative stone detail — block edges, mortar, cracks — that a flat brightness boost alone would have just turned to noise. The top-edge highlight, bottom shadow and occasional chipped corner, plus the distinct corner stone at each of the room's four corners, are still drawn as vector overlays on top of that corrected photographic fill exactly as before; if the asset hasn't finished loading yet, the same call transparently falls back to the old procedural gradient rather than drawing nothing. Since redrawing all that per frame would be far too expensive, each room's four wall strips are still baked once to an offscreen canvas the first time it's rendered and cached (a capped FIFO, cleared at the start of every run) — the per-frame cost is just blitting the cached image. Doors are carved directly into that same baked masonry as an irregular gap flanked by chunkier worked jamb stones — the reference photo's own pillar-and-torch swatch, mirrored for the far jamb so the threshold reads as one deliberately-built, symmetric doorway — with a few loose fragments at the threshold, rather than a separate clean insert; a soft contact shadow along each wall's inner edge sells the floor genuinely meeting that stone rather than butting into a flat seam. The floor is built the same way from its own reference photo (`assets/textures/dungeon-room-ref.png`, a full top-down dungeon room render): each room's floor is tiled, once and cached alongside its walls, from individually-shaped flagstones rather than plain rects — each slab's silhouette is a rounded rectangle with jittered corner radii and a slight bow along each edge (`rendering/RoomTexture.ts`'s `slabPath`), so it reads as hand-cut rather than a stamped shape. The whole canvas is first filled with a pale, warm grout color; each slab then clips to its own silhouette and fills only that shape with a levels-corrected photo crop, a zone tint, and a soft per-slab "dome" (lighter center, darker rounded edge) — so the grout shows through every gap as a deliberate, always-opaque joint, never a void, and rows still alternate a half-cell offset so no seam lines up into a grid. Two source bands, sampled well clear of the reference photo's own torch-lit hotspot so its lighting doesn't get baked in and fight the game's real dynamic light, are picked per-slab alongside independent horizontal/vertical mirroring and a crop kept deliberately small relative to the slab — enough combined variety that neighboring slabs, and different rooms, don't read as the same picture tiled. Sparse moss and loose rubble are scattered across the baked floor the same way the walls scatter cracks and moss. One subtlety cost a visible bug during development: the levels stretch needs `putImageData`, which — unlike `drawImage` — writes raw pixels straight into the canvas ignoring whatever clip path is active, so doing it directly against an organic (non-rectangular) slab clip painted a rectangular halo right through the silhouette; the fix draws and corrects each crop on a small unclipped scratch canvas first and only composites the finished result into the real destination via `drawImage`, which does respect the clip (`rendering/FloorAsset.ts`, `rendering/ImageLevels.ts`). The shop's own reference sheet was split out to its own file (`assets/textures/shop-props.png`, `rendering/ShopAsset.ts`) once the floor stopped sharing an image with it. Only the door's dynamic state — a color-coded glow that brightens as the player approaches, and barred geometry when locked — is still drawn fresh every frame on top (`rendering/draw/drawRoom.ts`). This is purely a rendering concern layered on the existing door/wall data — collision and the door-gap geometry itself (`Room.getWalls`) are untouched. Chest, rest, shop, and event rooms each spawn a dedicated landmark obstacle — a chest, a lit brazier, a merchant's stall, or a mysterious shrine, respectively (`world/LevelGenerator.ts`'s `populateRoomContent`) — offset off the room's exact center (`landmarkPosition`) so it doesn't sit on the straight line between two opposite doors and block the room's most direct traversal; the room-center interaction (`Browse Wares`, `Rest at the Brazier`, `Investigate`) tracks that landmark's actual position, so it always corresponds to the real, lit object the player can see and walk up to. The merchant's stall is itself a crop of that same reference sheet rather than a procedural drawing — chroma-keyed once, from the sheet's own flat background to real transparency, and cached, so every later draw is a plain, cheap image blit (`rendering/ShopAsset.ts`) — with its registered light sized to actually bathe its larger, more detailed footprint rather than just the small candle painted at its center (`core/Game.ts`'s `registerLights`).

## 11. Boss: The Ashen Colossus

Three phases, gated by HP thresholds (66% / 30%), with a brief invulnerable "phase transition" beat between them (roar + camera shake + screen banner):

- **Phase 1** — melee slam (telegraphed ground-crack) when close, projectile volleys at range. Slow, deliberate.
- **Phase 2** — unlocked at 66% HP: adds a growing-ring **shockwave** attack and summons 2 Ash Crawlers; faster movement.
- **Phase 3** — unlocked at 30% HP: adds a **double-slam combo**, summons Shadow Stalkers instead, and starts a continuous **meteor rain** — telegraphed ground reticles that detonate after 1.5s, forcing constant repositioning on top of the boss's own attack pattern.

Every attack is telegraphed for at least `telegraphTime` (0.7s base) before it lands, and the boss commits to (cannot cancel) an attack once the telegraph starts — the fight is meant to be **hard but fair and fully readable**.

### Zone conclusions

Zones 1 and 2 end in a **heart room** rather than a boss: a guardian fight, then the stairwell down. Zone 1's is a promoted regular enemy (Gravebound, ×3.2 HP). Zone 2's is a champion with its own two-phase design (The Sunken Warden, §6 and §9) — the same telegraph-and-commit rules as the Colossus, the boss HP bar, a banner on the phase change — chosen over a second full boss so the run keeps one true climax while Level 2 still has a real ending.

## 12. Economy & Balancing Philosophy

- All scaling uses formulas (see §9, §4, §7's cost growth), not hand-placed magic numbers per encounter, so the curve can be retuned globally by changing a handful of constants.
- Shop and chest pricing follow the same rarity-weight table used for random upgrade rolls, so "buying power" and "luck" always mean the same thing everywhere in the game.
- Rarity luck (`rarityLuck` stat) affects *chests, shop offers, and room-clear rewards* identically via one shared `rollRarity()` function — never duplicated, never inconsistent between systems.
- Elite and heart-guardian encounters bias the post-fight upgrade roll upward (+0.15 luck) so a harder optional fight is never a *worse* deal than skipping it.
- **The Level-30 rebalancing pass** narrowed Zone 1 to one deliberately simple baseline (130 starting / 180 ceiling HP, 200 HP / 8 damage mobs, 17 fixed M1 damage) specifically so early runs read as *legible* rather than swingy, then reintroduces power gradually and gates two stats — Attack Speed, Ability Damage — behind concrete gameplay moments (finding the Bow; reaching Zone 2) instead of making them available from the first stat point. The Player Level cap of 30 exists so the stat-point curve has a defined endpoint to design future zones' XP/enemy scaling against, rather than growing unbounded. One brief item was intentionally left unimplemented rather than guessed at: a literal ability base-range value of "10" didn't map onto the existing `areaDamageMult` 1.0-based multiplier system without either being a no-op (10 read as a flat addend) or breaking Ember Burst's radius outright (10 read as the new multiplier, an 800%+ radius increase) — the actionable, mechanically unambiguous part of that same request (the 5/10/15/17% range-upgrade tiers) is implemented in full; the base-value question is left for the next balancing pass to resolve with an explicit answer on which field "10" is meant to describe.

## 13. Replayability

Every run varies via: seeded-but-different room graphs, randomized room-type placement, randomized enemy composition per room, a shuffled upgrade pool (with luck bias), randomized shop offers, one of five events per encounter, and — once far enough into meta-progression — a different weapon/ability loadout choice at the start of the run. The seed is displayed at the end of every run for reproducibility (bug reports, sharing an unusually good/bad layout).

## 14. Localization

The game ships fully in French (the default language) with English also selectable from Settings — a change there persists to the save and reloads the page so every already-built screen picks up the new locale (text is baked into DOM nodes at construction time throughout the UI layer, not reactive, so a fresh load is the simplest way to guarantee nothing is left stale).

`src/i18n/index.ts` exposes two lookup functions, both falling back to the English text passed at the call site if a key is missing (so a partially-translated future language degrades gracefully instead of showing blanks):
- `t(key, fallbackEn)` — flat semantic keys for UI chrome (menus, HUD labels, buttons, toasts, onboarding hints, settings).
- `tc(id, field, fallbackEn)` — data-driven content (enemies, weapons, abilities, upgrades, permanent upgrades, zones, unlocks, synergies, world events and their options), looked up by the object's own existing stable `id` plus a field name (`'name'`, `'description'`, `'title'`, `'subtitle'`, `'label'`, `'detail'`) — no changes needed to any `src/data/*.ts` file's structure, the English strings already there simply double as the fallback.

`src/i18n/fr.ts` holds the French dictionary (`FR_UI` and `FR_CONTENT`). Adding a further language later means adding one more sibling file with the same two shapes and a branch in `t`/`tc` — the data files and every call site stay untouched.

"Ember" is kept untranslated everywhere — it's the game's central lore proper noun (Ember Blade, Ember Burst, Ember Sight, Ember Citadel, the Embers currency...), not an ordinary word, the same way an invented in-fiction term usually survives a localization intact rather than being translated per-occurrence. "Soul Ash" becomes "Cendre d'Âme" throughout. "Run" and "Build" (as in a character's collected upgrades) are kept as the common French roguelite-community loanwords they already are ("cette run", "ton build") rather than forced into an awkward literal translation.
