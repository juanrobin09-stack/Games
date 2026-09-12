class_name EnemyCharacter
extends CharacterBody2D
## Ports entities/Enemy.ts. One scene is reused for all 11 EnemyDefinitions
## via setup(), exactly like the Web build's single Enemy class driven by
## an assigned `def`. Real AI (EnemyAI.update) and combat (CombatManager)
## now drive this — see combat/enemy_ai.gd and autoload/combat_manager.gd.
##
## `ai_velocity` is the AI-controlled movement component, kept deliberately
## separate from `knockback_velocity` (CharacterBody2D's own `velocity` is
## only ever their SUM, assembled fresh each physics tick right before
## move_and_slide()) — mirrors the Web build keeping `vx`/`knockbackVx` as
## two permanently separate fields, only summed at the position-integration
## step. Folding knockback into the same field the AI reads/writes (e.g.
## the warden's `velocity *= 0.6`) would let a knockback impulse silently
## bleed into the AI's own state instead of decaying independently.

signal died(enemy: EnemyCharacter)

enum State { SPAWNING, IDLE, CHASE, WINDUP, ATTACK, COOLDOWN, VANISHED, REAPPEARING, STAGGER, DEAD }

var def: EnemyDefinition
var radius: float = 12.0
var facing: float = 0.0

var hp: float = 0.0
var max_hp: float = 0.0
var alive: bool = true
var death_timer: float = 0.0
## Set once CombatManager.on_enemy_death has processed this death, whether
## it died to a direct hit or a status-effect tick — mirrors deathHandled.
var death_handled: bool = false

var state: State = State.SPAWNING
var state_timer: float = 0.0
var attack_cooldown_timer: float = 0.0
var contact_cooldown_timer: float = 0.0
var hit_flash_timer: float = 0.0
var anim_phase: float = randf() * 10.0

var ai_velocity := Vector2.ZERO
var knockback_velocity := Vector2.ZERO

var difficulty_hp_mult: float = 1.0
var difficulty_damage_mult: float = 1.0
var is_elite_instance: bool = false
## Ember Citadel only: a rare, visibly tainted variant of a regular enemy.
var is_mutated_variant: bool = false
var display_name: String = ""

var status_effects: Array = []

# ---- warden (shield-bearer) state
## Guard is down while > 0 (right after a bash): frontal damage reduction is off.
var exposed_timer: float = 0.0
## Champion only: the shield is gone for good once it drops below half health.
var shield_broken: bool = false
## Remaining bash travel time; ai_velocity stays locked along `facing` while > 0.
var bash_timer: float = 0.0
var bash_hit_landed: bool = false
## Champion second-bash bookkeeping.
var combo_step: int = 0
## Set by the AI the frame a champion's shield shatters; consumed once by CombatManager.
var phase_just_changed: bool = false
## Set by the AI when this warden should leave a spore cloud where it stands
## (phase-2 champion) — consumed once per frame by CombatManager.
## consume_pending_cloud() (called from this file's own _physics_process),
## which spawns a real HazardNode there.
var pending_cloud_radius: float = 0.0

# ---- bloat (self-detonating) state
## Set by the AI the frame the swell completes; CombatManager resolves the burst exactly once.
var pending_burst: bool = false
## True once the burst went off by itself (vs. the bloat being killed early).
var burst_detonated: bool = false

## Warden: is the shield currently turning aside frontal hits?
func shield_up() -> bool:
	return (
		alive
		and def != null
		and def.behavior == EnemyDefinition.Behavior.WARDEN
		and not shield_broken
		and exposed_timer <= 0.0
		and state != State.STAGGER
		and state != State.COOLDOWN
	)

func contact_damage() -> float:
	return def.contact_damage * difficulty_damage_mult

func attack_damage() -> float:
	return def.base_damage * difficulty_damage_mult

## Call once after instancing (before or after add_child, either order
## works — _ready() re-applies the collision radius either way).
func setup(enemy_def: EnemyDefinition, spawn_pos: Vector2, hp_mult: float, damage_mult: float) -> void:
	def = enemy_def
	global_position = spawn_pos
	radius = def.radius
	difficulty_hp_mult = hp_mult
	difficulty_damage_mult = damage_mult
	max_hp = roundf(def.base_hp * hp_mult)
	hp = max_hp
	attack_cooldown_timer = def.attack_cooldown * (0.4 + randf() * 0.4)
	state_timer = 0.15 + randf() * 0.2
	if is_inside_tree():
		_apply_shape()

func set_state(new_state: State) -> void:
	state = new_state
	state_timer = 0.0

func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	hit_flash_timer = 0.16
	if hp <= 0.0:
		hp = 0.0
		alive = false
		set_state(State.DEAD)
		died.emit(self)

func apply_knockback(dir: Vector2, force: float) -> void:
	knockback_velocity += dir * force

func _ready() -> void:
	add_to_group("enemies")
	# Enemies are children of their RoomContainer (build-order step 6),
	# which sits at z_index = -10 so its own floor rect draws behind the
	# player — counter that back to 0 or every enemy would be invisible
	# behind that same floor.
	z_as_relative = false
	_apply_shape()
	($Glow as PointLight2D).texture = DrawUtils.glow_texture()

func _apply_shape() -> void:
	var shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if shape and shape.shape is CircleShape2D:
		(shape.shape as CircleShape2D).radius = radius

func _physics_process(delta: float) -> void:
	state_timer += delta
	anim_phase += delta
	if hit_flash_timer > 0.0:
		hit_flash_timer -= delta

	if not alive:
		death_timer += delta
		queue_redraw()
		_update_light()
		return

	if attack_cooldown_timer > 0.0: attack_cooldown_timer -= delta
	if contact_cooldown_timer > 0.0: contact_cooldown_timer -= delta
	if exposed_timer > 0.0: exposed_timer -= delta

	knockback_velocity *= maxf(0.0, 1.0 - 8.0 * delta)

	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	EnemyAI.update(self, player, delta)
	EnemyAI.apply_separation(self)
	if phase_just_changed:
		phase_just_changed = false
		CombatManager.on_champion_shield_break(self, player)
	CombatManager.check_contact_damage(self, player)
	CombatManager.check_bash_hit(self, player)

	velocity = ai_velocity + knockback_velocity
	move_and_slide()
	StatusEffectRuntime.process(self, delta)
	if pending_burst:
		CombatManager.detonate_bloat(player, self)
	CombatManager.consume_pending_cloud(self)
	queue_redraw()
	_update_light()

