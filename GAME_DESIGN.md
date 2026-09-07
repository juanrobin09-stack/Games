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
| In-run power | **Embers** | Yes | Upgrade choices, shop purchases, chest rewards |
| Meta progression | **Soul Ash** | No (persists forever) | Main Menu → Upgrades (stat nodes) / Armory (unlocks) |

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

## 4. Player Stats

The player's live `StatBlock` (see `data/types.ts`) is built as `base → + permanent Soul Ash modifiers → + owned in-run upgrades`, using one consistent formula everywhere:

- `flat` modifiers add their raw value.
- `mult` modifiers multiply the stat's *current* value by `(1 + value)` — this lets `*Mult` fields (base `1.0`) compound predictably, and lets reduction fields (like dodge cooldown) shrink safely toward zero via negative values.

Base stats: 100 HP, 0.4 HP/s regen, 190 move speed, 5% crit chance, 1.5× crit damage, 100 energy (6/s regen), 70 pickup range. All other multipliers start at `1.0`; all other flat bonuses (armor, lifesteal, burn chance, shield charges, projectile count, rarity luck) start at `0`.

## 5. Combat

- **Melee weapons** hit *every* enemy inside an arc (`arcDegrees`) out to `range × rangeMult` the instant the swing starts — an intentional design choice for crowd-clearing game feel over single-target precision.
- **Ranged weapons** fire `1 + projectileCount` projectiles that pierce `pierce` targets before expiring.
- **Crits** roll at `critChance` (stat + weapon bonus) and multiply damage by `critDamage`. A crit landed on an enemy mid-windup **interrupts** its attack (except elites/boss) — a skill reward for aggressive, well-timed play.
- **Dodge** grants full invulnerability for its duration (~0.22s, scaled by `dodgeCooldownMult`) and a directional burst of speed. A **perfect dodge** (avoiding a real hit) always triggers a distinct particle flash and chime so skilled timing is immediately readable regardless of build; the **Shadow & Dodge** synergy additionally grants +35% damage for 3s on top of that universal feedback.
- **Contact damage**: non-telegraphed touch damage from a chasing enemy, capped to once per 0.6s per enemy, so standing in a crowd chips rather than melts you — the *real* threat is always the telegraphed attack.
- **Hit-stop**: crits, Ember Burst, elite kills, and boss-phase/death beats briefly slow the whole simulation (not just the visuals) to a crawl for 45–140ms — a classic "hitlag" trick layered on top of screen shake and hit-flash so the heaviest moments read as heavier than routine hits, without ever fully freezing input.
- **Danger vignette**: a full-screen ember-red vignette fades in once HP drops below 35% and breaks into an urgent pulse below 15%, so mortal danger is readable at a glance instead of requiring a glance at the corner HP bar mid-fight.

## 6. Enemies

| Enemy | Behavior | HP | Damage | Speed | Notes |
|---|---|---|---|---|---|
| Ash Crawler | Chaser | 16 | 6 | 255 | Fast, fragile, hunts in numbers |
| Hollow | Tank | 68 | 13 | 85 | Slow, high HP, heavy telegraph |
| Flame Wisp | Ranged | 22 | 9 | 125 | Flying, kites at range, fireballs |
| Gravebound | Heavy | 58 | 20 | 105 | Big telegraphed slam |
| Shadow Stalker | Stalker | 30 | 14 | 235 | Vanishes and repositions to ambush |
| Ember Devourer | Elite | 230 | 22 | 145 | Hybrid melee/ranged, appears in elite/heart rooms |
| Cinder Wraith *(unlockable)* | Ranged/phasing | 36 | 12 | 155 | Vanish-and-reposition ranged attacker |

All values are base; see §9 for zone/time scaling. Every enemy can be spawned as an **elite instance** (empowered ×2.1 HP / ×1.35 damage, named `Empowered <Name>`) in elite rooms, or as a **zone heart guardian** (×3.2 HP / ×1.5 damage) at the end of zones 1 and 2.

## 7. Weapons, Abilities & Permanent Progression

### Weapons (3)

| Weapon | Type | Damage | Cooldown | Notes | Unlock |
|---|---|---|---|---|---|
| Ember Blade | Melee | 16 | 0.45s | Balanced, wide-ish arc | Default |
| Void Scythe | Melee | 34 | 0.85s | Slow, huge arc, +8% crit | 150 Soul Ash |
| Solar Spear | Ranged | 14 | 0.55s | Pierces 2 targets | 220 Soul Ash |

### Abilities (3)

| Ability | Cooldown | Cost | Effect | Unlock |
|---|---|---|---|---|
| Ember Burst | 8s | 45 energy | AoE nova, knockback | Default |
| Stormstep | 6.5s | 35 energy | Dash-blink that damages everything in its path + brief invuln | 140 Soul Ash |
| Warding Sigil | 15s | 60 energy | Planted totem: damages nearby enemies and heals the player over 5s | 190 Soul Ash |

### Permanent upgrades (10 stat nodes, Soul Ash)

Warden's Resolve (+10 HP), Ember Edge (+5% dmg), Swift Boots (+12 move speed), Fortune's Favor (+5% rarity luck), Ember Hoard (+8% Ember gain), Second Wind (+1.2 energy regen), Iron Skin (+3% armor), Keen Eye (+3% crit chance), Vital Embers (+0.3 HP regen), Deep Pockets (+20 pickup range & +1 shield) — each has 3–5 levels with `cost = baseCost × growth^level`.

### Unlocks (6, Soul Ash) — the Armory

