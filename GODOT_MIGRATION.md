# Migrating EMBERFALL: LAST LIGHT to Godot

This project was deliberately architected so a future Godot port is a **translation of logic**, not a rewrite of the game. Every gameplay system is a plain TypeScript class with no DOM or `CanvasRenderingContext2D` dependency; only `src/rendering/draw/*.ts` and `src/ui/*.ts` touch presentation. This document explains the current architecture in Godot terms, what maps directly, what should be rewritten to use engine-native features instead of a ported hack, and a recommended migration order.

## 1. Current architecture, briefly

```
Game.ts (single per-frame orchestrator)
 ├─ GameStateMachine        → what the game is currently doing
 ├─ InputManager            → keyboard/mouse/touch → unified actions
 ├─ RunState / MetaProgression → per-run and permanent progression
 ├─ world/*                 → room graph generation, physics resolution
 ├─ entities/*              → Player, Enemy, Boss, Projectile, Pickup, Chest, Obstacle (pure state + update(dt))
 ├─ ai/EnemyAI.ts           → per-behavior state machines, decoupled from rendering
 ├─ combat/*                → the one damage pipeline everything routes through
 ├─ rendering/*              → Canvas2D renderer, particle pool, additive lighting, draw functions
 ├─ audio/*                  → Web Audio synthesis (SFX + ambient score)
 └─ ui/*                     → DOM screens (HUD, menus, shop, events...)
```

Only the last two groups (`rendering/`, `audio/` synthesis, `ui/`) are genuinely web-specific. Everything else is data + timers + math.

## 2. Node & resource correspondence

