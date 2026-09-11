class_name PlayerCharacter
extends CharacterBody2D
## Ports entities/Player.ts. Movement is applied through CharacterBody2D's
## own move_and_slide() — the Web build integrates position manually, then
## Game.ts resolves collision separately afterward; move_and_slide() folds
## both into one call, per GODOT_MIGRATION.md §2's own prescription.
##
## Input is read directly via raw Input.is_physical_key_pressed()/
## is_mouse_button_pressed() calls rather than a project.godot InputMap —
## a deliberate build-order-step-3 simplification to avoid hand-authoring
## the InputMap's more complex serialized format with no engine available
## to verify it against. Wiring real named actions later (via the editor,
## which generates that format correctly itself) is a safe, easy follow-up,
## not a redo — nothing here depends on the raw-key approach specifically.
##
## Not ported yet, on purpose (see build-order step 6, Progression):
## recomputeStats()/addUpgrade()/addBonusModifier()/synergies. `stats` sits
## at StatBlock.fresh() — no owned upgrades exist yet, so there is nothing
## to recompute from. cloakPhase WAS deferred here the same way, until real
## rendering (step 7) needed it for the cape's idle sway — see cloak_phase's
## own doc-comment below.

signal died
signal hp_changed(current: float, max: float)

const STAMINA_REGEN_DELAY := 0.55
const STAMINA_REGEN_RATE := 45.0
const DODGE_STAMINA_COST := 15.0
const BASE_ENERGY_REGEN := 6.0
const DODGE_DURATION := 0.22
const MOVE_ACCEL := 14.0

enum AnimState { IDLE, RUN, ATTACK, HIT, DEAD, DODGE, ABILITY }

var stats: StatBlock = StatBlock.fresh()
var weapon_id: String = "emberBlade"
var ability_id: String = "emberBurst"
var unlocked_weapons: Array[String] = ["emberBlade"]
var unlocked_abilities: Array[String] = ["emberBurst"]

## Debug-only: edge-detect state for the Q weapon-cycle key (see
## cycle_weapon()) so a held key advances once per press, not once per frame.
var _cycle_weapon_key_down: bool = false

var radius: float = 15.0
var hp: float = 100.0
var shield_charges: int = 0
var energy: float = 100.0
var stamina: float = 100.0
var stamina_regen_delay_timer: float = 0.0
var alive: bool = true
var death_timer: float = 0.0

var invuln_timer: float = 0.0
var hit_flash_timer: float = 0.0

## Set by LevelFlow during the scripted stairwell walk (build-order step 6):
## no input, no regen/status-effect ticking, position driven externally —
## mirrors Game.ts's updatePlaying short-circuiting entirely to
## updateTransition while a stairs transition is in progress.
var is_transitioning: bool = false

var attack_cooldown_timer: float = 0.0
var attack_anim_timer: float = 0.0
var is_attacking: bool = false
var attack_facing_lock: float = 0.0
var attack_swing_id: int = 0

var dodge_cooldown_timer: float = 0.0
var is_dodging: bool = false
var dodge_timer: float = 0.0
var dodge_dir := Vector2.ZERO
var last_dodge_end_time: float = -10.0

var is_channeling_ability: bool = false
var ability_anim_timer: float = 0.0

var anim_state: AnimState = AnimState.IDLE
var anim_time: float = 0.0
var move_cycle_phase: float = 0.0
## Pure cosmetic timer for the cape's idle sway (drawPlayer.ts's cloakPhase)
## — deferred at build-order step 3 (see this file's own class doc-comment
## above) until real rendering (step 7) needed it, which it now does. Ticks
## unconditionally by dt each physics step, same as Player.ts's cloakPhase,
## but — also like the TS source — only while alive: _update_state()
## returns before reaching this once `alive` goes false, so it (and the
## cape sway it drives) freezes at the moment of death instead of drifting
## through the death animation.
var cloak_phase: float = 0.0