## Ports Game.ts's registerLights() enemy loop exactly: three mutually
## exclusive cases (a dead enemy — the `if (!e.alive) continue` guard in the
## caller — gets no light at all, and elif here mirrors the source's actual
## if/else-if chain, so a champion that happened to also be a fire-type
## would still only light once, same as the source). BossCharacter overrides
## this entirely below rather than falling into any of these branches — the
## boss's id/behavior/champion never match any of them, same as the source's
## own registerLights() handling the boss as a separate `if (this.boss...)`
## block, not through this enemy loop.
func _update_light() -> void:
	var glow: PointLight2D = $Glow
	if not alive:
		glow.enabled = false
		return
	if def.id == "flameWisp" or def.id == "emberDevourer" or def.id == "cinderWraith":
		_set_light(glow, 90.0, def.accent_color, 0.7)
	elif def.behavior == EnemyDefinition.Behavior.BLOAT:
		var swell: float = 0.0
		if state == State.WINDUP:
			swell = minf(1.0, state_timer / maxf(0.05, def.telegraph_time))
		_set_light(glow, 60.0 + swell * 60.0, Palette.FUNGUS, 0.4 + swell * 0.5)
	elif def.champion:
		_set_light(glow, 110.0, Palette.FUNGUS if shield_broken else Palette.SOUL, 0.55)
	else:
		glow.enabled = false

func _set_light(glow: PointLight2D, light_radius: float, color_hex: String, intensity: float) -> void:
	glow.enabled = true
	glow.texture_scale = light_radius / 128.0
	glow.color = Color(color_hex)
	glow.energy = intensity

## Wobble seeds shared by every organic blob silhouette below — ports
## drawEnemy.ts's module-level WOBBLE_SEEDS constant verbatim (plain float
## literals, no cross-script enum reference, so safe as a top-level const —
## see the cheat sheet's note on load-order risk for the kind that isn't).
const WOBBLE_SEEDS := [0.1, -0.08, 0.14, -0.05, 0.09, -0.12, 0.06, -0.1]

