# Emberfall: Last Light — Godot rebuild

This is the Godot-side counterpart to the Web prototype in `src/` at the
repo root. Full context — what exists in the Web build, what should be
kept/improved/rebuilt, the recommended architecture, and the complete
12-step build order this project is following — lives in
[`GODOT_MIGRATION.md`](../GODOT_MIGRATION.md) at the repo root. Read that
first; this file only tracks what's actually been built here so far.

## Status: build-order step 7 of 12 — real rendering + lighting

**Important caveat:** this project was authored without access to the
Godot editor or engine binary — this environment doesn't have Godot
installed, so most of it has not been opened, run, or validated by the
actual engine. **Steps 1-5 have been confirmed working** by the user
running them in their own Godot editor, including live debugging of three
real issues this session surfaced and fixed (a null-guard gap in
`weapon()`/`ability()`, a debug-label layout overlap, and a duplicate
`combo_step` field GDScript rejects that TypeScript silently allows).
**Step 6 has partial live confirmation**: combat rooms clearing and their
doors unsealing on kill is confirmed working. Chests, resting, the sanctum
rite, and the bidirectional stairs transition haven't been explicitly
exercised yet (the sanctum only exists in Zone 2 — Hollow Ruins — not the
Zone 1 starting zone, so a fresh run won't encounter one immediately).
**Step 7 below has NOT yet had any live confirmation.** Treat both as
carrying real risk until run and reported back. If anything fails to parse
or run, report the exact error.

### Steps 1-5 — scaffold, data, core entities, combat+AI, weapons (confirmed working)

5 Autoloads, 80 `.tres` Resource files across 10 content categories,
Player/Enemy/Boss as `CharacterBody2D` entities with real movement/
stamina/dodge/cooldown gating, the full damage pipeline (melee arc,
projectiles, contact damage, warden bash, bloat detonation), all 6 enemy
AI behavior families, the generic status-effect runtime, and a real
`WeaponBehavior` Strategy split so ranged weapons actually fire. Full
detail in git history — see the step-1 through step-5 commits, or
`GODOT_MIGRATION.md` for the architecture.

### Step 6 — level generation: real rooms, walls, and bidirectional stairs (combat/doors confirmed; chest/rest/sanctum/stairs not yet exercised)

The point of this step per `GODOT_MIGRATION.md` §5: port `LevelGenerator.ts`
and get a full run genuinely navigable start-to-boss-and-back, with the
*bidirectional* stairs (retreat to the previous zone) working from day
one rather than bolted on later. Every generated room is a real,
permanent `RoomContainer` node — created once, never freed or
regenerated; only the one the player is standing in is ever visible or
simulating (see `world/room_container.gd`'s own header for exactly why,
and how that's enforced beyond just hiding it).

| File | Ports | State |
|---|---|---|
| `world/room_container.gd` | `world/Room.ts` | Room data + real wall geometry: `StaticBody2D` segments built from `get_walls(locked)`, rebuilt the instant a room clears so the door physically opens. `set_active()` is the room-persistence mechanism — see its own comment |
| `world/level_generator.gd` | `world/LevelGenerator.ts` | The full generator: the frontier-growth room graph, the elite/shop/chest/sanctum/event/rest type budget, obstacle scatter (door-lane and landmark clearance included), stairs placement, the Ruins/Citadel encounter-template composition, the mutated-variant roll, the sanctum wave spawner, and the luck-biased rarity roll |
| `world/obstacle_node.gd`, `chest_node.gd`, `pickup_node.gd` | `Obstacle.ts`, `Chest.ts`, `Pickup.ts` | New entity types — obstacles are real `StaticBody2D`s (move_and_slide blocks against them for free, exactly like it already does for nothing before this step); chests and pickups are plain `Node2D`s, proximity-driven like the source |
| `autoload/level_flow.gd` | The room/zone-flow half of `core/Game.ts` | New autoload: door crossing, room-clear detection, the sanctum rite, resting, opening a chest, and the full scripted stairs transition (walk in → zone switch → walk out), both directions |
| `autoload/run_state.gd` | `progression/RunState.ts` | `advance_zone()`/`retreat_zone()`/`move_through_door()` are real now — all 3 zones generate up front at run start and stay resident for the whole run, so retreating mid-fight and coming back finds survivors exactly where they were |
| `entities/projectile.gd` | `resolveProjectileWalls` + the obstacle-blocking half of `updateProjectiles` | Bolts now actually stop at a wall or a `blocksProjectiles` obstacle instead of sailing through |
| `entities/player.gd` | — | New **E** interact key; a `is_transitioning` flag suppresses input during the scripted stairs walk |

**Deferred this pass, on purpose:** the actual reward-*granting* UI (the
3-choice upgrade pick on a cleared room, a chest's single upgrade) needs
the upgrade-ownership system, which is real UI — step 9. Every reward
*beat* still plays out (a cleared heart room's stairs unseal, a chest
plays its open animation, the sanctum rite heals 30% and pays 35 embers)
except the upgrade choice itself, which prints to the Output panel instead
of silently doing nothing. Shop and event landmarks spawn and are
walkable-up-to, but pressing E on either just prints that it needs step
9's real UI. Kill rewards that *don't* need new UI — XP (already-working
`RunState.grant_xp`) and Ember pickups — are fully wired.

`scenes/main/main.gd` no longer spawns the fixed one-of-each-behavior
playground — it boots a real run via `LevelFlow.start_new_run()` with a
fresh random seed each launch (shown nowhere yet but reproducible within
one engine session; see `GODOT_MIGRATION.md` §6 on why a seed isn't
expected to reproduce the Web build's own layouts). The live debug panel
now also shows the current room (type/locked/cleared/doors/enemy count),
zone/embers/level/XP, and the current interact prompt.

**How to test it:** run the project. You should land in an empty starting
room — walk to any door-shaped gap in the wall and cross it; you should
land in the next room with the camera/player continuous (no jarring
teleport look, though it technically is one). Find a **combat** room
(locked — walls should look sealed across every door until you clear it):
kill everything and confirm the walls covering the doors disappear and
the Output panel prints a "cleared" line. Find the **chest** room, walk
up to it and press **E** — it should visibly open and print its tier.
Find the **rest** room and press E at the brazier — your HP should jump
up. If Level 1 (Ashen Woods) has a **sanctum** room, kneel at its circle
(E) and fight through 3 waves — doors should stay sealed throughout, then
unseal with a heal + embers on completion. Clear the zone's **heart**
room and its stairwell should visibly unseal — walk up and press E to
descend: watch the short walk-in/fade/walk-out, land in the next zone's
start room next to an *up* stairwell, then immediately press E there to
ascend back — you should land back in the heart room you just cleared,
by the same stairs, and it should still show `cleared=true` with the same
enemies gone. None of this has been confirmed working yet — report
exactly what you see, especially anything about doors not sealing/
unsealing correctly, walls that seem to block or fail to block movement
oddly, or an error in the Output panel (parse errors will likely show up
immediately on load, the same way `combo_step` did last step).

### Step 7 — real rendering: `_draw()` ports + PointLight2D lighting (just added, unverified)

Per `GODOT_MIGRATION.md` §5 and §4's approach (a): every placeholder flat
circle/rect is replaced with a real procedural `_draw()` port of the Web
build's own `rendering/draw/*.ts` functions, plus `PointLight2D` sources
wherever `Game.ts`'s `registerLights()` called `lighting.add(...)`.
Lighting itself is a **rewrite, not a port** — per `GODOT_MIGRATION.md`
§4/§6, Godot's real 2D lighting has no reason to copy Canvas2D's
darken-then-additive-gradient hack; see `autoload/level_flow.gd`'s
`_update_ambient()` header for exactly how the two approaches map onto
each other.

| File | Ports | State |
|---|---|---|
| `rendering/palette.gd`, `rendering/draw_utils.gd` | `rendering/Palette.ts`, `rendering/DrawUtils.ts` | Shared color tokens and drawing primitives (soft shadows, glow circles, blob silhouettes) every other file below calls into |
| `entities/enemy.gd` | `rendering/draw/drawEnemy.ts` | All 9 unique enemy silhouettes, elite/mutated rings, telegraph indicators, status overlay |
| `entities/player.gd`, `entities/boss.gd` | `drawPlayer.ts`, `drawBoss.ts` | Real body/cloak/weapon rendering; the boss has its own silhouette, rage-glow, and cracking-armor-at-low-HP overlay (does not reuse the generic enemy body) |
| `world/obstacle_node.gd` | `drawObstacle.ts` | All 13 obstacle silhouettes (trees, braziers, the stairwells' reveal animation, etc.) |
| `world/chest_node.gd`, `world/pickup_node.gd`, `entities/projectile.gd` | `drawChest.ts`, `drawPickup.ts`, `drawProjectile.ts` | Chest lid-opening animation with real rarity coloring; Ember/Heart pickups; projectile glow+trail |
| `world/room_container.gd` | — | Floor/wall colors now read each zone's own palette instead of one fixed gray |
| every entity/obstacle/chest above, plus `autoload/level_flow.gd` | `rendering/Lighting.ts`'s `registerLights()` | A `PointLight2D` "Glow" child on every light-casting node, turned on/off and recolored each frame to match that node's own current state (a fire enemy's glow, a bloat's windup swell, a champion's shield-broken color flip, the boss's phase-based rage glow, a lit obstacle, an opened chest, a stairs-transition well) — see below |

**Lighting specifics:**
- Every `PointLight2D` shares one procedurally-built soft-circle texture
  (`DrawUtils.glow_texture()`, built once in code from a `Gradient` +
  `GradientTexture2D` rather than hand-authored as a `.tres` — this
  environment has no editor to round-trip a resource file through) with
  the same 3-stop falloff `LightingSystem.ts` used per-light, so each
  node only ever needs to set that light's `texture_scale` (radius),
  `color`, and `energy` (the source's per-light `intensity`).
  `Light2D.blend_mode` is left at its engine default, which is already
  additive — matching the source's own `globalCompositeOperation =
  'lighter'` for free.
- Ambient darkness (`zone.darkness`) is a `CanvasModulate` LevelFlow
  creates once and updates whenever the active room's zone changes. It
  tints the whole base canvas, which is why the debug/live labels moved
  under a `CanvasLayer` (`scenes/main/main.tscn`'s new `UI` node) — a
  `CanvasModulate` doesn't reach into a separate canvas layer, so the
  debug text stays legible regardless of how dark a zone gets.
- The one light that isn't owned by a persistent entity — the stairs
  transition's traveling glow — is a single `PointLight2D` LevelFlow
  owns directly and repositions/recolors every frame of the transition.

**Deferred this pass, on purpose:** hazards (fungal pools), the sanctum's
lit candles, and the player's warding-sigil ability aren't ported into
Godot yet at all (not a step-7 gap — those systems themselves don't exist
yet), so their `registerLights()` entries have nothing to wire to. Real
occluders (`LightOccluder2D` on walls, so lights actually cast shadows)
are a natural follow-up once the base lighting is confirmed working —
`GODOT_MIGRATION.md` §4 calls this out as lighting's whole reason for
being a rewrite rather than a port, but it's additional polish, not
required for the lights to work.

**How to test it:** run the project and confirm every entity now has a
real silhouette instead of a flat circle/rect — enemies should be visibly
distinct per type, the player/boss should show cloak/weapon/body detail,
obstacles should read as trees/braziers/statues/etc., and room floors/
walls should tint per zone. For lighting specifically: the player should
cast a warm glow around themselves at all times; braziers/crystals/the
merchant stall/fungus/lit stairwells should glow; a Spore Bloat should
brighten as it winds up to burst; the Hollow Warden champion's glow
should flip color when its shield breaks; the boss should glow more
intensely each phase; an opened chest should glow in its reward's rarity
color; and the whole scene should visibly darken/brighten between zones
(Ashen Woods vs. the Hollow Ruins) while the debug text in the corner
stays readable throughout. None of this has been confirmed working yet —
report exactly what you see, especially anything about a light that
doesn't appear at all (likely a `$Glow` node/texture wiring issue) versus
one that appears but looks visually wrong (likely a color/radius/timing
tuning issue).

### Next steps (not started)

Per `GODOT_MIGRATION.md` §5, step 8: particles — replace every
`spawn*Vfx`/`ParticlePresets` call with the matching `GPUParticles2D`
scene/preset.
