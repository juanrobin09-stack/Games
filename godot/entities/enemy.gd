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
## (phase-2 champion) — the cloud itself is a deferred follow-up (see enemy_ai.gd).
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
		return

	if attack_cooldown_timer > 0.0: attack_cooldown_timer -= delta
	if contact_cooldown_timer > 0.0: contact_cooldown_timer -= delta
	if exposed_timer > 0.0: exposed_timer -= delta

	knockback_velocity *= maxf(0.0, 1.0 - 8.0 * delta)

	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	EnemyAI.update(self, player, delta)
	if phase_just_changed:
		phase_just_changed = false
		CombatManager.on_champion_shield_break(self)
	CombatManager.check_contact_damage(self, player)
	CombatManager.check_bash_hit(self, player)

	velocity = ai_velocity + knockback_velocity
	move_and_slide()
	StatusEffectRuntime.process(self, delta)
	if pending_burst:
		CombatManager.detonate_bloat(player, self)
	queue_redraw()

func _draw() -> void:
	if def == null:
		return
	var base_color := Color(def.color) if def.color != "" else Color.GRAY
	draw_circle(Vector2.ZERO, radius, base_color)
	if hit_flash_timer > 0.0:
		draw_circle(Vector2.ZERO, radius, Color(1.0, 1.0, 1.0, hit_flash_timer / 0.16 * 0.6))
	if def.behavior == EnemyDefinition.Behavior.WARDEN and shield_up():
		draw_arc(Vector2.ZERO, radius + 4.0, facing - (def.shield_arc if def.shield_arc > 0.0 else 1.1), facing + (def.shield_arc if def.shield_arc > 0.0 else 1.1), 16, Color("#b9b3c9"), 3.0)
	# Debug-only HP/state text — no art pass yet (step 7), but this is what
	# makes "is combat actually doing anything" visible without one.
	var font := ThemeDB.fallback_font
	if font != null:
		var label: String = "%s  %d/%d" % [State.keys()[state], int(ceil(maxf(hp, 0.0))), int(max_hp)]
		draw_string(font, Vector2(-radius - 10.0, -radius - 10.0), label, HORIZONTAL_ALIGNMENT_LEFT, 160.0, 13, Color.WHITE)
	if not alive:
		draw_circle(Vector2.ZERO, radius, Color(0.0, 0.0, 0.0, 0.5))