## Ports drawEnemy.ts (build-order step 7 — real rendering). Structure
## mirrors the source's own drawEnemy() wrapper: soft shadow, elite/mutated
## rings+glow, telegraph ring, the per-id silhouette (one _draw_<id>
## function each, dispatched below exactly like the source's DRAWERS
## lookup — including its fallback to the Ash Crawler shape for an
## unmapped id, which is what lets the boss, BossCharacter's inherited
## _draw(), fall back the same way the source does), then the status
## overlay and an elite/mutated name label. The old placeholder's warden
## shield-arc draw_arc call is gone from here — _draw_warden() below now
## owns the shield visual entirely (a whole slab/stub, not just an arc), so
## there's exactly one place drawing it instead of two.
##
## A few consistent, deliberate simplifications apply throughout this file
## (each also called out locally where it matters most):
## - Canvas2D's `globalCompositeOperation = 'lighter'` (additive blending)
##   has no per-shape equivalent in Godot's immediate-mode draw calls
##   without a node-wide CanvasItemMaterial — every such spot below just
##   uses plain alpha blending instead.
## - Multi-stop linear/radial gradients are approximated either as a single
##   flat color sampled at one representative point (for a small or subtly
##   shaded shape) or as a handful of concentric solid circles fading
##   toward a highlight point (for an off-center "glossy" highlight) — the
##   same discrete-steps trick DrawUtils.draw_soft_shadow/draw_glow_circle
##   already use for their own gradients, just reused for solid (non-fading)
##   recoloring here. A couple of source gradients also had two color stops
##   at the same offset (the first invisibly overridden by the second) —
##   ported as whatever actually renders, not the dead stop.
## - `ctx.shadowColor`/`shadowBlur` behind a small filled shape (an eye, a
##   pustule) is approximated with a DrawUtils.draw_glow_circle underneath
##   it, sized roughly shape-radius-plus-blur.
## - Rounded rects (`roundedRectPath`) simplify to plain sharp-cornered
##   `draw_rect` calls — Godot's immediate-mode API has no rounded-rect
##   primitive.
## - The source's death-fade squashes+stretches the corpse via
##   `ctx.scale()` while it fades; Godot has no scoped equivalent (see
##   `draw_set_transform`'s dangling-state risk in the cheat sheet), and
##   several drawers below (_draw_hollow, _draw_blightbloat, _draw_warden)
##   already use it themselves for their OWN rotation/scale, so composing a
##   second transform on top blind, with no engine here to check the
##   result, risked a worse bug than the effect is worth. Only the fade
##   (self_modulate, a pure rendering property — it never touches physics,
##   collision, or child nodes) is ported; the squash is dropped.
func _draw() -> void:
	if def == null:
		return
	var r: float = radius
	var death_t: float = 0.0 if alive else minf(1.0, death_timer / 0.4)
	# self_modulate stands in for the source's scoped ctx.globalAlpha death
	# fade — unlike the source (which only fades the silhouette + status
	# overlay), this fades this node's ENTIRE _draw() output for the frame,
	# soft shadow and the debug text below included; both are unnoticeable
	# on an already-vanishing corpse, so this is a fine trade for not
	# threading an alpha parameter through every Color() in every drawer.
	var alpha: float = clampf(1.0 - death_t, 0.0, 1.0)
	if def.id == "cinderWraith":
		# The source keeps this one permanently around 90% opacity (its own
		# "always slightly translucent" look), on top of a vanish-state fade
		# this port doesn't track yet (see _draw_shadow_stalker's note).
		alpha *= 0.9
	self_modulate = Color(1.0, 1.0, 1.0, alpha)

	if def.behavior != EnemyDefinition.Behavior.RANGED or def.id == "flameWisp":
		DrawUtils.draw_soft_shadow(self, 0.0, r * 0.75, r * 0.9, r * 0.35, 0.2 if (def.id == "flameWisp" or def.id == "cinderWraith") else 0.4)

	if is_elite_instance and alive:
		var pulse: float = 0.5 + sin(anim_phase * 3.0) * 0.2
		var ring_color := Color(Palette.EMBER5)
		ring_color.a = pulse
		draw_arc(Vector2(0.0, r * 0.6), r * 1.15, 0.0, TAU, 32, ring_color, 2.5, true)
		DrawUtils.draw_glow_circle(self, 0.0, 0.0, r * 2.0, Palette.EMBER4, 0.22)

	if is_mutated_variant and alive:
		# A colder violet tainting the Citadel's warm palette — the game's
		# existing visual language for "something otherworldly" (Shadow
		# Stalker, Cinder Wraith, the Sunken Warden), reused here rather
		# than inventing a new one.
		var mutated_pulse: float = 0.45 + sin(anim_phase * 4.2) * 0.25
		var mutated_ring := Color(Palette.SOUL_BRIGHT)
		mutated_ring.a = mutated_pulse
		draw_arc(Vector2(0.0, r * 0.6), r * 1.05, 0.0, TAU, 32, mutated_ring, 2.0, true)
		DrawUtils.draw_glow_circle(self, 0.0, 0.0, r * 1.6, Palette.SOUL, 0.2)

	_telegraph_ring(r)

	match def.id:
		"ashCrawler":
			_draw_ash_crawler()
		"hollow":
			_draw_hollow()
		"flameWisp":
			_draw_flame_wisp()
		"gravebound":
			_draw_gravebound()
		"shadowStalker":
			_draw_shadow_stalker()
		"cinderWraith":
			_draw_cinder_wraith()
		"emberDevourer":
			_draw_ember_devourer()
		"blightbloat":
			_draw_blightbloat()
		"hollowWarden", "sunkenWarden":
			_draw_warden()
		_:
			# Unmapped id (e.g. the boss's "ashenColossus", drawn by a
			# separate task) — mirrors the source's own DRAWERS fallback,
			# which is what makes BossCharacter (inheriting this _draw()
			# unchanged) fall back to the same shape today.
			_draw_ash_crawler()

	_status_overlay(r)

	# Debug-only HP/state text — no real HUD yet (step 9), but this is what
	# makes "is combat actually doing anything" visible without one.
	var font := ThemeDB.fallback_font
	if font != null:
		var label: String = "%s  %d/%d" % [State.keys()[state], int(ceil(maxf(hp, 0.0))), int(max_hp)]
		draw_string(font, Vector2(-radius - 10.0, -radius - 10.0), label, HORIZONTAL_ALIGNMENT_LEFT, 160.0, 13, Color.WHITE)

	if font != null and (def.is_elite or is_elite_instance or is_mutated_variant):
		# Name label above the head — ports drawEnemy.ts's own label. No
		# Godot i18n system exists yet (source looks up tc(def.id,'name',..)
		# first), so this just falls back straight to display_name/def.name.
		# draw_string has no shadow/outline primitive either, so the
		# source's shadowBlur behind the text is dropped — a flat color
		# read is enough at this scale.
		var shown_name: String = display_name if display_name != "" else def.name
		var name_color: Color = Color(Palette.SOUL_BRIGHT) if (is_mutated_variant and not is_elite_instance and not def.is_elite) else Color(Palette.EMBER5)
		draw_string(font, Vector2(-70.0, -r - 18.0), shown_name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 140.0, 13, name_color)

## Ports drawEnemy.ts's telegraphRing(): a windup-only cue whose shape
## depends on the enemy's own attack behavior. `r` is only used by the
## warden's lane (the source's own telegraphRing also only reads its
## `radius` parameter in that one branch).
func _telegraph_ring(r: float) -> void:
	if state != State.WINDUP:
		return
	var telegraph_time: float = def.telegraph_time * (0.45 if combo_step > 0 else 1.0)
	var t: float = minf(1.0, state_timer / maxf(0.05, telegraph_time))
	match def.behavior:
		EnemyDefinition.Behavior.WARDEN:
			_telegraph_warden_lane(r, t)
		EnemyDefinition.Behavior.BLOAT:
			_telegraph_bloat_burst(t)
		_:
			var default_color := Color(Palette.BLOOD_BRIGHT)
			default_color.a = 0.5 * t
			draw_arc(Vector2.ZERO, def.attack_range * t, 0.0, TAU, 32, default_color, 2.0 + t * 2.0, true)

## The bash is a line, so its telegraph is one: a lane along the facing
## that fills up as the lunge gets closer. Step out of the lane. Ported
## point-by-point (Vector2.rotated) rather than via draw_set_transform,
## per the cheat sheet's preference for a single small nested shape.
func _telegraph_warden_lane(r: float, t: float) -> void:
	var lane_len_full: float = def.attack_range + 40.0
	var w: float = r * 1.7
	var lane_len: float = lane_len_full * t
	var fill_alpha_mult: float = 0.35 + 0.5 * t
	# The fill's own gradient (0.7 alpha near the entity, fading to 0.12 at
	# the lane's full un-filled length) is approximated as a few solid
	# strips rather than a true per-pixel gradient.
	var segs := 6
	for i in range(segs):
		var t0: float = float(i) / float(segs)
		var t1: float = float(i + 1) / float(segs)
		var mid_x: float = (t0 + t1) * 0.5 * lane_len
		var grad_t: float = clampf(mid_x / lane_len_full, 0.0, 1.0)
		var seg_color := Color(Palette.BLOOD_BRIGHT)
		seg_color.a = (0.7 + (0.12 - 0.7) * grad_t) * fill_alpha_mult
		var quad := PackedVector2Array([
			Vector2(t0 * lane_len, -w / 2.0).rotated(facing),
			Vector2(t1 * lane_len, -w / 2.0).rotated(facing),
			Vector2(t1 * lane_len, w / 2.0).rotated(facing),
			Vector2(t0 * lane_len, w / 2.0).rotated(facing),
		])
		draw_colored_polygon(quad, seg_color)
	var stroke_color := Color(Palette.BLOOD_BRIGHT)
	stroke_color.a = 0.45 + 0.45 * t
	var outline := PackedVector2Array([
		Vector2(0.0, -w / 2.0).rotated(facing),
		Vector2(lane_len_full, -w / 2.0).rotated(facing),
		Vector2(lane_len_full, w / 2.0).rotated(facing),
		Vector2(0.0, w / 2.0).rotated(facing),
		Vector2(0.0, -w / 2.0).rotated(facing),
	])
	draw_polyline(outline, stroke_color, 2.0, true)
	var tip := PackedVector2Array([
		Vector2(lane_len, -w / 2.0).rotated(facing),
		Vector2(lane_len + 10.0, 0.0).rotated(facing),
		Vector2(lane_len, w / 2.0).rotated(facing),
	])
	draw_polyline(tip, stroke_color, 2.0, true)