Void Scythe (weapon), Solar Spear (weapon), Stormstep (ability), Warding Sigil (ability), **Awaken the Deep** (adds Cinder Wraith to zones 2–3's enemy pool), **Ember Sight** (allows Legendary-rarity upgrades to appear at all).

## 8. Upgrades, Rarities & Synergies

22 in-run upgrades across 5 rarities (weights: Common 40, Uncommon 30, Rare 18, Epic 9, Legendary 3 — biased upward by `rarityLuck` via an exponential roll transform). Legendary upgrades are gated behind the **Ember Sight** unlock so they never appear for a save that hasn't earned them.

### Synergies (5)

Detected automatically from the *tags* on owned upgrades — no separate synergy currency, they just activate. The instant one does, a banner names it over a distinct chime so the moment reads as a discovery rather than a silent stat change; the pause menu's "Your Build" screen also lists every synergy currently active alongside every upgrade collected so far this run.

- **Ember & Critical** — crits have a 35% chance to detonate a small Ember explosion.
- **Ash & Fire** — burning enemies take +40% damage from all sources.
- **Shadow & Dodge** — a dodge that avoids a real hit ("perfect dodge") grants +35% damage for 3s.
- **Light & Healing** — killing a burning/warded enemy has a chance to drop a healing mote.
- **Wrath of the Warden** — damage scales up to +50% as your HP drops toward zero (needs 2 Wrath-tagged upgrades).

### World Events (5)

The Old Shrine (Embers vs. full heal), The Forgotten Merchant (buy a guaranteed upgrade at a floor rarity), The Dying Flame (sacrifice 25% HP for a guaranteed Rare+), The Whisper (50/50 double-or-halve your Embers), The Ember Well (spend Embers for immediate Soul Ash). Each event is seen at most once per run.

## 9. Zones & Difficulty Curve

| Zone | Rooms | Enemy pool | Heart guardian | Ambient |
|---|---|---|---|---|
| 1 — Ashen Woods | 8 | Ash Crawler, Hollow, Flame Wisp | Gravebound | Falling ash |
| 2 — The Hollow Ruins | 9 | + Gravebound, Shadow Stalker, (Cinder Wraith if unlocked) | Shadow Stalker | Drifting spores |
| 3 — Ember Citadel | 7 | Gravebound, Shadow Stalker, Flame Wisp, Ember Devourer, Cinder Wraith | **The Ashen Colossus** | Rising embers |

Difficulty scales via `getDifficultyFactors(zoneIndex, runMinutes)`:

```
hpMult      = 1 + zoneIndex × 0.32 + corruption × 0.55
damageMult  = 1 + zoneIndex × 0.22 + corruption × 0.35
extraEnemies = floor(zoneIndex × 0.6 + corruption × 1.6)
```

`corruption = min(1, runMinutes / 14)` — the **darkness pressure** meter shown in the HUD, reinforced by a slow-fading shadow-toned screen vignette so the pressure is felt ambiently, not just read off a corner bar. It never insta-kills the player; it just makes dawdling progressively more dangerous, giving a soft push toward the zone's heart rather than a hard timer.

## 10. Level Generation

A randomized-growth spanning tree starting from the entry room guarantees every room is reachable (no cycles, no unreachable rooms, no unsolvable seed). The single farthest room from the entrance becomes the zone's **heart** (zones 1–2) or **boss** room (zone 3). The remaining rooms are assigned in two passes rather than fixed counts. First, one **elite** (never adjacent to the entrance), one **shop**, and one **chest** are reserved unconditionally — these three are guaranteed in every zone regardless of how small or unlucky its layout turns out, since a zone with no shop or no chest would silently starve the player of upgrades. Whatever rooms remain are then split roughly in half between a guaranteed **combat** minimum and secondary specials (**event**, **rest**, then a bonus second **event**/**chest** for bigger zones); any leftover defaults to combat. Rooms with enemies **lock** their doors until cleared; every other room type is always open.

## 11. Boss: The Ashen Colossus

Three phases, gated by HP thresholds (66% / 30%), with a brief invulnerable "phase transition" beat between them (roar + camera shake + screen banner):

- **Phase 1** — melee slam (telegraphed ground-crack) when close, projectile volleys at range. Slow, deliberate.
- **Phase 2** — unlocked at 66% HP: adds a growing-ring **shockwave** attack and summons 2 Ash Crawlers; faster movement.
- **Phase 3** — unlocked at 30% HP: adds a **double-slam combo**, summons Shadow Stalkers instead, and starts a continuous **meteor rain** — telegraphed ground reticles that detonate after 1.5s, forcing constant repositioning on top of the boss's own attack pattern.

Every attack is telegraphed for at least `telegraphTime` (0.7s base) before it lands, and the boss commits to (cannot cancel) an attack once the telegraph starts — the fight is meant to be **hard but fair and fully readable**.

## 12. Economy & Balancing Philosophy

- All scaling uses formulas (see §9, §4, §7's cost growth), not hand-placed magic numbers per encounter, so the curve can be retuned globally by changing a handful of constants.
- Shop and chest pricing follow the same rarity-weight table used for random upgrade rolls, so "buying power" and "luck" always mean the same thing everywhere in the game.
- Rarity luck (`rarityLuck` stat) affects *chests, shop offers, and room-clear rewards* identically via one shared `rollRarity()` function — never duplicated, never inconsistent between systems.
- Elite and heart-guardian encounters bias the post-fight upgrade roll upward (+0.15 luck) so a harder optional fight is never a *worse* deal than skipping it.

## 13. Replayability

Every run varies via: seeded-but-different room graphs, randomized room-type placement, randomized enemy composition per room, a shuffled upgrade pool (with luck bias), randomized shop offers, one of five events per encounter, and — once far enough into meta-progression — a different weapon/ability loadout choice at the start of the run. The seed is displayed at the end of every run for reproducibility (bug reports, sharing an unusually good/bad layout).
