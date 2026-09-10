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
## to recompute from. cloakPhase (a pure rendering-animation timer) is
## skipped until real rendering (step 7) needs it.

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
	# The hit check runs once, instantly, right as the swing starts — not
	# delayed to when the swing animation completes. Melee only for now;
	# a ranged weapon's own fire behavior is build-order step 5 (the
	# WeaponBehavior Strategy split), not something to half-wire here.
	if w.kind == WeaponDefinition.Kind.MELEE:
		CombatManager.perform_melee_attack(self)

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

func _physics_process(delta: float) -> void:
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

	if is_channeling_ability:
		ability_anim_timer += dt
		if ability_anim_timer > 0.35:
			is_channeling_ability = false

	if not is_attacking and not is_dodging and not is_channeling_ability:
		anim_state = AnimState.RUN if moving else AnimState.IDLE

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, body_color)
	if hit_flash_timer > 0.0:
		draw_circle(Vector2.ZERO, radius, Color(1.0, 1.0, 1.0, hit_flash_timer / 0.28 * 0.5))
	# Facing indicator — the only way to see aim direction without real art.
	draw_line(Vector2.ZERO, Vector2(cos(facing), sin(facing)) * radius * 1.4, Color.WHITE, 2.0)