| Current (TS class / module) | Godot equivalent | Notes |
|---|---|---|
| `entities/Player.ts` | `CharacterBody2D` + `player.gd` | Stats/cooldowns port as typed fields; movement via `move_and_slide()` |
| `entities/Enemy.ts` | `CharacterBody2D` + `enemy.gd`, one scene reused for all types | Visuals driven by the assigned `EnemyDefinition` resource, same as today's `def` field |
| `entities/Boss.ts` | Dedicated `ashen_colossus.tscn`, extends the Enemy script or composes it | Phase FSM ports almost as-is; consider `AnimationPlayer` for telegraph timing instead of manual timers |
| `entities/Projectile.ts` | `Area2D` (or `CharacterBody2D` if you want solid collision response) | Pool via a Godot `Node` pool or `preload()`+`instantiate()` with a max-alive cap |
| `entities/Pickup.ts` | `Area2D` pickup scene | Magnet-toward-player logic ports directly into `_physics_process` |
| `entities/Chest.ts` | `Area2D`/`StaticBody2D` + `AnimationPlayer` | |
| `entities/Obstacle.ts` | `StaticBody2D` scenes, or `TileMap` cells for the common ones | TileMap is far cheaper for dozens of static decorations |
| `data/*.ts` (Enemy/Weapon/Ability/Upgrade/Zone/Event/PermanentUpgrade/Unlock definitions) | Custom `Resource` scripts (`class_name EnemyDefinition extends Resource`) saved as `.tres` files | This *is* Godot's data-driven-design idiom — one `.tres` per current data object |
| `world/LevelGenerator.ts` | Plain GDScript class (Autoload or a `RefCounted` utility) | Pure graph algorithm, no rendering dependency — should port almost line-for-line |
| `world/Room.ts` | GDScript `Room` class holding a `Node2D` root populated at runtime | See §4 for the "reused local space" caveat |
| `combat/CombatSystem.ts` | Autoload `CombatManager` | Same single-pipeline design; keep it as the *only* place damage is applied |
| `ai/EnemyAI.ts` | Per-behavior GDScript state machines, or a shared `enemy_ai.gd` with a `match` on behavior enum | |
| `core/GameStateMachine` | Autoload `GameState` singleton, enum + `signal changed(state)` | |
| `core/GameEvents.ts` (EventBus) | **Native Godot signals** | Don't port the EventBus class — emit real signals from `CombatManager`/`RunState` instead |
| `progression/RunState.ts`, `MetaProgression.ts` | Autoload singletons | Godot's standard pattern for cross-scene persistent state — direct match |
| `progression/SaveSystem.ts` | `FileAccess` + `JSON.stringify/parse` to `user://save.json` | The validation/migration *logic* ports almost verbatim; only the I/O calls change |
| `utils/Random.ts` | `RandomNumberGenerator` (built-in, has a `.seed` property) | Godot already does exactly this — don't port the mulberry32 implementation, just use the engine's RNG (see §6 for the determinism caveat) |
| `utils/Vector2.ts` | Godot's built-in `Vector2` | Delete this file — Godot's is native and faster |
| `utils/Collision.ts` (AABB/circle helpers, `SpatialGrid`) | Godot's physics engine (`Area2D`/`CharacterBody2D` collision, `PhysicsServer2D` queries) | The custom broad-phase grid becomes redundant once real physics bodies do this natively |
| `utils/ObjectPool.ts` | Still useful for pooled `Node` instances (projectiles) if not using `GPUParticles2D` | Pattern ports directly |
| `rendering/ParticleSystem.ts` + `ParticlePresets.ts` | **`GPUParticles2D` / `CPUParticles2D`** | Rewrite, don't port — trigger built-in particle nodes/presets instead of hand-rolled particle math |
| `rendering/Lighting.ts` | **`PointLight2D` / `CanvasModulate`** | Rewrite, don't port — Godot's 2D lighting (with real occluders) is strictly better than the darken-then-additive-gradient hack this project uses for Canvas2D compatibility |
| `rendering/draw/*.ts` (procedural silhouettes) | `Node2D._draw()` overrides, **or** authored sprites + `AnimatedSprite2D` | See §4 |
| `audio/SoundFactory.ts`, `MusicEngine.ts` | `AudioStreamGenerator` (keeps runtime synthesis), or bake once to `.ogg`/`.wav` | See §4 |
| `ui/*.ts` (DOM screens) | `Control`-node scenes + a shared `Theme` resource | Full rewrite, mechanical: one `.tscn` per current screen class |
| `ui/HUD.ts`'s minimap (`refreshMinimap()`) | `GridContainer` with two interleaved track resolutions (room cells + thin connector cells in the gaps) | Port the *concept*, not the DOM: a room cell shows if visited/current/the zone's heart-or-boss room (always shown, even undiscovered — see §7's sibling note below on keeping gameplay rules out of view code), a hint pip shows for an unvisited neighbor of a shown room. Pull this selection logic into a plain helper before the `Control` port so it's testable without a scene tree. |
| `style.css` | A Godot `Theme` resource (`.tres`) + per-control theme overrides | Design tokens (colors, spacing) translate directly as Theme constants |

## 3. Systems that port with little to no change

These have **zero** rendering or DOM dependency today and should translate almost mechanically into GDScript:

- `world/Difficulty.ts` (pure formulas)
- `world/LevelGenerator.ts` (graph generation — the biggest win, since a buggy port here would be very noticeable)
- `progression/UpgradePool.ts` (rarity rolling)
- `combat/CombatSystem.ts`'s damage formulas (crit, synergy multipliers, burn/lifesteal math)
- `ai/EnemyAI.ts`'s state machine logic (timers and transitions, not the rendering that reacts to them)
- `data/stats.ts`'s `applyModifiers` (the flat/mult stacking rule)
- All of `data/*.ts` as data, once converted to `.tres`
- `progression/RunState.ts`'s `layouts` map — every zone's room graph is generated once, at run start, and kept resident in memory for the entire run rather than regenerated per visit. This is a deliberate design, not an oversight: it's what makes the bidirectional stairs (walk back to a previous zone's heart/boss room, then redescend) free of any regeneration, duplication, or "impossible state" risk — a room's visited/cleared/chest/enemy state is the same live object regardless of which zone is currently active. Keep this "generate once, hold every zone resident" shape in the Autoload port; simplifying it down to "only the current zone's layout exists" would silently reintroduce the reset bug this design avoids.

## 4. Systems to rewrite (not port) — and why

