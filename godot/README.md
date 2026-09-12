# Emberfall: Last Light — Godot rebuild

This is the Godot-side counterpart to the Web prototype in `src/` at the
repo root. Full context — what exists in the Web build, what should be
kept/improved/rebuilt, the recommended architecture, and the complete
12-step build order this project is following — lives in
[`GODOT_MIGRATION.md`](../GODOT_MIGRATION.md) at the repo root. Read that
first; this file only tracks what's actually been built here so far.

## Status: build-order step 10 of 12 — Audio (SFX complete; step 9/UI complete, including the Phase B meta-shell)

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
had no reachable trigger in this port at the time this step was built —
every TS call site was either the player's Ember Burst ability's damage
effect (`player.gd`'s `start_ability()` was animation-only then) or one of
the Ashen Colossus's phase attacks; the ability side is real now, wired
via `CombatManager.ember_burst_ability()` (see the "everything necessary"
pass at this README's end). This paragraph used to claim that surfaced a
real gap — "the boss has no attack FSM at all in this port" — reasoning
from `boss_state` having no visible trigger at the time this step was
written. Re-checked directly while writing the "everything necessary"
pass at this README's end: that claim was already stale by then. `boss.gd`
has a complete `BossState` enum (`INTRO`/`IDLE`/`TELEGRAPH_SLAM`/
`TELEGRAPH_COMBO`/`TELEGRAPH_SHOCKWAVE`/`TELEGRAPH_PROJECTILE`/
`SUMMONING`/`RECOVER`/`PHASE_TRANSITION`/`DYING`) with real telegraph-
timing logic that sets `pending_melee_slam`/`pending_shockwave`/
`pending_summon_count`, resolved every frame by `CombatManager.
resolve_boss_pending_actions()` into the slam/combo/shockwave/projectile/
summon attacks `GODOT_MIGRATION.md` describes — no dedicated pass needed,
this was integration glue away from working, not a missing system.
`spawnZoneAmbientParticle` (a continuous per-zone atmosphere effect,
technically `drawRoom.ts` not `ParticlePresets.ts`) reads `ZoneDefinition`
fields (`ambientParticle`, `sporeColors`, `palette.ambient`/`accent`) that
don't exist on this port's `ZoneDefinition` resource yet — left for a
dedicated atmosphere pass. (A handful of individual call sites of
otherwise-ported presets were unwired at this step because they were
gated on the shop/event UI or the reward-choice system — all resolved
once step 9 built those; see `vfx_presets.gd`'s own header.)

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

### Step 9 — UI (complete: every Phase-A gameplay-critical screen, the toast/banner feedback system, the minimap, both vignettes, and the boss attack-FSM + boss bar — landed and confirmed against a real running build)

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

**4. The shop** — the merchant's wares screen, opened from a shop room's
landmark:

| File | Ports | State |
|---|---|---|
| `ui/shop_ui.gd` | `ui/ShopUI.ts` | Modal like `UpgradeSelectUI`, but stays open across multiple purchases/rerolls instead of tearing down after one pick — mirrors the source's own `render()`/`renderList()` split: every Buy/Sold/Reroll click just rebuilds the offer list rather than closing. Real `Button` nodes for Buy/Reroll/Leave (this screen's first, everything before it used `UpgradeCard`'s own hand-rolled `_gui_input` clicking) with per-instance `StyleBoxFlat` overrides for normal/hover/pressed/disabled — still no shared Theme resource, same convention as every other screen |
| `autoload/run_state.gd` | `RunState.ts`'s `spendEmbers` | New `spend_embers(amount)` — fails without mutating if embers can't cover it, same shape as the existing `spend_stat_point` |
| `autoload/level_flow.gd` | `Game.ts`'s `openShopRoom` | New `open_shop_room(room)` builds the 3-upgrade-plus-heal offer list via the already-existing `Shop`/`ShopOffer` and shows it; the shop interact prompt (previously a "deferred to step 9" stub) now calls it for real |

Two real GDScript gotchas hit and fixed while building this, worth keeping
in mind for `EventUI`/`InventoryUI` next:
- **`Control`/`CanvasItem` already defines `show()`.** `ShopUI`'s first
  draft named its static factory `show(parent, offers, ...)`, matching the
  shape of `UpgradeSelectUI.show_choices`/`RewardPopup.show_reward` — but
  unlike those two, `show` collides with the built-in 0-argument
  `CanvasItem.show()`, which Godot treats as an override attempt and
  refuses to compile (signature mismatch). Renamed to `show_shop`, and
  every new screen's static factory should keep avoiding bare verbs
  (`show`/`hide`/`update`/etc.) that `Control`'s own ancestry already owns.
- **GDScript lambdas capture locals by value, once, at creation** — never
  by reference, and a captured local can't be reassigned from inside the
  lambda either (that only rebinds the lambda's own copy). `open_shop_room`
  needs a `reroll_count` shared and mutated across three sibling lambdas
  (`make_offers`/`on_reroll`, built once, called many times as the player
  rerolls); a plain `var reroll_count := 0` would have each lambda capture
  its own frozen snapshot, so `on_reroll`'s `+= 1` would never be visible
  to `make_offers`, and every reroll would silently reseed with count 0
  and return identical offers. Fixed by boxing it in a 1-element Array
  (`[0]`) instead — arrays are captured by value too, but that value is a
  reference to the same underlying data, so mutating *contents*
  (`reroll_count[0] += 1`, never reassigning the variable itself) stays
  visible across every lambda that captured it. See `open_shop_room`'s own
  comment for the full write-up.

Building this screen also surfaced (and fixed) a smaller, pre-existing gap
in `upgrade_select_ui.gd`: the TS source's own `UpgradeSelectUI` uses the
same `.screen-panel.wide.panel` class `ShopUI.ts` does, which draws a real
background/border/shadow behind the title and cards — the first Godot pass
never added that (easy to miss without a real panel elsewhere to compare
against; `UpgradeCard`'s own opaque background made its absence far less
obvious). Now wrapped in a `PanelContainer` with the same style as
`ShopUI`'s own panel.

**5. The event/shrine encounter** — the last of the room-landmark screens:

| File | Ports | State |
|---|---|---|
| `ui/event_ui.gd` | `ui/EventUI.ts` | Modal like the others, but with no Leave/Cancel — matches the source having none either; an encounter must be resolved by picking one of its (affordable) options. Each option is a `PanelContainer` (auto-sizes to its label/detail/cost text, which varies per event), not a `Button` — clicks come from `Control`'s own `gui_input` signal, which every Control already has, wired by hand instead of listening for a `pressed` a real Button would emit |
| `autoload/run_state.gd` | `RunState.ts`'s `usedEventIds` | New `used_event_ids: Array[String]` — a plain array, not a Set, since it never holds more than the 7 world events |
| `autoload/level_flow.gd` | `Game.ts`'s `openEvent`/`applyEventEffect` | New `open_event_room(room)` (rolls a zone-aware event the first time a room is opened, preferring one this run hasn't used yet) and `_apply_event_effect(option, room)` (all 10 `EventOption.EffectKind` branches — embers/HP/upgrade grants, the 50/50 embers gamble, Soul Ash, shield charges, max-HP, the two lose-HP-for-a-reward trades). The event interact prompt now calls it for real |

`_apply_event_effect` skips two details the source has that nothing in the
Godot port can call yet, same as every other screen this step: `playSfx(...)`
(no audio system exists yet — a separate, not-yet-started migration step)
and `camera.addShake(...)` on the `loseHpForEmbers` option (no camera-shake
utility has been ported either). Neither changes what the option actually
grants, only how it *feels* landing — worth remembering if a camera-shake
utility gets built later, since this is the one call site already waiting
for it.

A small layout lesson from this screen, useful for any future variable-
length modal (`InventoryUI` included): a `VBoxContainer`'s `alignment`
property centers its *own* stack within extra space on its primary axis,
not just cross-axis content — events range from 2-3 options with
descriptions of very different lengths, so the fixed-size panel often has
real slack; `ALIGNMENT_CENTER` distributes it evenly above and below the
title+description+options group instead of leaving it all as dead space
under the last option (the default top-packed behavior, confirmed to look
noticeably less finished via a real screenshot before this fix).

**6. The character sheet (`InventoryUI`)** — the last screen the upgrade-
ownership system was built to unblock, and by far the biggest so far:

| File | Ports | State |
|---|---|---|
| `ui/inventory_ui.gd` | `ui/InventoryUI.ts` | Two tabs (Character: Level/XP bar + the 7 stat-point rows; Build: active synergies + every owned upgrade), opened globally with **I** rather than via a room landmark. First screen with a `ScrollContainer` — the panel's chrome (title/tabs/Back) stays fixed while only the tab body scrolls, since both tabs' content is open-ended (0 to 25+ owned upgrades) unlike every previous screen's small fixed content |
| `ui/upgrade_card.gd` | (extended) | New `show_tags: bool` — the Build tab reuses this same card for owned upgrades but, like the source's own simpler Build-tab markup, with no tags row (level folds into the name line instead) and a shorter fixed height (`CARD_SIZE_NO_TAGS`) rather than the picker's taller one, which left visibly dead space below the description once the tags row was gone (confirmed, then fixed, via a real screenshot) |
| `autoload/level_flow.gd` | `Game.ts`'s `openInventory` + its own `update()`'s inventory-key branch | New `open_inventory_ui()` and `_check_inventory_key()`/`_check_inventory_key_down` (mirrors `_check_interact_key`'s own debounce). Unlike chest/shop/event, this key check runs unconditionally (not gated on room type or proximity) — matches the source checking `wasPressed('inventory')` globally too |

Two things worth flagging about this screen specifically:
- **It's a global keybind, not a room interaction** — the only step-9 modal
  opened this way so far. The source guards `openInventory()` with
  `if (this.modalScreen) return;` so pressing I on top of another open
  screen no-ops; the Godot port gets the same guarantee for free from
  `get_tree().paused` itself — `LevelFlow._physics_process` (where the I
  key is checked) simply doesn't run at all while any other modal has
  paused the tree, since the autoload was never marked
  `PROCESS_MODE_ALWAYS` the way the modals themselves are.
- **PauseMenu's own entry point stays deferred.** The source also opens
  this screen (on the Build tab) from a "Your Build" button in `PauseMenu`
  — that menu doesn't exist yet (Phase B), so `open_inventory_ui`'s
  `initial_tab` parameter has no second caller yet, kept for when it does.

**7. The toast/phase-banner/synergy-banner feedback system** — the first
step-9 work item that isn't a screen: three small, reusable pieces of HUD
feedback, wired into every existing gameplay moment that wants one, all
newly real this pass.

| File | Ports | State |
|---|---|---|
| `ui/hud.gd` | `HUD.ts`'s `showToast`/`showPhaseBanner`/`showSynergyBanner` | New `_build_banners()` (toast area, one reused phase-banner Label, one reused synergy-banner panel) plus the 3 public methods. First HUD feedback to use `Tween` instead of this file's usual manual `_process()` interpolation — CSS's multi-keyframe opacity+transform animations chain directly onto `tween_property()`/`tween_interval()`, which manual per-frame easing math doesn't buy anything over |
| `autoload/combat_manager.gd` | (new) | New `champion_shield_broken` signal, emitted from the existing `on_champion_shield_break` (which already did the bloat-spawn/VFX half of `Game.ts`'s `onChampionShieldBreak` — only the banner call was missing) |
| `autoload/level_flow.gd` | every `showToast`/`showPhaseBanner`/`showSynergyBanner` call site in `Game.ts` | New `hud` field (set by `main.gd`, same pattern as `ui_root`) plus calls added at: level-up, the elite-den Bow find, synergy formation (staggered 0.9s apart, matching the source — a single grant can complete more than one), resting at a brazier, a heart room's stairs unsealing, both halves of a zone transition (only the descent half also shows the delayed zone subtitle toast, matching the source), all three sanctum-rite beats (begins/wave N/done, the last with its reward toast), and the champion shield-break |

Two real Tween gotchas hit and fixed while building this — both confirmed
via small standalone scenes run through the same Godot+Xvfb setup (a
`print` timing log is a faster way to nail down animation-sequencing
questions than a screenshot is):
- **A Tween's `.position` is an absolute placement, not an animatable
  offset from wherever anchors put a Control.** Both banners' entrance/
  exit animations first tried animating `.position` for the CSS
  `transform: translateY(...)` slide effect — which instead teleported
  each banner to its parent's literal top-left corner the moment the
  animation started (confirmed via a real screenshot: the synergy banner
  landed on top of the HP bar). `.position` is a Control's fully-resolved
  placement, computed once from anchors+offsets; writing to it directly
  discards that computed placement rather than nudging it, and nothing
  re-triggers anchor resolution afterward to put it back. Fixed by
  animating `offset_top`/`offset_bottom` together instead (by the same
  delta, to preserve box height) — offsets stay anchor-relative the whole
  time, which is what a slide effect actually needs.
- **`set_parallel(true)` + `chain()` did not behave as documented.**
  The plan was: mark a block of tweeners parallel, `chain()` back to
  sequential for a hold `tween_interval()`, then `set_parallel(true)`
  again for the exit block. In practice the tweener added right after
  `chain().tween_interval(...)` fired at the same time as the FIRST
  tweener in an EARLIER parallel block, not after the interval — the
  "hold" collapsed to ~0s and every banner faded back out almost as soon
  as it finished fading in (confirmed both via a screenshot taken mid-
  animation, where the phase banner had already vanished, and via a
  standalone timing-log scene). The fix, verified the same way: never use
  `set_parallel(true)`/`chain()` at all — call the single-shot `.parallel()`
  as its own statement immediately before each tweener that should start
  alongside the one before it. `.parallel()` transitively chains (marking
  C parallel with B, itself parallel with A, correctly starts A/B/C all
  together), which is exactly what multi-property keyframes need.

**8. The minimap** — `refreshMinimap`'s "double-resolution" room-graph
grid, the last piece of `hud.gd` itself this step was waiting on.

| File | Ports | State |
|---|---|---|
| `ui/hud_minimap.gd` | `HUD.ts`'s `refreshMinimap` + its `.hud-minimap*` CSS | A new `HudMinimap` Control, drawn entirely via one `_draw()` (this project's usual approach for anything hand-drawn — see `hud_icon.gd`) rather than as a tree of child Controls in a CSS-Grid-equivalent container, since the real layout is sparse (most (col,row) slots are empty) and needs alternating room-sized/gap-sized tracks — neither fits `GridContainer`'s "N uniform columns" model. Room cells tint by type (reusing existing `Palette` tokens — every one of the source's 6 `MINIMAP_TINT` values turned out to already be an exact match for one), the heart/boss room draws as a rotated gold diamond and is always shown regardless of discovery, a "hint" cell (faint outline only) marks a room known-but-unvisited, and door connectors between two shown rooms tint ember when either end is the current room |
| `autoload/level_flow.gd` | (wiring) | New `_on_room_changed` connects to the already-existing `room_changed` signal (already fired from run start, every same-zone room entry, and both zone-transition landings) — one connection covers every real `refreshMinimap` call site in the source at once, rather than repeating the call by hand at each of those functions the way the source itself does |

Sizing/positioning reuses the exact `scale` + `pivot_offset` technique the
toast/banner fix above established: `HudMinimap` sets its own anchor
fractions once in `_ready()` (top-right of the HUD), then every `refresh()`
call only ever reassigns offsets (to a box sized to the current zone's
actual room-graph footprint) and `scale` (`min(1, MAX_PX / footprint)`,
matching the source's own "shrink large zones down, never grow small
ones" rule) — offsets and direct anchor/scale reassignment are both plain,
safe property writes even on an already-parented node (this project's own
bar-fill-ratio code has reassigned `anchor_right` every frame for 3 steps
now with no issue); only `set_anchors_preset()` itself has the "discards
the current rect" gotcha this step's HUD investigation first turned up.

**9. The vignettes** — `dangerVignette`/`corruptionVignette`, the last
pieces of `hud.gd` itself this step was waiting on besides the boss bar.

| File | Ports | State |
|---|---|---|
| `ui/hud.gd` | `HUD.ts`'s `dangerVignette`/`corruptionVignette` + their `.hud-*-vignette` CSS | New `_build_vignettes()` (called first in `_ready()`, ahead of every other region, matching the source's own "these two are the earliest children of `.hud`" stacking — corruption before danger, so danger paints on top where they'd overlap) builds both as a `GradientTexture2D`-backed `TextureRect` stretched full-screen: danger red (opacity climbs as HP drops below 35%, capped at 0.55; below 15% HP it pulses instead via a raised-cosine wave standing in for the source's own keyframes) and corruption purple (opacity = `RunState.corruption_ratio() * 0.4`, reusing the already-exact `Palette.SHADOW` token for its color instead of re-typing the same hex) |

**A real gap in this project's own toolbox, closed here.** Every earlier
gradient in this codebase (HP/stamina/energy/XP bar fills, chest tier
glows) simplified to a single flat color — this file's own header calls
that out as "no cheap gradient-fill primitive on a plain Control." A
radial vignette can't take that shortcut; the falloff *is* the whole
effect. `GradientTexture2D`'s `FILL_RADIAL` mode turned out to be exactly
the missing primitive: it treats `fill_from`/`fill_to` as a circle in the
texture's own square UV space, and stretching that square non-uniformly
onto a `TextureRect` (`stretch_mode = STRETCH_SCALE`) is exactly what
turns the circle into an ellipse matching the target box's own aspect
ratio — the same shape CSS's `radial-gradient(ellipse at 50% 50%, ...)`
draws. The one number worked out on paper rather than guessed: sizing
that circle's radius to `1/sqrt(2)` in UV space reproduces the source's
default `farthest-corner` sizing keyword exactly (both reduce to "an
ellipse scaled by `sqrt(2)` so it passes through the box's own corner") —
the gap between that and a naive radius-0.5 guess is the gap between the
color reaching full strength only at the four literal corners (correct)
versus already maxing out at the edge midpoints (a visibly harsher,
wrong-shaped vignette).

Verified carefully given this file's own explicit risk flag ("a botched
full-screen overlay risks making the game unreadable") — a real headless
run forced HP down to 21% (danger, non-pulsing) then 6% (critical,
pulsing — two screenshots ~0.55s apart confirmed via a PIL pixel-average
diff that opacity actually oscillates, not just a static guess that the
code *should*), then forced `corruption_ratio()` to its max, each checked
against a full-HP/no-corruption baseline. All four states stay readable —
only the screen's outer edges darken; the player, HUD, and minimap stay
legible throughout.

**9. The boss attack-FSM + boss bar** — the last piece: closing the gap
this file's own header had flagged since step 4 ("the boss currently
fights as a generic enemy with no slam/combo/shockwave/projectile/summon
attacks"), then the HUD readout that data makes possible.

| File | Ports | State |
|---|---|---|
| `entities/boss.gd` | `entities/Boss.ts`'s `tick`/`chooseNextAttack`/`updateMeteors`/`enterState`/`beginFight`/`takeDamage` override | The visual half (`_draw()`, `_update_light()`) was already landed here in an earlier step; this pass adds the actual FSM driving it — phase transitions at 64%/30% HP, 5 attack types (melee slam, 2-hit combo, shockwave, 3-shot projectile fan, summon), phase-3 meteor rain, and an own `_physics_process()` override (needed because the generic one — enemy.gd's — stops calling any AI at all once `alive` is false, but the boss's own dying state needs to keep ticking for its 2.2s death animation to finish) |
| `combat/enemy_ai.gd` | (dispatch) | `EnemyAI.update()` special-cases `BossCharacter` at its own top — routes to `boss.tick()` + `CombatManager.resolve_boss_pending_actions()` instead of the generic `Behavior`-keyed dispatch every other enemy gets (the boss's own `.tres` `behavior` value, `ELITE`, is never actually read once this branch exists — a placeholder from before this port had a real boss FSM) |
| `autoload/combat_manager.gd` | `combat/BossSystem.ts`'s `resolveBossPendingActions` | New `resolve_boss_pending_actions()` resolves the pending-action flags `tick()` sets each frame into real damage (reusing `damage_enemy_to_player`), projectiles (`spawn_enemy_projectile`), summons (`ashCrawler`/`shadowStalker`, spawned via `room.add_enemy` so `check_cleared()` still sees them), meteor impacts, and — gated on the ~2.2s death animation actually finishing, not just HP hitting 0 — a two-tone defeat fanfare. New `boss_phase_changed`/`boss_defeated` signals stand in for the source's own generic `gameEvents.emit(...)` calls (this port has no pub/sub event bus at all; every existing signal here already follows "declared on whichever autoload resolves that concern") |
| `vfx/vfx_presets.gd` | `rendering/ParticlePresets.ts`'s `spawnEmberBurstVfx` | New `ember_burst_vfx()` — previously unported for lack of a caller (this file's own header said so explicitly); now wired to all 3 of the boss's impact types |
| `autoload/level_flow.gd` | (wiring) | The boss's own `beginFight()` is gated on the Web build's intro/roar presentation beat, which this port has no cutscene system to reproduce — a plain fixed delay stands in instead, paired with an intro phase banner naming the boss, so the room-entry moment still reads as an event and the boss isn't instantly attacking the instant the door seals. `boss_phase_changed`/`boss_defeated` get their own banners ("PHASE 2", "THE ASHEN COLOSSUS FALLS"), same `show_phase_banner()` mechanism as every other beat |
| `ui/hud.gd`, `scenes/main/main.gd` | `HUD.ts`'s `bossBar`/`bossName`/`bossFill`/`bossDots` + `Game.ts`'s own boss branch of `updateHud()` | A new top-center bar (name, HP fill, phase-remaining dots — ports the source's own `i < maxPhase - phase + 1` dot math exactly) shown only while `main.gd`'s new `_boss_hud_data()` finds a live `BossCharacter` in the current room |

Camera shake, hit-stop, and SFX from `BossSystem.ts` are deliberately NOT
ported — `combat_manager.gd`'s own header already flags this as a
whole-game gap predating the boss (no such system exists anywhere in this
port yet), so building one just for the boss's own attacks would be
inconsistent with every other hit in the game still lacking the same
polish. Left for that dedicated pass.

Verified via a real headless run that warped straight to a forced zone-2
boss room (rather than playing 3 zones to reach it) and exercised every
state by hand: intro banner and delayed `begin_fight()`, a real phase-1
attack cycle that actually landed damage on the (stationary) player and
fired real projectiles, a phase-1 `SUMMONING` roll that spawned two real
chasing adds entirely on its own (not forced), a forced HP drop crossing
the 64% threshold confirmed via screenshot to show the invulnerability
glow, the phase banner, and the boss bar's dots correctly depleting
3-lit → 2-lit → 1-lit across phases 1/2/3 (pixel-zoomed to check, not just
eyeballed), a forced phase-3 entry to confirm the meteor-telegraph code
path doesn't error, and a forced death that correctly gated the two-tone
defeat fanfare and "THE ASHEN COLOSSUS FALLS" banner on
`death_animation_done`, not the instant HP hit 0. No script errors from
any of it. The debug/diagnostic panel (`DebugLabel`/`LiveLabel`) still
exists, hidden by default — toggle with **F1**.

**How to test it:** same as before (HUD live-updating, F1 toggle, opening
a chest, clearing a room for the 3-card picker, browsing the shop, an
event's shrine, the character sheet, every toast/banner) — all confirmed
working via real screenshots, not just believed to. New this pass: check
the minimap appears top-right below the corruption bar, the current room
shows a bright ring, room types you've found tint correctly (chest gold,
shop frost-blue, elite blood-red, event toxic-green, rest ember,
sanctum fungal-teal), a room one door away but not yet entered shows only
a faint outline, the heart/boss room shows as a gold diamond from the
start (never hidden), connectors between discovered rooms light up ember
only where they touch the room you're standing in, and — in a zone with
enough rooms to exceed the "mini" footprint — the whole thing shrinks
down rather than growing past its corner. Also new: at low HP the screen
edges should darken red (stronger as HP drops further, pulsing once
below ~15%), and as a run drags on past the corruption soft cap the edges
should also pick up a purple tint — both stay a background read, never
cover the actual play area. Newest this pass: reach the Ember Citadel's
Colossus room (zone 3) and the boss should sit still and invulnerable
for a couple seconds under an intro banner before actually fighting —
approaching, telegraphing (a ring for slam/combo, a pulsing wider ring
for shockwave, a brief pause with no visible tell for the 3-shot
projectile fan — matches the source), occasionally summoning adds or
raining meteors once in phase 3. A top-center bar should track its name,
HP, and phase (dots depleting left-to-right as phases pass); crossing a
phase threshold should glow the boss briefly invulnerable and show a
banner; killing it should hold on its shrink-and-fade for ~2 seconds
before "THE ASHEN COLOSSUS FALLS" and a bigger burst than a normal kill.

### Phase B — the meta-shell (in progress)

Every in-run screen (Phase A) is done. Phase B wraps a run: MainMenu,
PauseMenu, Settings, Victory/Defeat, Credits, and the Armory (permanent
upgrades + weapon/ability unlocks), per `GODOT_MIGRATION.md`'s own
Phase-A/Phase-B split. Landing in ordered slices rather than one pass —
each slice is a real, tested, working state of the game, not a partial
screen with dead buttons.

**Slice 1 — meta-progression + run-stats foundation.** Pure data/logic,
no new screens: `MetaProgression`'s real permanent-upgrade cost/afford/
purchase logic and `get_permanent_stat_modifiers()` (ports
`MetaProgression.ts`, never carried over before — nothing needed it),
unlock purchase/afford + weapon/ability-id resolution, a `settings`
Dictionary, hint tracking, `last_seed`; `RunState.add_embers`/
`record_kill`/`record_damage_dealt`/`record_damage_taken`/
`record_upgrade` (ports `RunState.ts`'s own already-centralized methods,
also never carried over), wired at the natural existing hook points
(`CombatManager`'s damage pipeline and `on_enemy_death`, pickup
collection, the upgrade-grant funnel).

**Slice 2 — MainMenu, Victory/Defeat, Credits, and the real GameState
machine.** The single biggest structural change so far: the game used to
boot straight into a run (`main.gd`'s own header used to say so
explicitly) with `GameState`'s stack machine fully ported but never once
called anywhere in the whole port — confirmed by a project-wide grep
during this slice's own research pass, zero call sites for
`change_state`/`push_state`/`pop_state` outside the autoload's own
definitions. Now:

| File | Ports | State |
|---|---|---|
| `ui/menu_ui_kit.gd` | style.css's shared `.screen-overlay`/`.screen-panel`/`.btn*`/`.button-row`/`.button-column` primitives | New shared `MenuUiKit` — every other screen this project has built keeps its own private copy of this kind of helper (fine at 2-3 files), but 7 meta-shell screens all wanting the exact same overlay/panel/button chrome is a different scale of duplication, so this one case gets a shared module (the same reasoning already applied to `DrawUtils`/`VfxPresets`/`VfxSystem` for their own cross-cutting concerns) |
| `ui/main_menu_ui.gd` | `ui/MainMenu.ts` | Title, seed field (typed text only so far — no `?seed=` URL param to pre-fill from), Play/Upgrades/Armory/Settings/Credits buttons. The rising-ember canvas animation is rewritten against `GPUParticles2D` rather than ported line-by-line (GODOT_MIGRATION.md §4: particles are a rewrite, not a port, case — same call this project's own step 8 already made) |
| `ui/victory_defeat_ui.gd` | `ui/VictoryScreen.ts`'s own `VictoryScreen` + `DefeatScreen` | One file, two static factories, not two classes — the source's own two classes are already near-identical (same stat-grid, seed label, panel chrome; only title/subtitle copy and button count differ), which doesn't earn a second class here either |
| `ui/credits_ui.gd` | `ui/CreditsScreen.ts` | Static text panel; the "tech" line is adapted (Godot Engine/GDScript), not translated verbatim — the source's own line names TypeScript/Vite/Canvas2D/Web Audio, which would be factually wrong here |
| `autoload/game_state.gd` (no changes — just finally called) | `core/GameStateMachine`'s real transitions | `main.gd` now calls `change_state` at every point the source's own `Game.ts` does: boot → `MAIN_MENU`, Play → `RUN_START` → `EXPLORATION`, boss-defeated/player-died → `VICTORY`/`DEFEAT`. `EVENT`/`SHOP`/`COMBAT` stay unentered for now (Shop/Event already work correctly as pause-gated modals with no state-machine dependency; a boss room sets `BOSS`... not yet either — deferred to the same follow-up as PauseMenu, see below) |
| `scenes/main/main.gd` | `core/Game.ts`'s own top-level orchestration (`showMainMenu`/`startNewRun`/`endRun`) | Rewritten from a direct `_start_run()` boot into a real screen orchestrator: `_show_main_menu()`/`_begin_run()`/`_end_run()`, a `_current_screen` slot mirroring the source's own single `modalScreen` (closed before the next screen opens — a real bug caught here, not guessed: the first working draft never freed the previous end screen, so "Try Again" would leave Defeat's own panel sitting on top of the new run), and the exact Soul Ash formula (`kills*0.6 + eliteKills*4 + (victory?70:0) + embers*0.08`) |
| `autoload/level_flow.gd` | (new) | `start_new_run()` now frees every room the PREVIOUS run created before generating fresh ones — GODOT_MIGRATION.md §6's own explicit warning ("stale nodes... a GC-free engine won't clean up for you"); the first-ever call has nothing to free (`RunState.layouts` starts empty) so this needed a second run to actually exercise and catch |

Permanent-upgrade modifiers are applied for real now too: `_begin_run()`
bakes `MetaProgression.get_permanent_stat_modifiers()` into the player's
`base_stats` *before* the node enters the tree, so `player.gd`'s own
`_ready()` → `recompute_stats()` picks them up on its first pass with no
second manual recompute needed. `unlocked_weapons`/`unlocked_abilities`
now start from the player's own real baseline (`["emberBlade"]`/
`["emberBurst"]`) plus whatever's actually been purchased, replacing the
old hardcoded "all 4 weapons" debug seed — the Q-cycle debug stand-in
(still no real loadout-selection screen — `LoadoutSelectUI`, not built
yet) now cycles through what's genuinely unlocked instead.

Two real bugs found and fixed by actually running this, not just reading
the diff:
- **`GPUParticles2D` has no `mouse_filter`** (that's `Control`-only —
  this node is a `Node2D`) — assigning it threw a script error that
  silently aborted the rest of `_build_ember_particles()` before
  `emitting = true` or `add_child()` ever ran, so the very first screenshot
  showed no ember background at all, not a broken one.
- **`DrawUtils.glow_texture()`'s native size is 256×256px** (its own doc
  comment: "texture_scale = desiredRadius / 128.0") — every other call
  site divides by 128 first; this one didn't, and a `scale_min/max` of
  `1.0`-`2.6` turned each of the 46 motes into a 250+px blown-out circle,
  confirmed via a real screenshot showing the entire lower half of the
  screen as one saturated white mass. Fixed to `0.02`-`0.05` (a ~5-13px
  dot, matching the source's own small mote size) and reconfirmed via a
  second screenshot.
- (A third, non-visual layout bug: `VBoxContainer` stretches a plain
  child to its own full width regardless of `custom_minimum_size` — the
  MainMenu's button column and seed field rendered full-screen-wide until
  `size_flags_horizontal = SIZE_SHRINK_CENTER` was added to both.)

**Verified** via a real headless run: menu boots and renders (particles
included, after the fixes above), Play starts a real run (HUD visible,
room populated, weapon/ability correctly show the real baseline), a
forced player death correctly shows Defeat with the right zone name and
a real stat grid, Try Again correctly starts a **second** run with no
orphaned-node errors (the room-cleanup fix, actually exercised), a forced
boss-defeat correctly shows Victory, and `MetaProgression.lifetime_stats`
correctly accumulated across both runs (`runs_started`, `runs_won`,
`total_deaths`, `best_time_seconds`, `total_soul_ash_earned` all checked
against the exact expected formula, not just "looked fine").

**Slice 3 — PauseMenu + Settings.** Escape now opens a real pause menu
mid-run, and Settings exists both as MainMenu's own standalone screen and
embedded inside Pause — matching `SettingsMenu.ts`'s own `embedded`
constructor parameter exactly, one implementation, not two.

| File | Ports | State |
|---|---|---|
| `ui/pause_menu_ui.gd` (new) | `ui/PauseMenu.ts` | True modal like Shop/Event/Inventory/UpgradeSelectUI (`get_tree().paused` + this root's own `process_mode = ALWAYS`). Three views swapped by requeuing `_content_holder`'s children — the same convention already used for HUD's shield pips and the boss bar's phase dots — rather than three separate scenes: main (Resume/Your Build/Settings/Abandon Run), a confirm-abandon step, and Settings rendered inline via `SettingsUI.show_settings(_content_holder, true, _render_main)` |
| `ui/settings_ui.gd` (new) | `ui/SettingsMenu.ts` | All 12 source rows, built for real: language (segmented), master/music/sfx volume (sliders), mute + screen shake (toggles), particle + graphics quality (segmented), text scale (slider), high contrast + reduced motion (toggles), fullscreen. Every control writes straight to `MetaProgression.settings` and saves immediately — same "each mutation is its own synchronous save" convention the rest of `meta_progression.gd` already uses |
| `ui/menu_ui_kit.gd` | style.css's `.toggle`/`.segmented-control` | Two new shared primitives: `make_toggle(initial)` and `make_segmented(options, labels, selected, on_pick)`, plus a `chrome: bool` parameter added to the existing `make_panel()` (see bug below) |
| `scenes/main/main.gd` | `Game.ts`'s pause input handling | Escape polled the same way F1 already is (`Input.is_physical_key_pressed`, no input-map action needed); the triggered logic lives in its own `_try_open_pause()` method rather than inline in `_process()`, both because that's the natural place for the guard logic (`GameState.is_in([...]) and not get_tree().paused`, porting `Game.ts`'s own `pauseGame()` guard) and because it makes the logic directly callable from a test without fighting physical-key-state simulation under headless Xvfb |

Only **fullscreen** (`DisplayServer.window_set_mode()`) and the
persistence itself do anything real yet. Volumes, mute, screen shake,
particle/graphics quality, text scale, high contrast, reduced motion, and
language all store a real, saved value with nothing yet consuming it —
this port has no audio system, no quality-tier rendering path, no
accessibility system, and (confirmed via a project-wide grep this slice:
no `TranslationServer`, no `i18n`, no `locale`) **no i18n system at all**
— the French localization work referenced elsewhere in this project's
history was TS-only, never ported; every Godot-side string in every
screen this project has built, this one included, is English-only today.
Exactly the same "camera shake/hit-stop/SFX" kind of honest, documented
gap this project already carries from the boss work, not a new one
invented here — storing the value now means the day one of those systems
lands, it reads a real saved preference instead of needing a migration.

One real bug found and fixed by actually running this, not just reading
the diff: **the embedded Settings panel lost its centering.** The first
draft branched `if embedded: add_child(content) else:
add_child(MenuUiKit.make_panel(content, false))` — skipping `make_panel()`
entirely when embedded, which correctly skipped the panel's own
background chrome but *also* lost its centering anchors, since both lived
in the same call. A real screenshot showed the embedded Settings panel
pinned to the top-left corner, overlapping the HUD, instead of centered
over Pause's backdrop. Fixed by giving `make_panel()` a `chrome: bool`
parameter that keeps centering unconditional and only makes the
background conditional (a `StyleBoxEmpty` with matching content margins
in place of the `StyleBoxFlat` when `chrome=false`) — ports style.css's
own `screen-panel${embedded ? '' : ' panel pop-in'}` pattern precisely
(only the background/pop-in classes are conditional; the base class's own
centering never is). Reconfirmed via a second screenshot.

**Verified** via a real headless run: Settings opens standalone from
MainMenu and embedded from Pause (post-fix, correctly centered in both);
a slider drag and a toggle click both wrote through to
`MetaProgression.settings` and persisted; Escape mid-run correctly pushes
`GameState.PAUSED` and pauses the tree while Pause's own UI keeps
responding to clicks; Pause → Settings → Done correctly returns to
Pause's main view (not MainMenu); Pause → Abandon Run → confirm → Abandon
correctly pops back to `GameState.DEFEAT` with the tree unpaused again.

**Slice 4 — the Armory + the real loadout picker (Phase B complete).**
MainMenu's Upgrades/Armory buttons now open a real screen, and a run's
starting weapon/ability is chosen through an actual UI instead of the
Q-cycle debug stand-in from build-order step 5 — which this slice
removes outright (`player.gd`'s `cycle_weapon()` and its Q-key poll),
since the real flow now exists everywhere Q-cycle stood in for it.

| File | Ports | State |
|---|---|---|
| `ui/armory_ui.gd` (new) | `ui/MetaProgressionMenu.ts` | One panel, two tabs (Upgrades/Armory) sharing one Soul Ash balance and one scrolling row list — switching tabs swaps both the row list AND the title/subtitle/active-tab styling, matching the source's own single `render()` rebuilding everything on `switchMode`. Upgrade rows show the real `requires`-gated lock state (dimmed, "Locked", the blocking upgrade's own name in the description) and a level-pips row; Armory rows resolve a weapon/ability unlock's description from the real `WeaponDefinition`/`AbilityDefinition` it points to (`ref_id`), exactly like `MetaProgressionMenu.ts`'s own `detail` lookup |
| `ui/loadout_select_ui.gd` (new) | `ui/LoadoutSelectUI.ts` | Weapon/ability cards the player can click to change selection before confirming; reuses `MetaProgression`'s own already-built `get_unlocked_weapon_ids()`/`get_unlocked_ability_ids()` (slice 1) rather than adding a second lookup path |
| `scenes/main/main.gd` | `Game.ts`'s own `startNewRun` gate | `_begin_run()` now builds the room and player first (unchanged order), then only shows `LoadoutSelectUI` when `unlocked_weapons.size() > 1 or unlocked_abilities.size() > 1` — ports the source's `weapons.length > 1 \|\| abilities.length > 1` check exactly; with nothing purchased yet, a run still begins immediately with no screen in the way, same as today. `_confirm_loadout()` (mirrors the source's own `begin()` closure) applies the chosen ids and only then flips `GameState` to `EXPLORATION` |
| `entities/player.gd` | — | `cycle_weapon()` and its Q-key edge-detect state removed — it was always documented as "debug-only... the real equip flow is LoadoutSelectUI.ts's own screen", and that screen now exists, so the stand-in doesn't linger as a second, undocumented way to change weapons the source has no equivalent for |

One real bug found and fixed via a real screenshot, a new variant of a
bug this project has already hit once before: a card's icon badge,
built exactly like every other icon badge in this project (a plain
`Control` sized 36×36 holding a full-rect background + an absolutely
positioned icon), rendered as a full-width bar with the icon stranded in
its corner instead of a clean square. Every *working* badge in this
project sits inside an `HBoxContainer` row; `LoadoutSelectUI`'s card is
the first to build one inside a `VBoxContainer` column — and a
`VBoxContainer` stretches a plain child across its own full width by
default, the exact same gotcha that hit MainMenu's button column in
slice 2, just on a new element. Fixed with the same fix:
`size_flags_horizontal = SIZE_SHRINK_BEGIN` on the badge. Caught by
zooming into the actual screenshot rather than trusting a full-window
thumbnail — at normal scale the misplaced badge was small enough to miss.

**Verified** via a real headless run: bought a real Armory weapon unlock
(Soul Ash deducted, `get_unlocked_weapon_ids()` picked it up immediately)
and a real permanent upgrade (level 0→1, cost deducted, a `requires`-locked
row correctly refused the same click and left both level and balance
unchanged); Back correctly returns to MainMenu; Play then correctly opened
the loadout picker (two unlocked weapons now), reselecting a card updated
the highlighted choice, and Begin carried that exact choice through
`_confirm_loadout` into the live HUD — the run's weapon readout showed the
picked weapon, not the default.

Every screen `GODOT_MIGRATION.md`'s Phase A/Phase B split calls for is now
built and wired: MainMenu, PauseMenu, Settings, Victory/Defeat, Credits,
and the Armory. **Not built yet, and out of scope for Phase B**: the
underlying systems several of these screens already store real,
persisted-but-inert preferences for — audio, quality tiers, accessibility,
and i18n (see Settings' own header comment) — each its own future phase,
not a UI gap.

### Step 10 — Audio (SFX engine, every real trigger site, and the generative score — complete)

`GODOT_MIGRATION.md` §4 frames audio as an explicit fork: bake each
procedural SFX to a `.ogg` once and play it back with a normal
`AudioStreamPlayer` ("simplest, most reliable"), or port the oscillator/
envelope/filter math to `AudioStreamGenerator` and synthesize at trigger
time ("a real rewrite, not a port"). This project has never shipped a
single binary asset — every wall, icon, particle and piece of UI chrome
across all nine build-order steps so far is procedurally drawn, precisely
because there's no editor here to author or preview one against. That
same reasoning applies to audio: baking would be the first binary asset
in the whole Godot port, and there's no more ability to *listen* to a
baked file here than to a synthesized one — so baking's real advantage
(avoiding runtime DSP bugs) doesn't buy back the thing this environment
actually lacks. **Chose synthesis.**

| File | Ports | State |
|---|---|---|
| `audio/audio_synth.gd` (new) | `audio/SoundFactory.ts`'s `tone()`/`noise()` | Renders a complete buffer per call up front rather than streaming — every SFX in this game is under 2 seconds, so the "ring-buffer refill" cost GODOT_MIGRATION.md warns about doesn't apply; AudioEngine pushes the finished buffer to an `AudioStreamGeneratorPlayback` in one `push_buffer()` call. Frequency/amplitude exponential ramps are one `pow()` call plus a per-sample multiply, not a `pow()` per sample. `noise()`'s sweeping bandpass/highpass/lowpass filter is a textbook RBJ "Audio EQ Cookbook" biquad — the same formulas the Web Audio spec itself cites for `BiquadFilterNode`, recomputed every 64 samples (inaudibly coarse) rather than every sample |
| `autoload/audio_engine.gd` (new) | `audio/AudioEngine.ts` + all 51 of `audio/SoundFactory.ts`'s `SfxId`s | Master→{Music, SFX} bus graph with a brickwall `AudioEffectLimiter` on Master (the source's own comment already calls its 20:1 `DynamicsCompressor` a "brickwall limiter" — Godot has a purpose-built node for exactly that intent, used instead of hand-chasing a Web-Audio-specific node's parameters). SFX play through a fixed pool of 24 pooled `AudioStreamPlayer` voices (round-robin stealing only once every voice is genuinely busy) rather than Web Audio's unbounded per-call node graphs — every real commercial game caps simultaneous voices for the same reason. Every one of the 51 SFX definitions is a direct, near-literal transcription of the source's own `players` record, one function each, calling shared `_tone()`/`_noise()`/`_sub()` helpers that take a Dictionary of named options (mirroring `ToneOpts`/`NoiseOpts` verbatim) rather than a long positional-argument signature — with 90+ individual `tone`/`noise` call sites to transcribe, a keyword-shaped call that reads like the TS object literal it ports was worth the small extra verbosity to get right the first time |
| `autoload/meta_progression.gd` | — | New `settings_changed(patch)` signal, emitted from `save_settings()` — AudioEngine (and any future consumer) reacts live to a volume/mute change instead of polling |
| `ui/settings_ui.gd` | — | Header comment updated: Master/Music/SFX Volume and Mute All move from the "honest gap" list to the "real, immediate effect" list, alongside Fullscreen |

**Verified** via a real headless run (no audio device exists in this
environment — `AudioServer` falls back to Godot's own dummy driver, same
as it has every other test this whole session; nothing here can be heard,
only exercised): bus graph is 3 buses (Master/Music/SFX) with the limiter
present; default bus volumes match `linear_to_db()` of the settings'
own defaults to two decimal places; raw `generate_tone()`/`generate_noise()`
buffers are finite (no NaN/Inf) with peak amplitude in the expected range;
triggering a single-layer SFX (`uiClick`) occupies exactly one pooled
voice, a two-layer SFX (`attackSwing`, noise+tone) occupies exactly two;
a same-ID retrigger inside the 25ms throttle window is correctly dropped
(confirmed against `Time.get_ticks_msec()`, not scene-tree time — under
`--quit-after`'s unthrottled frame rate, many seconds of scene-tree time
can elapse within a handful of real milliseconds, so only a real
wall-clock delta proves the throttle actually fired rather than just
having "enough nominal time" pass); voices correctly return to the free
pool once their sound finishes, with no leak; and a live
`MetaProgression.save_settings()` call updates the Master bus's mute
state and dB level immediately, with no restart needed.

**Slice 2 — every real trigger site.** The TS source calls `playSfx(...)`
at 75 call sites outside `SoundFactory.ts` itself — 39 in `Game.ts`, 16 in
`CombatSystem.ts`, 7 in `BossSystem.ts`, the remaining 13 spread across
`ShopUI.ts`/`InventoryUI.ts`/`MetaProgressionMenu.ts`/`UpgradeSelectUI.ts`/
`EventUI.ts` — and they're deliberately *not* uniform (only 3 of the 9
screens in `src/ui/` play a click sound on a button at all; a blanket
"every `MenuUiKit.make_button()` press plays `uiClick`" shortcut was
considered and rejected specifically because it would add feedback the
source's own design leaves several screens without). Wired faithfully by
walking each of those 8 source files and replicating its own actual call
sites — not inferring a pattern — in the matching Godot file:
`combat_manager.gd` (melee/ranged attacks, every branch of the
player↔enemy damage pipeline, bloat/warden combat beats, the champion's
shield-shatter, boss pending-action resolution), `level_flow.gd` (doors,
stairs, zone arrival, the sanctum rite, chest/rest/event interactions,
room-clear rewards, synergy formation, level-ups, stat-point spends,
E-interact), `enemy_ai.gd` (a warden's bash windup, a bloat's swell —
the latter needed the same before/after `state` comparison the existing
attack-trigger check already made, not a new mechanism), `pickup_node.gd`
(ember/heart collection), `player.gd` (dodge), `main.gd` (pause), and
five UI screens (`shop_ui.gd`, `inventory_ui.gd`, `upgrade_select_ui.gd`,
`event_ui.gd`, `armory_ui.gd`) — 71 of the 75 wired at the time, the
remaining 4 correctly left silent because the system they'd trigger from
didn't exist yet in this port: 2 of Game.ts's own ability-effect calls
(Warding Sigil, Stormstep) and a synergy-triggered detonation SFX
(emberCritical's own, since synergy *effects* weren't wired into the
damage pipeline yet) are all real now — see the "everything necessary"
pass at this README's end. Only one legacy no-stairwell `advanceZone()`
fallback path stays silent, correctly: Godot's own `get_interaction()`
never offers that path to begin with (already noted in that function's
own comment before this slice).
One genuine two-layer case, replicated rather than "simplified" away:
spending a stat point plays `uiClick` from inside
`LevelFlow.spend_stat_point()` (the core-logic level, matching
`Game.ts`'s own `spendStatPoint`) *and* `shopBuy` from
`InventoryUI.ts`'s own click handler on top of it — two sounds
layered on one click in the source, not a bug to collapse into one.

**Verified** via a real headless run exercising the actual call sites,
not just a code read: every one of the 44 distinct SfxId strings used
across this slice checked against `AudioEngine`'s own `_players`
dictionary (0 unknown — no typos); a real melee attack occupied exactly
2 voices (`attackSwing`'s noise+tone layers); a real (forced, non-dodging,
unshielded) hit correctly took the `playerHurt` branch; a forced kill
correctly resolved through `on_enemy_death`; a real door crossing
(teleporting the player to a door-bearing wall and letting
`_check_door_crossing()`'s own physics-process pick it up) actually
changed rooms; Pause correctly paused/unpaused; and
`LevelFlow._chest_sound_for()` mapped all 5 `UpgradeDefinition.Rarity`
values to the exact TS `chestSoundFor()` output
(`common`/`uncommon`→`chestOpenCommon`, `rare`→`chestOpenRare`,
`epic`→`chestOpenEpic`, `legendary`→`chestOpenLegendary`).

**Slice 3 — MusicEngine, the generative score.** `MusicEngine.ts`'s drone
is the one place in this whole audio port that genuinely can't use the
"render one buffer up front" trick `AudioSynth` relies on for every SFX —
it has no fixed duration, so it has to be topped up forever. `autoload/
music_engine.gd` runs 3 continuous voices (two detuned sawtooths a chord's
root/fifth, one sine an octave down) through a shared lowpass on a new
"Drone" bus, each refilled every `_process()` frame from a **persistent,
never-reset phase accumulator** — the same reason `AudioSynth`'s one-shot
generation accumulates phase per sample rather than recomputing it from
`t`: resetting it on every refill would leave an audible phase-discontinuity
click at every buffer boundary. A sparse tension layer (plucks on a scale,
a filtered noise pulse at max intensity, mood-1-only water drips) reuses
the exact pooled-voice/generation-counter pattern `AudioEngine` already
established in Slice 1, just an 8-voice pool instead of 24. Every
`setTargetAtTime` glide in the source (filter cutoff, chord frequency,
tension volume) ports as the same one-line exponential-approach
recurrence, `_approach()`, computed once per frame rather than modeled as
a real Web-Audio automation curve.

The one Web Audio idiom with no direct Godot node is `tensionGain` — a
live `GainNode` every tension-layer one-shot is routed *through*, so it
gets scaled by whatever that gain happens to be the instant it plays.
Godot has no per-voice gain automation for a playing `AudioStreamPlayer`,
but a **bus's own volume** affects every voice currently routed through it
identically to a live `GainNode` — so the new "Tension" bus's volume is
continuously animated by the same `_approach()` call the source uses for
`tensionGain.gain`, and every pluck/pulse voice is simply routed to that
bus. Same audible result, zero per-voice bookkeeping.

| File | Ports | State |
|---|---|---|
| `autoload/music_engine.gd` (new) | `audio/MusicEngine.ts` | 3-oscillator drone (Drone bus + shared `AudioEffectLowPassFilter`) + pooled tension plucks/pulse (Tension bus, its volume standing in for `tensionGain`) + mood-1 water drips (straight to Music bus). `start()`/`stop()` idempotent; `set_intensity()`/`set_mood()` retarget without restarting the drone |
| `autoload/audio_synth.gd` | — | Added `waveform_sample()`, a public wrapper around the existing `_waveform()` — MusicEngine's per-frame drone refill needs a single raw sample, not a whole enveloped buffer, so it calls straight into the same waveform table `generate_tone()` already uses |
| `autoload/level_flow.gd` | `Game.ts`'s private `syncCombatState()` | New `_sync_combat_state()` — see below |
| `scenes/main/main.gd` | `Game.ts`'s `music.start()`/`setMood(0)`/`setIntensity(0)` call sites | `MusicEngine.start()` unconditionally in `_ready()` (the source's own `music.start()` is one-shot-gated behind the *first* pointer/key event purely to satisfy browser autoplay policy — `AudioStreamGenerator` has no such restriction, so starting the score on boot is the faithful port of "plays for the whole session," not of the browser workaround around it); `set_mood(0)` in `_begin_run()`, `set_intensity(0)` in `_confirm_loadout()`, both in `_end_run()` |
| `project.godot` | — | `MusicEngine` autoload registered after `AudioEngine` |

**A genuine pre-existing gap, found while wiring `setIntensity`.**
`GameState.State.COMBAT` and `.BOSS` were never set anywhere in this port
— a project-wide grep turned up zero call sites, the same class of gap
`GODOT_MIGRATION.md`/this README already flagged once before ("GameState
fully ported but never called"). The reason it never mattered before now:
nothing previously *read* `GameState.current` for anything gameplay-
critical. `music.setIntensity()` is the first thing that does, and the
source ties it directly to the same function that drives the state
machine — `syncCombatState()` sets both together, in one place, every
time. Porting anything less than the whole function (e.g. a Godot-only
"just call `set_intensity` from wherever" shortcut) would have left
`GameState` with the same gap it already had; `_sync_combat_state()` is a
line-for-line port of the source instead, wired into the exact 6 real
call sites `syncCombatState()` has in `Game.ts` (`enterRoom`,
`completeDescent`/`completeAscent`'s shared landing helper, `beginRite`,
`updateRite`, `completeRite`, and the room-clear branch of the main
update loop) — boss room → `BOSS`/intensity 2; the sanctum rite or an
uncleared combat/elite/heart room with a live enemy → `COMBAT`/intensity
1; otherwise → `EXPLORATION`/intensity 0, matching the source's exact
3-way branch.

**One real bug, found by the first real playback check, not a code
read.** `_setup_voice_pool()` called `get_stream_playback()` on each
continuous voice immediately after creating it — before that player had
ever had `.play()` called on it. Godot logs "Player is inactive. Call
play() before requesting get_stream_playback()" and hands back `null` in
that case; `_refill_continuous()` already had a defensive `if playback ==
null: return phase` guard, so nothing crashed — the drone would have just
played 3 correctly-`.playing == true` voices of pure silence, forever,
with no error after boot to point at why. Godot's own docs example for
`AudioStreamGenerator` fetches playback *after* `play()`; the fix moves
the 3 `get_stream_playback()` calls out of setup and into `start()`,
right after its own `play()` calls — and since a fresh `play()` hands back
a fresh playback object, this also makes a `stop()`-then-`start()` restart
correct, not just first boot.

**Verified** via a real headless run: bus graph now 5 buses (Master,
Music, SFX, Drone, Tension) with the lowpass filter attached to Drone;
after `start()`, all 3 drone voices report `playing == true` *and* — the
check that actually matters, post-bugfix — a non-null, non-empty playback
object whose ring buffer sits fully topped up (`get_frames_available() ==
0`) after 30 frames, with the phase accumulator having advanced into the
hundreds of radians, proving real samples are continuously being pushed,
not just that the player looks active; directly driving
`LevelFlow._sync_combat_state()` against a synthetic room (flipping
`type`/`cleared`/`ritual_active`/a fake enemy's `alive` by hand) correctly
produced all 4 branches — `BOSS`/intensity 2, `COMBAT`/intensity 1 for
both a live-enemy combat room and an active sanctum rite, `EXPLORATION`/
intensity 0 once the enemy died or the rite went inactive; `set_mood(1)`
correctly swapped in `RUINS_PLUCK_SCALE`; and a `stop()`/`start()` cycle
correctly silenced then correctly revived all 3 drone voices.

Every system `GODOT_MIGRATION.md`'s recommended build order calls for
through Step 10 is now built, wired, and verified.

### Step 11 — Save system hardening (complete)

`GODOT_MIGRATION.md`'s own framing for this step — "port `SaveSystem.ts`'s
validation/migration logic onto `FileAccess`/`JSON`" — undersold it.
`MetaProgression.load_save()` already existed (it's had to, since
Settings/Armory/Inventory needed real persistence from Phase B onward) and
already looked thorough: every field individually pulled from the parsed
Dictionary with a fallback default. Reading it next to `SaveSystem.ts`'s
own `migrateSave()`/`sanitizeSettings()` line by line turned up gaps that
weren't cosmetic — they were a real crash path, confirmed by writing and
running actual malformed-save fixtures through it rather than reasoning
about the code in the abstract:

- **`int(x)`/`float(x)` abort on the wrong Variant type — they don't
  return a fallback.** TS's `num()` helper is a *guard*:
  `typeof value === 'number' && Number.isFinite(value) ? value : fallback`,
  so any non-number — `null`, a nested object, an array — just falls back.
  GDScript's `int()`/`float()` constructors have no such guard: a real
  headless test confirmed `int(null)` and `int({})` both abort with
  "Invalid call. Nonexistent 'int' constructor", not a caught exception —
  GDScript has nothing resembling `loadSave()`'s own top-level try/catch,
  so one bad field was one script error away from wherever `load_save()`
  happened to stop. A save file with `"soul_ash": null` — corrupted mid-
  write, hand-edited, or produced by a future bug elsewhere — hit exactly
  this.
- **`permanent_levels`/`unlocks` were accepted wholesale once confirmed to
  be *a* Dictionary, with no per-entry check.** `migrateSave()` validates
  every entry (`typeof value === 'number' && Number.isFinite(value) &&
  value >= 0`, floored) and drops the rest; the Godot side just took the
  whole Dictionary as-is, so one bad entry (a string, a negative, a
  nested object) among many good ones would have carried straight into
  `get_permanent_cost()`'s `pow(cost_growth, level)`.
- **`settings` was type-checked, not range/enum-checked.** A `master_volume:
  999` or `language: "xx"` matched its field's Godot type (FLOAT, STRING)
  and was accepted outright — `sanitizeSettings()` additionally clamps
  every volume/`textScale` to its real range and checks every enum field
  (`particleQuality`/`graphicsQuality`/`language`) against its actual
  allowed-value list, neither of which a bare type match catches.

Fixed by adding `_safe_num()`/`_safe_int()`/`_safe_bool()` — direct ports
of `num()`/`bool()` — and routing every conversion in `load_save()`
through them instead of a raw `int()`/`float()` on unchecked JSON, plus
per-entry validation for `permanent_levels`/`unlocks` and per-field range/
enum validation for `settings`, matching `sanitizeSettings()` field for
field. `hints_shown`/`last_seed` already had correct per-element/type
checks and needed no change. One thing deliberately *not* ported:
`migrateSave()`'s legacy-`tutorialSeen`-to-`hintsShown` migration branch —
this Godot save format has had `hints_shown` from its first version, so
there is no pre-`hints_shown` Godot save to ever migrate from; porting
that branch would be dead code guarding against a history this engine
never had.

**A second real bug, found by the fixtures, not by re-reading the code**:
the initial `unlocks` fix wrote `if loaded_unlocks[key] == true`, which
looks like the obviously-safe version of the old unchecked assignment —
until a fixture with `"shadowStep": 1` (a JSON number) hit it and
GDScript's `==` threw "Invalid operands 'float' and 'bool' in operator
'=='" instead of just returning false the way JS's `===` would. Fixed by
checking `typeof(value) == TYPE_BOOL` first so the mismatched `==` is
never reached — the same lesson as the `int()`/`float()` fix one level
up: a comparison across Variant types is exactly as unsafe here as a
conversion across them, and both need the type check to come first.

**Verified** via a real headless run against 11 fixtures written straight
to the real save path and loaded through the actual `load_save()`, not a
mocked one: unparseable text, a JSON array/number at the top level (both
correctly reset to full defaults); `soul_ash` as `null`, a nested object,
and a bare `true` (all three correctly settled on the safe default `0`
with zero script errors — the exact crash class this was fixing);
`permanent_levels` with 5 mixed entries (string, negative, float, nested
object, valid int) correctly kept only the 2 valid ones, the float
correctly floored; `unlocks` with 4 mixed entries (bool, string, bool,
number) correctly kept only the 2 real booleans; a `settings` block with
an out-of-range volume, an unknown language, an unknown quality tier, an
out-of-range `text_scale`, and a non-bool `muted` all correctly clamped
or fell back to default, field by field; a `lifetime_stats` block with a
`null` counter correctly defaulted while a legitimately negative
`best_time_seconds` was correctly accepted as-is (matches the source —
it's never floored to 0, only checked for finiteness); and, the
regression check that matters as much as any fixture, a fully well-formed
save with every field populated loaded back byte-for-byte correctly,
confirming none of the hardening changed behavior on the actual common
case of a save file nothing has ever corrupted.

### Step 12 — Full integration playtest + final audit

`GODOT_MIGRATION.md`'s own framing for this step is "full playtest &
rebalance pass," with an explicit warning that physics/frame-pacing
differences mean identical numbers can *feel* different. That half of the
step — does a dodge feel responsive, does a hit land with weight, is a
zone's difficulty curve fun — genuinely needs a human actually playing
the build; this environment has no display or audio output and has run
every verification this whole migration through printed state, not
perception. What real, non-perceptual work remained after step 11 was:
(1) confirm nothing across 12 build-order steps' worth of separately-
tested systems is silently broken when they all run together in one
continuous session, and (2) a documentation audit for anything still
describing itself as "not built yet" that later work had quietly closed
without updating the note.

**Documentation audit.** Two header comments still described real gaps
that no longer existed: `vfx/vfx_presets.gd` claimed `spawnHealSparkle`'s
3 call sites, `spawnChestOpenBurst`'s reward-gate, `spawnLevelUpBurst`'s
bow-unlock variant, and `spawnDeathBurst`'s boss two-tone flourish were
all blocked on "step 9, not built yet" — false since Phase B; a grep
confirmed all 4 are wired (5 `heal_sparkle` call sites now, if anything
more than the source). Checking the one specific claim worth verifying
rather than assuming the whole comment was stale — chestOpenBurst firing
without `rewardDef` set, unlike the source's own gate — led one level
deeper: `LevelFlow.open_chest()`'s `if def == null: return` guards
against `UpgradePool.pick_upgrade_at_least_rarity()` ever returning null,
which its own 3-tier fallback (matching the TS picker's own non-nullable
return type) makes structurally unreachable — so the concern doesn't
apply; the chest can't open without a reward to trigger the burst. Fixed
the comment to record that, not just delete it, so a future reader
doesn't have to redo the same check. `autoload/combat_manager.gd`
similarly still cited "build-order step 6" for synergy/ability effects —
a numbering that never matched `GODOT_MIGRATION.md`'s own order (step 6
is level generation) — while ALSO still being correct that neither
system has a real combat-pipeline hook: synergy *formation* is fully
wired (ownership, banner, SFX) but synergy *effects* (ashFire spreading
burn, wrath's damage boost, etc.) and ability effects (Ember Burst,
Warding Sigil) are still genuinely unimplemented, confirmed by grep, not
assumed from the stale comment. Both are real, disclosed, substantial
features — not integration glue — so left deferred, with the comment
corrected to say so accurately as of this audit rather than pointing at
a step number that was never right.

**Full integration playtest.** A single continuous run driven through
`LevelFlow`/`CombatManager` directly (this environment can't reliably
script WASD/mouse input under headless Xvfb, and the goal here is
cross-system integration, not re-proving any one system's own click
handling already covered by its own build-order step): every room in a
real zone-0 layout visited via `enter_room()`, combat/elite/heart rooms
force-cleared through the actual damage pipeline
(`CombatManager.damage_player_to_enemy` with a lethal hit, not `alive`
flipped by hand, so `on_enemy_death`'s full fallout — rewards, VFX, SFX,
XP, GameState sync — genuinely runs), the sanctum rite triggered and
completed, a chest opened, a rest used; the same sweep repeated for
zone 1 (adding a shielded `sunkenWarden` heart guardian to the mix);
`_complete_descent()` called directly into zone 2; the real boss found,
fought, and killed through the same real damage pipeline; and a second,
independent run driven straight to a lethal player hit for the defeat
path.

Three bugs surfaced, all three in the *test harness itself* — none were
findings about the actual game:

- A copy-paste field-path error (`player.stats.hp` instead of `player.hp`
  — current HP lives on the entity, `max_hp` lives on its `StatBlock`)
  that aborted the harness's own print statement with a script error.
  Unremarkable on its own, except that error silently truncated the rest
  of that zone's room sweep — GDScript unwinds the whole calling function
  on an uncaught script error, it doesn't just skip the offending
  statement — which hid the real finding below entirely on the first run.
- A room-clear reward opens `UpgradeSelectUI`, a real tree-pausing modal
  exactly like a live player would see. The harness never drove it to a
  choice (that click path is already covered by step 9's own slice), so
  it sat open, `get_tree().paused` stuck `true`, silently freezing
  `LevelFlow._physics_process` (not `PROCESS_MODE_ALWAYS`) for every room
  visited afterward — enemies could still be force-killed directly, but
  `check_cleared()` never got called automatically to notice. Fixed with
  a general "find any `PROCESS_MODE_ALWAYS` Control under `ui_root` and
  force it closed" helper rather than one-off handling per modal type,
  since every modal in this codebase already shares that exact shape.
- Calling `LevelFlow._complete_descent()` directly (to skip simulating
  the walk-*into*-the-stairwell animation, already proven when the
  transition was first built) still leaves it starting the *other* half
  of the same transition — the walk *off* the arrival stairwell,
  `_transition` held non-empty for `DESCENT_IN_SECONDS`. `_physics_process`
  early-returns to just `_update_transition()` for as long as
  `_transition` is non-empty, so `_update_room_clear()` doesn't run
  *at all* until it clears — confirmed by calling `check_cleared()`
  directly (worked correctly every time) versus waiting on the automatic
  per-frame path (didn't, until this was fixed) on the exact same room.
  Fixed by waiting on `_transition.is_empty()` after every direct
  `_complete_descent()` call rather than a fixed, too-short frame count.

With all three fixed, the full run — 2 zones swept exhaustively/lightly,
a shielded heart guardian, a sanctum rite, chests, rest, 5 level-ups, a
zone-2 boss kill, victory, and an independent defeat path — completed
with zero script errors and every room, reward, and state transition
resolving exactly as designed. Debug harness fully reverted (verified via
`git diff`) after confirming; none of it ships.

Every system `GODOT_MIGRATION.md`'s recommended build order calls for now
has at least one working, tested pass — all 12 steps.

### Closing the disclosed gaps — synergy/ability effects, and a real bug

Asked directly to keep going and implement whatever was still genuinely
missing rather than stop at "audited and disclosed," this pass closed
every gap step 12 named, plus one it hadn't looked for.

**A real, currently-active bug, found on the way in.** `entities/enemy.gd`
carried a `DEBUG_HP_MULT := 0.15` constant — explicitly marked temporary
in its own comment ("asked for directly... revert to 1.0... once testing
is done") — applied to every enemy's max HP by default. Sanctum rite
waves were the one deliberate opt-out; everything else, including the
zone-2 boss, was spawning at 15% of its real HP. `ashCrawler.tres`'s own
`base_hp = 200.0` matches this session's own earlier-established "~200 HP"
Zone 0 balance target exactly — the debug cut was never reverted after
whatever testing pass asked for it. Removed the constant and the
parameter entirely (`setup()`'s signature shrinks back to 4 args, the one
opt-out call site in `level_generator.gd`'s sanctum-wave spawn drops its
now-meaningless 5th argument) rather than just flipping it to 1.0, so
there's no dead toggle left for a future pass to wonder about. Verified
via a real headless run: the same `ashCrawler` that spawned at 30 HP
before now spawns at exactly 200; the zone-2 boss that had 369 HP now has
exactly 2460 (369 / 0.15) — precise confirmation this was a pure
multiplier bug, not a coincidence.

**Synergy effects** — `player.gd` gained `synergy_damage_multiplier()`
(wrath's HP-scaled bonus, up to +50% at the brink of death, times 1.35
while `perfect_dodge_timer` is running) and `trigger_perfect_dodge()`,
threaded into both weapon-damage formulas in `combat_manager.gd`
(`perform_melee_attack`/`fire_player_projectile`) exactly where the
source multiplies by its own `synergyDamageMultiplier` getter.
`damage_player_to_enemy` gained ashFire (1.4x damage on a burning target
— `EnemyCharacter.has_burn()` is a new small public helper, factored out
of the status-overlay's own inline burn check it already had) and
emberCritical (a 35%-chance VFX/SFX-only detonation on a crit, no bonus
damage — ported exactly as the source has it, not "improved").
`on_enemy_death` gained lightHealing (40% chance to heal 6% max HP when a
burning-or-elite enemy dies) and, since a DoT-tick kill previously passed
`on_enemy_death` a null player (the one place this port's own more
general status-effect system needed a small extension the source never
needed, since it always has `this.player` in scope), `StatusEffectRuntime`
now threads the effect's own `source` through so a burn-DoT kill still
credits the right player. `damage_enemy_to_player` gained the
shadowDodge trigger on a perfect dodge.

**Ability effects** — `CombatManager` gained an "Ability" section:
`ember_burst_ability()` (radial damage + knockback + VFX + camera shake +
hit-stop), `perform_stormstep()` (a 5-sample dash-line hit check, a direct
position teleport with no collision resolution — Stormstep is meant to
cut through what's in its way — brief invulnerability), and
`warding_sigil_tick()` (a continuous AoE damage+heal zone, ticked every
physics frame from `player.gd` while `warding_sigil_active` is set,
`silent` on its own damage calls so a multi-tick-per-second zone doesn't
spam a hit's normal VFX/SFX/damage-number/camera-shake). `player.gd`'s
`start_ability()` now dispatches by `ability_id` right after resetting
the resource/animation state — same "instant effect, cosmetic animation
plays alongside it" shape `start_attack()`'s own weapon-behavior dispatch
already had.

**Camera shake and hit-stop, previously whole-game gaps, not just an
ability one.** `Camera.ts`'s magnitude/duration/decay math (a new shake
only overrides a weaker, still-decaying one) ported onto the player's own
`Camera2D.offset` rather than a second manual coordinate system, since
this port already uses a native camera. `HitStop.ts`'s controller ported
onto `Engine.time_scale` — genuinely simpler than the source's own
approach of threading a scaled `dt` through every system by hand, since
Godot already scales every `_process`/`_physics_process` delta engine-
wide from one place. The one real subtlety: the countdown has to be
tracked in real (`Time.get_ticks_msec()`) time, not `_process()`'s own
delta — that delta is itself scaled once a hit-stop is active, so
counting down with it would make a slowdown outlast its own requested
duration. Wiring these up surfaced that `combat_manager.gd`'s own crit/
elite-hit/elite-death shake and hit-stop calls, and — cross-referencing
`BossSystem.ts` directly while already in this territory — every one of
the Ashen Colossus's own phase-change/melee-slam/shockwave/meteor/death
shakes, were all real source calls with nothing to attach to before now;
all wired, with their exact literal magnitudes, not approximated. The
phase-change beat was also missing its own ember-burst VFX entirely
(spawnEmberBurstVfx at 180 radius) — added alongside its shake.

**Damage numbers** reuse `world/floating_text.gd` (already built for the
XP-on-kill popup) rather than a second floating-text system, extended
with an optional font-size parameter so a crit (20pt, ember) reads bigger
than a normal hit (15pt, cream) or a blocked one (12pt, grey) — matching
`DamageNumber.ts`'s own sizing exactly.

**Verified** via a real headless run driving every new code path
directly: wrath's multiplier at full HP (1.0) and 10% Hp (1.45, matching
`1 + 0.9*0.5`); a dodge-blocked hit correctly setting the 3-second
perfect-dodge timer and the *1.35 it adds; ashFire dealing exactly 140
damage from a 100 base hit (`100 * 1.4`); 20 emberCritical crits and 15
lightHealing burning-kills run back to back with no error and at least
one real heal landing; Ember Burst damaging every enemy in its radius
with the right shake/hit-stop state; Stormstep moving the player exactly
230px and damaging what it passed through; Warding Sigil ticking damage
and healing for 30 frames then correctly clearing on a forced expiry;
camera shake decaying to exactly `(0, 0)` well past its requested
duration; hit-stop restoring `time_scale` to exactly `1.0` ~117ms after a
100ms request; and a damage number actually appearing as a new
`FloatingText` child after a hit. Followed by a full regression pass
reusing step 12's own playtest shape — a real heart-room clear, two zone
descents, and a real zone-2 boss kill through to VICTORY — all still
completing with zero script errors now that the entire damage pipeline
routes through several times more code on every single hit than it did
before this pass, and every enemy (including that boss) has ~6.67x the
HP it briefly had. Debug harness fully reverted (verified via `git diff`)
after confirming; none of it ships.

**What's genuinely left, and needs a human, not this environment**:
actually playing it — does combat feel weighty, is the pacing across 3
zones right now that enemies have their real intended HP back, do the
numbers this session tuned on the Web build still feel the same once
movement is real physics instead of a fixed timestep loop.

### Closing every remaining disclosed gap

Asked directly to close every point the previous pass's own closing
section named — `spawnZoneAmbientParticle`, the two hazard/separation
gaps, every inert setting, and the still-entirely-missing i18n system —
rather than leave any of them for later. All five landed, each read
against its own TS source rather than approximated, each verified via a
real headless Godot run before committing.

**Hazards (spore clouds).** `combat/CombatSystem.ts`'s Hazard system
(`spawnSporeCloud`/`updateHazards`/`consumePendingClouds`) is real now:
new `world/hazard_node.gd` + `.tscn`, a self-contained Node2D per active
hazard (spawn/tick/free itself) rather than TS's own flat ticked array —
matches every other transient world entity in this port
(pickup/chest/obstacle/floating-text), and needs no spatial cap the
source's own `MAX_HAZARDS` exists for, since each hazard is already a
cheap, self-freeing node rather than a slot in one shared, ticked pool.
Two real spawn sites, both using the source's own literal values: a
Blightbloat's burst (`detonate_bloat`, using its own `cloud_radius`/
`cloud_duration`) and a phase-2 Sunken Warden's bash landing
(`consume_pending_cloud`, fixed 3.5s — `enemy.gd`'s own
`pending_cloud_radius` field, set by the AI, was already there waiting on
this). Lighting is a real `PointLight2D` child, the same native
substitution every other lit thing in this port already uses instead of
a manual per-frame accumulator. Fixing this surfaced two more shake/
hit-stop call sites that pre-date this session's shake system and were
never updated: `detonate_bloat`'s own shake, and `check_bash_hit`'s
shake+hit-stop on a landed bash — both wired with the source's own
values. `damage_enemy_to_player` also gained the hazard/normal feedback
split it was missing entirely (a quieter fungusBright damage number +
weak shake on a hazard tick, a bloodBright number + real shake
otherwise) — previously a player taking a direct hit got no damage
number and no shake at all.

**Enemy separation.** `ai/EnemyAI.ts`'s `applyEnemySeparation` — the
soft push-apart between overlapping enemies — is ported exactly,
including its literal, not-`dt`-scaled per-frame nudge. The source backs
its neighbor query with a `SpatialGrid` purely to avoid an O(n²) scan
across potentially hundreds of entities; this port's rooms top out at a
handful at once, so `EnemyAI.apply_separation()` scans every other alive
enemy in the "enemies" group directly — the grid was always just a
performance optimization, never part of the separation math, so this
changes nothing about the actual behavior. Wired into both `enemy.gd`'s
and `boss.gd`'s own `_physics_process` — the source's own loop has no
boss exception either, and a boss-phase summon can plausibly spawn
overlapping the boss itself.

**Zone ambient particles.** `drawRoom.ts`'s `spawnZoneAmbientParticle`
is real too. Researching it found the previous closing section's own
claim for why it was deferred was stale: it said this port's
`ZoneDefinition` resource was missing the fields the function needs
(`ambientParticle`, `sporeColors`, `palette.ambient`/`accent`). It
wasn't — `resources/definitions/zone_definition.gd` already declares
`ambient_particle`/`spore_colors`/`palette_ambient`/`palette_accent`, and
all 3 zone `.tres` files already have them fully populated with the
exact values from `data/zones.ts`. Only the spawn function itself and
its per-frame call were ever actually missing — a much smaller gap than
documented. `vfx_presets.gd` gains `zone_ambient_particle()`, switching
on the zone's own enum: ash falls (Ashen Woods), spores scatter two
glowing motes in the zone's own violet/teal colors (Hollow Ruins —
reuses `spore_mote()`, extended with an optional colors list so hazards'
own call sites keep their existing default untouched), embers rise
(Ember Citadel). `level_flow.gd` gains the source's own 0.12s
`ambientTimer` cadence, spawning at a random point within (and slightly
overscanning) the player's camera view.

**Settings effects.** `MetaProgression.settings` has persisted
`screen_shake`/`particle_quality`/`graphics_quality`/`text_scale`/
`high_contrast`/`reduced_motion` correctly since step 11, but none of
them did anything. Four of the six do now, each checked against
`Game.ts`'s own `applySettings()`: `screen_shake` gates
`add_camera_shake()`/`trigger_hit_stop()` (the source reuses one flag for
both; so does this); `particle_quality` halves `VfxSystem.emit()`'s
particle count on "low", matching `ParticleSystem.ts`'s own `burst()`
rule exactly (its other lever, a hard cap on total simultaneously-active
particle slots, has no equivalent here — this port's `emit()` builds an
independent one-shot node per call rather than drawing from one shared
pool, so there's no shared slot count to cap); `text_scale` applies as
`CanvasLayer.scale` on `$UI` itself, the nearest equivalent to the
source's own "one CSS variable the whole DOM's font-size cascades from"
now that this port's UI sets explicit per-label sizes with no such
cascade point; `reduced_motion` scales every toast/phase-banner/synergy-
banner Tween's durations and hold intervals toward near-zero, reproducing
the source's own `animation-duration: 0.001ms !important` — the whole
timeline collapsing, not just the transitions. `graphics_quality` and
`high_contrast` are left as genuine, disclosed gaps: the former's real
mechanism (a window/viewport render-scale) can't be visually verified in
this environment and risks interacting oddly with the fixed
`--resolution` this whole session's own test harness relies on; the
latter would need a proper alternate UI color theme touching many
individual `Color(...)` literals across every screen, not a safe pass
without being able to see the result.

**i18n.** New `autoload/i18n.gd` ports `i18n/index.ts`'s
`t(key, fallbackEn)`/`tc(id, field, fallbackEn)` contract exactly, backed
by `i18n/fr.ts`'s own `FR_CONTENT`/`FR_UI` dictionaries transcribed
verbatim — every enemy/weapon/ability/upgrade/permanent-upgrade/zone/
unlock/synergy/world-event's real French text, plus every flat UI-chrome
string. Deliberately not reactive, matching the source's own explicit
non-goal (it reloads the whole page after a language change rather than
retranslating whatever's already baked into the DOM) — this port's own
screens are already rebuilt fresh every time they're shown, so a
language change takes effect the next time each screen reopens, the same
practical result without needing a reload.

`MainMenuUI` landed first as a real, end-to-end case, honestly disclosed
at the time as the only screen actually wired — a follow-up pass has
since swept every remaining screen through `I18n.t()`/`.tc()` the same
way: HUD (room/level/synergy/XP labels, the key hint), settings + pause
menu, loadout + upgrade-select + the shared upgrade card + the reward
popup, shop + event, inventory + armory, victory/defeat + credits, plus
the cross-cutting construction sites in `main.gd`, `level_flow.gd`,
`enemy.gd`, and `level_generator.gd` (zone/weapon/ability/boss names,
every toast and phase banner, mutated/empowered/heart-warden display
names). Two small gaps surfaced and were fixed alongside the sweep rather
than deferred: `gainShieldCharge` events never actually told the player
anything happened (`Game.ts`'s own handler plays `shieldUp` *and* shows a
`toast.wardenWard` toast; this port only had the SFX) — the missing toast
call is now there too. And Victory/Defeat shared one hardcoded "Time
Survived" stat label where the source uses two different keys
(`stat.time` for Victory, `stat.timeSurvived` for Defeat) — this now
matches the source exactly. A couple of strings stay deliberately English
in both languages, the same "no fabricated translation" discipline
`hud.levelMax` already established: `credits.techGodot` (this port's own
"Built with Godot Engine and GDScript" line — the source's real
`credits.tech` translation names TypeScript/Vite/Canvas2D/Web Audio,
which would be factually wrong here) and `settings.languageHintGodot`
(the source's own `settings.languageHint` says "Reloads the game to
apply," describing *its* reload-on-change behavior; this port's screens
just re-read the language next time they're shown, so that hint would be
actively misleading if reused).

**Verified** via real headless Godot runs, one per system, each with
precise numeric assertions before committing: a hazard's shake, cloud
radius/duration, and real tick damage against a player standing in it;
overlapping enemies pushed apart by the exact expected fractional-pixel
amount, a distant pair untouched, a mid-bash enemy correctly skipped;
each of the 3 zones' `zone_ambient_particle()` branches executing without
error and a real started run's own ambient timer ticking correctly;
`screen_shake` off making both shake and hit-stop true no-ops while on
they apply exactly as requested, `particle_quality` low emitting exactly
half the requested count, `text_scale` visibly changing `$UI`'s own
scale, `reduced_motion`'s exposed factor flipping between 1.0 and 0.05;
`I18n.t()`/`.tc()` returning the correct French string, the correct
English fallback, and the exact unmodified fallback for an untranslated
key, plus `MainMenuUI`'s own Play button actually rendering "JOUER" end-
to-end with the language set to French. The follow-up sweep was verified
the same way, at real scale: a dedicated headless run built every
converted screen (Credits, Settings, both Armory tabs, Pause, Loadout,
Upgrade-select, Shop, a real Event drawn from `DataRegistry`, Inventory,
and both Victory and Defeat) with the language set to French and asserted
a specific, known French string — or, for the two Godot-only hint
strings, the exact expected English — actually rendered somewhere in that
screen's live node tree: 27 assertions, 27 passes, zero script errors.
Followed by a full cumulative
regression: a real 3-zone run with all three ambient-particle types,
overlapping enemies, and a bloat detonation exercised together, zero
script errors throughout. (A separate, pre-existing "Invalid polygon
data, triangulation failed" rendering warning surfaces from `enemy.gd`'s
own polygon-based body silhouettes when several enemies render across
many frames — confirmed unrelated to any of this pass's code, none of
which calls `draw_colored_polygon`; a real but purely cosmetic issue that
predates this pass, not fixed here since it's outside this pass's own
scope.) Debug harness reverted after each (verified via `git diff`)
before committing.

**What's genuinely still open**: `graphics_quality` and `high_contrast`
(named above, with why) and the pre-existing enemy silhouette rendering
warning just noted — plus, as ever, actually playing it.