var move_input := Vector2.ZERO
var facing: float = 0.0
var run_time: float = 0.0
var perfect_dodge_timer: float = 0.0

## No status effect currently ever targets the player (only enemies can be
## burned/bled today) — present for symmetry so StatusEffectRuntime can
## treat Player and Enemy identically, not because anything applies one yet.
var status_effects: Array = []

@export var body_color: Color = Color("#e0c9a6")

## Null-guarded and loud on failure (push_error, once per distinct missing
## id) rather than letting a bad/missing DataRegistry entry silently break
## every gating check that reads weapon()/ability() — diagnosed during
## step-3 testing where a broken lookup here made attack/ability appear
## to do nothing with no visible cause.
var _warned_missing_weapon: String = ""
var _warned_missing_ability: String = ""

func weapon() -> WeaponDefinition:
	var w: WeaponDefinition = DataRegistry.get_weapon(weapon_id)
	if w == null and _warned_missing_weapon != weapon_id:
		_warned_missing_weapon = weapon_id
		push_error("PlayerCharacter: weapon '%s' not found in DataRegistry (loaded: %d) — check resources/weapons/%s.tres exists and its `id` field matches" % [weapon_id, DataRegistry.counts().get("weapons", 0), weapon_id])
	return w

func ability() -> AbilityDefinition:
	var a: AbilityDefinition = DataRegistry.get_ability(ability_id)
	if a == null and _warned_missing_ability != ability_id:
		_warned_missing_ability = ability_id
		push_error("PlayerCharacter: ability '%s' not found in DataRegistry (loaded: %d) — check resources/abilities/%s.tres exists and its `id` field matches" % [ability_id, DataRegistry.counts().get("abilities", 0), ability_id])
	return a

func attack_cooldown_duration() -> float:
	var w := weapon()
	return w.attack_cooldown / stats.attack_speed_mult if w != null else 999.0

func dodge_cooldown_duration() -> float:
	return 0.95 * stats.dodge_cooldown_mult

func is_invulnerable() -> bool:
	return invuln_timer > 0.0 or is_dodging

func can_attack() -> bool:
	return alive and not is_dodging and attack_cooldown_timer <= 0.0 and has_enough_stamina()

## Split out from can_attack() so callers (HUD/input feedback) can tell a
## stamina-blocked swing apart from one that's merely still on cooldown.
func has_enough_stamina() -> bool:
	var w := weapon()
	return w != null and stamina >= w.stamina_cost

func can_dodge() -> bool:
	return alive and not is_dodging and dodge_cooldown_timer <= 0.0 and has_enough_stamina_for_dodge()

func has_enough_stamina_for_dodge() -> bool:
	return stamina >= DODGE_STAMINA_COST

func can_use_ability() -> bool:
	return alive and not is_dodging and energy >= stats.energy_max

func start_attack() -> void:
	var w := weapon()
	if w == null:
		return
	is_attacking = true
	attack_anim_timer = 0.0
	attack_facing_lock = facing
	attack_cooldown_timer = attack_cooldown_duration()
	attack_swing_id += 1
	anim_state = AnimState.ATTACK
	anim_time = 0.0
	stamina = maxf(0.0, stamina - w.stamina_cost)
	stamina_regen_delay_timer = STAMINA_REGEN_DELAY
	# The hit check (melee) or the shot(s) (ranged) fire once, instantly,
	# right as the swing starts — not delayed to when the swing animation
	# completes. Real Strategy dispatch (build-order step 5): which archetype
	# runs is entirely WeaponDefinition.kind's business, not this function's.
	var behavior := WeaponBehavior.for_kind(w.kind)
	if behavior != null:
		behavior.execute(self, w)

## Debug-only weapon switching, added for build-order step 5 so the
## Bow/Solar Spear are actually testable — the real equip flow is
## LoadoutSelectUI.ts's own screen, still build-order step 9. Cycles
## unlocked_weapons the same way that screen sets weaponId directly (a
## plain field write there too, nothing more). The playground scene seeds
## unlocked_weapons with all 4 weapons for exactly this reason.
func cycle_weapon() -> void:
	if unlocked_weapons.is_empty():
		return
	var idx: int = unlocked_weapons.find(weapon_id)
	weapon_id = unlocked_weapons[(idx + 1) % unlocked_weapons.size()]

