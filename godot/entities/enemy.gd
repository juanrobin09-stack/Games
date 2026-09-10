class_name EnemyCharacter
extends CharacterBody2D
## Ports entities/Enemy.ts's data shell — HP/knockback/state fields and the
## constructor math. Real AI decision-making (updateEnemyAI's 6 behavior
## dispatch functions) is build-order step 4, not here: `state` sits at
## SPAWNING and nothing transitions it yet — velocity is knockback-only
## until then. One scene is reused for all 11 EnemyDefinitions via setup(),
## exactly like the Web build's single Enemy class driven by an assigned
## `def`. Burn/status-effect fields are intentionally left off this shell —
## they land with the real status-effect runtime in step 4 too (see
## GODOT_MIGRATION.md §7), rather than being half-wired here.

signal died(enemy: EnemyCharacter)

enum State { SPAWNING, IDLE, CHASE, WINDUP, ATTACK, COOLDOWN, VANISHED, REAPPEARING, STAGGER, DEAD }

var def: EnemyDefinition
var radius: float = 12.0
var facing: float = 0.0

var hp: float = 0.0
var max_hp: float = 0.0
var alive: bool = true
var death_timer: float = 0.0

var state: State = State.SPAWNING
var state_timer: float = 0.0
var attack_cooldown_timer: float = 0.0
var contact_cooldown_timer: float = 0.0
var hit_flash_timer: float = 0.0
var anim_phase: float = randf() * 10.0

var knockback_velocity := Vector2.ZERO

var difficulty_hp_mult: float = 1.0
var difficulty_damage_mult: float = 1.0
var is_elite_instance: bool = false
## Ember Citadel only: a rare, visibly tainted variant of a regular enemy.
var is_mutated_variant: bool = false
var display_name: String = ""

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

	knockback_velocity *= maxf(0.0, 1.0 - 8.0 * delta)
	velocity = knockback_velocity
	move_and_slide()
	queue_redraw()

func _draw() -> void:
	if def == null:
		return
	var base_color := Color(def.color) if def.color != "" else Color.GRAY
	draw_circle(Vector2.ZERO, radius, base_color)
	if hit_flash_timer > 0.0:
		draw_circle(Vector2.ZERO, radius, Color(1.0, 1.0, 1.0, hit_flash_timer / 0.16 * 0.6))
	if not alive:
		draw_circle(Vector2.ZERO, radius, Color(0.0, 0.0, 0.0, 0.5))
