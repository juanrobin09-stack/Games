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

**The merchant stall sprite.** `world/obstacle_node.gd`'s own
`_draw_merchant_stall()` used to carry an honest disclosed gap: "No stall
sprite asset is ported to Godot yet," always drawing `drawObstacle.ts`'s
procedural fallback shape since there was no equivalent to the source's
own `rendering/ShopAsset.ts` (`getStallSprite()`, chroma-keyed off
`assets/textures/shop-props.png`). That's now ported: a new
`assets/textures/shop_stall.png` is an offline, one-time crop of the same
source sheet, with the same luminance chroma-key baked in (`chromaKey()`'s
own [10,19] alpha ramp) rather than reproduced at runtime — Godot's
`preload()` is synchronous, so there's no load-order reason to redo that
processing on every launch the way the source's lazy `<img>` decode
effectively forces in a browser. `_draw_merchant_stall()` draws that
texture with the source's own tuned width (`spriteW = r * 7.2`); the old
procedural shape is gone outright rather than kept as a fallback, since
`preload()` either resolves at compile time or the project fails to open —
unlike the source's async-decode race, there's no runtime path left that
would ever reach it. This is the one sprite in the whole project that
isn't pure `_draw()` procedural generation — every other obstacle, entity,
particle, and UI element still is.