func start_dodge(dir: Vector2) -> void:
	is_dodging = true
	dodge_timer = 0.0
	dodge_dir = dir
	dodge_cooldown_timer = dodge_cooldown_duration()
	anim_state = AnimState.DODGE
	anim_time = 0.0
	stamina = maxf(0.0, stamina - DODGE_STAMINA_COST)
	stamina_regen_delay_timer = STAMINA_REGEN_DELAY

func start_ability() -> void:
	energy = 0.0
	is_channeling_ability = true
	ability_anim_timer = 0.0
	anim_state = AnimState.ABILITY
	anim_time = 0.0

## Returns {taken, blocked, shield_consumed} — mirrors Player.ts's return
## shape exactly (a Dictionary here, an object literal there).
func take_damage(amount: float) -> Dictionary:
	if is_invulnerable() or not alive:
		return {"taken": 0.0, "blocked": true, "shield_consumed": false}
	var dmg: float = amount * (1.0 - stats.armor)
	if shield_charges > 0:
		shield_charges -= 1
		invuln_timer = 0.4
		hit_flash_timer = 0.25
		return {"taken": 0.0, "blocked": true, "shield_consumed": true}
	dmg = maxf(1.0, dmg)
	hp -= dmg
	hit_flash_timer = 0.28
	invuln_timer = 0.55
	anim_state = AnimState.HIT
	anim_time = 0.0
	if hp <= 0.0:
		hp = 0.0
		alive = false
		anim_state = AnimState.DEAD
		anim_time = 0.0
		died.emit()
	hp_changed.emit(hp, stats.max_hp)
	return {"taken": dmg, "blocked": false, "shield_consumed": false}

func heal(amount: float) -> void:
	hp = clampf(hp + amount, 0.0, stats.max_hp)
	hp_changed.emit(hp, stats.max_hp)

func _ready() -> void:
	add_to_group("player")
	hp = stats.max_hp
	energy = stats.energy_max
	stamina = stats.stamina_max
	var shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if shape and shape.shape is CircleShape2D:
		(shape.shape as CircleShape2D).radius = radius
	# Ports Game.ts's registerLights(): "lighting.add(player.x, player.y, 260,
	# Palette.ember4, 1)" — constant for the run's whole lifetime, so this is
	# the only place it needs setting (unlike the enemy/obstacle lights that
	# change condition every frame).
	var glow: PointLight2D = $Glow
	glow.texture = DrawUtils.glow_texture()
	glow.texture_scale = 260.0 / 128.0
	glow.color = Color(Palette.EMBER4)
	glow.energy = 1.0
	glow.enabled = true

func _physics_process(delta: float) -> void:
	if not is_transitioning:
		_read_input()
		_update_state(delta)
		move_and_slide()
		StatusEffectRuntime.process(self, delta)
	queue_redraw()

func _read_input() -> void:
	var x := 0.0
	var y := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): x += 1.0
	move_input = Vector2(x, y)
	if move_input.length_squared() > 1.0:
		move_input = move_input.normalized()
	facing = (get_global_mouse_position() - global_position).angle()

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and can_attack():
		start_attack()
	if Input.is_physical_key_pressed(KEY_SPACE) and can_dodge():
		# Dodge toward current move input; fall back to facing (aim) if the
		# player isn't holding a direction — exact port of Game.ts's
		# performDodge, including its 0.1 magnitude threshold.
		var dir := move_input
		if dir.length() < 0.1:
			dir = Vector2(cos(facing), sin(facing))
		else:
			dir = dir.normalized()
		start_dodge(dir)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and can_use_ability():
		start_ability()

	if Input.is_physical_key_pressed(KEY_Q):
		if not _cycle_weapon_key_down:
			_cycle_weapon_key_down = true
			cycle_weapon()
	else:
		_cycle_weapon_key_down = false

