# Emberfall: Last Light — Godot rebuild

This is the Godot-side counterpart to the Web prototype in `src/` at the
repo root. Full context — what exists in the Web build, what should be
kept/improved/rebuilt, the recommended architecture, and the complete
12-step build order this project is following — lives in
[`GODOT_MIGRATION.md`](../GODOT_MIGRATION.md) at the repo root. Read that
first; this file only tracks what's actually been built here so far.

## Status: build-order step 9 of 12 — UI (in progress)

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
**Step 7 is confirmed working** after one live fix: the editor caught a
parser error (`boss.gd` accidentally overrode a same-named method it
inherited from `enemy.gd` with an incompatible signature — see git history
for the fix), and the user confirmed everything renders correctly once
that was corrected. **Step 8 below has NOT yet had any live confirmation.**
Treat it as carrying real risk until run and reported back — same as every
step before it that turned out to need at least one real-engine fix. If
anything fails to parse or run, report the exact error.

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

### Step 7 — real rendering: `_draw()` ports + PointLight2D lighting (confirmed working, after one live parser-error fix)

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
stays readable throughout. **Confirmed working** — the user ran it after
one fix (see the status note above).

### Step 8 — particles: `GPUParticles2D` (just added, unverified)

Per `GODOT_MIGRATION.md` §5/§4/§6: "replace every `spawn*Vfx`/
`ParticlePresets` call with the matching `GPUParticles2D` scene/preset" —
another rewrite, not a port, same reasoning as lighting: Canvas2D's
hand-rolled `ParticleSystem.ts` (a fixed-capacity pool with its own
per-frame update/render) only exists because Canvas2D has no native
particle system. Godot's `GPUParticles2D` already does everything that
loop did, so only `ParticlePresets.ts`'s 13 *reachable* visual recipes
(hit sparks, death bursts, spore bursts, shield sparks, dodge trails,
heal/level-up/chest-open sparkles, stone chips, ritual candle catches —
see `vfx/vfx_presets.gd`'s own header for the full list and exactly which
TS call site each one ports) needed porting, not the engine underneath them.

