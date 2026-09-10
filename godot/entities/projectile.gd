class_name ProjectileEntity
extends Area2D
## Ports entities/Projectile.ts. An Area2D — a projectile only ever needs
## overlap detection, never collision response. Self-contained: each
## projectile checks distance against the "enemies"/"player" groups itself
## every physics tick (matching the Web build's own polling-style
## updateProjectiles loop) rather than routing through a central manager,
## since Godot doesn't need one array owner the way the Web build's
## CombatSystem.projectiles list does.
##
## Two Projectile fields the Web source carries but CombatSystem.
## damagePlayerToEnemy never actually reads — crit_damage_mult and
## lifesteal (it reads player.stats.critDamage/lifesteal directly instead,
## even for a projectile hit) — are kept here anyway for a faithful data
## port, not because anything consumes them yet.

var velocity := Vector2.ZERO
var speed: float = 0.0
var angle: float = 0.0
var radius: float = 6.0
var damage: float = 0.0
var from_player: bool = true
var pierce: int = 0
var knockback: float = 0.0
var crit_chance: float = 0.0
var crit_damage_mult: float = 1.0
var burn_chance: float = 0.0
var lifesteal: float = 0.0

## Only set when from_player — damagePlayerToEnemy needs the live player
## object (it reads player.stats.lifesteal/burnChance at hit time, not a
## baked copy), exactly as the Web build's own call site does.
var source_player: PlayerCharacter = null

var alive: bool = true
var age: float = 0.0
var max_lifetime: float = 2.4
var _hit_ids: Dictionary = {}

func _ready() -> void:
	# An enemy-fired bolt is parented under that enemy's RoomContainer
	# (z_index = -10, so its floor rect draws behind the player — see that
	# class's own comment); counter it back to 0 or the bolt is invisible.
	# A player-fired bolt is parented under Main (z_index 0) and is
	# unaffected either way.
	z_as_relative = false

func setup(spawn_pos: Vector2, p_angle: float, p_speed: float, p_damage: float, p_radius: float) -> void:
	global_position = spawn_pos
	angle = p_angle
	speed = p_speed
	velocity = Vector2(cos(angle), sin(angle)) * speed
	damage = p_damage
	radius = p_radius
	rotation = angle
	var shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if shape and shape.shape is CircleShape2D:
		(shape.shape as CircleShape2D).radius = radius

## Returns true the first time this target is hit; false on a repeat
## (pierce dedup) — also flips `alive` false once hit count exceeds pierce.
func register_hit(target_id: int) -> bool:
	if _hit_ids.has(target_id):
		return false
	_hit_ids[target_id] = true
	if _hit_ids.size() > pierce:
		alive = false
	return true

func _physics_process(delta: float) -> void:
	if not alive:
		queue_free()
		return
	age += delta
	global_position += velocity * delta
	if age >= max_lifetime:
		alive = false

	if alive and _blocked_by_room():
		alive = false

	if alive:
		if from_player:
			_check_hit_enemies()
		else:
			_check_hit_player()

	if not alive:
		queue_free()
	else:
		queue_redraw()

## Ports CombatSystem.ts's obstacle-blocking check inside updateProjectiles
## plus its separate resolveProjectileWalls — both fold into one check here
## since Area2D projectiles don't get wall collision from move_and_slide
## the way Player/EnemyCharacter do (build-order step 6 added real wall/
## obstacle StaticBody2D geometry; this is what stops a bolt at one instead
## of sailing through).
func _blocked_by_room() -> bool:
	var room := RunState.current_room()
	if room == null:
		return false
	for o in room.obstacles:
		if o.blocks_projectiles and global_position.distance_to(o.position) <= radius + o.radius:
			return true
	for wall in room.get_walls(room.is_locked()):
		var closest := Vector2(
			clampf(global_position.x, wall.position.x, wall.position.x + wall.size.x),
			clampf(global_position.y, wall.position.y, wall.position.y + wall.size.y)
		)
		if global_position.distance_to(closest) <= radius:
			return true
	return false

func _check_hit_enemies() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyCharacter
		if enemy == null or not enemy.alive or enemy.state == EnemyCharacter.State.VANISHED:
			continue
		if global_position.distance_to(enemy.global_position) > radius + enemy.radius:
			continue
		if not register_hit(enemy.get_instance_id()):
			continue
		var crit: bool = CombatManager.roll_crit(crit_chance)
		var dir: Vector2 = enemy.global_position - global_position
		dir = dir.normalized() if dir.length() > 0.01 else Vector2(cos(angle), sin(angle))
		CombatManager.damage_player_to_enemy(source_player, enemy, damage, crit, {
			"knockback_dir": dir,
			"knockback_force": knockback,
			# A bolt's "origin" for the warden-shield check is back along its
			# flight path, not the player's own position.
			"source_pos": global_position - Vector2(cos(angle), sin(angle)) * 60.0,
		})
		if not alive:
			return

func _check_hit_player() -> void:
	var player_node := get_tree().get_first_node_in_group("player") as PlayerCharacter
	if player_node == null:
		return
	if global_position.distance_to(player_node.global_position) > radius + player_node.radius:
		return
	alive = false
	CombatManager.damage_enemy_to_player(player_node, damage, {
		"knockback_dir": Vector2(cos(angle), sin(angle)),
		"knockback_force": 70.0,
	})

func _draw() -> void:
	# Ports drawProjectile.ts. `rotation` is already set to `angle` in
	# setup(), so this local frame is already the bolt's facing direction —
	# draw forward along +X directly, no rotation math needed here.
	#
	# ProjectileEntity has no `visual` field (Projectile.ts's solarBolt/
	# emberBolt/shadowBolt/voidOrb collapse to just from_player here).
	# CombatSystem.ts always uses 'solarBolt' for player bolts and
	# 'emberBolt' for enemy bolts, except the cinderWraith-specific
	# 'shadowBolt' — not reachable from from_player alone, so not
	# reproduced — so this uses those two default cases' colors.
	var core_hex: String = Palette.EMBER6 if from_player else Palette.EMBER5
	var glow_hex: String = Palette.EMBER5 if from_player else Palette.EMBER3

	DrawUtils.draw_glow_circle(self, 0.0, 0.0, radius * 2.6, glow_hex, 0.75)

	var trail := PackedVector2Array()
	trail.append(Vector2(-radius * 3.2, -radius * 0.5))
	trail.append(Vector2(-radius * 0.6, 0.0))
	trail.append(Vector2(-radius * 3.2, radius * 0.5))
	var trail_color := Color(glow_hex)
	trail_color.a = 0.55
	draw_colored_polygon(trail, trail_color)

	draw_circle(Vector2.ZERO, radius, Color(core_hex))