func _update_state(dt: float) -> void:
	run_time += dt
	anim_time += dt
	if not alive:
		death_timer += dt
		return

	if invuln_timer > 0.0: invuln_timer -= dt
	if hit_flash_timer > 0.0: hit_flash_timer -= dt
	if attack_cooldown_timer > 0.0: attack_cooldown_timer -= dt
	if dodge_cooldown_timer > 0.0: dodge_cooldown_timer -= dt
	if stamina_regen_delay_timer > 0.0: stamina_regen_delay_timer -= dt
	if perfect_dodge_timer > 0.0: perfect_dodge_timer -= dt

	hp = clampf(hp + stats.hp_regen * dt, 0.0, stats.max_hp)
	if stamina_regen_delay_timer <= 0.0:
		stamina = clampf(stamina + STAMINA_REGEN_RATE * dt, 0.0, stats.stamina_max)
	# energyRegen (Second Wind) scales this proportionally to its base value,
	# so the ability always finishes a full 0->100% recharge in exactly its
	# own cooldown duration at the default regen rate, faster with upgrades.
	var current_ability := ability()
	if current_ability != null:
		var ability_regen_rate: float = (stats.energy_max / current_ability.cooldown) * (stats.energy_regen / BASE_ENERGY_REGEN)
		energy = clampf(energy + ability_regen_rate * dt, 0.0, stats.energy_max)

	if is_attacking:
		attack_anim_timer += dt
		var swing_duration: float = minf(0.32, attack_cooldown_duration() * 0.85)
		if attack_anim_timer >= swing_duration:
			is_attacking = false

	if is_dodging:
		dodge_timer += dt
		var t: float = dodge_timer / DODGE_DURATION
		var speed: float = stats.move_speed * 3.1 * (1.0 - t * 0.3)
		velocity = dodge_dir * speed
		# Ports Game.ts's per-frame "if (player.isDodging)
		# spawnDodgeTrail(...)" — one trail particle every physics tick for
		# the dodge's whole (short) duration, same density as the source.
		var vfx_parent := get_parent()
		if vfx_parent != null:
			VfxPresets.dodge_trail(vfx_parent, global_position, facing, Palette.EMBER4)
		if dodge_timer >= DODGE_DURATION:
			is_dodging = false
			last_dodge_end_time = run_time
	else:
		var target_velocity: Vector2 = move_input * stats.move_speed
		velocity += (target_velocity - velocity) * minf(1.0, MOVE_ACCEL * dt)

	var moving: bool = move_input.x != 0.0 or move_input.y != 0.0
	if moving:
		var speed_ratio: float = velocity.length() / maxf(1.0, stats.move_speed)
		move_cycle_phase += dt * 7.2 * maxf(0.4, speed_ratio)
	cloak_phase += dt

	if is_channeling_ability:
		ability_anim_timer += dt
		if ability_anim_timer > 0.35:
			is_channeling_ability = false

	if not is_attacking and not is_dodging and not is_channeling_ability:
		anim_state = AnimState.RUN if moving else AnimState.IDLE

