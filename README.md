# EMBERFALL: LAST LIGHT

A self-contained, dark-fantasy top-down action roguelite for the browser. Every sprite, particle, light and sound is generated procedurally at runtime — there are no external image, audio, or font files anywhere in this project.

> *The Ember is dying. Someone must carry the last light.*

---

## Concept

You play **The Warden**, guardian of the last surviving Ember — the dying source of light holding back an encroaching corruption. Each run sends you through three increasingly hostile zones, fighting through procedurally generated rooms, collecting **Embers** to power temporary upgrades, and permanently investing your death's **Soul Ash** into a growing Warden legacy. Runs are built to last roughly **10–20 minutes** and end either in victory over **The Ashen Colossus** or in a fall that still leaves you stronger for the next attempt.

The core loop:

```
explore → fight → loot → upgrade → push your luck → reach the zone's heart → face the Colossus → repeat, stronger
```

## Features

- **Full combat kit**: melee/ranged weapon swap, a dodge with i-frames, and 3 special abilities, all with real hit detection, knockback, crits, and status effects.
- **10 enemy types** (9 base + 1 unlockable) with distinct silhouettes, AI behaviors, and attacks, plus an elite variant system — including Level 2's **Hollow Warden** (a slow-turning shield wall you must flank or punish after its telegraphed bash) and **Blightbloat** (swells, bursts, and leaves a lingering spore-cloud hazard where it dies).
- **A 3-phase boss fight** — The Ashen Colossus — with telegraphed attacks, adds, and an environmental hazard phase, plus a two-phase **champion** ending Level 2 (The Sunken Warden: its shield shatters at half health).
- **A real Level 2 — The Hollow Ruins — and a real Level 3 — The Ember Citadel**: the same ruined stone further down and further gone. Level 2 is darker, damper, lit by cold fungal growth instead of fire, with its own composed encounters, zone-bound events, and an opt-in three-wave ritual arena (the Drowned Sanctum) paying out Rare-or-better; Level 3 hits harder with composed encounter templates and a rare "Ember-Marked" mutated-enemy variant. Zones connect through **stairwells**, not teleports, and the trip is **bidirectional**: a sealed, rune-carved lid in the heart room grinds open once the guardian falls, descending is a scripted moment (walk into the well, fade to black, arrive at the foot of the matching stairs below), and the same stairwell carries you back up to the previous zone's heart room with every room's discovered/cleared/loot state intact in both directions. A reworked **minimap** always shows the zone's heart/boss room as a fixed landmark, discovered or not, alongside every room you've actually explored.
- **Deterministic seeded procedural generation**: every run's room graph, loot, and enemy placement is reproducible from its seed. The seed is shown on the end screen, and can be typed back into the main menu's seed field (or passed as a `?seed=` URL query param) to replay or share an exact layout — handy for reporting a specific bug.
- **28 in-run upgrades** across 5 rarities, **5 cross-upgrade synergies** (visibly announced with a banner and a distinct chime the moment a pair activates), and a full **permanent meta-progression** tree (11 stat nodes + 6 unlocks) spent with Soul Ash between runs. The pause menu's "Your Build" screen lists every upgrade collected and synergy currently active mid-run.
- **A run-scoped Player Level** (cap 30, independent of the permanent Soul Ash tree): every kill grants XP, each level grants a stat point spendable across 6 stats, and reaching the Ember Citadel (Level 3) grants and auto-equips **the Bow** — a 4th weapon, and the only one unlocked by in-run progress rather than an Armory purchase.
- **Weighty combat feedback**: crits, Ember Burst, elite kills, and boss-phase beats trigger a brief real-time hit-stop on top of the existing screen shake / hit-flash / damage numbers, tied to the screen-shake accessibility toggle. A perfect dodge always gets its own particle flash and chime, a full-screen ember-red vignette makes low HP readable at a glance without watching the corner bar, and a slow shadow-toned vignette makes rising corruption ("darkness pressure") felt ambiently rather than just read off a corner meter.
- **Real stone masonry, not a color fill**: walls are baked, per room, from hand-picked crops of an actual reference painting of ancient dungeon stone (`assets/textures/ancient-wall.png`) — resampled per block, full-bleed with no gap between blocks (the mortar joint is a thin stroke on top, never an unpainted seam), with a random offset and occasional mirroring, then hue-shifted to each zone's palette via canvas `'color'` blending so the photo's own depth and shading survive under three visually distinct zone tones. Because the source is a scene lit mostly by its own torches, a per-region levels stretch (`rendering/ImageLevels.ts`) remaps each crop's own dim, scene-specific brightness back up to something legible before it's tiled, so a block cut from a part of the photo the torches never lit reads as real detailed stone rather than a dark, empty-looking patch. Doors are carved directly into that same masonry as an irregular gap between worked jamb-and-torch stones (mirrored from the same source crop) rather than a separate clean insert.
- **A floor of individually-shaped flagstones, not a ruled grid**: each room's floor is tiled, once and cached, from slabs whose silhouette is a rounded rectangle with jittered corners and a slight bow per edge — hand-cut-looking rather than a stamped shape — clipped and filled with a levels-corrected, zone-tinted crop of a reference dungeon photo (`assets/textures/dungeon-room-ref.png`), plus a soft per-slab "dome" shading. Rows alternate a half-cell offset so no seam lines up into a grid, two separate source bands (kept clear of the photo's own torch-lit hotspot, so that lighting never gets baked into the tile) are picked per slab alongside independent horizontal/vertical mirroring, and the base of the whole canvas is a pale, warm grout color that shows through every gap between slabs as a deliberate joint — never a void — even where the reference's own painted mortar isn't visible at that spot.
- **Legible room exits**: a state-colored glow spills further into the room as the player approaches a door, and barred geometry marks locked ones so the state reads without relying on color alone.
- **Legible room landmarks**: shop, rest, and event rooms each build around a dedicated lit structure — a merchant's stall, a brazier, or a mysterious shrine — offset so it never blocks the straight line between two doors, so their interaction is always tied to something visible, not an invisible trigger zone in empty floor. The stall itself is a real cropped sprite from the same floor-and-shop reference sheet, its flat sheet background chroma-keyed to transparency once and cached, rather than a procedural drawing.
- **4 weapons, 3 abilities, 10 enemies** — two weapons, two abilities, and one enemy type are unlockable via the Armory; the 4th weapon (the Bow) is unlocked in-run instead, by reaching Level 3 of the dungeon.
- **Procedural audio**: every sound effect and the ambient score are synthesized live with the Web Audio API — no audio files.
- **Procedural visuals**: canvas-drawn silhouettes, a pooled particle system, and a two-layer Canvas2D lighting model (ambient darkness + additive glow sources).
- **Data-driven content**: enemies, weapons, abilities, upgrades, zones, and events are all plain data objects (see `src/data/`), not hardcoded logic.
- **Full meta layer**: localStorage save with validation/migration, settings (volume, particle/graphics quality, accessibility), and lifetime stats.
- **Responsive & accessible**: scales from small laptop screens to ultrawide monitors, works with mouse+keyboard or a single-stick touch layout, includes a screen-shake toggle, particle-density control, text scaling, and a high-contrast mode.