## The burst radius, growing to full as the swell completes — and the
## cloud it will leave, in the same cold colour.
func _telegraph_bloat_burst(t: float) -> void:
	var burst_r: float = def.burst_radius if def.burst_radius > 0.0 else def.attack_range
	var cur: float = burst_r * (0.4 + 0.6 * t)
	var fill_color := Color(Palette.FUNGUS)
	fill_color.a = 0.14 * t
	draw_circle(Vector2.ZERO, cur, fill_color)
	var stroke_color := Color(Palette.FUNGUS_BRIGHT)
	stroke_color.a = 0.35 + 0.45 * t
	_draw_dashed_circle(cur, stroke_color, 2.0 + t * 2.0, 7.0, 5.0)

## Approximates Canvas2D's ctx.setLineDash([dash, gap]) for a full-circle
## stroke — draw_arc has no native dash support.
func _draw_dashed_circle(circle_radius: float, color: Color, width: float, dash: float, gap: float) -> void:
	if circle_radius <= 0.5:
		return
	var dash_angle: float = dash / circle_radius
	var gap_angle: float = gap / circle_radius
	var angle: float = 0.0
	while angle < TAU:
		var end_angle: float = minf(angle + dash_angle, TAU)
		draw_arc(Vector2.ZERO, circle_radius, angle, end_angle, 6, color, width, true)
		angle += dash_angle + gap_angle

## The source reads a dedicated `enemy.burn` field; this port's
## generalized `status_effects` array (see status_effect_instance.gd) has
## no equivalent single field, so this looks for an active "burn"
## instance in it instead — same condition, same trigger. Shared by the
## ashFire synergy check (CombatManager.damage_player_to_enemy) and the
## status overlay's own burn tint below.
func has_burn() -> bool:
	for entry in status_effects:
		var inst: StatusEffectInstance = entry
		if inst != null and inst.definition != null and inst.definition.id == "burn":
			return true
	return false

## Ports drawEnemy.ts's statusOverlay(): a burn tint (while alive) and the
## on-hit white flash (regardless of alive, matching the source exactly).
func _status_overlay(r: float) -> void:
	if alive and has_burn():
		var burn_color := Color(Palette.EMBER4)
		burn_color.a = 0.35 + sin(anim_phase * 16.0) * 0.12
		draw_circle(Vector2(0.0, -r * 0.2), r * 0.9, burn_color)
	if hit_flash_timer > 0.0:
		draw_circle(Vector2.ZERO, r * 1.05, Color(1.0, 1.0, 1.0, (hit_flash_timer / 0.16) * 0.75))

func _draw_ash_crawler() -> void:
	var r: float = radius
	var leg_phase: float = anim_phase * 12.0
	var leg_color := Color(def.color)
	for i in range(4):
		var side: float = -1.0 if i < 2 else 1.0
		var front: bool = i % 2 == 0
		var swing: float = sin(leg_phase + float(i) * 1.6) * 5.0
		var base_x: float = side * r * 0.6
		var base_y: float = -r * 0.3 if front else r * 0.3
		draw_line(Vector2(base_x, base_y), Vector2(base_x + side * 6.0, base_y + swing), leg_color, 2.0)
	# Body: the source's radial gradient has two color stops at the same
	# offset (0) — the first is instantly overridden by the second, so the
	# only color that ever actually renders is '#5a4a3a' fading out to
	# def.color at the edge. Base fill + a shrinking highlight near the
	# gradient's own off-center focal point approximates that.
	draw_colored_polygon(DrawUtils.blob_points(0.0, 0.0, r, 8, 0.08, WOBBLE_SEEDS), Color(def.color))
	var highlight := Color("#5a4a3a")
	var base_color := Color(def.color)
	for i in range(4, 0, -1):
		var t: float = float(i) / 4.0
		draw_circle(Vector2(-2.0, -3.0), r * t * 0.6, highlight.lerp(base_color, t))
	# Eyes, with a soft glow standing in for the source's shadowBlur.
	DrawUtils.draw_glow_circle(self, -3.0, -2.0, 6.6, def.accent_color, 0.6)
	DrawUtils.draw_glow_circle(self, 3.0, -2.0, 6.6, def.accent_color, 0.6)
	var accent := Color(def.accent_color)
	draw_circle(Vector2(-3.0, -2.0), 1.6, accent)
	draw_circle(Vector2(3.0, -2.0), 1.6, accent)

