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

	if alive:
		if from_player:
			_check_hit_enemies()
		else:
			_check_hit_player()

	if not alive:
		queue_free()
	else:
		queue_redraw()

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
	var color: Color = Color("#5aa9e6") if from_player else Color("#e2694f")
	draw_circle(Vector2.ZERO, radius, color)