**A real integration bug, caught by the user, not this pass's own first
verification.** The first cut used `ShopAsset.ts`'s own `STALL_STONE` crop
rect verbatim (x=948,y=45,w=465,h=340) and a straight port of `chromaKey()`
— and a headless screenshot at the time looked clean. It wasn't: in actual
play, the stall read as a pasted-on rectangle against the room floor. The
screenshot that first "verified" it used an isolated obstacle, a bright
default clear color, and a casual look at the whole frame rather than its
edges — exactly the kind of miss this README has already flagged once
before ("caught by zooming into the actual screenshot rather than trusting
a full-window thumbnail"), repeated here with a new element instead of the
lesson carrying over. Direct pixel sampling (measuring the same luminance
formula `chromaKey()` uses, along every edge of the cropped image) found
the actual cause: `STALL_STONE`'s own rect cuts straight through real
painted content on 3 of its 4 sides — most visibly the counter's own drop
shadow at the bottom, which never fades to background within that rect at
all, confirmed by sampling luminance there directly rather than assuming
it. This sheet packs its props tightly enough that no crop rect can
guarantee a clean, fully-faded margin on every side by content position
alone. Fixed two ways: the crop is now wider (w=473,h=385 — extended
mainly downward, clearing the counter's real shadow before the next prop
row starts, verified by sampling the gap between them), and a 16px alpha
feather now runs inward from every edge of the crop as a deliberate
safety net with no source equivalent — forcing true transparency at the
image's own border regardless of exactly where content sampling says it
should start, rather than trusting that judgment call alone a second time.
The vertical placement anchor also moved from the source's own `spriteH *
0.6` to `spriteH * 0.53`, re-derived for the taller crop so the counter
still lands at the same real position (`0.6 * 340/385`) instead of
drifting as a side effect of the height change.

**Verified** the same way the bug was found, not just "does it still
render": re-sampled the regenerated PNG's own edge pixels with the exact
same luminance formula and confirmed 0 maximum alpha anywhere on its
border (not "looks clean" — measured). A real headless screenshot dropped
into an isolated test still looked clean at that point, but a *second*
real-gameplay screenshot — a genuine generated shop room, entered through
`LevelFlow._sync_active_room()` rather than an isolated obstacle, full HUD
and room floor and ambient tint all present — was the one that actually
mattered, and zooming into it confirmed the edges were real: clean,
no seam, no box.

**A second round, this time about style, not transparency.** Edges clean
didn't mean integrated. The sprite is a soft, painterly reference image;
every other visual in this entire project — obstacles, entities, particles,
UI — is flat-shaded straight `Palette` colors with no photographic
gradients anywhere. Next to that, even a perfectly alpha-clean sprite still
reads as pasted-on, because it's rendered in a different register
entirely, not because anything is technically broken. Fixed by pushing the
sprite's own RGB (never its alpha) toward that same flat-shaded register:
+35% contrast, +45% saturation, -8% brightness, then posterized to 5
levels per channel to flatten lingering soft gradient banding. Re-verified
the same two ways as the edge fix — re-sampled border alpha (still 0,
confirming the color pass touched only RGB) and a fresh real-gameplay
screenshot, this time showing visibly punchier, more graphic colors that
sit together with the room's other flat-shaded elements (its chest,
its own glow) rather than apart from them.

**A third round found the actual dominant problem.** Asked directly
whether the issue was really understood to be about transparency, it
wasn't — not fully. Exporting the sprite's own alpha channel as a
grayscale image (not sampling scattered coordinates, which had already
produced one wrong read this pass) showed a large gray haze filling most
of the crop's "empty" space, and re-running the same export on the raw
output of `chromaKey()`'s own formula — before any of this port's changes
— showed the same haze already there. Root cause: the reference painting
has a real light source (the candle) baked in, so background near it
reads at a luminance well above the simple [10,19] "background" band —
ambient light on nothing, numerically inseparable from real material by
luminance alone (raising the threshold would erase legitimate stone-in-
shadow first, per `chromaKey()`'s own header, ported faithfully). Fixed
with a gamma curve on the post-`chromaKey()` alpha (`** 3.2`) rather than
a threshold change: already-confident alpha (the real silhouette) stays
close to opaque, while every hazy partial value collapses toward
transparent, since haze can't be as opaque as the object painted over it.
Re-verified the same two ways again — border alpha still 0, and a fresh
real-gameplay screenshot showing the haze actually gone, not just the
edges: the background around the stall now reads as genuinely dark,
matching the room around it, with only the candle's own light spilling
naturally into its immediate surroundings.

**A fourth round, asked to rule out the renderer and stop trusting "the
PNG must be it."** Explicitly audited the full chain rather than the
asset alone: `git diff` confirmed the working-tree PNG is byte-identical
to what's pushed (no un-pushed local state); a grep across the whole repo
found exactly one copy of `shop_stall.png` plus its own gitignored
`.import`/`.godot/imported/` cache siblings, so there's no second asset
the game could be reading instead; `obstacle_node.tscn`/`.gd` carry no
`CanvasItemMaterial`, no `light_mode`, no `modulate`/`self_modulate`
override, and a repo-wide search found no `CanvasGroup`, custom
`blend_mode`, or `WorldEnvironment` anywhere near this rendering path —
nothing between the texture and the screen that could selectively punch
holes in it. Re-verified the PNG's own alpha channel fresh from the
working tree (not memory of the earlier check): border still 0, interior
haze still gone. Then wiped `godot/.godot/` *and* every asset's
`.import` sidecar entirely — simulating a truly first-ever project open,
the same state a fresh clone starts from — and reimported and screenshotted
from that clean slate: identical clean result, plus the running game's own
`ObstacleNode.STALL_TEXTURE.resource_path` and `.get_size()` printed and
confirmed to be the one expected file at its current, fixed dimensions,
not a stale or alternate copy.

No new defect turned up in this pass — everything traced back to the same
already-fixed, already-pushed asset. The one thing this environment can't
rule out is a stale *local* import cache on a machine that already had an
older copy of `shop_stall.png` open in the Godot editor across several
quick pushes: Godot compiles textures into `.godot/imported/*.ctex` once
per machine (both that folder and every `.import` sidecar are gitignored,
never pushed), and an editor instance that was already running when a
newer commit landed doesn't always notice the source file changed
underneath it. If the sprite still looks wrong after pulling the latest
commit, closing the Godot editor fully, deleting the project's local
`.godot/` folder, and reopening it (forcing a full reimport from the
current, verified-clean PNG) is the next concrete step — before assuming
the asset itself regressed again.

**A fifth round replaced the source image entirely**, supplied directly
rather than derived from the old `shop-props.png` sheet this port had
been cropping from since the start. Before touching anything, the raw
supplied image (1685×934) got the same alpha-channel-as-grayscale-image
check as every round above — and unlike every prior crop from the old
sheet, it came back clean on its own: a crisp, fully-opaque silhouette
against a fully-transparent background, no haze to gamma-curve away.
Processing was correspondingly light — crop to real content bounds plus
a small margin, downscale to 660×406 via Lanczos (this sprite is drawn
at a few hundred px on screen; no reason to ship the source's full
resolution), and an 8px inward feather as a cheap safety net rather than
a fix for a known problem. Border alpha re-verified at 0 after each step.

Swapping in a wider/flatter image (406/660 ≈ 0.62, vs. the old crop's
385/473 ≈ 0.81) meant the vertical anchor inherited from that old crop's
own lineage — `-spriteH * 0.53`, itself re-derived from the ported
source's `0.6` for an image since fully replaced — no longer had any
basis. Rather than guess, the new image's alpha channel got sampled row
by row: the two pillars stand apart (the archway's opening between them)
until ~47% down, join into one continuous span (the counter filling that
gap) to ~75%, then narrow again to the pillar bases and the banner.
Centering the origin at that span's midpoint (`0.5`) reproduces the same
relationship the old anchor was tuned for — archway opening above the
obstacle's own position, counter and banner below it — measured fresh
against this image rather than carried over from one that no longer
exists in the repo.

Verified the only way this account now trusts for this asset: a real
run, teleported into an actual shop room via the admin menu's own
teleport path (not a hand-rolled shortcut), screenshotted at normal
gameplay zoom, then that region cropped and upscaled 3x for a close edge
pass. No box, no haze, no hard rectangular cutoff anywhere along the
arch, pillars, counter, or banner silhouette against the room's own dark
ambient background — the only brightening near the sprite is the
candle's own glow spilling outward, the same kind of soft radial falloff
every other lit prop here already draws. The player's interaction prompt
("[E] Browse Wares") lit up at the teleported-in distance, confirming the
new anchor didn't drift the interaction point away from where the player
actually stands.

**What's genuinely still open**: whether this reads as "integrated enough"
is inherently a subjective call a human needs to make in real play, not
something a screenshot diff alone can close out — this account is honest
about that rather than declaring the aesthetic question settled by
process. The stale-local-import-cache caveat from the fourth round still
applies in principle to this new file too (same filename, same gitignored
`.import`/`.godot/imported/` cache mechanics) — closing the Godot editor
and deleting the project's local `.godot/` folder before reopening is
still the first thing to try if an older render somehow persists. Beyond
that: `graphics_quality` and `high_contrast` (named above, with why) and
the pre-existing enemy silhouette rendering warning just noted — plus, as
ever, actually playing it.

### Real floor texture — the first non-procedural floor art in the Godot port

Every room's floor had been a flat zone-tinted `draw_rect` since build-order
step 7 (`room_container.gd`'s own comment there called real per-tile floor/
wall textures "a deliberately separate, much larger art-production task
this pass doesn't attempt," matching GODOT_MIGRATION.md §4's recommendation
to start with a faithful procedural port). A supplied stone-flagstone image
(1254×1254, dropped via the same file-hand-off branch as the shop stall)
closes that gap for the floor specifically — walls stay the flat
zone-tinted rect for now, no wall texture was supplied this round.

Unlike the shop stall, this needed no alpha/transparency work at all: it's
a fully opaque RGB image, always the bottom-most layer, no chroma-key or
feathering to get right — copied in essentially as supplied. The one real
decision was how to fit a square image into the room's own 1000×620
rect (`ROOM_WIDTH`/`ROOM_HEIGHT`, a 1.61:1 aspect): stretched non-uniformly
to fill it exactly via `draw_texture_rect`, not tiled. Tiling was ruled out
specifically because the source has its own baked-in directional lighting
(a warm highlight sweeping diagonally across it) — repeating that would
show as a visible seam and a repeated hot spot every ROOM_WIDTH/HEIGHT,
exactly the kind of artifact a seamless tileable texture is built to avoid
and this one isn't. One shared texture for every zone/room rather than a
per-zone set, since only one image was supplied; `zone.palette_floor`
no longer tints anything in `_draw()` as a result, though it's still read
by `vfx_presets.gd` for particle coloring, so it stays on `ZoneDefinition`.

Verified with two real screenshots from a running build, not just "the
code compiles": the starting room (Ashen Woods · Entrance) showing the
stretched texture filling the visible floor with no seams, no missing-
texture fallback, and no leftover gap at the room edges; and a shop room,
to confirm the new floor and the previously-fixed shop stall — both
supplied images, both now in the same warm dark-stone palette — read
consistently next to each other rather than clashing.

### Real wall texture — and the harder problem the floor didn't have: doors

A supplied wall image (1763×892, same file-hand-off channel) closes the
wall half of the gap the floor's own section above left open. Unlike the
floor, this one couldn't just be stretched over the room the simple way:
the source is a single picture of a complete, CLOSED rectangular frame —
all four walls and their corners in one image, no door gaps drawn into it
anywhere — while a real room's walls have actual gaps wherever
`has_door()` says a door exists, the same gaps `get_walls()` already
leaves out of its own returned rects so the player can walk through them.
Stretching the closed frame uniformly over every room regardless of its
actual doors would have shown solid wall exactly where a door should
read as open — a real navigation-clarity regression, not just a cosmetic
one, and exactly the kind of door-legibility problem step 7's own door
visual identity work had already solved once.

So each wall piece draws a proportional CROP of that side's own border
band out of the source, sized and positioned to match where that piece
falls along the room's width/height, rather than the whole image
stretched once — the same `has_door()`/`is_locked()` branching
`get_walls()` uses internally is reproduced in a new `_draw_walls()`
(not threaded through `get_walls()`'s own Rect2-only return, which
`_setup_physics_bodies()`'s collision setup and `projectile.gd`'s own
wall check both still need untouched), so a door-split side crops the
same real gap out of the source that `get_walls()` leaves out of the
destination, and — easy to miss, since it only shows up on the single
most common room state in the game — a LOCKED room (any uncleared
COMBAT/ELITE/HEART/BOSS room, not just a boss fight specifically, per
`is_locked()`'s own condition) draws a third piece filling the gap with
the middle crop that would otherwise be skipped, so a sealed door reads
as sealed instead of showing an opening the collision barrier still
blocks.

**A real bug a corner-only glance would have missed.** Border thickness
came out a consistent ~72px in from a ~26px empty margin on all four
sides at each edge's own MIDDLE — measured the same brightness-scan-
outward-from-black way as the floor's own margin, since this is another
plain RGB image with no alpha. Naively mapping each piece's full
lengthwise span onto that band at a fixed thickness rendered fine along
every straight stretch, but a real screenshot of an actual corner (not
assumed correct from the middle-span measurement alone) showed a
black wedge exactly where two pieces met. Cause: the frame's outer
silhouette is rounded at each corner, not square, so the ~26px margin
that holds up mid-span is nowhere near enough right at a corner — a
pixel scan outward from a corner found no content at all for roughly
80px, versus ~26px mid-span. A piece sampling its full lengthwise range
via a naive proportional map reaches straight into that pulled-back
black region at its own corner-adjacent end. Fixed by insetting the
lengthwise sampling window symmetrically by a safe margin (100px, clear
of the ~80px measured) before mapping the destination onto it, so every
piece's corner-adjacent end — whether that end is a true room corner or
a door edge one span-length in — samples from just inside the corner
posts' own solid art instead of their black surroundings. Re-verified
with real screenshots at all four wall midpoints plus both diagonal
corners of an actual locked room: continuous stone at every straight
run, a sealed-looking barrier exactly where a locked door's gap would
otherwise show, and clean corner posts with no black bleed at either
corner checked.

### The wall texture, replaced again — a cleaner source sidesteps the whole corner problem

A follow-up reference PNG replaced `wall_frame.png` before that asset had
been in the repo for more than a few minutes: not another closed-frame
scene this time, but a proper sprite sheet of separately pre-cut
horizontal and vertical wall strips at several lengths each, already
alpha-cut clean. A straight brightness-scan-outward check (the same
technique used on every supplied image this project has taken in) found
literally zero border alpha on the longest horizontal piece and only
single-digit-out-of-255 residue on the longest vertical one — negligible,
no feathering needed, the cleanest of the three supplied images so far.

This doesn't just swap the picture, it removes a whole category of bug
the closed-frame image needed real machinery to work around. That image
was one picture of all four walls at once with no door gaps drawn in, so
every wall piece had to crop a proportional slice out of a shared border
band — and because the frame's outer corners were rounded rather than
square, a piece sampling near its own corner-adjacent end could reach
past the corner post into the frame's own black interior (the bug the
previous section's corner screenshot caught), fixed only by an inset
margin tuned to clear that rounding. Picking the longest horizontal
(949×48) and longest vertical (48×325) piece off the new sheet instead
gives each piece its own dedicated, fully self-contained texture with
nothing beyond its own edges to ever sample past — so a wall piece is
just stretched to fill its destination rect the same simple way
FLOOR_TEXTURE already is, no shared crop and no corner-margin math left
in the code at all. `_draw_walls()` keeps exactly the same
`has_door()`/`is_locked()` branching as before — that part of the
problem (a door needs a real gap, a locked room needs that gap sealed)
was never about the closed-frame image specifically, it's inherent to
drawing any single wall texture onto a room whose doors move gaps
around, sprite sheet or not.

Re-verified with the same real-screenshot battery as the frame version —
all four wall midpoints plus both diagonal corners of an actual locked
room — before calling it done rather than assuming a cleaner source
couldn't have introduced its own new problem: continuous stone at every
straight run, sealed-looking barriers at both of this room's locked
doors, and clean corners with no black bleed, this time with no inset
hack required to get there.

**Reported as a quality problem right after those screenshots went out —
and it was real, isolated to exactly one case.** Every wall piece
stretches its own dedicated texture to fill its destination rect, and
every piece does that at close to native resolution except one:
WALL_TEXTURE_H's 949px width stretches to ROOM_WIDTH's 1000 (~1.05x,
negligible) and every door-split or barrier piece on either axis
*shrinks* its source to fit (a downscale, no blur risk) — except the
full, undoored W/E wall, which stretches WALL_TEXTURE_V's 325px height
to ROOM_HEIGHT's 620, a ~1.9x upscale. Cropping the same screen region
from the W-wall screenshot at 3x and comparing it directly against the
same crop from an N/S wall confirmed it: individual stone blocks read
clearly on the horizontal wall, and turn to mush on the vertical one.

Fixed with `_draw_wall_v_tiled()`: instead of one `draw_texture_rect`
stretching the full height in a single pass, it splits the destination
into evenly-sized tiles sized so no single tile stretches WALL_TEXTURE_V
by more than 1.1x, and draws each separately. For ROOM_HEIGHT that comes
out to 2 tiles of 310 each — a 0.95x scale, matching the horizontal
wall's own near-native sharpness. The source isn't built to tile
seamlessly, so the join between the two tiles repeats the same joint
pattern rather than hiding it, but a repeat reads far better than a blur
mid-wall. Only the full-height (no-door) case needed the change — the
door-split and barrier pieces on that axis were already downscaling, so
they were never blurry, and left as plain single stretches rather than
routing every vertical draw through the tiling helper for cases that
didn't need it. Re-cropped the exact same screen region from a fresh
screenshot after the fix: individual stone blocks now read as clearly
on the vertical wall as they do on the horizontal one.

### The wall textures, replaced a third time — a genuinely higher-resolution source

A follow-up reference PNG (1620×971, roughly 60% more linear resolution
than the sprite sheet it replaced) landed after two separate pieces of
feedback: a report that the vertical wall still looked lower-quality
than expected, and a separate observation that the left (vertical) wall
looked wider than the horizontal one. Unlike every prior wall image, this
one wasn't already alpha-cut — its "transparent" area was a literal
checkerboard pattern painted in as opaque near-white/gray pixels (R≈G≈B,
brightness > ~195), a known ChatGPT/image-generator artifact when a
transparent background is requested but the model draws a placeholder
pattern instead of emitting real alpha. Chroma-keyed those pixels to
alpha 0 (the same technique as every prior asset's own cleanup, just a
different key color this time) and ran a MedianFilter(3) over the
resulting alpha channel first to remove the handful of stray single-
pixel misclassifications visible in the alpha-as-grayscale check, before
touching anything else.

The image itself is a single L-shaped corner piece — one continuous
horizontal band across the top and one continuous vertical band down the
left, meeting at a real corner — rather than a sheet of separate pieces.
Cropping the horizontal and vertical bands out of the SAME image (rather
than two separately-generated pieces, as the previous sprite sheet's
longest-of-each-orientation picks were) is very likely what the "left is
wider" report was actually about: two independently-generated pieces
have no reason to agree on how thick their own buttress joints are drawn
relative to their own length, while two crops of one coherent piece
share the same proportions by construction. Re-hit the same rounded-
corner lesson learned from the very first wall_frame.png attempt while
finding the safe crop boundaries — a first pass right at the visually-
measured boundary caught a transition row/column where the silhouette
was already receding into the corner's own rounding, verified by scanning
for the largest y (for the horizontal band) and x (for the vertical
band) where the ENTIRE remaining width/height was still fully opaque,
not just checking a single sample point — WALL_HORIZONTAL came out
1592×157 and WALL_VERTICAL 163×795, both with confirmed 0/255 alpha
(fully binary, no haze) along every border of the final crop.

At this resolution, every wall piece — the previously-blurry full-height
vertical case included — now downscales rather than upscales (795→620
is 0.78x), so `_draw_wall_v_tiled()`'s own stretch-factor check
naturally resolves to a single tile with no stretching-related code
change needed; the fix from the previous round stays in place as a
safety margin for whatever the next source image's own resolution turns
out to be, rather than becoming dead code. Re-verified with the same
real-screenshot battery as every wall version before it: individual
stone blocks read clearly on both orientations at every wall midpoint
and both diagonal corners of an actual locked room, with the corner
posts' own proportions now visibly matched between the two bands.

### Window Size and a real Fullscreen setting

A further "still blurry" report, after two rounds of asset fixes, traced
to something outside every texture entirely: the player's own display was
scaling a small, DPI-unaware game window up at the OS level, which no
amount of source-image resolution can fix — the blur is added after
Godot has already rendered a perfectly sharp frame. `project.godot` never
declared a `[display]` section at all, meaning `window/stretch/mode` sat
at its engine default of `"disabled"` — resizing the actual window did
nothing to the rendered canvas, so the only way to get more real pixels
on screen was already-correct texture work fighting an OS compositor
upscaling too few of them.

Added an explicit `[display]` section (`window/stretch/mode=
"canvas_items"`, `aspect="keep"`, viewport still 1152x648): every
existing screen's UI is built in that same fixed pixel space
already, so this changes nothing about how anything is laid out, only how
the finished 1152x648 canvas maps onto whatever real window size the OS
window actually is. On top of that, `settings_ui.gd` gets a real Window
Size row (1x/1.25x/1.5x/2x, `DisplayServer.window_set_size()`) and the
existing Fullscreen control — previously a bare button calling
`DisplayServer.window_set_mode()` directly with nothing remembering the
choice — is now a real persisted setting like every other row, going
through `MetaProgression.settings`/`settings_changed` the same reflexive
way `text_scale` already does, so `main.gd`'s new `_apply_window_scale()`/
`_apply_fullscreen()` pick it up automatically and it survives a relaunch
instead of resetting to windowed every time.

The one real subtlety: leaving fullscreen has to actively restore the
chosen window scale, not just fall back to whatever size Godot happens to
leave the window at. `_apply_window_scale()` itself no-ops while
`DisplayServer.window_get_mode()` reports fullscreen (resizing a
fullscreen window is meaningless and would read back the wrong size next
time), and `_apply_fullscreen()` explicitly re-calls it the instant it
switches back to windowed. Verified directly rather than assumed: saved
`window_scale: "1.5"` and confirmed the real window resized to 1728x972,
toggled `fullscreen: true` and confirmed `DisplayServer.window_get_mode()`
actually reported fullscreen, then toggled it back off and confirmed the
window returned to 1728x972 — the saved 1.5x, not the original 1152x648 —
rather than trusting that the round-trip would work from reading the code
alone.

**A user report that these two rows "did nothing" led to an F11 shortcut,
not a rewrite.** Direct property checks (the verification just above)
already showed `DisplayServer.window_set_size()`/`window_set_mode()`
firing and taking effect correctly when the settings change, and
`project.godot` has no `resizable=false` or similar override that would
block it — so the Settings rows themselves aren't the likely fault. The
more likely explanation this account can't verify directly (no real OS
window in this environment to press F11 in and watch): Godot 4.3+'s
Embedded Game View, a per-machine EDITOR preference (not a project
setting, so nothing in this repo controls it) that runs the game inside
the editor's own window on F5 instead of a real standalone one — no
fullscreen or resize call has anywhere real to take effect against that.
Added an F11 shortcut in `main.gd`'s `_process()` (before the
`player == null` early-return, so it works from the main menu too) that
flips the same `fullscreen` setting Settings' own row does, purely as a
fast way to tell the two apart: if F11 does nothing either, on a real
window it definitely should, which points at the editor's own embedding
rather than these rows.

### Toggle switches looked like empty rectangles — because they were

Reported against a real screenshot: every toggle row (Mute All, Screen
Shake, High Contrast, Reduced Motion, Fullscreen) rendered as a flat
color pill with nothing inside it — correct on inspection, `MenuUiKit.
make_toggle()` really was just a StyleBoxFlat swap between a dark "off"
background and a translucent ember "on" one, no knob, no shape, nothing
a glance would read as a switch rather than an unstyled placeholder box.

Added an actual sliding knob: a small round `Panel` child, positioned at
the pill's left end when off and right end when on, its own fill color
swapping between a dim neutral (off) and solid ember (on) alongside the
position change — the two together are what make it read as "a switch
in a position" instead of "a box that changed color." Animated with a
short `Tween` (0.12s, cubic) so flipping one feels like a slide rather
than a jump cut, except when `reduced_motion` is on, where it snaps
instantly — the same motion-gating this project's other effects already
respect, checked directly off `MetaProgression.settings` rather than
routed through hud.gd's own motion-scale helper (this one lives in
`menu_ui_kit.gd`, general UI chrome rather than gameplay HUD).

Verified by rebuilding the Settings screen twice with different
saved states — the visible difference was the actual thing being
checked, not just that a screenshot didn't crash: before, Screen Shake
alone showed its knob on the right in ember; after flipping every
toggle to the opposite state, that same row's knob had moved to the left
in neutral gray while the newly-enabled rows (Mute All, High Contrast)
showed theirs on the right, confirming the knob really tracks each
toggle's own state rather than being a static decoration drawn the same
way regardless.

### Window Size, from a 4-way multiplier to a real resolution dropdown with Custom

A follow-up request asked for more than the 1x/1.25x/1.5x/2x segmented
row could offer: a dropdown of real named resolutions, plus a genuine
custom width/height option — the segmented-button shape (borrowed from
Particles/Graphics Quality) doesn't scale past 3-4 choices before it runs
out of row width, and a multiplier on the project's own non-standard
1152x648 base was never going to line up with the resolutions a player
actually thinks in (1080p, 1440p) anyway.

Replaced the stored setting itself, not just the control: `window_scale`
(a string multiplier) is gone, replaced by `window_width`/`window_height`
(actual pixel dimensions, `main.gd`'s renamed `_apply_window_size()`
passing them straight to `DisplayServer.window_set_size()`) — the more
direct representation once real resolutions were the goal instead of
scaling a fixed base. `_build_resolution_row()` builds an `OptionButton`
listing four 16:9 presets (1280×720 through 2560×1440 — all exact
multiples of the project's own aspect ratio, so `window/stretch/mode=
"canvas_items"` scales any of them with no letterboxing) plus a
"Custom…" entry; picking Custom reveals two `SpinBox` fields (width
640–7680, height 360–4320) that apply live on every change, matching
the sliders' own already-established live-apply convention rather than
needing a separate confirm step. The custom fields stay hidden behind
a preset match and only appear for Custom, and — since `OptionButton`
and `SpinBox` are both Godot stock controls with no relation to this
project's own dark StyleBoxFlat chrome — both got the same custom
styling treatment (dark background, thin border, 6px corner radius)
`main_menu_ui.gd`'s own seed-input `LineEdit` already established,
rather than importing `MenuUiKit`'s private `_button_stylebox()` across
a class boundary it was never meant to cross (an early pass tried
exactly that and hit a real "function not found" parse error before
landing on building the StyleBoxFlat inline instead).

Verified by rebuilding the Settings screen at three different saved
states: the project's own un-matched default (1152×648) correctly fell
back to "Custom…" with both fields showing 1152 and 648; setting
1920×1080 selected that exact preset and hid the custom fields; and a
genuinely arbitrary custom size (3413×1920) round-tripped correctly —
`DisplayServer.window_get_size()` read back that exact value, and
reopening Settings showed "Custom…" selected with 3413/1920 in the
fields, confirming the round trip works in both directions, not just
that saving a value doesn't crash.

### Main menu: embers clustered at the bottom, title read as a thick cartoon outline

Two complaints against one real screenshot of the main menu: the ember
background looked "badly placed," and the "EMBERFALL" title's style was
disliked outright. Both had real, separate root causes in
`main_menu_ui.gd`.

**Embers.** `_build_ember_particles()`'s `GPUParticles2D` had
`lifetime = 5.0` — a value that was never actually tuned against the
distance a mote needs to travel. Motes spawn just below the bottom edge
and drift upward at 18-44 px/s (ported straight from the source's own
`spawnMote()`); crossing the full canvas (648px, +40 for the spawn/
despawn margins) takes 15-38s depending on speed, not 5. At a 5s
lifetime every mote died having covered at most 220px — the screenshot
showed the entire top ~80% of the screen completely empty, every ember
crammed into a narrow band near the bottom. Retuned to `lifetime = 24.0`
(`preprocess` kept matching it 1:1, same as before, so the whole cycle
is still pre-warmed and frame 1 shows motes already spread across the
full height rather than starting from nothing). 24s is sized to the
*average* of the 18-44 px/s range rather than the slowest case:
GPUParticles2D has no equivalent to the source's own mid-flight
`if (mote.y < -20) respawn` cutoff, so a single fixed lifetime can't be
exactly right for every speed in the range — slow motes now comfortably
clear mid-screen and fast ones reach the very top before recycling,
instead of every single one dying in the bottom third.

**Title.** `shadow_outline_size = 18` on a 56px Label — a big enough
outline that it stopped reading as a soft glow (the effect the source's
own CSS actually uses: `text-shadow: 0 0 40px rgba(255,123,61,0.55)`, a
*blurred* halo) and instead read as a thick, uniform, hard-edged ring
around every letter, i.e. a cartoon outline, which is exactly what got
flagged. Godot's Label shadow has no blur — `shadow_outline_size` just
expands a hard-edged copy of the glyph outward, so one single pass at
any size can only ever be a ring, never a soft falloff. Replaced the
single Label with three stacked ones (`_build_title()` +
`_make_title_layer()`): two wide, faint, invisible-fill "glow" passes
(outline 24 at 0.14 alpha, outline 11 at 0.26 alpha) behind a crisp
front layer (outline 2, opaque fill, a 2px downward offset standing in
for the source's separate grounding drop-shadow). Stacked hard rings at
decreasing size and increasing alpha approximate a blurred gradient
without a shader — the same kind of "simplify the CSS effect to its
identity-defining parts" call this project already made for
`MenuUiKit.make_overlay`'s gradient background, applied to a shadow
instead of a fill this time.

The three-Label stack needed its own container: a plain `Control` can't
lay out overlapping children, so the first attempt hand-set the wrap's
`custom_minimum_size` from `title.get_minimum_size()` right after
building it — and got a too-small value back, because a Label's
minimum size doesn't reflect theme overrides applied before the node is
inside the live tree. The outer `VBoxContainer` reserved too little
height for the title row, and the "Last Light" subtitle rendered
overlapping into the bottom of the title (caught on a real screenshot,
not assumed). Switched the wrap to a `MarginContainer`, which computes
its own minimum size — the max of its children's — through the normal
container/tree machinery instead of a manual snapshot, and fits every
child into that same content rect; the overlap was gone on the next
screenshot with no other layout changes needed.

Verified by rebuilding the main menu against a real headless run
(Xvfb + `--rendering-driver opengl3`, no Vulkan device available in
this sandbox) before and after: the "before" screenshot showed the
empty-top-80%-of-the-screen ember clustering and the thick title
outline exactly as reported; the "after" screenshot showed motes spread
across the entire canvas height and a visibly softer, thinner title
glow with the letters reading as crisp text with a halo rather than a
cartoon outline, no subtitle overlap, and no script errors in the
console.

### Main menu title, take two: a real logo asset, keyed out of its own black backdrop

The three-Label glow approximation above was a same-session follow-up
to a real reference asset showing up on GitHub: a proper carved-stone/
ember-fire "EMBERFALL" wordmark, the kind of hand-authored logo art no
amount of Label theme-shadow stacking was ever going to match. It
replaces `_build_title()`/`_make_title_layer()` outright — both deleted,
not kept around as a fallback.

The source PNG was an opaque RGB render (no alpha channel) on a solid
near-black backdrop — every corner sampled at RGB(4-7), confirming it's
genuinely flat, not a subtle gradient — which is exactly the "there's
still a background" problem flagged when it showed up. Rather than
asking for a re-export, it gets keyed to real transparency directly:
per pixel, `alpha = ramp(max(r,g,b), low=10, high=34)` — fully
transparent at/below 10, fully opaque at/above 34, linear in between.
A soft ramp instead of a hard cutoff matters here specifically because
the art's own fire glow fades gradually into the black; a boolean
threshold would have turned that gradual bloom into a hard-edged ring,
the same "thick outline" problem the Label version had just been fixed
for. Verified two ways before it ever reached the project: composited
over a checkerboard (letter counters — the inside of B, R — punch
through to transparent, correctly indistinguishable from the true
background; no dark fringe at any letter edge) and over the menu's own
`#120c10` backdrop color (seamless — no visible rectangle boundary).
Cropped to the keyed result's own bounding box afterward, so the
in-repo asset carries no dead transparent margin and
`TITLE_LOGO_TEXTURE.get_size()` reflects real art bounds.

Wired up as a plain `TextureRect` (`expand_mode = EXPAND_IGNORE_SIZE`,
`stretch_mode = STRETCH_KEEP_ASPECT`) in place of the old title Label,
`custom_minimum_size` computed from the texture's own real aspect ratio
at a fixed 640px display width rather than a hardcoded height — self-
corrects if the source art is ever re-cropped. `size_flags_horizontal =
SIZE_SHRINK_CENTER` keeps it from being stretched to the VBoxContainer's
full width the way a centered-text Label needs to be; a texture centers
by sizing itself and letting the container center *that*, not by
stretching to fill and centering content within.

Verified against the same real headless run as every other screen this
project ships: the logo renders with no visible background rectangle,
no console errors, no layout overlap with the "Last Light" subtitle or
button column below it, and the surrounding ember particles (from the
fix above) now read as thematically reinforcing the logo's own fire
motif rather than an unrelated background effect.

### Main menu background: a real illustrated scene in place of the flat wash

A follow-up upload was a full menu mockup — the same logo, French
button labels, and a rich illustrated dungeon corridor (stone arches,
a lit torch, a torn banner, a sword and shield leaning against a
pillar) all composited together as one flat image. Not directly usable
as-is: the baked French button labels aren't the real, functional,
already-i18n'd buttons this screen builds (wrong language for an
English default, wrong position, no click handling), so using the
whole composite as the background would have drawn a second, fake,
misaligned button list behind the real one. What the upload actually
contributes is the illustration itself.

Cropped to the region clear of every baked letter and button edge —
checked visually, not assumed: a first attempt at the seam left stray
glyph fragments bleeding in from the left edge, so the crop moved
further right until a recheck showed a completely clean edge — all the
way out to the source frame's right border. That crop (`main_menu_bg.
png`, a portrait-ish 772×940 in its own right) replaces the flat
`ColorRect("#120c10")` wash entirely, via a `TextureRect` with
`stretch_mode = STRETCH_KEEP_ASPECT_COVERED`: it scales the art up
uniformly until it covers the full 1152×648 canvas and crops whatever
overflows, the same idea as CSS's `background-size: cover`, rather
than distorting the architecture's proportions to force an exact
aspect-ratio match (which a plain stretch-to-fit would have done, and
which the title logo's own `STRETCH_KEEP_ASPECT` deliberately avoids
too, just solving the opposite problem — sizing the *element* to the
art instead of the *canvas* to the art).

One legibility issue showed up on the first real screenshot: the art's
own torch flame sits close to screen-center, right behind the "Last
Light" subtitle and the footer tagline — both plain Labels with no
opaque panel behind them, unlike the buttons (which carry their own
solid fill regardless of what's under them). Text was still technically
readable but noticeably lower-contrast against the bright fire than it
had ever been against the old flat backdrop. Added a flat `Color(0, 0,
0, 0.4)` scrim over the whole scene — the same fix the reference upload
itself already uses (its own baked text sits on a darkened gradient
over this identical art) — rather than patching a panel behind each
affected Label individually; a re-screenshot confirmed the subtitle
reads clearly against the flame now, with the rest of the illustration
still clearly visible through it.

Verified against the same real headless run as everything else in this
project: no console errors, no distortion or visible seam in the
background art, the ember particles and logo both still read clearly
on top, and the "Last Light"/footer contrast issue confirmed fixed on
a follow-up screenshot rather than assumed fixed from the code change
alone.

### Main menu buttons: real button art, with real baked text removed first

A follow-up upload delivered exactly what an earlier exchange had
promised was possible: ornate diamond-tipped button chrome — Play's own
ember-lit frame plus a plain dark-stone frame repeated for every other
row — sheeted as one PNG. Same fake-transparency checkerboard as the
logo and background uploads (an opaque RGB render, no alpha channel;
confirmed by sampling — the "empty" squares were literal near-neutral
gray pixels in the 238-255 range, not real transparency), but a harder
version of it this time: the checkerboard's own color range overlaps
almost exactly with the buttons' own white label text (`(255,253,254)`
sampled directly off "JOUER"), so the brightness-threshold key that
worked for the logo would have erased real text too.

Fixed with connected-component labeling instead of a color threshold
(`scipy.ndimage.label`): flood the near-neutral-colored pixels, then
keep only whichever components actually touch the image border. The
checkerboard is one contiguous region touching every edge; white text
sits enclosed inside a dark button frame and can never be reached
without crossing non-candidate (dark) pixels first, so it survives
untouched no matter how close its color sits to the checkerboard's own.
Confirmed on a real render: every baked label (Play included) came
through fully intact while the surrounding checkerboard cleared to true
alpha=0.

The baked labels themselves still aren't reusable, for the same reason
the logo mockup's weren't: wrong language for an English default, and
this project's Buttons need live text for hover/pressed states and
i18n, not a flattened raster in French. Unlike the logo, though, the
art *underneath* the text had to survive intact for the frame to still
read as a frame — this needed the equivalent of Photoshop's
content-aware fill, not just a cutout.

The plain stone frame made this easy: every row shows what its own
text-free margins look like immediately above and below the letters, so
stretching a clean strip from one of those margins over the letter band
(PIL resize, not tiling — tiling a strip this thin at this stretch
factor produced an obviously repeating pattern, confirmed by looking
at it) filled the gap with matching material. Checked over a
checkerboard afterward: no readable letter ghosting at any zoom level
tried.

Play's ember-fire frame resisted the same trick — confirmed by trying
it twice. Flame is directional and high-contrast in a way stone isn't,
so both a stretched vertical strip and a horizontally-sourced fill from
the same row left a visible rectangle where "JOUER" used to be (a
patch reads as a patch once its neighborhood has real texture to
compare against, which the flame has and the stone barely does). What
worked instead: isolating just the letter pixels by saturation, not
brightness — flame is bright but strongly orange, so "white-ish text on
orange fire" separates from its background on saturation the way it
never could on brightness alone (checked by rendering the mask before
trusting it: it caught "JOUER" precisely and nothing else) — then
running OpenCV's Telea inpainting on only that mask, dilated a few
pixels to reach the letters' own drop-shadow edges. Inpainting fills a
small, letter-shaped gap from its own true local neighbors instead of
importing texture from somewhere else in the image, which is exactly
why it succeeds where whole-region resampling didn't: there's no
"somewhere else" in a flame that looks right stretched over a
rectangle, but there is a plausible local answer for a few isolated,
letter-thin gaps. Re-checked over a checkerboard afterward with zero
readable ghosting at normal viewing size — a very faint soft smudge
survives at heavy digital zoom, in exactly the spot the real "PLAY"
label now sits on top of anyway.

Wired up through a new `_apply_frame_texture()` helper (`main_menu_ui.
gd` only — deliberately not folded into `MenuUiKit.make_button()`,
which every other screen's buttons also use; this specific stone/fire
chrome is this mockup's identity, not necessarily right for a Settings
toggle row or a Pause menu Resume button) that wraps a Button or
LineEdit's stylebox in a `StyleBoxTexture`, sized to a fixed 300px
width with height computed from each source texture's own aspect ratio
— the same "derive from the real asset, don't hardcode a number"
approach `TITLE_LOGO_TEXTURE` already established. `content_margin_
left/right` reserve space for each frame's ornate end-caps (measured
per source image — 8% of width for the plain frame's tighter caps, 20%
for the primary frame's glow-softened ones) so real text can never
render on top of the decorative diamond tips. Godot's Button exposes
separate normal/hover/pressed/disabled stylebox slots this single
static image has no separate art for; `StyleBoxTexture.duplicate()`
(a shallow copy — same shared Texture2D, independent `modulate_color`)
gives each state its own brightness tweak (brighter on hover, dimmer
pressed/disabled) without needing 4x the source art.

Applied to Play, the three plain nav buttons (Upgrades/Armory/
Settings), and the Seed field — Credits kept its existing borderless
GHOST styling, matching how the reference mockup itself gives Credits a
lighter, no-full-box treatment rather than the same heavy frame.
Verified against a real headless run: all five re-skinned rows render
with legible, correctly-centered text and no visible artifacts from
either text-removal technique, at both normal screenshot scale and a
digital zoom crop of each one.

### In-game HUD: real Health/Stamina/Ability bar art via TextureProgressBar

A further upload delivered the same ornate treatment for the in-game
resource bars — one icon (heart/chevron/sun-and-compass) and one frame
per bar, sheeted together with each bar shown at a baked "100"/"100/100"
to demonstrate the look.

**Keying, harder than the previous two uploads.** Same fake-transparency
checkerboard as before (an opaque RGB render — confirmed no alpha
channel), but this one was a genuinely clean solid black background
(every sampled pixel exactly `(0,0,0)`, not the near-neutral-gray
checkerboard tiles the logo/button uploads had), so a plain brightness
ramp keyed it perfectly on the first attempt — no connected-component
trick needed this time, since there was no ambiguity with bright
low-saturation content to protect.

**Removing the baked numbers took four attempts, not one.** The
technique that cleanly erased "JOUER" against Play's flame frame
(saturation-based masking + OpenCV inpainting) came back to bite here:
bold numeral strokes are much thicker than script-font letters, and
raising the mask dilation to compensate just traded one artifact for
another — `cv2.inpaint`'s TELEA algorithm fills a wide hole by
propagating smoothly from its edges, and a smooth fill is exactly wrong
against a fill texture whose whole identity is a busy, high-frequency
crack pattern: even with perfect color matching, the inpainted region's
un-cracked smoothness silently retraced the numerals' own shape. A
local-contrast mask (median-blur deviation, catching both a numeral's
bright highlight AND its dark bevel edge, rather than a plain brightness
+ saturation threshold) fixed the mask's own coverage but not this
underlying smoothness problem. What actually worked: cloning a same-
height patch of real, already-cracked texture from elsewhere in the same
bar directly over the number, feathered at the edges — real texture
detail transplanted wholesale, not resynthesized, so there's no
smoothness mismatch left for the eye to catch. Re-verified over a
checkerboard afterward with the numerals completely gone, not just
faded.

**Architecture: `TextureProgressBar`, introduced to this project for the
first time.** Every other bar in `hud.gd` (`_make_bar_row()`) is a flat
`ColorRect` whose `anchor_right` gets animated 0→1 — fine for a flat
fill, but with no way to also show a fixed frame on top regardless of
fill level. `TextureProgressBar` is Godot's own purpose-built answer:
`texture_over` (the frame) always draws at full opacity no matter what
`value` is, `texture_progress` (the cleaned crack fill) is clipped to
just its own left `value` fraction via `FILL_LEFT_TO_RIGHT`, and
`texture_under` shows through the unfilled remainder — a small generated
solid-color texture standing in for this art's own missing "empty"
state, since every reference bar shows 100/100 full with no depleted
version to crop from. Added as `_make_resource_bar_row()`, a second,
parallel bar builder used only for HP/Stamina/Energy — `_make_bar_row()`
and `_set_bar_ratio()` are untouched and still drive XP/corruption/boss,
which this art was never scoped to.

**A real Godot gotcha, caught by an actual screenshot, not assumed
away:** the first working build rendered each bar at its *source
texture's own pixel width* (up to 1579px!) instead of the intended
~300px, blowing out across the whole top of the screen and covering the
top-right HUD entirely. `custom_minimum_size` alone doesn't win here —
`TextureProgressBar.get_minimum_size()` reports the texture's own native
size unless told otherwise, and Godot's actual effective minimum is
`max(custom_minimum_size, get_minimum_size())`, so the huge native-
resolution source silently overruled every explicit size set in code.
Fixed by pre-resizing the actual PNG assets to their real on-screen
target size (a clean downscale — LANCZOS, never blurry, per this
project's own established upscale-vs-downscale rule) rather than fighting
the node's sizing rules at runtime; the code's own aspect-ratio-derived
`custom_minimum_size` computation was kept as a self-correcting safety
net rather than removed, since it's now provably harmless (texture
height already equals `RESOURCE_BAR_HEIGHT`, so the formula reduces to
the texture's own already-correct size) and still protects against a
future re-crop.

One more alignment pass once real sizes were on screen: Health's own
source frame carries extra glow padding the Stamina/Ability frames
don't, giving it a visibly different aspect ratio (8.9:1 vs the other
two's 10.0:1) — at a shared height that put its right edge ~30px short
of the other two, an obvious jog in an otherwise-aligned three-bar
stack. Resized Health's frame and fill to the same 300×30 as the other
two (a mild ~12% horizontal stretch, invisible against the frame's own
asymmetric ornament) rather than leaving the mismatch or trying to
crop Health's source tighter.

Verified end to end against a real run, not just the main menu: a
temporary harness started a run headlessly and force-set
HP/Stamina/Energy to 36%/82%/3% before screenshotting — confirming
`FILL_LEFT_TO_RIGHT` clips each bar's fill to the correct fraction with
the frame still fully intact around it and the dark "empty" groove
showing through the rest, not just that a full bar renders correctly.

### HUD bars, round two: a lit end-cap gem that never turned off, and icons re-cropped denser

Playing with a drained bar exposed what the earlier full-bar screenshot
couldn't: the ornate arrow-shaped end-cap baked into each frame's
`texture_over` carries its own small faceted gem, painted with a bright
glowing core — and because `texture_over` always renders at full opacity
regardless of `value` (the entire point of the layer, so the frame stays
intact as the fill drains), that gem stayed lit at 100% brightness even
with the bar down to a sliver. Next to an obviously-drained fill, a
still-blazing gem at the tip reads as a leftover fixed piece rather than
part of the frame — exactly what got reported.

**Fix: darken the gem pixels directly in the source frame textures, not
in a shader.** No per-frame runtime state exists to dim by by (`value`
already drives the fill, not the frame), and this is a one-time asset
defect, not a behavior — so the honest fix is repainting the three
`hud_bar_frame_*.png` files themselves. Isolated the gem's actual
brightness/saturation profile (its lit core is both brighter and more
saturated than the surrounding metal, which stays warm and moderately
saturated even at its brightest specular highlights) and pulled every
pixel in that profile down toward the frame's own dark tone, scaled by
how far over the threshold it sat — so the faceted diamond *shape*
survives as a normal, unlit socket ornament (matching the other, already-
unlit gems elsewhere on the same frame) instead of vanishing into a flat
hole.

**A second, less obvious fixed piece, found only by comparing all three
bars side by side:** Stamina's frame carried a patch of fully-saturated
green immediately left of its end-cap — the same structural element
Health and Ability also have there, but baked much more opaque and far
more saturated for Stamina specifically, so it alone read as a solid
static chunk regardless of fill level (Health's and Ability's equivalent
patches are faint enough to pass as shadow). A brightness-based mask
couldn't isolate it — its pixels are individually fairly dark, just
saturated — so this needed a hue-based mask instead (green channel
clearly dominant over both red and blue), which is safe specifically
*because* nothing else in any of the three frames' warm bronze/copper
palette is ever green-dominant: the same mask fires on ~5,800 pixels for
Stamina and exactly zero for Health or Ability, confirming it targets
only the actual anomaly. Muted it toward the frame's own dark neutral and
cut its opacity to match its siblings' faintness, rather than inventing a
color for it.

**The centering complaint, and what "recadrer" (re-crop) turned out to
mean in practice.** Pixel-level investigation — alpha-weighted centroids,
strict-alpha bounding boxes, grid overlays comparing icon extents against
the bar's own extents in both the live screenshot and the original source
sheet — found no single layout bug: icon and bar are both hard-set to the
exact same `RESOURCE_BAR_HEIGHT` (30px) inside the same row, with no
stray margin or misaligned anchor on either side. What the numbers didn't
capture is that each icon (a heart, a chevron-stack, a sun) is a spiked
medallion tapering to thin points at its own top and bottom, so even the
tightest possible alpha-based crop spans nearly the icon's full slice
height while carrying far less visual *mass* near those edges than the
bar's uniformly-dense rectangle beside it — a real optical effect, not a
measurement error. Re-cropped each icon tighter around its bold medallion
core, deliberately trimming the thin spike extremities the original crop
preserved, so the icon now reads as filling its row the way the bar does.
This is a best-effort reading of an inherently fuzzy complaint rather
than a confirmed root-cause fix — worth another look if it still doesn't
land.

Re-verified with the same kind of harness as the first HUD pass — a
headless run forced to a partial, unequal fill on all three bars
(≈33%/31%/25%) before screenshotting — specifically because the bug only
shows up once a bar has visibly drained; a full-bar screenshot would have
passed either version of the frame art.

### HUD bars, round three: a genuinely oversized icon, and more breathing room between rows

A follow-up screenshot at the *default* 100/100/100 state (rather than
the partial fill the previous round tested with) surfaced what a drained
bar hadn't: the Stamina icon read as visibly larger and less contained
than Health's and Ability's next to it, and none of the three rows had
much room between them.

**The Stamina icon was a real, measurable outlier, not an optical
illusion this time.** Every icon is sized off its own texture's aspect
ratio at a shared height (`RESOURCE_BAR_HEIGHT`, `hud.gd`'s
`_make_resource_bar_row()`), so a wider source texture directly becomes a
wider on-screen icon. Stamina's dense crop from the previous round
(195×90, a 2.17:1 aspect — a chevron core flanked by two horizontally-
splayed gem ornaments) is meaningfully wider relative to its height than
Health's (195×112, 1.74:1) or Ability's (195×127, 1.54:1), so at the same
render height it came out 65px wide against their 52px and 46px —
confirmed by direct measurement, not just by eye. Rather than re-crop the
source horizontally (risking an asymmetric cut through one of the two
gem ornaments, which sit at slightly different distances from center),
padded its canvas vertically instead — 195×90 centered inside a new,
transparent 195×112 canvas, matching Health's own aspect ratio exactly.
Since on-screen width is derived from height × aspect, and the padding
lowers the aspect ratio without touching a single content pixel, the
whole icon now renders at 52×30 (down from 65×30) with a few pixels of
natural breathing room top and bottom — smaller *and* better centered,
from one change, with the source art itself untouched.

**Separately, gave every row more room to begin with.** Pixel-sampling
the previous build's screenshot column-by-column showed the three rows'
own rectangular fills were already cleanly separated by a dark gap — but
each row's *ornamental* edges (the icon's flanking gem tips, the frame's
jagged top/bottom trim) sit close enough to their own row's boundary that
they had almost no margin against the neighboring row, reading as
crowding even without literally crossing into it. Raised the HUD column's
`VBoxContainer` separation from 6px to 11px (`hud.gd`'s
`_build_top_left()`) — cheap, low-risk, and it helps regardless of which
element a future re-skin makes wider or spikier again.

Verified against the same default-100% state the report screenshot used
(rather than a forced partial fill, since both of this round's fixes are
independent of resource level): Stamina's icon now sits at the same
visual scale as its neighbors, and all three rows show a clear dark
margin above and below their ornamental edges, not just their plain
rectangles.

### HUD bars, round four: the actual root cause — three bars that were never the same width on screen

Two more rounds of "something still sticks out at the end of the bar"
kept pointing at the same spot, and neither a gridline-verified check
(no vertical overflow) nor removing the right-end diamond ornament
outright made it go away. The user's own read of the follow-up
screenshot is what actually found it: the three bars are not the same
length on screen, and the "overflow" was always that mismatch, not the
diamond's shape.

**Root cause: the bar starts right after its own icon, and the icons
aren't the same width.** `_make_resource_bar_row()` packs icon then bar
into one `HBoxContainer` with fixed separation — so even though every
`TextureProgressBar` control is sized identically (all three frame
textures are 300×30, giving identical `custom_minimum_size`), each row's
bar starts at a different x because it's placed immediately after
whatever width that row's *icon* happens to be. Ability's icon (46px,
from the previous round's own re-crop) is 6px narrower than Health's and
Stamina's (52px each), so Ability's whole row — icon and bar both — sits
6px further left, and an identically-*sized* bar ending 6px further left
reads as a *shorter* one next to its neighbors. Three individually
correct bars that still didn't line up as a column.

Fixed by giving every icon a fixed-width slot instead of letting it pack
at its own native width: a `CenterContainer` (`ICON_SLOT_WIDTH := 52.0`,
matching the widest icon already in use) now sits between the row and
the icon, so Health's and Stamina's icons fill it exactly as before and
Ability's is centered inside it with a few pixels of margin either side.
All three bars now start — and, being the same width, end — at the same
x. Verified by measuring the actual on-screen right edge of each bar's
own fill color (not a raw brightness threshold, which turned out to
false-positive on the stone floor's own background texture variation at
exactly the wrong x once): Health, Stamina and Ability all now end
within a single pixel of each other, confirmed against a cyan guide line
drawn across all three in the same screenshot.

**The previous round's diamond removal turned out to have quietly made
this worse, not better.** Trimming each frame's right-end ornament used
a per-image cutoff picked from where that specific image's own diamond
happened to start (x=270 for Health, x=260 for Stamina/Ability, out of
each 300px-wide frame) — a reasonable per-image call at the time, but it
meant Health's frame kept 10 more pixels of visible width than the other
two's, adding a second, independent misalignment on top of the icon-slot
one above. Re-cut Health at the same x=260 the other two already used
once this was caught, rather than leaving three assets that no longer
agreed on where "the end of the bar" is.

The right-end diamond ornament itself stays removed for now (this round
didn't re-litigate that call) — the left end, against the icon, still
has its matching decorative arrow.

### HUD bars, round five: restoring the diamond now that alignment is fixed

With the icon-slot alignment fix in, the natural next question was
whether the right-end diamond ever actually needed to go — or whether it
only ever looked wrong *because* it was riding on top of three
inconsistently-positioned bars. Restored the full ornament (gem-dimmed,
per round two, but not cut off) on all three frames from the same
pre-cut source the round-three removal started from, re-resized fresh to
300×30, and re-checked.

It holds up: with every bar now starting and ending at the same x,
the diamond tip lands at the same relative position on all three,
confirmed the same way as the alignment fix itself — a guide line drawn
across all three rows in one screenshot, which now clears each
diamond's tip by the same margin on Health, Stamina and Ability alike,
instead of Health's sitting further right than the other two's the way
it did before round four's fix. What had looked like "the ornament
itself is the problem" across three separate rounds was consistently a
symptom of the underlying column misalignment, not a defect in the
diamond shape or size — restoring it changes nothing about that
alignment, since it only affects `texture_over`'s own pixels, not the
`TextureProgressBar` control's size or position.

### HUD bars, round six: the colored fill itself bled past the box into the connector

With the diamond back and correctly aligned, one more thing still read
as wrong: the coloured fill (`texture_progress`) isn't clipped to the
frame's own decorated "box" region — `FILL_LEFT_TO_RIGHT` clips it to a
fraction of the *entire* 300px control, and every `hud_bar_fill_*.png`
had real, opaque color data across its full width, box and connector and
all. At 100% that's invisible only where the frame happens to be opaque
on top of it; in the thin, mostly-transparent connector strip between
the box's right border and the diamond (a ~2px bottom line with
transparency above and below it — the same region round four traced
while fixing the alignment), the raw fill color showed through those
transparent gaps instead of the frame's own dark metal tone, so the
"meaningful" colored bar never had a clean right edge — it just trailed
off into that connector strip before the diamond swallowed it. Asked
directly, the request was exactly this: the bar should stop precisely
where the gem starts, not fade through the gap first.

Fixed at the fill-texture level, matching the boundary already
established for the frame's own diamond removal: made every
`hud_bar_fill_*.png` transparent from x=260 onward (the same cutoff
Stamina's and Ability's frames used, and Health's was re-cut to match
in round four), so `texture_progress` has no color left to reveal past
that point regardless of `value` — a 33% bar and a 100% bar both now
stop their color at the identical x, they just differ in how much of
the 0-260 range is filled in. `texture_under`'s flat dark track color
shows through the connector's transparent gaps instead, reading as the
frame's own inert metal groove rather than an extension of the resource
bar. Verified at both 100% and a mixed partial fill (56/73/43 —
deliberately uneven, so a stray per-bar regression in the clip math
wouldn't hide behind three identical numbers): all three now show a
clean, snapped-off color edge with a visible dark gap before the
diamond, at any fill level.

### HUD bars, round seven: the end-cap gem becomes its own element, from a cleaner reference

The user resolved the ambiguity every earlier round had been guessing
at by posting the original ChatGPT-generated reference sheet directly
(re-uploaded to the repo's `main` branch, `ChatGPT Image 13 sept. 2026,
13_58_44.png`) and asking for the bars to match it. At full resolution
this settled a question none of the prior rounds had actually asked:
in the source art, the end-cap gem is not part of the bar at all — it's
a separate ornament with real dark space between it and the box's own
right border, the same bookend relationship the icon already has on
the row's other end. Every round through six had instead kept it fused
to the frame texture, connected by a thin metal line with no true gap —
structurally different from the reference regardless of how well its
brightness or alignment was tuned, which is why "something at the end
doesn't look right" kept resurfacing under different descriptions.

**Extracting the gem as its own texture, from source material worth
re-deriving from.** This upload is the same subject at meaningfully
higher fidelity than the sheet the original HUD reskin worked from —
2125×740 against the old crop's 1774×602 — so re-extracting the gem
fresh from it, rather than continuing to patch the lower-resolution
asset, was worth the redo. Keying was the easy part (solid black
background, same brightness-ramp approach as the original HUD sheet).
Finding the gem's own left boundary wasn't: a naive crop caught the
tail end of the bar's own crack-fill color bleeding in, since the gem
sits close enough to the bar that any generous bounding box overlaps
it. Fixed by scanning for each row's own saturated fill-color signature
(high red for Health, high green for Stamina, same idea for Ability)
across a full column instead of eyeballing an x-coordinate — the
fraction of "real fill color" per column holds steady near the bar's
own color for its whole length, then collapses sharply over a handful
of pixels at almost exactly the same x for all three (≈1790-1798, out
of 2125), which is the actual gap the reference draws between box and
gem. Cropping from there instead of an earlier guess left a clean
ornament with only a faint, plausible ember-glow bleeding in from the
left — feathered its last ~14px anyway as a safety margin against
whatever of that is still bar rather than ambient light.

**Wiring it in as a true sibling, not a patch on the frame.** Cropped
`hud_bar_frame_*.png` and `hud_bar_fill_*.png` down to 260px (from
300) — an actual canvas crop, not another alpha-zeroing pass like
rounds three and six's — removing the connector line and old baked-in
diamond entirely, so `TextureProgressBar.custom_minimum_size` (derived
from the frame texture's own size, same pattern as everywhere else in
this reskin) shrinks with it instead of leaving 40px of invisible
reserved space that would have pushed the new gem too far right.
`_make_resource_bar_row()` takes a new `gem_texture` parameter and adds
a `TextureRect` as the row's third child (after icon-slot and bar),
sized the same way the icon already is (aspect-derived width at
`RESOURCE_BAR_HEIGHT`) — the row's own `HBoxContainer` separation (6px)
now does double duty as the gap on both sides of the bar, for free,
without a special case.

One side effect worth naming rather than silently accepting: the gem
is now always fully lit, matching the reference, which never shows a
depleted state to design against. Round two's argument for dimming it
— that a lit gem next to a drained bar read as "a fixed piece left
behind" — doesn't obviously disappear just because the gem moved. What
does change is the visual grouping: a gem fused to the bar via a
connector line reads as part of the same element the fill belongs to,
so a viewer expects it to react to fill state the way the color does;
a gem separated by real dark space reads as its own bookend ornament,
the same way the icon on the row's other end was never expected to
react to fill state either. Left it lit on that basis rather than
re-applying round two's dimming preemptively — worth a real partial-
fill screenshot in front of the user rather than assuming either
reading is right from here.

### HUD bars, round eight: the icons themselves were the ones actually cut off

A zoomed-in screenshot of just the three icons finally made a much
older decision visible for what it was: round one's "recadre" fix
(the very first response to "pas bien centré") had deliberately
trimmed each icon tighter around its bold medallion core, cutting off
the thin outer spike tips the original crop preserved, reasoning that
the tighter crop would read as denser and better-filling its row. It
did — but "denser" and "cut off" are the same edit described by two
different viewers, and a full-resolution look at the reference this
round already had on hand (the same sheet round seven re-extracted the
gem from) settled which reading was right: every icon's outer spikes
are a real, deliberate part of the design, not incidental padding
around a "true" dense core.

**Re-extracted all three icons from the same high-fidelity source,
this time keeping the full housing.** Same keying approach as the gem
(clean solid-black background), same bar-bleed problem on the edge
facing the bar (icon and bar sit close enough here that, unlike the
gem's clearly-separated right side, there's no wide gap to crop
into) — handled the same way, with a feathered fade on that edge
rather than a hard cut, rather than the gem's fill-color-signature
scan, since the icon-to-bar boundary here runs across a much fuzzier,
closer transition than the bar-to-gem one did. Sized the same way
every asset in this reskin has been since round one — height locked to
`RESOURCE_BAR_HEIGHT`, width derived from each icon's own aspect ratio
— which is why this didn't need a code change, only new source files:
`hud_icon_health/stamina/ability.png` at the same filenames `hud.gd`
already preloads.

The three now render at 35/42/43px wide (up from the deliberately
trimmed 52/52/46) with their full spiked-diamond silhouette intact —
visibly denser than before despite being smaller in raw pixels,
because a complete spike crown reads as more solid than the same
crown with its points sawn off, confirming that round one's fix was
solving a real complaint with the wrong tool: crop for density is a
lossy trade against the source art, when the actual fix was always to
use a truer copy of it.

### HUD bars, round nine: the gem glued flush against the bar, overriding the reference

Explicit request this round, overriding round seven's own reference-
matching choice: glue the gem directly against the bar with zero gap,
rather than the dark space the source sheet actually draws there. Not
a rediscovery of a missed detail this time — a deliberate stylistic
departure from the reference, stated as one.

`_make_resource_bar_row()`'s row previously held icon-slot, bar and
gem as three siblings in one `HBoxContainer`, so a single `separation`
value set the gap on both sides of the bar identically — no way to
close one gap while keeping the other. Nested the bar and gem inside
their own inner `HBoxContainer` (`separation = 0`), itself the row's
second child after the icon slot: the outer row's 6px separation still
opens the icon-to-bar gap, the inner container's zero closes the
bar-to-gem one. No texture changes — this is a container-nesting
change only, so it also sidesteps round seven's own concern about
fusing the gem back into the frame texture (which had tied its
apparent size and position to the bar's own width and cropping).

### Floor braziers: a real photo, keyed by diffing against this project's own floor texture

A supplied reference — a top-down, lit brazier sitting on cracked stone
— replaced `obstacle_node.gd`'s `_draw_brazier()`, previously pure
procedural drawing (a flat trapezoid "bowl" plus a two-Bézier-arc flame
silhouette, no real art at all).

**The keying problem every other asset this project pulled from a
generated image didn't have:** no clean solid-color or checkerboard
background to threshold against — the brazier sits on a busy, natural
stone-floor photo. What made this tractable: the reference (1254×1254)
turned out to be pixel-dimension-identical to this project's own
`floor_stone.png`, and diffing the two directly showed near-zero
difference everywhere except the brazier's own silhouette (and its
cast shadow) — strong evidence the reference was generated starting
from this exact floor tile with the brazier composited on top, not a
coincidence of matching canvas sizes. That difference map, not a
brightness or color threshold, became the alpha mask: thresholded,
kept only the largest connected region (dropping scattered unrelated
floor-texture noise elsewhere in the frame), holes closed, a stray
disconnected blob from a shadow/lighting difference manually trimmed,
edges softened with a small Gaussian feather.

The resulting silhouette is a little ragged rather than a clean traced
outline — expected, given the mask comes from "how much did this pixel
change" rather than "where does the object's edge fall." Composited
onto this project's own floor tile at an offset (to confirm it wasn't
just re-revealing the identical source pixels underneath), the ragged
edge reads as scorched, uneven stone around a fire pit, not as a
cutout error — left alone rather than smoothed.

**Integration follows the `shop_stall.png`/`STALL_TEXTURE` precedent**
already established in this same file (the one other painted-image
obstacle, everything else here being `_draw()` procedural generation):
`draw_texture_rect()` inside `_draw_brazier()`, sized off `radius`
(`radius * 4.5`) and the texture's own aspect ratio, rather than a
child `Sprite2D` node — consistent with every other visual this class
draws. Centered on both axes, unlike the stall's own top-anchored
placement: the stall is an angled structure standing on the floor, so
its own comment describes measuring how far down its sprite to anchor
against the ground; this brazier is a flat top-down photo of a round
object, with no "which part touches the floor" question to answer —
the ring's own center is the obstacle's true position. The old
version's flicker (a sine-driven flame-height scale) has no silhouette
left to redraw against, so it survives as a much subtler ±3% sprite
scale pulse instead, just enough that the object doesn't read as a
static decal. The real `PointLight2D` glow this file already sets up
per-visual-type (`_set_light()`, unchanged) still lights the scene the
same way regardless of what draws the silhouette underneath it.

Verified with a temporary harness spawning a brazier directly next to
the player (rather than navigating to a REST room, where this visual
normally spawns, which headless input can't easily steer to) — the
sprite renders, blends into the floor as intended, and the existing
warm point light still glows around it.

### The brazier, replaced again: a cleaner reference, same extraction technique

A second reference — visually similar (still a top-down lit brazier
on cracked stone) but a cleaner, more symmetric design: 8 evenly-
spaced spikes around a perfectly circular ring rather than the first
image's 4 larger, less regular ones — replaced `brazier.png` outright,
same filename, no code changes.

Same extraction technique as the first (diff against this project's
own `floor_stone.png`, largest connected component, holes closed,
edges feathered) worked again without modification: this second
upload was also generated from that exact floor tile (confirmed the
same way — near-zero difference everywhere except the object's own
silhouette). The resulting mask came out cleaner and closer to a true
circle than the first attempt's, matching this design's own more
regular geometry.

### The brazier, replaced a third time: a spec sheet instead of a single frame, enabling a real flame animation

Where the first two references were each a single flat "final result"
image, the third upload was a full spec sheet: a callout of the
brazier object alone (unlit coals, no flame), an 8-frame flame
animation strip, a glow/light sample, a composited "final result," an
in-game top-down preview against this exact project's own
`floor_stone.png`, and a character-scale reference. That in-game panel
is what justified switching art direction rather than treating this as
just another same-style swap: it showed the painted-icon ring reading
cleanly against this game's real floor, at a scale similar to what was
already placed.

**A much easier keying problem than the first two rounds.** Those had
no clean background at all — the object sat directly on a busy
stone-floor photo, forcing the floor-diff technique described above.
Every panel on this new sheet, by contrast, sits on a plain near-black
field (peak brightness in the low 20s outside the artwork itself), so
a normal brightness threshold works — with one wrinkle: the ring's own
coal bed is dark too (some pixels in the single digits), close enough
to the background's own brightness that a flat threshold alone would
punch transparent holes through it. Fixed the same way this project's
button-sheet checkerboard was: `scipy.ndimage.label` on the
"candidate dark" mask, keep only the components that DON'T touch the
crop's border (the coal bed is fully enclosed by brighter metal and
gems; true background always has a path out to the border),
`binary_fill_holes` to close what's left, then a soft distance-
transform feather on the final edge.

**Cropping the 8 flame frames to one shared box, not each one's own
tight bounding box.** Each frame's own silhouette is a slightly
different flame shape and width, and cropping every frame tightly to
its own content would make the fire appear to jump left/right/up/down
as frames swap — visible jitter, not flicker. Instead, every frame was
cropped to an identical 96×126 box, positioned per-frame only by its
own horizontal center and the y-coordinate where it meets the coal
line (both measured directly off the sheet, consistent within a couple
of pixels across all 8 frames), so the same fixed point within that
box — `BRAZIER_FLAME_BASELINE_FRACTION` down from its top — is the
fire's anchor in every frame, and only the flame shape above that
point changes.

**`_draw_brazier()` now draws two textures instead of one.**
`BRAZIER_RING_TEXTURE` (the unlit object, always visible, same
`draw_texture_rect()`-off-`radius` sizing as before) underneath, then
whichever of the 8 `BRAZIER_FLAME_TEXTURES` the current time picked
(`BRAZIER_FLAME_FPS = 10.0`, phase-offset per instance by
`seed_value` so multiple braziers in the same room don't flicker in
lockstep) on top, scaled to `BRAZIER_FLAME_WIDTH_RATIO` of the ring's
own on-screen width and positioned so its baseline lands on the ring's
center. That ratio (0.62) isn't something the sheet states directly —
its object and flame callouts are independent close-ups, not drawn to
a shared scale — so it was tuned by eye against a real headless render
until the fire read as overflowing the coal bed the way the sheet's
own "RÉSULTAT FINAL" composite does, rather than looking lost inside
the ring. The old single-texture version's flame-height scale pulse is
gone entirely: with 8 real hand-drawn frames doing the animating, a
synthetic scale wobble on top would be redundant rather than
additive. The `PointLight2D` glow (`_set_light()`, unchanged) still
lights the scene the same way regardless of which texture(s) draw the
silhouette underneath it.

Verified the same way as the first two rounds: a temporary harness
spawning a brazier directly next to the player, two screenshots ~0.3s
apart confirming the flame frame actually advances (not just present),
`brazier.png` (the now-superseded single-frame texture) removed from
the project entirely rather than left as dead weight.

Follow-up from that same verification screenshot: next to the player,
the new two-texture brazier read noticeably larger than the old
single-frame one had at the same `radius * 4.5` sizing — the flame
overflowing above the ring adds visual bulk the flat baked composite
never had. Cut the multiplier to `radius * 3.6` (ring and flame both
scale off it, so the two stay in proportion) and re-verified with the
same harness.

One more follow-up: the shrink above also shrank the flame along with
the ring, and the flame itself was asked to read bigger, not smaller —
reaching roughly another half-ring-height above the ring's own rim
instead of just poking over it. `BRAZIER_FLAME_WIDTH_RATIO` alone
controls that (flame height follows from its fixed aspect ratio once
its width is picked): raised from 0.62 to 0.85, re-verified with the
same harness.

Final follow-up: asked to revert that last size bump and instead
recenter the flame. `BRAZIER_FLAME_WIDTH_RATIO` went back to 0.62, but
reverting size alone wouldn't have fixed what the bigger flame had
actually made visible — a real, previously-unnoticed asymmetry. A
close-up render (a temporary huge `radius`, not a camera change, is
the cheapest way to blow up a `_draw()`-based sprite for inspection)
showed the fire's tip leaning right of the ring's own axis in 6 of the
8 frames, by as much as 11% of the frame's own width — invisible at
normal HUD-bar-icon-sized rendering but obvious once the flame was
tall enough to stand apart from the ring. Measuring precisely (an
alpha-weighted centroid over just the top 15% of each frame's content,
vs. the same centroid over the whole frame) showed why a single global
fix couldn't perfectly satisfy both ends: the tip leans one way while
the wider body near the coal line was already close to centered, so
shifting each frame far enough to zero out the tip's lean pushes the
body off by a comparable amount in the other direction — the flame
shapes themselves aren't laterally symmetric top-to-bottom, so no
horizontal shift can center both. Split the difference — each frame
shifted by half its measured tip offset, re-extracted from the
original sheet at that adjusted crop position (same border-safe
threshold technique as before) — leaving both ends within about half
their original worst-case offset rather than trading one asymmetry for
an equal-and-opposite one. Re-verified both close-up and at normal
size with the same two harnesses.

One more follow-up, after the horizontal fix above: asked to center
the flame on the ring's own middle instead. Every flame frame had been
positioned by its baseline (`BRAZIER_FLAME_BASELINE_FRACTION`, a fixed
fraction down from the top of its shared crop box) landing on the
ring's center, so the fire read as rising up out of the coal bed —
correct for a literal photo of a fire, but here it left most of the
flame floating above the ring's rim rather than filling the bowl.
Dropped that baseline anchor entirely and centered the flame's own box
on the ring's center instead, the same way the ring itself is
centered — one less constant to maintain, and the fire now reads as
sitting in the bowl rather than hovering over it.

### The player: from a hooded wraith to an armored knight, and a real bug the redesign exposed

A supplied reference — a full mockup of the in-game HUD with a knight
character mid-room next to a torch — asked for the character's own
look, not the torch (already covered above; the one in this reference
turned out to be the same design, just shown in context). Where the
player had been a procedural hooded, cloaked figure with a single
glowing eye (a "wraith guarding an ember" reading), the reference
showed an armored knight: a pointed steel helm, rounded pauldrons, a
flowing dark red cape, and a sword with a small amber gem set into its
guard.

**Redesigning the procedural silhouette, not replacing it with a
sprite.** The player's `_draw()` is pure code — ellipses, Bézier blobs,
and polygons composed through a shared bob/squash/death-rotation
transform (`_body_xf`) that every other animation state (movement,
attack swings, dodge, death) already depends on. A single static
reference image is one pose from one angle; swapping in a real sprite
would only be correct facing that one way, breaking every other
facing, the attack swing, and the death tumble. Redesigning the same
procedural pieces to read as this new silhouette keeps all of that
working unchanged, the same tradeoff already made for the brazier
above (spec sheet → real texture) doesn't apply here — there, an
unlit object and a flame just have to look right; a character has to
move.

**New pieces, ported one-for-one from the old hood/eye:**
- The old hood's 3-segment Bézier cone (a dome pointing up, away from
  the body) is gone; the skull ellipse itself is now the helm's crown,
  recolored to steel. A small wedge — `face_dir`-oriented, not damped
  by `head_angle` the way the crown itself is, with a thin outline so
  it doesn't disappear into the same-toned crown behind it — stands in
  for a nasal guard, riding the front edge and swinging to point
  wherever the character currently faces.
- The old single round eye-glow is now a narrower slit (same position
  formula, `eye_x`/`eye_y`, just flattened), reading as a visor rather
  than a hood-gap.
- Two new pauldron ellipses, fixed to the body (not `head_angle`-
  rotated — shoulders don't turn with a subtle head tilt the way a
  hood's peaked point plausibly would), give the torso an armored
  silhouette the old plain robe-ellipse body didn't have.
- The cape's own geometry (three Bézier segments, trailing opposite
  whichever way the character is moving or facing) is untouched —
  only its color changed, purple-grey to blood red.
- A small ember glow now sits at the weapon's guard (`_draw_weapon`,
  reusing the same manual arm_offset/rotate/`_body_xf` replay the
  chest ember's own center already needed, since `draw_glow_circle`
  takes one plain point with no per-point transform hook) — the same
  light the chest carries, reaching out to the hand that bears it.

**A new `STEEL`/`STEEL_DIM`/`STEEL_BRIGHT` palette family, deliberately
darker than a real steel swatch would suggest.** First attempt used a
mid-light neutral grey (a believable "steel" color read in isolation)
and it rendered as a washed-out warm tan in-game. Traced why:
`LevelFlow`'s per-room `CanvasModulate` darkens every canvas-polygon
fill first (`_update_ambient()`'s zone-darkness lerp toward a near-
black tint), then the room's own warm `PointLight2D` sources add
brightness back on top of that — and a flat color fill, unlike a
painted texture with its own baked-in shading, has no contrast of its
own to survive that round trip with its hue intact. Every other color
this file already uses for the player (`BG0`-`BG3`, the old hood's
literal `"#2a2632"`) sits in the same 10-50-per-channel range for
exactly this reason; the new steel family was re-darkened to match
once a real headless render showed why.

**A genuine, previously-unnoticed rendering bug, found while checking
the sword rendered at all:** it didn't. `_draw_weapon()`'s melee blade
is built from two quadratic Bézier curves — one from the grip out to
the tip, one back — meant to trace a simple lens/blade outline. Tracing
the actual point data, the two curves cross each other partway down
the blade's length: the "top" curve starts on the shape's lower side
and ends on its upper side, while the "bottom" curve does the reverse,
each swapping sides only somewhere in the middle. That makes the
result a self-intersecting ("bowtie") polygon, and Godot's
`draw_colored_polygon` — unlike the Canvas2D `fill()` this file ports
from, which fills a bowtie path fine under its own winding rule —
silently drops the fill when its triangulator can't handle one,
logging `Invalid polygon data, triangulation failed` and moving on.
That exact error had been showing up in this project's own headless
verification output for other rounds this session, dismissed each
time as unrelated to whatever was actually being checked; instrumenting
`_draw_weapon()` directly and counting lines confirmed a 1:1 match
between the error and every single weapon redraw — every melee
weapon's blade has silently never rendered, only its grip has. Fixed
by swapping which curve's base corner gets `+3` vs. `-3`: each curve
now starts and ends on the same side its own control point already
pulls it toward, so the two stay apart along the whole span and meet
only at the tip and at the shared base edge, the same silhouette the
math was always meant to produce.

Verified with a temporary harness: a real run, the camera zoomed onto
the player in place (`Camera2D.zoom`, cheaper than inflating geometry
the way the brazier close-up used `radius` — the player has no such
scale-everything knob) to inspect the design at a size actual gameplay
never renders it at, across facing right, facing up-left, mid-attack-
swing, and the death tumble — confirming the helm's nasal guard and
visor track facing correctly, the cape and blade both swing with it,
the blade itself is now visible, and death's rotation/fade still reads
correctly with the new colors.