func _draw_hollow() -> void:
	var r: float = radius
	var lean: float = sin(anim_phase * 1.6) * 0.05
	draw_set_transform(Vector2.ZERO, lean, Vector2.ONE)
	# Vertical gradient (dark head fading to def.color toward the feet)
	# sampled once per shape at that shape's own center — a full per-pixel
	# version would need ellipse-clipped polygon slices for a subtle gain.
	var dark := Color("#3a3a44")
	var base_color := Color(def.color)
	var body_color: Color = _linear_gradient_sample(Vector2(0.0, r * 0.2), Vector2(0.0, -r), Vector2(0.0, r), dark, base_color)
	draw_colored_polygon(_ellipse_points(0.0, r * 0.2, r * 0.78, r), body_color)
	var head_color: Color = _linear_gradient_sample(Vector2(0.0, -r * 0.55), Vector2(0.0, -r), Vector2(0.0, r), dark, base_color)
	draw_circle(Vector2(0.0, -r * 0.55), r * 0.5, head_color)
	var eye_color := Color(def.accent_color)
	eye_color.a = 0.85
	draw_colored_polygon(_ellipse_points(-r * 0.16, -r * 0.55, 2.4, 3.0), eye_color)
	draw_colored_polygon(_ellipse_points(r * 0.16, -r * 0.55, 2.4, 3.0), eye_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_flame_wisp() -> void:
	var r: float = radius
	var flicker: float = sin(anim_phase * 9.0) * 0.15 + 1.0
	DrawUtils.draw_glow_circle(self, 0.0, 0.0, r * 1.8 * flicker, def.accent_color, 0.55)
	var flame_color := Color(def.color)
	flame_color.a = 0.7
	var seed: float = float(get_instance_id())
	for i in range(6):
		var angle: float = (float(i) / 6.0) * TAU + anim_phase * 2.0
		var length: float = r * (0.8 + DrawUtils.hash_jitter(seed, float(i)) * 0.6) * flicker
		draw_line(Vector2.ZERO, Vector2(cos(angle), sin(angle)) * length, flame_color, 3.0)
	# Core: 3-stop radial (def.color at the edge, through accent, to a
	# cream center), approximated as concentric circles.
	var core := Color("#fff2d9")
	var accent := Color(def.accent_color)
	var base_color := Color(def.color)
	var core_r: float = r * 0.75
	var steps := 6
	for i in range(steps, 0, -1):
		var t: float = float(i) / float(steps)
		var c: Color = accent.lerp(base_color, (t - 0.5) * 2.0) if t > 0.5 else core.lerp(accent, t * 2.0)
		draw_circle(Vector2.ZERO, core_r * t, c)

func _draw_gravebound() -> void:
	var r: float = radius
	var stomp: float = absf(sin(anim_phase * 3.0)) * 2.0
	var body_pts := PackedVector2Array([
		Vector2(-r * 0.9, r * 0.6),
		Vector2(-r, -r * 0.3 - stomp),
		Vector2(-r * 0.4, -r * 0.9 - stomp),
		Vector2(r * 0.4, -r * 0.9 - stomp),
		Vector2(r, -r * 0.3 - stomp),
		Vector2(r * 0.9, r * 0.6),
	])
	var centroid := Vector2.ZERO
	for p in body_pts:
		centroid += p
	centroid /= float(body_pts.size())
	var body_color: Color = _linear_gradient_sample(centroid, Vector2(-r, -r), Vector2(r, r), Color("#4a4238"), Color(def.color))
	draw_colored_polygon(body_pts, body_color)
	var arm_swing: float = -0.9 if state == State.ATTACK else (0.6 if state == State.WINDUP else 0.0)
	var arm_origin := Vector2(r * 0.75, -r * 0.1)
	var arm_dir := Vector2(0.0, 1.0).rotated(arm_swing)
	var arm_perp := Vector2(1.0, 0.0).rotated(arm_swing)
	var arm_pts := PackedVector2Array([
		arm_origin - arm_perp * 4.0,
		arm_origin + arm_perp * 6.0,
		arm_origin + arm_perp * 6.0 + arm_dir * (r * 1.1),
		arm_origin - arm_perp * 4.0 + arm_dir * (r * 1.1),
	])
	draw_colored_polygon(arm_pts, Color(def.color))
	draw_circle(arm_origin + arm_dir * (r * 1.1), 8.0, Color(def.accent_color).lerp(Color.BLACK, 0.1))
	var eye_y: float = -r * 0.6 - stomp
	DrawUtils.draw_glow_circle(self, -4.0, eye_y, 7.8, def.accent_color, 0.6)
	DrawUtils.draw_glow_circle(self, 4.0, eye_y, 7.8, def.accent_color, 0.6)
	var eye_color := Color(def.accent_color)
	draw_circle(Vector2(-4.0, eye_y), 1.8, eye_color)
	draw_circle(Vector2(4.0, eye_y), 1.8, eye_color)

## TS also multiplies alpha by `enemy.vanishAlpha` here (fading during the
## vanish/reappear states). EnemyAI already drives State.VANISHED/
## REAPPEARING for this enemy (see enemy_ai.gd's `_run_stalker`-style
## logic), but nothing in this port tracks a per-instance fade timer for
## it — that update belongs in _physics_process (a per-tick state field),
## outside this task's drawing-only scope. Reads as always-opaque for now;
## a real gap, not a simplification — see final report.
func _draw_shadow_stalker() -> void:
	var r: float = radius
	var sway: float = sin(anim_phase * 5.0) * 3.0
	var p0 := Vector2(-r * 0.6, -r * 0.2)
	var p1 := Vector2(-r * 0.3, r * 1.5)
	var p2 := Vector2(r * 0.3, r * 1.5)
	var p3 := Vector2(r * 0.6, -r * 0.2)
	var tail_pts := PackedVector2Array([p0])
	tail_pts.append_array(_quad_bezier(p0, Vector2(-r * 0.9 + sway, r * 0.8), p1, 8))
	tail_pts.append_array(_quad_bezier(p1, Vector2(0.0, r * 1.1), p2, 8))
	tail_pts.append_array(_quad_bezier(p2, Vector2(r * 0.9 + sway, r * 0.8), p3, 8))
	tail_pts.append_array(_quad_bezier(p3, Vector2(0.0, -r * 0.5), p0, 8))
	var centroid: Vector2 = (p0 + p1 + p2 + p3) / 4.0
	var fade_end := Color(20.0 / 255.0, 16.0 / 255.0, 30.0 / 255.0, 0.0)
	var tail_color: Color = _linear_gradient_sample(centroid, Vector2(0.0, -r), Vector2(0.0, r * 1.4), Color(def.accent_color), fade_end)
	draw_colored_polygon(tail_pts, tail_color)
	draw_circle(Vector2(0.0, -r * 0.3), r * 0.55, Color(def.color))
	DrawUtils.draw_glow_circle(self, -3.0, -r * 0.32, 9.8, def.accent_color, 0.6)
	DrawUtils.draw_glow_circle(self, 3.0, -r * 0.32, 9.8, def.accent_color, 0.6)
	var eye_color := Color(def.accent_color)
	draw_colored_polygon(_ellipse_points(-3.0, -r * 0.32, 1.8, 1.2), eye_color)
	draw_colored_polygon(_ellipse_points(3.0, -r * 0.32, 1.8, 1.2), eye_color)

func _draw_cinder_wraith() -> void:
	var r: float = radius
	var bob: float = sin(anim_phase * 2.4) * 3.0
	var p0 := Vector2(0.0, -r + bob)
	var p1 := Vector2(r * 0.6, r * 0.9 + bob)
	var p2 := Vector2(-r * 0.6, r * 0.9 + bob)
	var pts := PackedVector2Array([p0])
	pts.append_array(_quad_bezier(p0, Vector2(r * 0.9, -r * 0.2 + bob), p1, 8))
	pts.append_array(_quad_bezier(p1, Vector2(0.0, r * 0.6 + bob), p2, 8))
	pts.append_array(_quad_bezier(p2, Vector2(-r * 0.9, -r * 0.2 + bob), p0, 8))
	var centroid: Vector2 = (p0 + p1 + p2) / 3.0
	var light_color: Color = Color(def.color).lerp(Color.WHITE, 0.15)
	var body_color: Color = _linear_gradient_sample(centroid, Vector2(0.0, -r + bob), Vector2(0.0, r + bob), light_color, Color(def.color))
	draw_colored_polygon(pts, body_color)
	DrawUtils.draw_glow_circle(self, 0.0, -r * 0.1 + bob, r * 0.5, def.accent_color, 0.7)

func _draw_ember_devourer() -> void:
	var r: float = radius
	DrawUtils.draw_glow_circle(self, 0.0, 0.0, r * 1.6, def.accent_color, 0.35)
	var pulse: float = 0.85 + sin(anim_phase * 4.0) * 0.15
	draw_colored_polygon(DrawUtils.blob_points(0.0, 0.0, r, 10, 0.1, WOBBLE_SEEDS), Color(def.color))
	var highlight := Color("#6a2c18")
	var base_color := Color(def.color)
	for i in range(4, 0, -1):
		var t: float = float(i) / 4.0
		draw_circle(Vector2(-r * 0.2, -r * 0.3), r * t * 0.85, highlight.lerp(base_color, t))
	var spike_color := Color(def.accent_color)
	spike_color.a = 0.5 + 0.3 * pulse
	for i in range(5):
		var angle: float = (float(i) / 5.0) * TAU - PI / 2.0
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(dir * (r * 0.3), dir * (r * 0.95), spike_color, 2.0)
	var glow_r: float = 3.2 + 10.0 * pulse
	DrawUtils.draw_glow_circle(self, -r * 0.22, -r * 0.15, glow_r, def.accent_color, 0.6)
	DrawUtils.draw_glow_circle(self, r * 0.22, -r * 0.15, glow_r, def.accent_color, 0.6)
	var accent := Color(def.accent_color)
	draw_circle(Vector2(-r * 0.22, -r * 0.15), 3.2, accent)
	draw_circle(Vector2(r * 0.22, -r * 0.15), 3.2, accent)

func _draw_blightbloat() -> void:
	var r: float = radius
	var swelling: bool = state == State.WINDUP
	var swell_t: float = (minf(1.0, state_timer / maxf(0.05, def.telegraph_time)) if swelling else 0.0)
	var strain: float = (sin(anim_phase * 30.0) * 0.03 * swell_t if swelling else 0.0)
	var scale: float = (1.0 + swell_t * 0.42 + strain) * (1.0 + sin(anim_phase * 3.0) * 0.04)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(scale, scale))
	DrawUtils.draw_glow_circle(self, 0.0, 0.0, r * (1.6 + swell_t * 1.2), Palette.FUNGUS, 0.22 + swell_t * 0.45)
	# Stubby legs, dragging.
	var leg_color := Color("#2a3122")
	var leg_phase: float = anim_phase * 6.0
	for i in range(4):
		var side: float = -1.0 if i < 2 else 1.0
		var front: float = -1.0 if i % 2 == 0 else 1.0
		var swing: float = sin(leg_phase + float(i) * 1.7) * 3.0
		draw_line(Vector2(side * r * 0.5, front * r * 0.35), Vector2(side * r * 0.95, front * r * 0.55 + swing), leg_color, 3.0)
	# The sac: a 3-stop off-center radial gradient (rim tone -> def.color ->
	# a highlight near (-0.3r,-0.35r)), approximated as concentric circles.
	draw_colored_polygon(DrawUtils.blob_points(0.0, 0.0, r, 9, 0.1, WOBBLE_SEEDS), Color("#232a1c"))
	var hi := Color("#6c7a56")
	var mid := Color(def.color)
	var dark := Color("#232a1c")
	for i in range(4, 0, -1):
		var t: float = float(i) / 4.0
		var c: Color = hi.lerp(mid, t / 0.7) if t <= 0.7 else mid.lerp(dark, (t - 0.7) / 0.3)
		draw_circle(Vector2(-r * 0.3, -r * 0.35), r * t * 0.75, c)
	draw_colored_polygon(_ellipse_points(-r * 0.25, -r * 0.3, r * 0.45, r * 0.3, -0.4), Color(1.0, 1.0, 1.0, 0.07))
	# Glowing pustules — brighter and bigger the closer it is to bursting.
	var spots := [
		[-0.35, -0.1, 0.22],
		[0.3, -0.25, 0.18],
		[0.1, 0.35, 0.2],
		[-0.1, 0.05, 0.12],
		[0.42, 0.25, 0.11],
	]
	var pustule_color: Color = Color(Palette.FUNGUS_BRIGHT) if swell_t > 0.5 else Color(Palette.FUNGUS)
	var blur: float = 6.0 + swell_t * 10.0
	for spot in spots:
		var sx: float = spot[0]
		var sy: float = spot[1]
		var pr: float = spot[2] * r * (1.0 + swell_t * 0.5)
		DrawUtils.draw_glow_circle(self, sx * r, sy * r, pr + blur, Palette.FUNGUS, 0.5)
		draw_circle(Vector2(sx * r, sy * r), pr, pustule_color)
	# What's left of the Hollow it grew from: a small skull leaning out the front.
	var hx: float = cos(facing) * r * 0.78
	var hy: float = sin(facing) * r * 0.78
	draw_circle(Vector2(hx, hy), r * 0.3, Color("#2c2c34"))
	var skull_eye := Color(Palette.FUNGUS_BRIGHT)
	draw_circle(Vector2(hx - 2.2, hy - 1.0), 1.3, skull_eye)
	draw_circle(Vector2(hx + 2.2, hy - 1.0), 1.3, skull_eye)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Shared by both wardens (hollowWarden and the champion, sunkenWarden) —
