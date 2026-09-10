class_name BossCharacter
extends EnemyCharacter
## Ports entities/Boss.ts's field shell for The Ashen Colossus. The real
## phase FSM (chooseNextAttack, meteor rain, phase transitions, the 5
## attack types) is build-order step 4 — these fields exist so step 4 has
## somewhere to land without a second refactor of this file. Boss reuses
## Enemy's physics/collision/placeholder-draw plumbing exactly as the Web
## build's Boss class extends Enemy for the same reason.
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

func move_speed_for_phase() -> float:
	var factor: float = 1.0 if phase == Phase.ONE else (1.3 if phase == Phase.TWO else 1.55)
	return def.move_speed * factor

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
		for p in _ellipse_points(eye_cx, -r * 0.75, 5.0, 3.0):
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
func _ellipse_points(cx: float, cy: float, rx: float, ry: float, segments: int = 20) -> PackedVector2Array:
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
