class_name BossCharacter
extends EnemyCharacter
## Ports entities/Boss.ts for The Ashen Colossus: the phase FSM (tick(),
## choose_next_attack(), update_meteors(), enter_state(), begin_fight(), the
## invulnerability-gated take_damage() override), its own _physics_process
## override (see that method's own comment for why it can't just reuse the
## shared one), and its silhouette (_draw(), below). Boss reuses Enemy's
## physics/collision plumbing exactly as the Web build's Boss class extends
## Enemy for the same reason; EnemyAI.update() special-cases BossCharacter
## at its own top to call tick() here instead of the generic behavior
## dispatch every other enemy gets, and CombatManager.
## resolve_boss_pending_actions() resolves the pending_* flags tick() sets
## into real damage/VFX/summons each frame (ports combat/BossSystem.ts).
##
## Camera shake and hit-stop from BossSystem.ts are wired too, in
## resolve_boss_pending_actions() (player.add_camera_shake()/this
## autoload's own trigger_hit_stop(), see combat_manager.gd), the same
## pending-flag branches that already spawn this boss's VFX and SFX
## (bossRoar/bossPhase/bossHit/bossDeath, step 10, audio_engine.gd).
##
## Boss.ts's own field list re-declares `comboStep = 0` even though its
## parent `Enemy` already has one (used there for the warden's champion
## combo) — harmless in TypeScript (redeclaring a same-typed field in a
## subclass is a no-op), but GDScript rejects it outright as a duplicate
## member. Not ported here for that reason: `combo_step` below is the one
## inherited from EnemyCharacter, reused as-is for the boss's own phase-3
## Combo attack (2 chained Melee Slams) rather than shadowed.

enum Phase { ONE = 1, TWO = 2, THREE = 3 }
enum BossState {
	INTRO, IDLE, TELEGRAPH_SLAM, TELEGRAPH_COMBO, TELEGRAPH_SHOCKWAVE,
	TELEGRAPH_PROJECTILE, SUMMONING, RECOVER, PHASE_TRANSITION, DYING,
}

## HP-ratio breakpoints for phase 1->2 and 2->3, per Boss.ts.
const PHASE_THRESHOLDS := [0.64, 0.30]

var phase: Phase = Phase.ONE
var boss_state: BossState = BossState.INTRO
var boss_state_timer: float = 0.0
var attack_choice_cooldown: float = 1.4
var invulnerable: bool = true
var meteor_spawn_timer: float = 4.0
var death_animation_done: bool = false
var intro_done: bool = false

## Set the frame an attack telegraph completes; CombatManager.
## resolve_boss_pending_actions() consumes each exactly once per frame.
var pending_melee_slam: bool = false
var pending_shockwave: bool = false
var pending_projectile_angles: Array[float] = []
var pending_summon_count: int = 0
var pending_meteor_impacts: Array[Vector2] = []
## Each: {pos: Vector2, timer: float, duration: float, resolved: bool} —
## a plain Dictionary array, same convention as hud_minimap.gd's own
## _cells/_connectors, rather than a small RefCounted class: this is
## exactly as transient/locally-shaped as those, and Boss.ts's own
## MeteorTarget is a plain interface too, not a class.
var meteor_targets: Array = []

## Renamed from Boss.ts's own `phaseJustChanged` — EnemyCharacter already
## declares a same-named field for the warden champion's shield-break
## bookkeeping (enemy.gd:78), wired to CombatManager.on_champion_shield_break
## in the shared _physics_process; reusing that name here wouldn't just be
## the harmless duplicate-member GDScript rejects outright (see this file's
## own header on `combo_step`) — this one would actually compile (a same-
## typed override isn't a duplicate-member error the way a re-`var` would
## be, since this file never redeclares it), silently misrouting the boss's
## own phase transitions into champion-only shield-break handling instead.
var boss_phase_just_changed: bool = false
var intro_just_started: bool = true
## The delayed, "animation actually finished" defeat fanfare gate —
## deliberately NOT the inherited `death_handled` (enemy.gd:46), which
## CombatManager.on_enemy_death already flips true on the killing blow
## itself, well before death_animation_done: reusing it here would leave
## this always-already-true by the time resolve_boss_pending_actions()
## checks it, and the fanfare would never fire.
var boss_defeat_resolved: bool = false