## `def.champion` is exactly the TS drawWarden(ctx, e, champion)'s boolean
## param, already sitting on the definition, so it's read directly here
## instead of threading it through as an argument.
func _draw_warden() -> void:
	var r: float = radius
	var champion: bool = def.champion
	var guard_down: bool = alive and not shield_up()
	var bashing: bool = bash_timer > 0.0
	var stomp: float = absf(sin(anim_phase * 4.0)) * 1.5
	var outer := Transform2D(facing, Vector2.ZERO)
	draw_set_transform_matrix(outer)

	if champion:
		# Captain's cloak trailing behind, in the ruins' own violet.
		var sway: float = sin(anim_phase * 2.2) * r * 0.25
		var cloak_color := Color(Palette.SOUL)
		cloak_color.a = 0.7 if shield_broken else 0.5
		var cloak_start := Vector2(-r * 0.5, -r * 0.55)
		var cloak_end := Vector2(-r * 0.5, r * 0.55)
		var cloak_pts := PackedVector2Array([cloak_start])
		cloak_pts.append_array(_quad_bezier(cloak_start, Vector2(-r * 1.8, sway), cloak_end, 8))
		draw_colored_polygon(cloak_pts, cloak_color)

	# Legs.
	var leg_color := Color("#26222f")
	draw_rect(Rect2(-r * 0.45, -r * 0.6, r * 0.38, r * 0.28 + stomp), leg_color, true)
	draw_rect(Rect2(-r * 0.45, r * 0.32, r * 0.38, r * 0.28 + stomp), leg_color, true)

	# Torso: hunched, armoured, leaning into the shield. The source's 3-stop
	# horizontal gradient is sampled once at the ellipse's own center.
	var torso_a := Color("#2b2738")
	var torso_b := Color("#5a5178") if champion else Color("#57536a")
	var torso_c := Color("#3d3a4c")
	var torso_t: float = clampf((-r * 0.1 + r) / (2.0 * r), 0.0, 1.0)
	var torso_color: Color = torso_a.lerp(torso_b, torso_t / 0.5) if torso_t <= 0.5 else torso_b.lerp(torso_c, (torso_t - 0.5) / 0.5)
	var torso_pts: PackedVector2Array = _ellipse_points(-r * 0.1, 0.0, r * 0.85, r * 0.7)
	draw_colored_polygon(torso_pts, torso_color)
	var torso_outline := torso_pts.duplicate()
	torso_outline.append(torso_pts[0])
	draw_polyline(torso_outline, Color(0.839, 0.816, 0.910, 0.4), 1.4, true)

	# Pauldrons.
	var pauldron_color := Color("#7a7096") if champion else Color("#6f6a84")
	var pauldron_outline := Color(0.0, 0.0, 0.0, 0.45)
	draw_circle(Vector2(-r * 0.15, -r * 0.56), r * 0.32, pauldron_color)
	draw_circle(Vector2(-r * 0.15, r * 0.56), r * 0.32, pauldron_color)
	draw_arc(Vector2(-r * 0.15, -r * 0.56), r * 0.32, 0.0, TAU, 24, pauldron_outline, 1.0, true)
	draw_arc(Vector2(-r * 0.15, r * 0.56), r * 0.32, 0.0, TAU, 24, pauldron_outline, 1.0, true)

	# Mace arm on the +y side.
	draw_rect(Rect2(r * 0.2, r * 0.5, r * 0.75, r * 0.16), Color("#3a3546"), true)
	draw_circle(Vector2(r * 0.98, r * 0.58), r * 0.22, Color("#8b8499"))

	# Helm.
	var helm_color := Color("#7a7296") if champion else Color("#77728a")
	draw_circle(Vector2(r * 0.35, 0.0), r * 0.38, helm_color)
	draw_arc(Vector2(r * 0.35, 0.0), r * 0.38, 0.0, TAU, 24, Color(0.0, 0.0, 0.0, 0.5), 1.0, true)
	if champion:
		# A broken crown of iron.
		var crown_color := Color("#7a7290")
		for off in [-0.22, 0.0, 0.22]:
			draw_rect(Rect2(r * 0.1, off * r - 2.0, r * 0.14, 4.0), crown_color, true)

	var eye_hex: String = Palette.SOUL_BRIGHT if champion else "#d8d2e8"
	var eye_blur: float = 9.0 if champion else 4.0
	DrawUtils.draw_glow_circle(self, r * 0.575, 0.0, r * 0.14 + eye_blur, eye_hex, 0.6)
	draw_rect(Rect2(r * 0.5, -r * 0.14, r * 0.15, r * 0.28), Color(eye_hex), true)

	if not shield_broken:
		# The shield: a door-sized slab of worked stone. Raised, it stands
		# square across the front; with the guard down it swings out to the
		# -y side and tilts, leaving the front open.
		var nested: Transform2D
		if guard_down:
			nested = Transform2D(-1.1, Vector2(-r * 0.05, -r * 0.95))
		else:
			nested = Transform2D(0.0, Vector2(r * 0.74, 0.0))
		draw_set_transform_matrix(outer * nested)
		var sw: float = r * 0.42
		var sh: float = r * 2.15
		# Sampled at the slab's own center (t=0.5, exactly the gradient's
		# own middle stop) — a small, evenly-lit-looking panel.
		var slab_color := Color("#a49ebb")
		# Rounded corners (roundedRectPath) simplified to a plain rect —
		# Godot's immediate-mode draw has no rounded-rect primitive.
		var slab_rect := Rect2(-sw / 2.0, -sh / 2.0, sw, sh)
		draw_rect(slab_rect, slab_color, true)
		draw_rect(slab_rect, Color(0.0, 0.0, 0.0, 0.55), false, 1.5)
		# Carved door-lines and a rune.
		var rune_color: Color = Color(Palette.SOUL) if champion else Color(0.824, 0.800, 0.894)
		rune_color.a = 0.7
		draw_line(Vector2(0.0, -sh * 0.36), Vector2(0.0, sh * 0.36), rune_color, 1.2)
		draw_line(Vector2(-sw * 0.3, -sh * 0.12), Vector2(sw * 0.3, -sh * 0.12), rune_color, 1.2)
		draw_line(Vector2(-sw * 0.3, sh * 0.12), Vector2(sw * 0.3, sh * 0.12), rune_color, 1.2)
		if champion and hp < max_hp * 0.75:
			# Cracks spreading as the shatter gets close.
			var crack_color := Color(0.0, 0.0, 0.0, 0.6)
			var crack1 := PackedVector2Array([
				Vector2(-sw * 0.4, -sh * 0.3), Vector2(sw * 0.1, -sh * 0.05), Vector2(-sw * 0.2, sh * 0.25),
			])
			draw_polyline(crack1, crack_color, 1.3, true)
			draw_line(Vector2(sw * 0.35, sh * 0.1), Vector2(0.0, sh * 0.32), crack_color, 1.3)
		draw_set_transform_matrix(outer)
	else:
		# What's left strapped to the arm: a jagged stub.
		var stub_pts := PackedVector2Array([
			Vector2(r * 0.6, -r * 0.55), Vector2(r * 0.9, -r * 0.4), Vector2(r * 0.78, -r * 0.05),
			Vector2(r * 0.95, r * 0.2), Vector2(r * 0.6, r * 0.3),
		])
		draw_colored_polygon(stub_pts, Color("#6a6482"))
		var stub_outline := stub_pts.duplicate()
		stub_outline.append(stub_pts[0])
		draw_polyline(stub_outline, Color(0.0, 0.0, 0.0, 0.55), 1.2, true)

	if bashing:
		var streak_color := Color(0.863, 0.839, 0.922, 0.4)
		for off in [-0.5, 0.0, 0.5]:
			draw_line(Vector2(-r * 1.1, off * r), Vector2(-r * 2.2, off * r * 1.3), streak_color, 2.0)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Guard-down cue, rotation-independent: a bright pulsing ring — "now".
	if guard_down and not shield_broken and state == State.COOLDOWN:
		var p: float = 0.45 + sin(anim_phase * 18.0) * 0.3
		var ring_color := Color(Palette.GOLD_BRIGHT)
		ring_color.a = p
		draw_arc(Vector2.ZERO, r * 1.18, 0.0, TAU, 32, ring_color, 2.0, true)

	if champion and shield_broken and alive:
		# Phase two: spores leaking from the cracks. (Source uses an
		# additive blend here too — see this file's own top-of-_draw() note.)
		DrawUtils.draw_glow_circle(self, 0.0, 0.0, r * 1.5, Palette.FUNGUS, 0.16 + sin(anim_phase * 5.0) * 0.06)