## Ports rendering/draw/drawPlayer.ts. _draw() runs in this node's own local
## space (a Node2D's origin is already its own global_position), so the
## source's outer `ctx.translate(screenX, screenY)` is simply dropped —
## everything below is already relative to that.
##
## Every shape's points funnel through _body_xf(), which reproduces the
## source's own transform stack in order: the idle-breathing/run bob offset
## and dodge squash-stretch (`ctx.translate(0, bob); ctx.scale(1/squash,
## squash)`), composed with the on-death fall-over rotate+drop (identity —
## angle 0, offset 0 — while alive, so it's safe to apply unconditionally
## to every point). A shape with its own additional local rotate/translate
## (the cape, the head/hood, the weapon+arm) applies that first — via
## Vector2.rotated()/plain addition — before handing the result to
## _body_xf, the same "compute the already-transformed points yourself"
## convention obstacle_node.gd's _rot_point already established in this
## project instead of draw_set_transform (which would leak into whatever
## draws next in the same _draw() call).
##
## Simplifications (Godot's immediate-mode _draw() has no equivalent):
## - Every ctx.createLinearGradient/createRadialGradient fill becomes a
##   single flat color — its stops' midpoint via DrawUtils.lerp_color_hex,
##   except the 3-stop weapon blade, which uses the weapon's own true color
##   (its middle and most identity-defining stop). Same convention
##   obstacle_node.gd already uses throughout (see its own gradient notes).
## - ctx.shadowBlur/shadowColor glow-on-stroke/fill effects are dropped
##   (plain flat color instead) — there's no blur primitive to reach for.
##   Where the source used drawGlowCircle instead (the chest ember), that's
##   kept via DrawUtils.draw_glow_circle exactly as written.
## - ctx.globalCompositeOperation = 'lighter' (additive) for the hit-flash
##   overlay is simplified to a plain alpha-blended overlay, matching
##   enemy.gd's own existing hit-flash treatment.
## - drawWeapon's swingProgress param only ever fed shadowBlur's intensity
##   (8 vs 18), so with shadowBlur dropped it has no remaining visual
##   effect and isn't threaded into _draw_weapon() at all.
func _draw() -> void:
	var w: WeaponDefinition = weapon()
	var draw_facing: float = attack_facing_lock if is_attacking else facing
	var moving: bool = velocity.length() > 6.0 and not is_dodging
	var bob: float = sin(move_cycle_phase) * 2.4 if moving else sin(anim_time * 2.0) * 0.8
	var squash: float = 1.15 if is_dodging else 1.0

	var is_dead: bool = not alive
	var death_t: float = minf(1.0, death_timer / 0.6)
	var death_angle := 0.0
	var death_offset_y := 0.0
	var death_alpha := 1.0
	if is_dead:
		death_alpha = maxf(0.15, 1.0 - death_t * 0.6)
		# Uses the raw `facing` field (not draw_facing) — matches the
		# source, which reads player.facing here even mid-attack.
		death_angle = (PI / 2.0) * _ease_out_cubic(death_t) * (1.0 if facing > 0.0 else -1.0)
		death_offset_y = _ease_out_cubic(death_t) * 10.0

	# Shadow anchors to the ground — drawn before bob/squash/death so it
	# doesn't move with the body above it.
	DrawUtils.draw_soft_shadow(self, 0.0, 20.0, 22.0, 9.0, 0.42)

	# --- Cape ---
	var cape_angle: float = atan2(velocity.y, velocity.x) if moving else draw_facing
	var cape_sway: float = sin(cloak_phase * 3.4) * 5.0
	var cape_local_angle: float = cape_angle + PI
	var cape_seg1 := _quad_bezier_points(Vector2(-4.0, -12.0), Vector2(18.0 + absf(cape_sway) * 0.4, -18.0 + cape_sway), Vector2(30.0, -4.0 + cape_sway * 0.6), 8)
	var cape_seg2 := _quad_bezier_points(Vector2(30.0, -4.0 + cape_sway * 0.6), Vector2(24.0, 6.0), Vector2(14.0, 10.0), 8)
	var cape_seg3 := _quad_bezier_points(Vector2(14.0, 10.0), Vector2(6.0, 14.0), Vector2(-4.0, 12.0), 8)
	var cape_raw := cape_seg1
	for i in range(1, cape_seg2.size()):
		cape_raw.append(cape_seg2[i])
	for i in range(1, cape_seg3.size()):
		cape_raw.append(cape_seg3[i])
	var cape_pts := PackedVector2Array()
	for p in cape_raw:
		cape_pts.append(_body_xf(p.rotated(cape_local_angle), bob, squash, death_angle, death_offset_y))
	# Gradient (bg1 -> near-black) simplified to its midpoint tone.
	var cape_color: Color = DrawUtils.lerp_color_hex(Palette.BG1, "#0a0810", 0.5)
	cape_color.a = death_alpha
	draw_colored_polygon(cape_pts, cape_color)
	var cape_outline := cape_pts.duplicate()
	cape_outline.append(cape_pts[0])
	var cape_stroke_color := Color(Palette.EMBER3)
	cape_stroke_color.a = 0.35 * death_alpha
	draw_polyline(cape_outline, cape_stroke_color, 1.2, true)

	# --- Body ---
	var body_pts := PackedVector2Array()
	for p in _ellipse_points(0.0, 2.0, 13.0, 16.0):
		body_pts.append(_body_xf(p, bob, squash, death_angle, death_offset_y))
	# Radial gradient (small inner highlight -> bg1) simplified to its midpoint tone.
	var body_color: Color = DrawUtils.lerp_color_hex("#3a3444", Palette.BG1, 0.5)
	body_color.a = death_alpha
	draw_colored_polygon(body_pts, body_color)

	# --- Chest ember (the light he guards) ---
	var pulse: float = 0.75 + sin(run_time * 3.2) * 0.25
	# draw_glow_circle draws directly in raw local space with no per-point
	# transform hook, so its center can follow bob and the death rotate/
	# drop (applied explicitly below, mirroring _body_xf's own math) but
	# not the dodge squash — that would need to turn the circle into an
	# ellipse, which this shared, already-written helper can't do. An
	# acceptable, small (dodge-only, sub-2px) discrepancy.
	var ember_center := Vector2(0.0, 4.0 + bob)
	if is_dead:
		ember_center = (ember_center + Vector2(0.0, death_offset_y)).rotated(death_angle)
	DrawUtils.draw_glow_circle(self, ember_center.x, ember_center.y, 13.0 * pulse, Palette.EMBER4, 0.9 * death_alpha)
	var ember_dot_pts := PackedVector2Array()
	for p in _ellipse_points(0.0, 4.0, 3.0, 3.0):
		ember_dot_pts.append(_body_xf(p, bob, squash, death_angle, death_offset_y))
	var ember_dot_color := Color(Palette.EMBER6)
	ember_dot_color.a = death_alpha
	draw_colored_polygon(ember_dot_pts, ember_dot_color)

	# --- Head + hood ---
	var head_angle: float = draw_facing * 0.18
	var skull_pts := PackedVector2Array()
	for p in _ellipse_points(0.0, -16.0, 9.0, 9.0):
		skull_pts.append(_body_xf(p.rotated(head_angle), bob, squash, death_angle, death_offset_y))
	var skull_color := Color("#2a2632")
	skull_color.a = death_alpha
	draw_colored_polygon(skull_pts, skull_color)

	var hood_seg1 := _quad_bezier_points(Vector2(-9.0, -18.0), Vector2(0.0, -30.0), Vector2(9.0, -18.0), 8)
	var hood_seg2 := _quad_bezier_points(Vector2(9.0, -18.0), Vector2(6.0, -12.0), Vector2(0.0, -10.0), 8)
	var hood_seg3 := _quad_bezier_points(Vector2(0.0, -10.0), Vector2(-6.0, -12.0), Vector2(-9.0, -18.0), 8)
	var hood_raw := hood_seg1
	for i in range(1, hood_seg2.size()):
		hood_raw.append(hood_seg2[i])
	for i in range(1, hood_seg3.size()):
		hood_raw.append(hood_seg3[i])
	var hood_pts := PackedVector2Array()
	for p in hood_raw:
		hood_pts.append(_body_xf(p.rotated(head_angle), bob, squash, death_angle, death_offset_y))
	var hood_color := Color(Palette.BG0)
	hood_color.a = death_alpha
	draw_colored_polygon(hood_pts, hood_color)

	# Eye glow (shadowBlur-based in the source) simplified to a flat fill.
	var eye_x: float = cos(draw_facing) * 4.0
	var eye_y: float = -16.0 + sin(draw_facing) * 2.0
	var eye_pts := PackedVector2Array()
	for p in _ellipse_points(eye_x, eye_y, 2.6, 1.6):
		eye_pts.append(_body_xf(p.rotated(head_angle), bob, squash, death_angle, death_offset_y))
	var eye_color := Color(Palette.EMBER5)
	eye_color.a = death_alpha
	draw_colored_polygon(eye_pts, eye_color)

	# --- Arm + Weapon ---
	# (weapon() can return null on a missing/misconfigured DataRegistry
	# entry — see weapon()'s own push_error above. Not something the
	# source's player.weapon getter has to account for, but skipping the
	# arm/weapon silhouette entirely is the safe fallback here rather than
	# guessing at a placeholder weapon.)
	if w != null:
		var weapon_angle: float = draw_facing
		if is_attacking:
			var swing_duration: float = minf(0.32, attack_cooldown_duration() * 0.85)
			var swing_progress: float = minf(1.0, attack_anim_timer / swing_duration)
			# `?? 90` in the source: arc_degrees is 0.0 (unset) on both
			# ranged weapons' resources, same as an absent field in TS —
			# same fallback idiom enemy_ai.gd already uses for other
			# optional EnemyDefinition floats (e.g. vanish_duration).
			var arc_degrees: float = w.arc_degrees if w.arc_degrees > 0.0 else 90.0
			var arc: float = arc_degrees * PI / 180.0
			var swing_angle: float = -arc / 2.0 + arc * _ease_out_cubic(swing_progress)
			weapon_angle = draw_facing + swing_angle
		var arm_offset := 10.0
		# Melee blade length is derived from the weapon's actual (stat-scaled) range so the
		# sprite always reaches exactly as far as the hitbox does — armOffset (above) and the
		# blade tip's own +4 extension (_draw_weapon's path) are both part of that total reach.
		var melee_length: float = maxf(20.0, w.range * stats.range_mult - arm_offset - 4.0)
		var weapon_length: float = melee_length if w.kind == WeaponDefinition.Kind.MELEE else 40.0
		_draw_weapon(w, weapon_length, weapon_angle, arm_offset, bob, squash, death_angle, death_offset_y, death_alpha)

	# --- Hit flash overlay ---
	if hit_flash_timer > 0.0 and not is_dead:
		var flash_pts := PackedVector2Array()
		for p in _ellipse_points(0.0, 0.0, 18.0, 20.0):
			flash_pts.append(_body_xf(p, bob, squash, death_angle, death_offset_y))
		var flash_color := Color(Palette.BLOOD_BRIGHT)
		flash_color.a = (hit_flash_timer / 0.28) * 0.55
		draw_colored_polygon(flash_pts, flash_color)

	if is_invulnerable() and alive and not is_dodging:
		var ring_pts := PackedVector2Array()
		for p in _ellipse_points(0.0, 2.0, 17.0, 20.0):
			ring_pts.append(_body_xf(p, bob, squash, death_angle, death_offset_y))
		ring_pts.append(ring_pts[0])
		var ring_pulse: float = 0.5 + sin(run_time * 30.0) * 0.2
		var ring_color := Color(Palette.EMBER5)
		ring_color.a = 0.6 * ring_pulse
		draw_polyline(ring_pts, ring_color, 1.5, true)