func move_speed_for_phase() -> float:
	var factor: float = 1.0 if phase == Phase.ONE else (1.3 if phase == Phase.TWO else 1.55)
	return def.move_speed * factor

## Ports entities/Boss.ts's beginFight(). Called by level_flow.gd a short
## delay after spawning the boss (see enter_room()'s own boss branch) —
## the source gates this on presentation the Web build has (a roar/intro
## beat) that this port doesn't; a plain fixed delay stands in so the boss
## isn't instantly mobile/vulnerable the moment the room spawns it, while
## the game has no cutscene system to gate the real thing on.
func begin_fight() -> void:
	intro_done = true
	enter_state(BossState.IDLE)
	invulnerable = false

func enter_state(new_state: BossState) -> void:
	boss_state = new_state
	boss_state_timer = 0.0
	# Only reset on a fresh entry — the mid-combo continuation (see the
	# TELEGRAPH_COMBO case in tick()) advances combo_step without calling
	# enter_state, so an interrupted combo (e.g. a phase transition) can't
	# leave a stale step behind. Mirrors Boss.ts's own enterState() exactly.
	if new_state == BossState.TELEGRAPH_COMBO:
		combo_step = 0

## Ports entities/Boss.ts's override takeDamage(): the boss ignores every
## hit while invulnerable (intro, and the ~1.3s phase-transition beat)
## instead of EnemyCharacter's normal always-applies behavior.
func take_damage(amount: float) -> void:
	if invulnerable:
		return
	super.take_damage(amount)