## Controls

| Action | Desktop | Touch |
|---|---|---|
| Move | `WASD` / Arrow keys | Left virtual stick |
| Aim | Mouse position | Follows movement direction |
| Attack | Left Click (hold to auto-swing) | Blade button |
| Special Ability | Right Click | Ember button |
| Dodge | `Space` | Dodge button |
| Interact | `E` | E button |
| Pause | `Esc` | Pause button (top center) |
| Debug overlay | `` ` `` (backquote) | — |

The game detects touch input automatically and swaps the on-screen control scheme; onboarding hints adapt their wording to match.

## Installation & running

Requirements: Node.js 20.19+ or 22.12+ (required by Vite 8).

```bash
npm install
npm run dev       # start the dev server (Vite), then open the printed local URL
```

Build & preview a production bundle:

```bash
npm run build      # type-checks, then builds to dist/
npm run preview    # serve the production build locally
```

Type-check only:

```bash
npm run typecheck
```

There is no backend, database, or network requirement — `dist/` is a fully static bundle you can open from any static file host (or `file://`, in browsers that allow module scripts from disk).

## Project structure

```
src/
  main.ts               entry point — boots the Game class
  style.css              the entire visual design system (tokens, HUD, menus)
  core/                  game loop, camera, input, state machine, event bus
    Game.ts               orchestrates every system per frame (the only "God" file, by design)
    GameState.ts           authoritative state machine (BOOT/MENU/EXPLORATION/COMBAT/...)
    GameEvents.ts           typed pub/sub for cross-system reactions (loot, stats, VFX)
    Input.ts                keyboard/mouse/touch → unified action interface
    Camera.ts               follow camera, screen shake, adaptive zoom
  entities/              plain logic classes — no rendering code (Player, Enemy, Boss, Projectile, Pickup, Chest, Obstacle)
  ai/EnemyAI.ts          per-behavior enemy state machines (chaser/tank/ranged/heavy/stalker/elite)
  combat/                damage pipeline, boss attack resolution, floating damage numbers
  world/                 room graph generator, room model + collision walls, difficulty curve, shop offers
  progression/           run state, meta-progression (Soul Ash), localStorage save system
  data/                  every enemy/weapon/ability/upgrade/zone/event as plain data (data-driven design)
  rendering/             Canvas2D renderer, particle system, lighting, procedural draw functions per entity
  audio/                 Web Audio API synthesis (SFX + generative ambient score)
  ui/                    all DOM-based screens (HUD, menus, shop, events, victory/defeat, touch controls)
  utils/                 Vector2, seeded RNG, collision math, object pooling, event bus
```