## Builds an axis-aligned (pre-rotation) ellipse as a closed point ring —
## Godot's draw_colored_polygon/draw_polyline have no ellipse primitive.
## `rotation` matches Canvas2D's ellipse() rotation argument.
static func _ellipse_points(cx: float, cy: float, rx: float, ry: float, rotation: float = 0.0, segments: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var angle: float = (float(i) / float(segments)) * TAU
		var local := Vector2(cos(angle) * rx, sin(angle) * ry)
		if rotation != 0.0:
			local = local.rotated(rotation)
		pts.append(Vector2(cx, cy) + local)
	return pts

## Samples a quadratic Bézier curve (Canvas2D's quadraticCurveTo has no
## direct Godot primitive) into `segments` straight-line steps, from just
## after `p0` through `p1` inclusive. Chain calls (feeding each curve's own
## end point back in as the next curve's `p0`) to build a multi-segment
## path exactly like chaining quadraticCurveTo calls — draw_colored_polygon
## closes the final shape back to the very first point automatically.
static func _quad_bezier(p0: Vector2, control: Vector2, p1: Vector2, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(1, segments + 1):
		var t: float = float(i) / float(segments)
		var mt: float = 1.0 - t
		pts.append(p0 * (mt * mt) + control * (2.0 * mt * t) + p1 * (t * t))
	return pts

## Flat-color stand-in for a Canvas2D linear gradient: the color it would
## show at point `p`, for a gradient running from `a` (color_a) to `b`
## (color_b). Picks ONE representative color per shape instead of a full
## per-pixel gradient — see this file's own top-of-_draw() note.
static func _linear_gradient_sample(p: Vector2, a: Vector2, b: Vector2, color_a: Color, color_b: Color) -> Color:
	var axis: Vector2 = b - a
	var len_sq: float = axis.length_squared()
	if len_sq <= 0.0001:
		return color_a
	var t: float = clampf((p - a).dot(axis) / len_sq, 0.0, 1.0)
	return color_a.lerp(color_b, t)
