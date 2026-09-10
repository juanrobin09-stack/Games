class_name ObstacleNode
extends StaticBody2D
## Ports entities/Obstacle.ts. Unlike the Web version (a plain data class —
## Game.ts resolves collision against room.obstacles manually every frame),
## this is a real StaticBody2D: move_and_slide() already resolves Player/
## EnemyCharacter movement against any collider on the shared default
## layer/mask (confirmed live in steps 3-5, before any obstacle existed),
## so letting the engine block movement here needs no manual push-out math
## at all. blocksProjectiles stays a plain per-instance flag exactly like
## the source — ProjectileEntity checks it directly (see projectile.gd)
## rather than through physics, since a piercing bolt still needs custom
## per-hit bookkeeping physics collision doesn't give for free.

enum Visual {
	TREE, ROCK, PILLAR, RUBBLE, BRAZIER, CRYSTAL, STATUE, MERCHANT_STALL,
	SHRINE, FUNGUS, SARCOPHAGUS, STAIRS_DOWN, STAIRS_UP,
}

var radius: float = 16.0
var visual: Visual = Visual.ROCK
var seed_value: float = 0.0
var blocks_projectiles: bool = false
var lit: bool = false
## World-space orientation (radians). Stairs: the direction they descend/ascend in.
var facing: float = 0.0
## Stateful landmarks (the sealed stairwell) flip this once their condition
## is met — LevelFlow.open_stairs() sets it true when a heart/boss room clears.
var activated: bool = false
var activated_at: float = -1.0

func setup(pos: Vector2, p_radius: float, p_visual: Visual, opts: Dictionary = {}) -> void:
	position = pos
	radius = p_radius
	visual = p_visual
	facing = opts.get("facing", 0.0)
	seed_value = randf() * 1000.0
	var default_blocks: bool = (
		visual == Visual.PILLAR or visual == Visual.STATUE
		or visual == Visual.ROCK or visual == Visual.SARCOPHAGUS
	)
	blocks_projectiles = opts.get("blocks_projectiles", default_blocks)
	var default_lit: bool = (
		visual == Visual.BRAZIER or visual == Visual.CRYSTAL or visual == Visual.MERCHANT_STALL
		or visual == Visual.SHRINE or visual == Visual.FUNGUS
		or visual == Visual.STAIRS_DOWN or visual == Visual.STAIRS_UP
	)
	lit = opts.get("lit", default_lit)
	_apply_shape()

func _ready() -> void:
	_apply_shape()

func _apply_shape() -> void:
	var shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if shape and shape.shape is CircleShape2D:
		(shape.shape as CircleShape2D).radius = radius

func activate() -> void:
	if activated:
		return
	activated = true
	activated_at = Time.get_ticks_msec() / 1000.0
	queue_redraw()

func _color() -> Color:
	match visual:
		Visual.TREE: return Color("#2f4a35")
		Visual.ROCK: return Color("#5a5551")
		Visual.PILLAR: return Color("#7a736a")
		Visual.RUBBLE: return Color("#4a443e")
		Visual.BRAZIER: return Color("#ff8a3d")
		Visual.CRYSTAL: return Color("#7ed9c9")
		Visual.STATUE: return Color("#8a8478")
		Visual.MERCHANT_STALL: return Color("#c9a45c")
		Visual.SHRINE: return Color("#b98fd9")
		Visual.FUNGUS: return Color("#6fbf5a")
		Visual.SARCOPHAGUS: return Color("#9c9284")
		Visual.STAIRS_DOWN: return Color("#c9a45c") if activated else Color("#4a443e")
		Visual.STAIRS_UP: return Color("#c9a45c")
		_: return Color.GRAY

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, _color())
	if lit:
		draw_circle(Vector2.ZERO, radius * 0.5, Color(1.0, 0.9, 0.7, 0.6))
	if visual == Visual.STAIRS_DOWN or visual == Visual.STAIRS_UP:
		draw_line(Vector2.ZERO, Vector2(cos(facing), sin(facing)) * radius * 1.3, Color.WHITE, 3.0)