## Ports entities/Boss.ts's tick(dt, player, bounds) — the real per-frame
## FSM (phase transitions, attack telegraphs -> pending-action flags,
## movement, phase-3 meteor rain). Called from EnemyAI.update() in place of
## the generic behavior dispatch (see that file's own boss branch) — the
## shared per-tick bookkeeping Boss.ts's own tick() gets from `super.update
## (dt)` is already covered here by _physics_process's OWN override below
## running it unconditionally before this is ever called, so there's
## nothing left for this method to do that isn't boss-specific.
##
## `bounds` is dropped from the signature entirely (present in the source):
## every room in this port is a fixed ROOM_WIDTH x ROOM_HEIGHT rectangle at
## local origin (room_container.gd's own header), so there's no per-instance
## bounds value to receive — BossSystem.ts's own summon code already reads
## the same ROOM_WIDTH/ROOM_HEIGHT/WALL_THICKNESS constants directly rather
## than a bounds parameter, so this isn't a new simplification, just the
## same one the source itself already uses elsewhere.
func tick(dt: float, player: PlayerCharacter) -> void:
	if not alive and boss_state != BossState.DYING:
		enter_state(BossState.DYING)
		hp = 0.0

	boss_state_timer += dt

	if boss_state == BossState.DYING:
		if boss_state_timer >= 2.2:
			death_animation_done = true
		ai_velocity = Vector2.ZERO
		return

	if not intro_done:
		return

	if boss_state != BossState.PHASE_TRANSITION and phase != Phase.THREE:
		var next_threshold: float = PHASE_THRESHOLDS[int(phase) - 1]
		if hp / maxf(1.0, max_hp) <= next_threshold:
			enter_state(BossState.PHASE_TRANSITION)
			invulnerable = true

	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()
	if dist > 0.01:
		facing = to_player.angle()

	if phase == Phase.THREE:
		update_meteors(dt, player)

	match boss_state:
		BossState.IDLE:
			var preferred: float = 160.0 if phase == Phase.ONE else 120.0
			if dist > preferred + 20.0:
				ai_velocity = to_player.normalized() * move_speed_for_phase()
			elif dist < preferred - 40.0:
				ai_velocity = -to_player.normalized() * move_speed_for_phase() * 0.6
			else:
				ai_velocity *= 0.8
			attack_choice_cooldown -= dt
			if attack_choice_cooldown <= 0.0:
				choose_next_attack(dist)
		BossState.TELEGRAPH_SLAM:
			ai_velocity = Vector2.ZERO
			if boss_state_timer >= def.telegraph_time:
				pending_melee_slam = true
				enter_state(BossState.RECOVER)
		BossState.TELEGRAPH_COMBO:
			ai_velocity = Vector2.ZERO
			if boss_state_timer >= def.telegraph_time * 0.75:
				pending_melee_slam = true
				combo_step += 1
				if combo_step >= 2:
					combo_step = 0
					enter_state(BossState.RECOVER)
				else:
					boss_state_timer = 0.0
		BossState.TELEGRAPH_SHOCKWAVE:
			ai_velocity = Vector2.ZERO
			if boss_state_timer >= def.telegraph_time * 1.3:
				pending_shockwave = true
				enter_state(BossState.RECOVER)
		BossState.TELEGRAPH_PROJECTILE:
			ai_velocity = Vector2.ZERO
			if boss_state_timer >= def.telegraph_time:
				var base: float = to_player.angle()
				pending_projectile_angles.append(base - 0.22)
				pending_projectile_angles.append(base)
				pending_projectile_angles.append(base + 0.22)
				enter_state(BossState.RECOVER)
		BossState.SUMMONING:
			ai_velocity = Vector2.ZERO
			if boss_state_timer >= 0.6:
				pending_summon_count = 3 if phase == Phase.THREE else 2
				enter_state(BossState.RECOVER)
		BossState.RECOVER:
			if boss_state_timer >= 0.55:
				attack_choice_cooldown = 0.9 if phase == Phase.THREE else 1.3
				enter_state(BossState.IDLE)
		BossState.PHASE_TRANSITION:
			ai_velocity = Vector2.ZERO
			if boss_state_timer >= 1.3:
				phase = Phase.TWO if phase == Phase.ONE else Phase.THREE
				invulnerable = false
				boss_phase_just_changed = true
				if phase == Phase.TWO:
					pending_summon_count = 2
				enter_state(BossState.IDLE)
				attack_choice_cooldown = 1.6

## Ports entities/Boss.ts's private chooseNextAttack(dist).
func choose_next_attack(dist: float) -> void:
	var roll := randf()
	if phase == Phase.ONE:
		enter_state(BossState.TELEGRAPH_SLAM if dist < 150.0 else BossState.TELEGRAPH_PROJECTILE)
		return
	if phase == Phase.TWO:
		if roll < 0.22:
			enter_state(BossState.SUMMONING)
		elif dist < 160.0:
			enter_state(BossState.TELEGRAPH_SHOCKWAVE if roll < 0.65 else BossState.TELEGRAPH_SLAM)
		else:
			enter_state(BossState.TELEGRAPH_PROJECTILE)
		return
	if roll < 0.18:
		enter_state(BossState.SUMMONING)
	elif roll < 0.42:
		enter_state(BossState.TELEGRAPH_COMBO)
	elif dist < 170.0:
		enter_state(BossState.TELEGRAPH_SHOCKWAVE if roll < 0.75 else BossState.TELEGRAPH_SLAM)
	else:
		enter_state(BossState.TELEGRAPH_PROJECTILE)