| File | Ports | State |
|---|---|---|
| `vfx/vfx_system.gd` | `rendering/ParticleSystem.ts`'s engine half | `VfxSystem.emit()`: one Dictionary shaped like TS's `ParticleOptions` in, one auto-freeing one-shot `GPUParticles2D` out. Builds its own ring/square shape textures (`GradientTexture2D`, reusing `DrawUtils.glow_texture()` for circle/spark) and per-call `Gradient`/`Curve` resources for color-over-lifetime and size-over-lifetime — every Godot property/enum this touches (`ParticleProcessMaterial`, `GradientTexture1D`, `CurveTexture`, `CanvasItemMaterial.blend_mode`) was cross-checked against the actual Godot 4.3 class docs, not recalled from memory |
| `vfx/vfx_presets.gd` | `rendering/ParticlePresets.ts` (13 of 18 functions — see below) | Thin wrappers, one `VfxSystem.emit()` call per TS `ps.spawn()`/`ps.burst()`, same order |
| `autoload/combat_manager.gd` | `CombatSystem.ts`'s VFX calls | Hit impact (normal + blocked/shield-sparks), death burst, perfect-dodge burst (which needed a small, faithful completion of `damage_enemy_to_player` — capturing `was_dodging` before `take_damage()`, mirroring the source's own `wasDodging` local, since `blocked` alone can't tell a dodge from any other invulnerability source), bloat detonation's spore burst, and the champion shield-break's stone chips + each reinforcement's spore burst |
| `autoload/level_flow.gd` | `Game.ts`'s VFX calls | Rest/sanctum-completion heal sparkles, the stairs-unseal stone chips + scattered spore motes (gated to the true first activation, not on re-entry — ported a `stairs.activated` check the Godot side was missing, matching the source's own `if (stairs.activated) return`), the stairs-transition's continuous spore motes, sanctum wave-spawn spore bursts + per-wave candle-ignite flares, and the player-level-up burst (connected to `RunState.player_leveled_up`, which already existed and had nothing listening to it) |
| `world/chest_node.gd` | `Game.ts`'s `spawnChestOpenBurst` | Fires on the chest's own OPENING → OPENED transition rather than waiting on a resolved reward (which needs step 9's real UI) — ties it to something that already exists and lines up with when the lid visually finishes anyway |
| `entities/player.gd` | `Game.ts`'s per-frame dodge-trail spawn | One trail particle every physics tick for the dodge's duration, same density as the source |
| `world/level_generator.gd` | `drawSanctum.ts`'s `SANCTUM_CANDLE_COUNT`/`sanctumCandlePosition` | Pure geometry, ported on its own so the rite's candle-ignite VFX has real positions to play at — no persistent candle visual/light exists (same gap step 7's lighting pass already noted) |

**Not ported, on purpose** (see `vfx/vfx_presets.gd`'s header for the full
reasoning on each): 5 of the 18 `ParticlePresets.ts` functions are dead
code in the TS source itself (never called from anywhere in the Web
build) and porting them would just be unused surface area. `spawnEmberBurstVfx`
has no reachable trigger in this port yet — every TS call site is the
player's Ember Burst ability's damage effect (not implemented —
`player.gd`'s `start_ability()` is animation-only) or one of the Ashen
Colossus's phase attacks. **That surfaced a real, previously-undocumented
gap this pass**: the boss has no attack FSM at all in this port —
`boss.gd`'s `boss_state`/`Phase` fields exist and drive its rendering, but
nothing anywhere ever assigns `boss_state`, so a run's boss currently
fights back only as a generic (very large) enemy via `EnemyAI`, none of
the slam/combo/shockwave/projectile/summon attacks `GODOT_MIGRATION.md`
describes. Worth a dedicated pass of its own rather than folding into this
one. `spawnZoneAmbientParticle` (a continuous per-zone atmosphere effect,
technically `drawRoom.ts` not `ParticlePresets.ts`) reads `ZoneDefinition`
fields (`ambientParticle`, `sporeColors`, `palette.ambient`/`accent`) that
don't exist on this port's `ZoneDefinition` resource yet — left for a
dedicated atmosphere pass. And a handful of individual call sites of
otherwise-ported presets stay unwired because they're gated on the
shop/event UI or the reward-choice system (step 9).

**How to test it:** run the project and trigger the actions above one at a
time — land a normal hit and a blocked (shield) hit on a Hollow Warden,
kill a regular enemy, get hit while dodging (should see a violet perfect-
dodge burst, not damage), pop a Blightbloat, break a champion's shield,
open a chest, rest at a brazier, clear a sanctum wave and complete the
rite, walk through a stairwell both directions, and level up. Each should
show a burst of particles roughly matching its described colors/shape
above, and every burst should clean itself up a moment later (no particles
should ever visibly freeze in place or accumulate indefinitely — if one
does, that's a `finished` signal/auto-free bug). None of this has been
confirmed working yet — report exactly what you see, especially anything
about a burst that never appears at all (likely a parent/positioning
issue) versus one that appears but looks visually wrong (likely a
color/shape/timing tuning issue in `vfx_presets.gd`).

### Step 9 — UI (in progress: upgrade-ownership system, core HUD, and the room-clear/chest reward flow all landed and confirmed against a real running build)

Per `GODOT_MIGRATION.md` §5.

**A capability upgrade partway through this step, worth recording:** this
environment turned out to have no Godot editor/binary *pre-installed*, but
nothing stopping one from being fetched — Godot 4.3's Linux binary
downloads directly from its GitHub release, and `Xvfb` (an X virtual
framebuffer, already present in the base image) gives it a real display to
render into headlessly. So this pass (and everything after it) is no
longer "authored against documentation and hoped" the way steps 1-8 and
the first half of this one were: every screen below was actually built,
run — `Godot_v4.3-stable_linux.x86_64 --path godot/ res://scenes/main/main.tscn
--resolution 1152x648` under `DISPLAY=:99` with Xvfb serving that
display — and checked against a real saved screenshot
(`get_viewport().get_texture().get_image().save_png(...)`) and the
console's own script-error output before being called done. This is how a
real, previously-shipped bug in the HUD (below) actually got found and
fixed, in-session, without needing a report back.

**1. The upgrade-ownership system** — the prerequisite step 8's README
flagged as missing (no owned-upgrades list on Player, no `UpgradePool`/
`Shop` port):

| File | Ports | State |
|---|---|---|
| `entities/player.gd` | `Player.ts`'s `recomputeStats`/`addUpgrade`/`addBonusModifier`/synergies | `upgrades`/`active_synergies`/`bonus_modifiers` fields + the 5 methods, ported verbatim against the TS source (including the "wrath" synergy's same-tag-twice exception, see `synergy_definition.gd`) |
| `godot/progression/` (new folder) | `data/playerProgression.ts`, `progression/UpgradePool.ts`, `world/Shop.ts` | `player_progression.gd`/`upgrade_pool.gd`/`shop.gd` — grouped as one domain rather than mirroring the TS split across `data/`/`progression/`/`world/`. `OwnedUpgrade`/`ShopOffer`/`PlayerStatDef` are small RefCounted data holders |
| `autoload/level_flow.gd` | `Game.ts`'s `openChest`/`grantUpgrade`/`currentGateIds`/`spendStatPoint` | `spend_stat_point()` is the real entry point (checks the Bow/Zone-1 lock `RunState.spend_stat_point` deliberately never did) — no caller yet, that's `InventoryUI`'s Character tab, still ahead |

**2. The core HUD** (`ui/hud.gd` + `ui/hud_icon.gd` + `scenes/ui/hud.tscn`)
— HP/stamina/energy bars with shield pips and buff icons, the ability
slot with its cooldown sweep, weapon/ability name + icon, embers/timer/
zone-room label, the corruption bar, the level/XP bar + stat-point hint,
and the interact prompt. Built entirely in GDScript (`_ready()`
constructs the whole Control tree) rather than hand-authored `.tscn` node
data. **A real, confirmed-live bug found and fixed here**, worth keeping
as a reference for the next Control-heavy screen: every region except the
top-left one rendered completely off-screen, because `Hud`'s own
`set_anchors_preset(PRESET_FULL_RECT)` call — made on a Control already
in the scene tree (the instanced root) — computes offsets that *preserve*
its pre-call (0,0) size instead of resetting to 0, unlike the same call
made on a not-yet-parented node (every child region's own `col`/`row`),
which cleanly resets. See `hud.gd`'s own header comment for the full
write-up. Fixed by giving `Hud` itself explicit `offset_* = 0` right after
its own preset call.

**3. The room-clear/chest reward flow** — the payoff the upgrade-ownership
system was built for:

| File | Ports | State |
|---|---|---|
| `ui/upgrade_card.gd` | `.upgrade-card`'s markup (shared by `UpgradeSelectUI.ts` and `RewardPopup.ts`) | One class serves both: `clickable` gates whether it handles clicks, `first_tag_text` is either a rarity name or a reward-source label. Border/background drawn via `_draw()`, not nested ColorRects, for a true unfilled outline |
| `ui/upgrade_select_ui.gd` | `ui/UpgradeSelectUI.ts` | The 3-choice room-clear picker. A true modal — pauses the whole `SceneTree` (mirrors `updatePlaying()`'s own `!this.modalScreen` early-out) with itself marked `PROCESS_MODE_ALWAYS` so it still takes clicks while everything else freezes |
| `ui/reward_popup.gd` | `ui/RewardPopup.ts` | Single auto-dismissing card (2.8s), non-modal — doesn't pause, doesn't block input, matches the source's own `pointer-events:none` |
| `autoload/level_flow.gd` | `Game.ts`'s `grantRoomClearReward`/`chooseUpgrade`/`openChest` | `_grant_room_clear_reward` now rolls real choices and shows `UpgradeSelectUI`, including the zone-luck bonus and the Sanctum's raised minimum rarity; `open_chest` now shows a real `RewardPopup` instead of a print. New `ui_root` field (set by `main.gd`, mirrors `Game.ts`'s own `uiRoot`) is where every modal/popup parents itself — deliberately not the world-space `parent` `start_new_run()` takes, since a `Control` under a `Node2D` room would render in world space, following the camera, not as a screen overlay |

**Also newly real, found while porting the above:** clearing the one
guaranteed elite den in the Ember Citadel (zone_index 2) now hands the
Bow over directly, on top of the room's normal reward — `grantRoomClearReward`'s
own logic in the source, never previously ported (masked by
`main.gd`'s own debug seeding already unlocking every weapon up front).

**Deliberately deferred, not forgotten:** the minimap, the toast/phase-
banner/synergy-banner system, the boss bar (needs the boss attack-FSM gap
closed first), both vignettes, `ShopUI`, `EventUI`, and `InventoryUI`. The
debug/diagnostic panel (`DebugLabel`/`LiveLabel`) still exists, hidden by
default — toggle with **F1**.

**How to test it:** same as before (HUD live-updating, F1 toggle, opening
a chest) — that part is now confirmed working via a real screenshot, not
just believed to. New this pass: clear a non-boss, non-sanctum room (kill
everything in it) and confirm a 3-card picker appears, pauses the action,
and picking a card actually changes your stats; clear the Ember Citadel's
elite den and confirm the Bow unlocks.

### Next steps (not started)

`ShopUI`, `EventUI`, and `InventoryUI` (Character tab for spending stat
points via the now-real `LevelFlow.spend_stat_point`, Build tab for owned
upgrades/synergies) — the upgrade-ownership system above was built to
unblock these too. Then the minimap/toasts/banners/vignettes deferred
above. `GODOT_MIGRATION.md`'s own Phase-A/Phase-B split (gameplay-
critical screens first, the MainMenu/PauseMenu/Settings/Victory/Credits
meta-shell after) is the intended order.