## Architecture

- **Logic/rendering separation.** Entities (`src/entities/`) hold only state and per-frame update logic — no `CanvasRenderingContext2D` ever appears there. Drawing lives entirely in `src/rendering/draw/*.ts` as pure functions of entity state. This mirrors a Godot Node (script) + visual representation split and is the basis for `GODOT_MIGRATION.md`.
- **Data-driven content.** `EnemyDefinition`, `WeaponDefinition`, `AbilityDefinition`, `UpgradeDefinition`, `ZoneDefinition`, `WorldEventDefinition`, `PermanentUpgradeDefinition`, and `UnlockDefinition` (all in `src/data/types.ts`) are the single source of truth for game content. Adding a new enemy or upgrade means adding a data entry, not writing new gameplay code.
- **Single game-loop authority.** `Game.ts` owns the `requestAnimationFrame` loop and is the only place that decides what updates each frame, gated by `GameStateMachine`. Systems (combat, AI, particles, audio) never update themselves independently, so there is one clear place to reason about frame order and pausing.
- **Deterministic core, cosmetic randomness at the edges.** Level layout, loot rarity, and room contents are derived from the run's seed via `Random` (a seeded PRNG). Purely visual variance (particle jitter, ambient motes) uses `Math.random()` since it never needs to be reproducible.
- **Room-local coordinate space.** Every room reuses the same `1000×620` local space (see `world/Room.ts`); moving through a door swaps the *active* room rather than scrolling a large world. This keeps collision, camera, and rendering cheap regardless of how large the dungeon graph gets — only the current room's entities ever simulate.
- **Event bus for decoupling.** `GameEvents.ts` lets combat, loot, and stat-tracking react to occurrences (`enemyKilled`, `playerDied`, `bossPhaseChanged`, ...) without importing each other directly.

## Key systems