## Ports entities/Boss.ts's private updateMeteors(dt, player, bounds) — see
## tick()'s own comment for why `bounds` isn't a parameter here.
func update_meteors(dt: float, player: PlayerCharacter) -> void:
	meteor_spawn_timer -= dt
	if meteor_spawn_timer <= 0.0 and meteor_targets.size() < 2:
		meteor_spawn_timer = 3.4
		var margin := 90.0
		var angle: float = randf() * TAU
		var dist: float = 40.0 + randf() * 160.0
		var x: float = clampf(player.global_position.x + cos(angle) * dist, margin, RoomContainer.ROOM_WIDTH - margin)
		var y: float = clampf(player.global_position.y + sin(angle) * dist, margin, RoomContainer.ROOM_HEIGHT - margin)
		meteor_targets.append({"pos": Vector2(x, y), "timer": 0.0, "duration": 1.5, "resolved": false})

	for meteor in meteor_targets:
		if meteor["resolved"]:
			continue
		meteor["timer"] += dt
		if meteor["timer"] >= meteor["duration"]:
			meteor["resolved"] = true
			pending_meteor_impacts.append(meteor["pos"])
	meteor_targets = meteor_targets.filter(func(m): return not m["resolved"])

## Overrides EnemyCharacter._physics_process entirely rather than letting
## the shared one call EnemyAI.update() — that shared version returns
## BEFORE calling EnemyAI.update() at all once `alive` is false (enemy.gd's
## own early-return for a dead enemy), but the boss's own tick() needs to
## keep running after death to drive its 2.2s dying-state timer to
## death_animation_done (see tick()'s own DYING branch) — every other enemy
## just fades out via a passive death_timer with no state machine still
## advancing. contact/bash-hit checks and the inherited phase_just_changed/
## pending_burst hooks are dropped entirely rather than left in as dead
## calls: none of them are ever triggered for a boss (nothing sets
## bash_timer/pending_burst on it, and its generic `state` never leaves
## SPAWNING since boss_state is what actually drives it), so calling them
## here would just be no-ops with nothing to say for themselves.
func _physics_process(delta: float) -> void:
	anim_phase += delta
	if hit_flash_timer > 0.0:
		hit_flash_timer -= delta
	knockback_velocity *= maxf(0.0, 1.0 - 8.0 * delta)

	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	EnemyAI.update(self, player, delta)
	EnemyAI.apply_separation(self)

	velocity = ai_velocity + knockback_velocity
	move_and_slide()
	if alive:
		StatusEffectRuntime.process(self, delta)
	queue_redraw()
	_update_light()

## Ports Game.ts's registerLights(): "lighting.add(this.boss.x, this.boss.y,
## 220, Palette.ember3, 0.55 + this.boss.rageGlow * 0.4)". Overrides
## EnemyCharacter._update_light() entirely rather than falling into any of
## its id/behavior/champion branches — the source handles the boss with its
## own separate `if (this.boss...)` block in registerLights(), never through
## the generic enemy loop, and ashenColossus matches none of that loop's
## conditions anyway (not a fire-type id, not BLOAT, not champion). rageGlow
## itself was never a stored field on Boss.ts beyond this one derivation
## (phase 1 -> 0, phase 2 -> 0.5, phase 3 -> 1), so it's computed inline here
## exactly like _rage_glow_hex() below does for the body's own glow.
func _update_light() -> void:
	var glow: PointLight2D = $Glow
	if not alive:
		glow.enabled = false
		return
	var rage_glow: float = 0.0 if phase == Phase.ONE else (0.5 if phase == Phase.TWO else 1.0)
	glow.enabled = true
	glow.texture_scale = 220.0 / 128.0
	glow.color = Color(Palette.EMBER3)
	glow.energy = 0.55 + rage_glow * 0.4

