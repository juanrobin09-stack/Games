class_name VfxPresets
extends RefCounted
## Ports the 13 rendering/ParticlePresets.ts functions this build-order
## step actually has a caller for (build-order step 8 — see VfxSystem's own
## header for the engine/rewrite rationale). Every function below is a thin
## wrapper around VfxSystem.emit(), one call per TS ps.spawn()/ps.burst()
## in the source function, in the same order.
##
## Not ported, on purpose:
## - spawnBloodlessDust, spawnFireFlicker, spawnSmoke, spawnMagicSparkle,
##   spawnPickupTrail: dead code in the TS source itself — defined in
##   ParticlePresets.ts but never called from anywhere in the Web build
##   (verified by grepping every call site). Porting an unreachable preset
##   would just be unused surface area.
## - spawnEmberBurstVfx: every TS call site is the player's Ember Burst
##   ability's damage application, an emberCritical-synergy detonation, or
##   one of the Ashen Colossus's phase attacks (slam/shockwave/projectile
##   impact) — none of those exist in this port yet (player.gd's
##   start_ability() is animation-only with no damage effect resolved yet,
##   and boss.gd has no attack FSM driving boss_state at all — see this
##   step's README note). Nothing to wire it to.
## - spawnZoneAmbientParticle (drawRoom.ts, not ParticlePresets.ts, but the
##   same shape of gap): reads ZoneDefinition fields (ambientParticle,
##   sporeColors, palette.ambient/accent) that don't exist on this port's
##   ZoneDefinition resource. A genuine atmosphere addition, not a
##   feedback effect tied to an existing action — left for a dedicated pass.
## - The 3 spawnHealSparkle call sites and spawnChestOpenBurst's reward-shown
##   gate, spawnLevelUpBurst's bow-unlock variant, and spawnDeathBurst's
##   boss-specific two-tone flourish: each depends on the shop/event UI or
##   reward-granting system, which is step 9, not built yet. The other call
##   site(s) of each of those same presets — the ones that don't depend on
##   unbuilt UI — are still wired below.
##
## A few deliberate, noted approximations recur (see VfxSystem's header for
## why): a constant extra directional bias added on top of an otherwise-
## radial TS burst is dropped rather than modeled; independent vx/vy jitter
## ranges become a narrow upward cone; and where TS randomizes a particle's
## start size AND end size independently (spawnSporeBurstVfx's burst), the
## ratio used here is the two ranges' midpoints, since VfxSystem's
## scale_curve can only express one constant ratio per emission.

static func hit_impact(parent: Node, pos: Vector2, color_hex: String, crit: bool) -> void:
	VfxSystem.emit(parent, {
		"position": pos, "count": 14 if crit else 8,
		"speed_min": 60.0, "speed_max": 320.0 if crit else 200.0,
		"gravity": 260.0, "drag": 2.2,
		"size_min": 2.0, "size_max": 5.0 if crit else 3.4,
		"color": color_hex, "end_color": Palette.BG0,
		"life_min": 0.25, "life_max": 0.5,
		"glow": true, "shape": "spark",
	})
	var ring_size: float = 22.0 if crit else 14.0
	var ring_end: float = 60.0 if crit else 32.0
	VfxSystem.emit(parent, {
		"position": pos, "size_min": ring_size, "end_size_ratio": ring_end / ring_size,
		"color": Palette.EMBER6, "alpha": 0.55, "life_min": 0.22,
		"glow": true, "shape": "ring",
	})

static func death_burst(parent: Node, pos: Vector2, color_hex: String) -> void:
	# TS mixes spark/circle 50/50 per-particle within one 22-count burst;
	# GPUParticles2D's texture is one-per-node, so this splits into two
	# 11-count bursts of each shape instead of picking a single shape.
	for shape in ["spark", "circle"]:
		VfxSystem.emit(parent, {
			"position": pos, "count": 11,
			"speed_min": 40.0, "speed_max": 260.0,
			"gravity": 200.0, "drag": 1.6,
			"size_min": 2.0, "size_max": 6.0,
			"color": color_hex, "end_color": Palette.BG0,
			"life_min": 0.4, "life_max": 0.9,
			"glow": true, "shape": shape,
		})
	VfxSystem.emit(parent, {
		"position": pos, "size_min": 10.0, "end_size_ratio": 7.0,
		"color": color_hex, "alpha": 0.6, "life_min": 0.4,
		"glow": true, "shape": "ring",
	})

static func perfect_dodge_burst(parent: Node, pos: Vector2) -> void:
	VfxSystem.emit(parent, {
		"position": pos, "count": 12,
		"speed_min": 60.0, "speed_max": 140.0,
		"drag": 3.2, "size_min": 1.5, "size_max": 3.2,
		"color": Palette.SOUL_BRIGHT, "end_color": Palette.BG1, "alpha": 0.95,
		"life_min": 0.25, "life_max": 0.45,
		"glow": true, "shape": "circle",
	})

static func spore_burst_vfx(parent: Node, pos: Vector2, radius: float) -> void:
	VfxSystem.emit(parent, {
		"position": pos, "count": 22,
		"speed_min": radius * 0.6, "speed_max": radius * 1.6,
		"gravity": -8.0, "drag": 2.4,
		"size_min": 4.0, "size_max": 9.0, "end_size_ratio": 14.0 / 6.5,
		"color": Palette.FUNGUS, "end_color": Palette.FUNGUS_DIM, "alpha": 0.7,
		"life_min": 0.6, "life_max": 1.2,
		"glow": true, "shape": "circle",
	})
	VfxSystem.emit(parent, {
		"position": pos, "size_min": radius * 0.25, "end_size_ratio": 4.0,
		"color": Palette.FUNGUS_BRIGHT, "alpha": 0.55, "life_min": 0.32,
		"glow": true, "shape": "ring",
	})