## Ports drawPlayer.ts's local drawWeapon() helper. `weapon_angle`/`arm_offset`
## are the arm's own rotate/translate: the source calls `ctx.rotate(weaponAngle)`
## then `ctx.translate(armOffset, 0)`, so — per the reverse-of-call-order
## composition this whole file follows — a raw point is translated first,
## then rotated, before being handed to _body_xf for the outer bob/squash/
## death transform.
func _draw_weapon(w: WeaponDefinition, length: float, weapon_angle: float, arm_offset: float, bob: float, squash: float, death_angle: float, death_offset_y: float, death_alpha: float) -> void:
	if w.kind == WeaponDefinition.Kind.MELEE:
		var width: float = 9.0 if w.id == "voidScythe" else 6.0
		var curve: float = 0.55 if w.id == "voidScythe" else 0.15
		var raw := _quad_bezier_points(Vector2(6.0, 3.0), Vector2(length * 0.55, -width - length * curve), Vector2(length, -width * 0.4), 8)
		raw.append(Vector2(length + 4.0, 0.0))
		var raw_seg2 := _quad_bezier_points(Vector2(length + 4.0, 0.0), Vector2(length * 0.55, width * 0.7 + length * curve * 0.6), Vector2(6.0, -3.0), 8)
		for i in range(1, raw_seg2.size()):
			raw.append(raw_seg2[i])
		var blade_pts := PackedVector2Array()
		for p in raw:
			blade_pts.append(_body_xf((p + Vector2(arm_offset, 0.0)).rotated(weapon_angle), bob, squash, death_angle, death_offset_y))
		# 3-stop gradient (bg3 -> weapon color -> near-white) simplified to
		# the weapon's own (middle, most identity-defining) flat color.
		var blade_color := Color(w.color)
		blade_color.a = death_alpha
		draw_colored_polygon(blade_pts, blade_color)

		var grip_raw := PackedVector2Array([Vector2(-6.0, -3.0), Vector2(6.0, -3.0), Vector2(6.0, 3.0), Vector2(-6.0, 3.0)])
		var grip_pts := PackedVector2Array()
		for p in grip_raw:
			grip_pts.append(_body_xf((p + Vector2(arm_offset, 0.0)).rotated(weapon_angle), bob, squash, death_angle, death_offset_y))
		var grip_color := Color(Palette.BG2)
		grip_color.a = death_alpha
		draw_colored_polygon(grip_pts, grip_color)
	else:
		var head_raw := PackedVector2Array([Vector2(4.0, 0.0), Vector2(length - 14.0, -4.0), Vector2(length, 0.0), Vector2(length - 14.0, 4.0)])
		var head_pts := PackedVector2Array()
		for p in head_raw:
			head_pts.append(_body_xf((p + Vector2(arm_offset, 0.0)).rotated(weapon_angle), bob, squash, death_angle, death_offset_y))
		# Gradient (bg3 -> weapon color) simplified to its midpoint tone.
		var head_color: Color = DrawUtils.lerp_color_hex(Palette.BG3, w.color, 0.5)
		head_color.a = death_alpha
		draw_colored_polygon(head_pts, head_color)

		var grip_raw := PackedVector2Array([Vector2(-4.0, -2.5), Vector2(6.0, -2.5), Vector2(6.0, 2.5), Vector2(-4.0, 2.5)])
		var grip_pts := PackedVector2Array()
		for p in grip_raw:
			grip_pts.append(_body_xf((p + Vector2(arm_offset, 0.0)).rotated(weapon_angle), bob, squash, death_angle, death_offset_y))
		var grip_color := Color(Palette.BG2)
		grip_color.a = death_alpha
		draw_colored_polygon(grip_pts, grip_color)

## Applies drawPlayer.ts's outer per-shape transform stack to a point
## already expressed in the character's own undistorted local draw space:
## the always-on dodge squash-stretch + idle/run bob offset, composed with
## the on-death fall-over rotate+drop (identity — angle 0, offset 0 — while
## alive, so this is safe to call unconditionally for every point).
func _body_xf(p: Vector2, bob: float, squash: float, death_angle: float, death_offset_y: float) -> Vector2:
	var q := Vector2(p.x / squash, p.y * squash)
	q.y += bob + death_offset_y
	return q.rotated(death_angle)

## Filled-ellipse point sampler — Godot's _draw() has no ellipse primitive.
## Mirrors DrawUtils' own internal ellipse loop, kept as a private copy
## here (rather than calling its underscore-prefixed _draw_ellipse) since
## every use in this file needs the raw points back to run through
## _body_xf first, not an immediate draw.
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