## Ports rendering/draw/drawBoss.ts's own distinct silhouette (The Ashen
## Colossus), overriding EnemyCharacter's generic circle-body _draw().
## Deliberately does NOT call super._draw(): that draws a plain filled
## circle of radius `radius` first, which — since every vertex of the body
## polygon below sits at 0.95-1.15x radius, with straight edges cutting
## inside that circle's arc between vertices — would peek out from behind
## the angular silhouette as an unwanted round fringe. It also has no
## equivalent of the source's own hit-flash overlay or generic "dead"
## dimming (drawBoss.ts never reads hitFlashTimer at all, and its own
## `dying` handling below — fade + shrink + drop — replaces the generic
## black death-overlay entirely), so calling it would add visuals the
## source doesn't have. The debug HP/state text at the bottom is
## reimplemented directly instead, matching enemy.gd's own _draw()
## exactly in font/position/format, so both the real silhouette AND that
## debug readout show together as required.
##
## Local points funnel through _boss_xf(), which reproduces the source's
## on-death shrink+drop (`ctx.scale(1 - deathT*0.3, 1 - deathT*0.5);
## ctx.translate(0, deathT*30)`) — identity (sx=sy=1, ty=0) while not
## dying, so it's safe to apply unconditionally. The eyes' and arms' own
## additional local rotate/translate are applied first via
## Vector2.rotated()/plain addition, same convention as player.gd and
## obstacle_node.gd's _rot_point use instead of draw_set_transform.
##
## Simplifications (Godot's immediate-mode _draw() has no equivalent):
## - Gradients become a single flat color (their stops' midpoint) — same
##   convention as obstacle_node.gd and player.gd.
## - shadowBlur/shadowColor glow-on-stroke/fill effects (cracks, eyes) are
##   dropped for a plain flat color — eyeGlow in particular only ever fed
##   shadowBlur, so with that gone it has no remaining visual effect and
##   isn't computed here at all.
## - The rage-tinted glow (mixColor(ember3, bloodBright, rage)) picks the
##   closest existing Palette token per phase instead of blending a new
##   hex value: draw_glow_circle takes a String, and rage only ever takes
##   phase's 3 discrete values today anyway (no continuous rage state
##   exists yet) — see _rage_glow_hex(). The body fill, which needs a real
##   Color rather than a String, still blends properly via lerp_color_hex.
## - drawMeteorTelegraph (a separate function in the source, for the
##   phase-3 meteor-rain markers) isn't ported: BossCharacter has no
##   meteor-target state yet (that's future phase-FSM work per Boss.ts's
##   own meteorTargets/pendingMeteorImpacts fields, none of which exist
##   here), and it isn't part of the boss's own silhouette anyway.
func _draw() -> void:
	if def == null:
		return
	var r := radius
	var dying: bool = boss_state == BossState.DYING
	var death_t: float = clampf(boss_state_timer / 2.2, 0.0, 1.0) if dying else 0.0

	# Shadow anchors to the ground — drawn before the dying shrink/drop so
	# it doesn't move with the body above it.
	DrawUtils.draw_soft_shadow(self, 0.0, r * 0.7, r * 1.3, r * 0.5, 0.55)

	# Attack telegraph rings — drawn before the dying transform too (the
	# two states can't be active at once anyway, boss_state is single-valued).
	if boss_state == BossState.TELEGRAPH_SLAM or boss_state == BossState.TELEGRAPH_COMBO:
		var slam_t: float = boss_state_timer / def.telegraph_time
		var slam_ring_color := Color(Palette.BLOOD_BRIGHT)
		slam_ring_color.a = clampf(0.5 * slam_t, 0.0, 1.0)
		var slam_center := Vector2(cos(facing) * 60.0, sin(facing) * 60.0)
		draw_arc(slam_center, 130.0 * slam_t, 0.0, TAU, 32, slam_ring_color, 3.0, true)
	if boss_state == BossState.TELEGRAPH_SHOCKWAVE:
		var shock_t: float = minf(1.0, boss_state_timer / (def.telegraph_time * 1.3))
		var shock_ring_color := Color(Palette.EMBER4)
		shock_ring_color.a = clampf(0.4 + 0.3 * sin(shock_t * 20.0), 0.0, 1.0)
		draw_arc(Vector2.ZERO, 230.0 * shock_t, 0.0, TAU, 32, shock_ring_color, 4.0, true)

	# Phase-3 meteor-rain markers — ports drawMeteorTelegraph (drawBoss.ts),
	# the one _draw() element here NOT run through _boss_xf's death shrink/
	# drop below: meteor_targets holds independent world positions (not
	# boss-relative geometry), converted to this node's own local draw space
	# via a raw offset from global_position rather than through any of the
	# body's own local-point vocabulary.
	if phase == Phase.THREE:
		for meteor in meteor_targets:
			_draw_meteor_telegraph(meteor)

	var sx := 1.0
	var sy := 1.0
	var ty := 0.0
	var death_alpha := 1.0
	if dying:
		sx = 1.0 - death_t * 0.3
		sy = 1.0 - death_t * 0.5
		ty = death_t * 30.0
		death_alpha = maxf(0.0, 1.0 - death_t)

	if invulnerable and intro_done:
		var invuln_center := _boss_xf(Vector2.ZERO, sx, sy, ty)
		var invuln_alpha: float = (0.35 + sin(boss_state_timer * 10.0) * 0.15) * death_alpha
		DrawUtils.draw_glow_circle(self, invuln_center.x, invuln_center.y, r * 1.6, Palette.SOUL_BRIGHT, invuln_alpha)

	var rage: float = 0.0
	if phase == Phase.TWO:
		rage = 0.5
	elif phase == Phase.THREE:
		rage = 1.0
	var rage_center := _boss_xf(Vector2(0.0, r * 0.1), sx, sy, ty)
	var rage_alpha: float = (0.28 + rage * 0.2) * death_alpha
	DrawUtils.draw_glow_circle(self, rage_center.x, rage_center.y, r * 1.4, _rage_glow_hex(phase), rage_alpha)

	# --- Body ---
	var body_raw := PackedVector2Array([
		Vector2(-r * 0.95, r * 0.7),
		Vector2(-r * 1.05, -r * 0.1),
		Vector2(-r * 0.55, -r * 0.95),
		Vector2(0.0, -r * 1.15),
		Vector2(r * 0.55, -r * 0.95),
		Vector2(r * 1.05, -r * 0.1),
		Vector2(r * 0.95, r * 0.7),
	])
	# Rounded belly: the source closes this last edge with a curve rather
	# than a straight line back to the first vertex.
	var body_curve := _quad_bezier_points(body_raw[6], Vector2(0.0, r * 0.95), body_raw[0], 8)
	for i in range(1, body_curve.size() - 1):
		body_raw.append(body_curve[i])
	var body_pts := PackedVector2Array()
	for p in body_raw:
		body_pts.append(_boss_xf(p, sx, sy, ty))
	# Linear gradient (rage-tinted highlight -> ember1) simplified to its midpoint tone.
	var body_stop0: Color = DrawUtils.lerp_color_hex("#3a2c22", Palette.BLOOD_BRIGHT, rage * 0.3)
	var body_color: Color = body_stop0.lerp(Color(Palette.EMBER1), 0.5)
	body_color.a = death_alpha
	draw_colored_polygon(body_pts, body_color)

	# --- Cracks ---
	# Glow (shadowBlur-based in the source) simplified to a flat-colored line.
	var crack_pulse: float = 0.5 + sin(anim_phase * (3.0 + rage * 4.0)) * 0.3 + rage * 0.3
	var crack_color := Color(Palette.EMBER4)
	crack_color.a = clampf(crack_pulse, 0.2, 1.0) * death_alpha
	_draw_boss_crack(Vector2(-r * 0.5, -r * 0.4), Vector2(-r * 0.1, r * 0.3), crack_color, sx, sy, ty)
	_draw_boss_crack(Vector2(r * 0.1, -r * 0.8), Vector2(r * 0.4, -r * 0.1), crack_color, sx, sy, ty)
	_draw_boss_crack(Vector2(-r * 0.2, r * 0.1), Vector2(r * 0.25, r * 0.55), crack_color, sx, sy, ty)
	_draw_boss_crack(Vector2(r * 0.5, r * 0.1), Vector2(r * 0.2, r * 0.6), crack_color, sx, sy, ty)

	# --- Eyes ---
	# eyeGlow (shadowBlur-based in the source, brighter during
	# telegraphProjectile) fed nothing but shadowBlur, so with that
	# dropped it has no remaining visual effect and isn't computed here.
	var eye_angle: float = facing * 0.12
	var eye_color := Color(Palette.EMBER6)
	eye_color.a = death_alpha
	for eye_cx in [-r * 0.22, r * 0.22]:
		var eye_pts := PackedVector2Array()
		for p in _boss_ellipse_points(eye_cx, -r * 0.75, 5.0, 3.0):
			eye_pts.append(_boss_xf(p.rotated(eye_angle), sx, sy, ty))
		draw_colored_polygon(eye_pts, eye_color)

	# --- Arms ---
	var arm_swing := 0.0
	if boss_state == BossState.TELEGRAPH_SLAM or boss_state == BossState.TELEGRAPH_COMBO:
		arm_swing = _ease_out_cubic(minf(1.0, boss_state_timer / def.telegraph_time))
	var arm_color := Color(Palette.EMBER1)
	arm_color.a = death_alpha
	# Right arm's own angle; the left arm is its exact mirror (source:
	# -0.3 - armSwing*0.8 vs +0.3 + armSwing*0.8).
	var base_arm_angle: float = -0.3 - arm_swing * 0.8
	var arm_corners := PackedVector2Array([Vector2(-14.0, 0.0), Vector2(14.0, 0.0), Vector2(14.0, r * 1.1), Vector2(-14.0, r * 1.1)])
	for side in [1.0, -1.0]:
		var shoulder := Vector2(side * r * 0.9, -r * 0.2)
		var arm_angle: float = base_arm_angle if side > 0.0 else -base_arm_angle
		var arm_pts := PackedVector2Array()
		for c in arm_corners:
			arm_pts.append(_boss_xf(c.rotated(arm_angle) + shoulder, sx, sy, ty))
		draw_colored_polygon(arm_pts, arm_color)

	# Debug-only HP/phase/state text — same convention as enemy.gd's own
	# _draw(), but surfacing the boss's own richer boss_state/phase (its
	# generic inherited `state` field isn't meaningfully driven for the
	# boss yet) since that's the more useful signal for testing without
	# real UI. Not gated on `dying`/death_alpha, matching enemy.gd's own
	# unconditional debug text.
	var font := ThemeDB.fallback_font
	if font != null:
		var label: String = "P%d %s  %d/%d" % [int(phase), BossState.keys()[boss_state], int(ceil(maxf(hp, 0.0))), int(max_hp)]
		draw_string(font, Vector2(-radius - 10.0, -radius - 10.0), label, HORIZONTAL_ALIGNMENT_LEFT, 160.0, 13, Color.WHITE)