- **Combat** (`combat/CombatSystem.ts`): a single `damagePlayerToEnemy` / `damageEnemyToPlayer` pipeline handles crit rolls, synergy multipliers, knockback, lifesteal, burn application, damage numbers, particles, sound, and screen shake — so every damage source (melee, projectiles, abilities, boss attacks) gets identical, synchronized feedback.
- **Enemy AI** (`ai/EnemyAI.ts`): a small state machine per behavior archetype (`spawning → chase → windup → attack → cooldown`), with dedicated handling for ranged kiting, stalker vanish/ambush, elite hybrid melee+ranged, the warden's slow-turning shield/bash/exposed loop, and the bloat's plant-swell-burst commitment. Attack resolution is delegated back to `CombatSystem` via callbacks so hit detection stays centralized; the warden's frontal damage reduction and the spore-cloud floor hazards (`CombatSystem.hazards`) live there too, so every damage source respects them identically.
- **Boss** (`entities/Boss.ts` + `combat/BossSystem.ts`): a 3-phase fight with telegraphed slam/shockwave/projectile-volley/summon attacks and a phase-3 meteor-rain hazard, expressed as declarative "pending action" flags resolved once per frame — the boss body reuses the generic `Enemy` class for physics/rendering plumbing.
- **Procedural generation** (`world/LevelGenerator.ts`): a randomized-growth spanning tree guarantees every room is reachable from the start (no unsolvable layouts by construction), then assigns room types (combat/elite/chest/shop/event/rest/heart/boss, plus the Hollow Ruins' sanctum) from the resulting graph. Heart rooms are always one-door leaves, which is what lets the exit stairwell sit on the far side from the way in; scatter keeps clear of door lanes, landmarks and each other, and Level 2's combat rooms are composed from encounter templates weighted by depth.
- **Lighting** (`rendering/Lighting.ts`): a cheap, fully Canvas2D-compatible technique — darken the frame with a translucent overlay, then re-brighten with additive radial gradients at each registered light source (player ember, fires, boss glow, projectiles).
- **Audio** (`audio/`): every effect is synthesized from oscillators and filtered noise with hand-tuned envelopes; the ambient score is a continuously-gliding detuned drone with sparse generative "ember chime" accents and a combat-intensity tension layer — no `<audio>` tags, no files.
- **Save system** (`progression/SaveSystem.ts`): versioned localStorage save with full validation on load — a corrupted or malformed save can never crash the game; it's replaced with (and immediately persisted as) a fresh default.

## Development notes

- TypeScript strict mode is on project-wide; `any` appears exactly once, inside the generic `EventBus`'s internal handler map (the public API is fully typed).
- No UI framework — `ui/dom.ts` provides a tiny `el()` hyperscript helper; all screens are plain DOM manipulation, kept snappy by never rebuilding whole trees for per-frame updates (HUD caches element references and only touches `textContent`/`style` each tick).
- No CSS framework — the entire design system (colors, type scale, component classes) lives in `src/style.css` as CSS custom properties.
- Debug overlay: press `` ` `` in-run to show FPS, seed, current room (key/type/lock state/doors), player position, live enemy/particle/projectile counts, and the current game state. Off by default; never shown in normal play.

## Build

```bash
npm run build
```

This runs a full TypeScript type-check (`tsc --noEmit`) followed by a Vite production build into `dist/`. The output is a static site: one HTML file, one CSS bundle, one JS bundle (no code-splitting is needed at this size — the whole game is under 50KB gzipped).

## Troubleshooting

- **No sound.** Browsers block audio until a user gesture. The game calls `AudioContext` unlock on the first click/keypress anywhere on the page — click once on the main menu if music doesn't start immediately.
- **Blank/black screen.** Check the browser console; the save system is defensive against corrupt data, but a `localStorage` write failure (e.g. private browsing with storage disabled) will be logged as a warning and the game continues with an in-memory default save rather than crashing.
- **Low FPS on older hardware.** Open Settings and drop "Graphics Quality" and "Particles" to Medium or Low — this scales the canvas backing resolution and the particle pool cap.
- **Touch controls not appearing on a touch laptop.** Detection uses `(pointer: coarse)`; a touch-screen laptop with a precision mouse/trackpad as primary pointer will correctly default to desktop controls. Touching the screen first will switch input mode.
- **Reproducing a specific run.** The seed shown on the victory/defeat screen (and in the debug overlay) fully determines room layout, loot rolls, and enemy placement — useful for reporting or investigating a specific bug.

## Future migration

The Godot rebuild has started: [`godot/`](./godot) holds a real, openable Godot project — through step 8 of the 12-step build order, with step 9 (UI) in progress (the scaffold + 6 core Autoloads; every enemy/weapon/ability/upgrade/zone/event/permanent-upgrade/unlock/synergy as a data-driven `Resource`; Player/Enemy/Boss as `CharacterBody2D` entities; real combat and weapon behaviors — the damage pipeline, all 6 enemy AI behaviors, projectiles for both melee and ranged weapons, and a live status-effect runtime; full level generation — real procedurally-generated rooms with physical walls that seal until cleared, obstacles, chests, and a complete bidirectional stairs flow, so a run is genuinely navigable start-to-boss-and-back; real rendering — every entity's own procedural `_draw()` silhouette replacing the flat placeholder shapes, zone-tinted rooms, and `PointLight2D` lighting for the player, obstacles, enemies, the boss, projectiles, and chests (confirmed working in a real Godot editor); particles — `GPUParticles2D` bursts for hits, deaths, dodges, heals, level-ups, chest openings, and the sanctum rite, replacing the Canvas2D-only hand-rolled particle pool; and now the start of UI — a real upgrade-ownership system (owned upgrades, synergies, stat points all actually apply now) plus a core HUD (health/stamina/energy/ability/embers/level-XP), with the reward-choice screens and minimap/menus still ahead. See [`godot/README.md`](./godot/README.md) for exactly what's implemented, deferred, or still unverified in a real editor). [`GODOT_MIGRATION.md`](./GODOT_MIGRATION.md) is the full transition plan this project follows, and [`STEAM_PORTING.md`](./STEAM_PORTING.md) covers what a commercial desktop/Steam release would additionally require. Game design details (enemy stats, upgrade formulas, economy) live in [`GAME_DESIGN.md`](./GAME_DESIGN.md).

## Known limitations

- Meteor telegraphs, dodges, and hit reactions are tuned for a single local player — there is no multiplayer or spectator mode.
- Only one save slot exists (no cloud sync, no multiple profiles).
- The permadeath run does not currently support mid-run save/resume (closing the tab mid-run forfeits that run, matching the genre's convention, though all permanent Soul Ash progress from *completed* runs is preserved).
