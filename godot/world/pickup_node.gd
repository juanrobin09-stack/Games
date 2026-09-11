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
		RunState.add_embers(gained)
	else:
		player.heal(value)
	var room := get_parent() as RoomContainer
	if room != null:
		room.pickups.erase(self)
	queue_free()

## Cubic bezier point sample — p0/p1 anchors, c1/c2 controls, t in [0, 1].
static func _cubic_bezier(p0: Vector2, c1: Vector2, c2: Vector2, p1: Vector2, t: float) -> Vector2:
	var mt: float = 1.0 - t
	return p0 * (mt * mt * mt) + c1 * (3.0 * mt * mt * t) + c2 * (3.0 * mt * t * t) + p1 * (t * t * t)

## drawPickup.ts's heart is two cubic beziers; Godot's _draw() has no
## bezier-fill primitive, so it's sampled into a polygon instead — the same
## technique DrawUtils.blob_points already uses for organic shapes.
static func _heart_points(radius: float, offset: Vector2) -> PackedVector2Array:
	var p0: Vector2 = offset + Vector2(0.0, radius * 0.8)
	var c1a: Vector2 = offset + Vector2(-radius, 0.0)
	var c1b: Vector2 = offset + Vector2(-radius * 0.5, -radius)
	var p1: Vector2 = offset + Vector2(0.0, -radius * 0.3)
	var c2a: Vector2 = offset + Vector2(radius * 0.5, -radius)
	var c2b: Vector2 = offset + Vector2(radius, 0.0)
	var p2: Vector2 = offset + Vector2(0.0, radius * 0.8)
	var segments := 12
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		pts.append(_cubic_bezier(p0, c1a, c1b, p1, float(i) / float(segments)))
	for i in range(1, segments + 1):
		pts.append(_cubic_bezier(p1, c2a, c2b, p2, float(i) / float(segments)))
	return pts

func _draw() -> void:
	# Ports drawPickup.ts.
	var bob: float = sin(bob_phase * 4.0) * 3.0
	var center := Vector2(0.0, bob)
	var color_hex: String = Palette.EMBER4 if kind == Kind.EMBER else Palette.TOXIC
	DrawUtils.draw_glow_circle(self, center.x, center.y, radius * 2.4, color_hex, 0.65)

	if kind == Kind.EMBER:
		var diamond := PackedVector2Array()
		diamond.append(center + Vector2(0.0, -radius))
		diamond.append(center + Vector2(radius * 0.7, 0.0))
		diamond.append(center + Vector2(0.0, radius))
		diamond.append(center + Vector2(-radius * 0.7, 0.0))
		draw_colored_polygon(diamond, Color(color_hex))
		var core := Color(Palette.EMBER6)
		core.a = 0.8
		draw_circle(center, radius * 0.35, core)
	else:
		draw_colored_polygon(_heart_points(radius, center), Color(color_hex))