## drawBoss.ts's mixColor(ember3, bloodBright, rage) for the rage-tinted
## glow, picking the closest existing Palette token per phase rather than
## blending a new hex string — see the class-level rage-glow simplification
## note above for why (draw_glow_circle takes a String, not a Color, and
## every other draw_glow_circle call site in this project already picks
## between existing string constants rather than computing a new one; see
## e.g. chest_node.gd's _tier_color() or projectile.gd's core_hex/glow_hex).
func _rage_glow_hex(p: Phase) -> String:
	match p:
		Phase.ONE:
			return Palette.EMBER3
		Phase.TWO:
			return Palette.BLOOD
		_:
			return Palette.BLOOD_BRIGHT

## Ports drawMeteorTelegraph (drawBoss.ts): a filling disc (transparent
## ember -> blood-bright as `timer` nears `duration`) plus a shrinking
## outline ring, exactly like the source's own two-shape telegraph.
func _draw_meteor_telegraph(meteor: Dictionary) -> void:
	var local_pos: Vector2 = meteor["pos"] - global_position
	var t: float = clampf(meteor["timer"] / meteor["duration"], 0.0, 1.0)
	var meteor_radius := 70.0
	var fill_color: Color = DrawUtils.lerp_color_hex(Palette.EMBER5, Palette.BLOOD_BRIGHT, t)
	fill_color.a = 0.25 + t * 0.5
	draw_circle(local_pos, meteor_radius, fill_color)
	var ring_color: Color = DrawUtils.lerp_color_hex(Palette.EMBER6, Palette.BLOOD_BRIGHT, t)
	ring_color.a = 0.7
	draw_arc(local_pos, meteor_radius * (1.0 - t) + 6.0, 0.0, TAU, 24, ring_color, 3.0, true)