## Single drifting spore mote — callers loop this to scatter several, same
## as the TS call sites do (a for-loop of individual spawnSporeMote calls,
## never ps.burst()). TS's 70/30 fungusBright/soulBright per-mote color
## pick is rolled right here since each call is already exactly one mote.
static func spore_mote(parent: Node, pos: Vector2) -> void:
	var color_hex: String = Palette.FUNGUS_BRIGHT if randf() < 0.7 else Palette.SOUL_BRIGHT
	VfxSystem.emit(parent, {
		"position": pos, "direction_deg": -90.0, "spread_deg": 25.0,
		"speed_min": 10.0, "speed_max": 26.0,
		"gravity": -4.0, "drag": 0.8,
		"size_min": 1.4, "size_max": 3.0, "end_size_ratio": 0.6 / 2.2,
		"color": color_hex, "end_color": Palette.FUNGUS_DIM, "alpha": 0.8,
		"life_min": 0.9, "life_max": 1.8,
		"glow": true, "shape": "circle",
	})

static func shield_sparks(parent: Node, pos: Vector2, facing: float) -> void:
	VfxSystem.emit(parent, {
		"position": pos, "count": 7,
		"direction_deg": rad_to_deg(facing), "spread_deg": rad_to_deg(0.9),
		"speed_min": 90.0, "speed_max": 220.0,
		"gravity": 220.0, "drag": 2.6,
		"size_min": 1.5, "size_max": 2.8,
		"color": "#e8e2f0", "end_color": "#5a5568",
		"life_min": 0.18, "life_max": 0.36,
		"glow": true, "shape": "spark",
	})

static func chest_open_burst(parent: Node, pos: Vector2, color_hex: String) -> void:
	VfxSystem.emit(parent, {
		"position": pos, "count": 26,
		"direction_deg": -90.0, "spread_deg": 90.0,
		"speed_min": 80.0, "speed_max": 260.0,
		"gravity": 320.0, "drag": 1.0,
		"size_min": 2.0, "size_max": 5.0,
		"color": color_hex, "end_color": Palette.EMBER6,
		"life_min": 0.5, "life_max": 1.0,
		"glow": true, "shape": "spark",
	})

static func dodge_trail(parent: Node, pos: Vector2, angle: float, color_hex: String) -> void:
	VfxSystem.emit(parent, {
		"position": pos, "direction_deg": rad_to_deg(angle + PI), "spread_deg": 0.0,
		"speed_min": 20.0, "speed_max": 20.0,
		"size_min": 10.0, "end_size_ratio": 0.2,
		"color": color_hex, "end_color": Palette.BG1, "alpha": 0.5,
		"life_min": 0.25,
		"glow": true, "shape": "circle",
	})

static func heal_sparkle(parent: Node, pos: Vector2) -> void:
	VfxSystem.emit(parent, {
		"position": pos, "count": 10,
		"direction_deg": -90.0, "spread_deg": 12.0,
		"speed_min": 30.0, "speed_max": 70.0,
		"gravity": 40.0, "drag": 1.0,
		"size_min": 2.0, "size_max": 4.0,
		"color": Palette.TOXIC, "end_color": "#dff7d0", "alpha": 0.9,
		"life_min": 0.5, "life_max": 0.9,
		"glow": true, "shape": "circle",
	})

## TS spaces these 30 particles evenly around the circle (angle = i/30 *
## tau); approximated here as a full-circle random spread instead, since
## VfxSystem has no evenly-spaced-per-particle emission mode.
static func level_up_burst(parent: Node, pos: Vector2) -> void:
	VfxSystem.emit(parent, {
		"position": pos, "count": 30,
		"speed_min": 80.0, "speed_max": 160.0,
		"gravity": -40.0, "drag": 1.6,
		"size_min": 2.0, "size_max": 4.0,
		"color": Palette.GOLD_BRIGHT, "end_color": Palette.EMBER3,
		"life_min": 0.5, "life_max": 0.9,
		"glow": true, "shape": "spark",
	})

static func stone_chips(parent: Node, pos: Vector2, count: int = 18) -> void:
	VfxSystem.emit(parent, {
		"position": pos, "count": count,
		"speed_min": 60.0, "speed_max": 260.0,
		"gravity": 420.0, "drag": 1.2,
		"size_min": 2.0, "size_max": 5.0, "end_size_ratio": 1.0 / 3.5,
		"color": "#8f8a9e", "end_color": "#2a2634", "alpha": 0.95,
		"life_min": 0.45, "life_max": 0.9,
		"shape": "square",
	})

## A sanctum candle catching. `sanctum_candle_position()` (LevelGenerator)
## gives the world position for a given candle index — this just plays the
## flare/spark at whatever position the caller already resolved.
static func ritual_ignite(parent: Node, pos: Vector2) -> void:
	VfxSystem.emit(parent, {
		"position": pos, "size_min": 6.0, "end_size_ratio": 34.0 / 6.0,
		"color": Palette.FUNGUS_BRIGHT, "alpha": 0.7, "life_min": 0.45,
		"glow": true, "shape": "ring",
	})
	VfxSystem.emit(parent, {
		"position": pos, "count": 8,
		"direction_deg": -90.0, "spread_deg": 23.0,
		"speed_min": 25.0, "speed_max": 60.0,
		"gravity": 20.0, "drag": 1.4,
		"size_min": 1.5, "size_max": 3.0,
		"color": Palette.FUNGUS_BRIGHT, "end_color": Palette.SOUL, "alpha": 0.9,
		"life_min": 0.4, "life_max": 0.8,
		"glow": true, "shape": "circle",
	})