- **Particles & lighting**: the current implementations exist specifically because Canvas2D has no native particle or lighting system. Godot does. Porting the hand-rolled versions would be strictly worse than using `GPUParticles2D` and `PointLight2D` — rewrite these against the engine's tools.
- **Rendering**: two honest paths. (a) **Faithful port** — re-implement each `draw*.ts` function as a `_draw()` override using `draw_circle`, `draw_polygon`, `draw_arc`, etc. This preserves the "procedurally generated, no art assets" identity and is a fairly direct translation (Canvas2D and Godot's immediate-mode `_draw()` are conceptually similar). (b) **Authored sprites** — commission real pixel/vector art and drive it with `AnimatedSprite2D` + `AnimationPlayer`. More idiomatic Godot, better performance headroom, easier for an artist to iterate on, but a genuine art production task. Recommendation: start with (a) to get a fully playable, visually-coherent build fast, then replace hot-path enemies/player with (b) if a commercial art pass is planned (see `STEAM_PORTING.md`).
- **Audio**: decide whether "no shipped audio assets" still matters once you're not constrained by a web deployment's bandwidth/reliability concerns. If it doesn't, **bake** each procedural SFX to a short `.ogg` once (trivial: run the existing Web Audio code, record the output) and use normal `AudioStreamPlayer` nodes — simplest, most reliable, standard Godot workflow. If it does still matter, port the oscillator/envelope/noise logic to `AudioStreamGenerator`, which supports writing raw PCM at runtime; the *envelope math* in `SoundFactory.ts` ports conceptually, but scheduling shifts from `AudioContext.currentTime` lookahead to filling a ring buffer each frame — a real rewrite, not a port.
- **UI**: DOM and Godot `Control` nodes share almost no code, only the *design language* (`style.css`'s tokens become `Theme` resources). Every screen in `src/ui/` needs a matching `.tscn` + script.

## 5. Recommended migration order

1. **Project scaffold**: Autoloads for `GameState`, `RunState`, `MetaProgression`, `CombatManager`. Get signals wired before anything else depends on them.
2. **Data**: convert `data/*.ts` into `Resource` scripts + `.tres` files. Low risk, validates the data model survives the jump, unblocks everything else.
3. **Core entities, no visuals**: `Player`/`Enemy`/`Boss` as `CharacterBody2D` with movement, stats, and cooldowns working, rendered as flat-colored `Polygon2D`/`ColorRect` placeholders. Get gameplay *feel* testable before spending time on art.
4. **Combat + AI + the status-effect runtime**: port the damage pipeline and enemy state machines, and build the generic status-effect component from §7 alongside them — Burn becomes one `StatusEffectDefinition` among however many, not a special case bolted on later. Verify hit detection, knockback, and death against the placeholder shapes.
5. **Weapon behaviors**: the Strategy split from §8 — the two archetypes that already exist (`MeleeArc` for the Ember Blade/Void Scythe, `ProjectileShot` for the Solar Spear/Bow) — proving the architecture before any new archetype is asked for.
6. **Level generation**: port `LevelGenerator.ts`, and build the *bidirectional* room-transition flow from day one — retreat-to-previous-zone is the current design, not a later add-on (see §3's `RunState.layouts` note and §6 for the reused-space caveat). Get a full run navigable start-to-boss-and-back with placeholder visuals.
7. **Real rendering**: `_draw()` ports (or authored sprites) per §4; wire `PointLight2D` sources where the current code calls `lighting.add(...)`.
8. **Particles**: replace every `spawn*Vfx`/`ParticlePresets` call with the matching `GPUParticles2D` scene/preset.
9. **UI**: rebuild `HUD`, menus, shop/event/upgrade screens as `Control` scenes; port the update-only-changed-fields pattern from `HUD.ts` (`update()` mutating cached node references, not rebuilding trees). The minimap's `GridContainer` port (§2) belongs here.
10. **Audio**: bake or port per §4; re-tune envelopes by ear — Godot's audio latency characteristics differ from the browser's.
11. **Save system**: port `SaveSystem.ts`'s validation/migration logic onto `FileAccess`/`JSON`.
12. **Full playtest & rebalance pass.** Physics differences (gravity-free top-down movement, collision resolution order, frame pacing) mean identical numbers can *feel* different — budget real tuning time here, don't assume a 1:1 port feels the same.

## 6. Known migration difficulties

- **`_process` vs `_physics_process`.** The web build runs one `requestAnimationFrame` loop with a clamped delta. In Godot, movement/collision (`CharacterBody2D`) belongs in `_physics_process(delta)` (fixed-ish timestep) while purely visual timers can stay in `_process(delta)`. Decide this split deliberately rather than dumping everything into one callback.
- **Determinism across engines.** `Random.fromString()` uses a custom string hash feeding a mulberry32 PRNG. Godot's `RandomNumberGenerator` uses a different algorithm entirely. **Do not** expect a seed from the web version to reproduce the same room layout in Godot — treat seeds as engine-local from day one, and don't promise cross-version seed sharing to players.
- **Room-reused-local-space trick.** The web version keeps every room in the same `0..1000, 0..620` coordinate space and swaps *contents* rather than moving through a large world — cheap in JS where old entities just become unreferenced and get garbage-collected. In Godot, prefer an explicit `RoomContainer` `Node2D` that is fully cleared (`queue_free()` on every child, not just visually hidden) before the next room populates it, or instance each room as its own sub-scene and free the old one on transition. Either works; what doesn't is silently leaving stale nodes around, which a GC-free engine won't clean up for you.
- **Weak string-union typing.** GDScript's static typing (even Godot 4's typed mode) doesn't have TypeScript's string-literal unions (`'chaser' | 'tank' | ...`). Use real `enum`s for `EnemyBehavior`, `RoomType`, `Rarity`, etc. instead of comparing strings — closer to the original's compile-time safety and much cheaper to compare at runtime.
- **Lighting look will change.** The Canvas2D "darken then add gradients" hack and Godot's shader-based 2D lighting produce a visibly different mood even with matching colors/radii. Budget a short art-direction pass to re-match (or deliberately improve) the atmosphere once real lights and occluders are in.
- **Melee "hit everyone in an arc instantly" model.** This was a deliberate web-build simplification (see `GAME_DESIGN.md` §5) rather than a persistent hitbox. It ports fine as an `Area2D` overlap query at swing-start, or (better, once you're in an engine with cheap physics) a genuine short-lived hitbox `Area2D` — either is a straightforward decision, just don't assume it needs to become an animation-frame-synced hitbox unless you specifically want that extra fidelity.

## 7. Upgrade & status-effect architecture (not implemented today — plan for Godot)

The web build has exactly one status effect: Burn, a single hardcoded `BurnStatus` slot on `Enemy` (not a list — a new burn replaces the current one only if its DPS is higher, otherwise it just refreshes the stronger one's timer), applied by a hardcoded `burnChance` check inside `CombatSystem`. That pattern doesn't generalize: adding Bleed, Poison, Slow, or any other conditional proc the same way means a new stat field *and* a new hardcoded `if` for each one, forever. Don't port this as-is — generalize it before building anything past Burn.

Two `Resource` types plus one runtime component cover every case the design calls for (bleed, burn, poison, slow, damage buffs/debuffs, on-crit/on-dodge/on-ability procs, stacking, conditional effects):

- **`StatusEffectDefinition`** (`Resource`) — the authored shape of one effect: `id/name/icon/category` (dot/cc/buff/debuff), a `damage_formula` (flat, % of target max HP, % of target current HP, or % of the source's own stat — Bleed's "percentage of the mob's HP per second" needs the max-HP variant specifically), `tick_interval`, `duration`, a `stack_rule` (`none`/`refresh`/`stack_intensity` capped at `max_stacks`/`stack_independent`, each application its own timer), a `tint_color` and optional particle scene for feedback, and an optional `move_speed_mult` for CC-type effects.
- **`TriggeredEffect`** (a plain struct, not a `Resource`) — the generalization of `burnChance`: `trigger` (`OnHit`/`OnCrit`/`OnKill`/`OnDodge`/`OnAbilityCast`/`OnBlock`/`OnTakeDamage`), `chance` (0–1), `effect` (a reference to a `StatusEffectDefinition`, or a direct stat modifier for a non-DoT proc), and `target` (self or the hit enemy). Attach a list of these to an upgrade, and later to a weapon (§8) or an enemy attack — one shape, several attachment points. Emit them from real signals the combat/dodge/ability systems already need to fire anyway (`hit_landed`, `crit_landed`, `dodge_perfected`, `ability_cast`) rather than inventing a new event system — this is also a concrete reason to skip porting `core/GameEvents.ts`'s EventBus (§2) and use native signals from day one.
- **Runtime**: a plain (non-`Resource`) `StatusEffectInstance` — `{definition, remaining_duration, stacks, tick_timer, source}` — living in a list on every `Character` (Player and Enemy share a base). One shared component processes every active instance each physics tick, applies tick damage *through the same central `CombatManager`* (so a DoT tick still respects whatever armor/resistance hooks exist), expires instances, and drives the status-icon row/tint automatically. Keep `source` on the instance — it's what lets a DoT kill still correctly attribute XP/kill-credit/lifesteal to the player who applied it, the same single-attribution guarantee `CombatSystem.onEnemyDeath` already has to provide today.

Worked example, Bleed (30% chance on hit, 2%-of-max-HP tick, stacks up to 3):

```
# bleed.tres — a StatusEffectDefinition resource
id: "bleed"
category: DOT
damage_formula: PERCENT_TARGET_MAX_HP
damage_value: 0.02        # 2% of the mob's max HP, per tick
tick_interval: 1.0
duration: 4.0
stack_rule: STACK_INTENSITY
max_stacks: 3
tint_color: Color(0.7, 0.1, 0.1)

# on the upgrade granting it — same struct reused, not a new system
triggered_effects: [
  { trigger: ON_HIT, chance: 0.30, effect: bleed_resource, target: ENEMY }
]
```

Nothing about Poison, Slow, or a Burn re-implementation needs new code once this exists — each is a new `.tres` file. Build it in step 4 of §5, alongside the AI/combat port, so Burn is never a special case to begin with.

## 8. Weapon architecture (extending today's system — plan for Godot)

`data/*.ts`'s `WeaponDefinition` is already good data (damage/cooldown/range/stamina cost/knockback/crit bonus — see §2's data-conversion row). The actual gap is execution: today, attacking is one function per weapon `kind` (`melee`/`ranged`) inside `CombatSystem.ts`. A third archetype means a third branch in that same function, and every existing weapon keeps having to pass through it. Don't port that shape — split data from execution strategy before adding anything past the current four weapons:

- **`WeaponDefinition.tres`** stays stats-only: damage, cooldown, range, stamina cost, knockback, crit bonus, color/visual references.
- **A `WeaponBehavior` script per attack archetype** (`MeleeArc`, `ProjectileShot`, and later `Beam`/`Thrown`/`Channeled` as needed) implements one shared `execute(attacker, weapon_def)`. A new attack *shape* means one new behavior script, not a wider `if/else` every weapon has to keep passing through.
- **A weapon scene** carries its own sprite/animation set, swapped onto the player's weapon-hand marker when the equipped `weapon_id` changes.

Three things from the current system already generalize cleanly and should carry over as-is rather than being redesigned:

- **Stamina as the shared resource cost** — every weapon already spends from one stamina pool by its own per-weapon amount (all four current weapons cost 10). No change needed unless a future weapon wants a genuinely separate resource, which this architecture shouldn't preclude but doesn't need to solve now.
- **Weapon-gated upgrades via the existing unlock-gate pattern** — the Bow's own Attack Speed upgrades are already gated `requiresUnlock: 'bow'`, through the exact same set-membership check permanent Armory unlocks and zone-progress gates use elsewhere. Carry this into Godot as `requires_weapon: StringName` on the upgrade `Resource` — a direct extension of a pattern already proven working, not a new one.
- **Intrinsic weapon effects** — a weapon that should always proc something (a cursed dagger with innate poison-on-hit, independent of any upgrade) fits as an optional `intrinsic_effects: Array[TriggeredEffect]` field directly on `WeaponDefinition`, reusing §7's struct rather than inventing a parallel one.

Build this in step 5 of §5, immediately after the status-effect runtime, using the two archetypes the current build already proves out (melee for the Ember Blade/Void Scythe, ranged-projectile for the Solar Spear/Bow) before any new archetype is requested.