## A single lightning-crack polyline (start -> midpoint+6 offset -> end),
## transformed by the on-death shrink+drop like everything else in _draw().
func _draw_boss_crack(p1: Vector2, p2: Vector2, color: Color, sx: float, sy: float, ty: float) -> void:
	var mid: Vector2 = (p1 + p2) / 2.0 + Vector2(6.0, 0.0)
	var pts := PackedVector2Array([_boss_xf(p1, sx, sy, ty), _boss_xf(mid, sx, sy, ty), _boss_xf(p2, sx, sy, ty)])
	draw_polyline(pts, color, 2.4, true)

## Applies drawBoss.ts's on-death shrink+drop transform to a point already
## expressed in the boss's own undistorted local draw space (identity —
## sx=sy=1, ty=0 — while not dying, so this is safe to call unconditionally
## for every point in _draw()).
func _boss_xf(p: Vector2, sx: float, sy: float, ty: float) -> Vector2:
	return Vector2(sx * p.x, sy * (p.y + ty))

## Filled-ellipse point sampler — Godot's _draw() has no ellipse primitive.
## Own private copy of the same helper player.gd and obstacle_node.gd each
## already keep (see player.gd's own copy for why it isn't shared/why this
## doesn't call DrawUtils's underscore-prefixed _draw_ellipse directly).
## Named _boss_ellipse_points rather than plain _ellipse_points: BossCharacter
## extends EnemyCharacter, which already declares its own static
## _ellipse_points(cx, cy, rx, ry, rotation=0.0, segments=24) for the warden's
## shield rendering — same name here would be a GDScript override the
## parser rejects outright (signature mismatch), not a harmless shadow the
## way an unrelated same-named private helper is everywhere else in this
## file. player.gd/obstacle_node.gd don't have this problem since neither
## extends a class that already owns the name.
func _boss_ellipse_points(cx: float, cy: float, rx: float, ry: float, segments: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var angle: float = (float(i) / float(segments)) * TAU
		pts.append(Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry))
	return pts

## Samples a quadratic Bézier curve into straight segments — Canvas2D's
## quadraticCurveTo has no direct Godot draw-API equivalent. Same
## name/signature/formula as obstacle_node.gd's own private helper.
func _quad_bezier_points(p0: Vector2, control: Vector2, p1: Vector2, segments: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var mt: float = 1.0 - t
		pts.append(p0 * (mt * mt) + control * (2.0 * mt * t) + p1 * (t * t))
	return pts

## Mirrors MathUtils.ts's easeOutCubic — no shared MathUtils.gd exists yet
## in Godot, so (like level_flow.gd's own private _ease_out_cubic) this
## file keeps its own small private copy of the same formula.
func _ease_out_cubic(t: float) -> float:
	var p := t - 1.0
	return p * p * p + 1.0
