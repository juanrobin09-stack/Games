class_name PickupNode
extends Node2D
## Ports entities/Pickup.ts. Self-contained like ProjectileEntity — looks up
## the player via the "player" group and grants its own reward on arrival
## rather than a central loop feeding it the player's position and splicing
## it out of an array. Ember pickups are spawned by CombatManager.on_enemy_death
## (mirrors Game.ts's 'enemyKilled' handler); nothing spawns a Heart pickup
## yet since the Web build doesn't appear to either outside of rare cases
## not read this session — the Kind.HEART path below is still fully ported
## and correct, just unexercised for now.

enum Kind { EMBER, HEART }

const SETTLE_FRICTION := 6.0
const MAGNET_MAX_SPEED := 760.0
const MAGNET_ACCEL := 1400.0
const COLLECT_DISTANCE := 14.0

var kind: Kind = Kind.EMBER
var value: float = 0.0
var radius: float = 8.0
var alive: bool = true
var age: float = 0.0
var bob_phase: float = 0.0
var velocity := Vector2.ZERO
var settle_timer: float = 0.25
var magnet_speed: float = 0.0

func _ready() -> void:
	# Counters RoomContainer's own z_index = -10 (see its own comment) so
	# the pickup doesn't inherit that and vanish behind the room's floor.
	z_as_relative = false

func setup(p_kind: Kind, pos: Vector2, p_value: float, pop_angle: float = randf() * TAU) -> void:
	kind = p_kind
	position = pos
	value = p_value
	bob_phase = randf() * 10.0
	velocity = Vector2(cos(pop_angle), sin(pop_angle)) * 90.0

func _process(dt: float) -> void:
	if not alive:
		return
	age += dt
	bob_phase += dt

	if settle_timer > 0.0:
		settle_timer -= dt
		position += velocity * dt
		velocity *= maxf(0.0, 1.0 - SETTLE_FRICTION * dt)
		queue_redraw()
		return

	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	if player == null:
		return
	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()
	if dist < player.stats.pickup_range:
		magnet_speed = minf(MAGNET_MAX_SPEED, magnet_speed + MAGNET_ACCEL * dt)
		var dir: Vector2 = to_player / maxf(0.001, dist)
		global_position += dir * magnet_speed * dt
		if dist < COLLECT_DISTANCE:
			_collect(player)
			return
	else:
		magnet_speed = 0.0
	queue_redraw()

func _collect(player: PlayerCharacter) -> void:
	alive = false
	if kind == Kind.EMBER:
		var gained: int = maxi(1, int(round(value * player.stats.ember_gain_mult)))
		RunState.embers += gained
	else:
		player.heal(value)
	var room := get_parent() as RoomContainer
	if room != null:
		room.pickups.erase(self)
	queue_free()

func _draw() -> void:
	var bob: float = sin(bob_phase * 3.0) * 2.0
	var color: Color = Color("#ffb84d") if kind == Kind.EMBER else Color("#e0546b")
	draw_circle(Vector2(0.0, bob), radius, color)
