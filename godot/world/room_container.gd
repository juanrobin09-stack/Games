class_name RoomContainer
extends Node2D
## Ports world/Room.ts. Unlike the Web build (every room sharing one JS
## object graph, swapped by reference), every generated room in Godot is a
## real, permanent Node2D — created once when its zone's layout generates,
## never freed or regenerated, sitting at local origin (0,0) in the same
## shared 0..1000,0..620 rectangle Room.ts itself uses. Only the room the
## player currently occupies is ever active; see set_active().
##
## Why nodes stay alive instead of being cleared/rebuilt (GODOT_MIGRATION.md
## §6 generically recommends queue_free()-based clearing over "just hidden"):
## RunState.ts's own retreatZone() comment is explicit that "every room
## object (visited/cleared/chest/enemy state) is untouched by a zone switch
## either direction, so nothing needs to be saved or restored" — leaving a
## combat room mid-fight and returning later finds the same survivors where
## you left them, because populateRoomContent's spawnedContent guard means
## content is only ever generated once and then simply not re-ticked while
## you're elsewhere. Keeping the actual Nodes alive (hidden + process-
## disabled) is the direct Godot equivalent of that guarantee; discarding
## and regenerating them would lose it.
##
## set_active(false) is not enough on its own to stop a hidden room's walls
## and enemies from physically blocking the ACTIVE room sitting at the same
## coordinates — Godot keeps a CollisionObject2D's shapes live in the
## physics world regardless of process_mode. Every wall/obstacle/enemy this
## room owns is tracked in _physics_bodies specifically so set_active() can
## also zero out collision_layer/collision_mask on all of them.

enum Direction { N, S, E, W }
enum Type { START, COMBAT, ELITE, HEART, BOSS, CHEST, SHOP, EVENT, REST, SANCTUM }

const ROOM_WIDTH := 1000.0
const ROOM_HEIGHT := 620.0
const WALL_THICKNESS := 46.0
const DOOR_WIDTH := 120.0

const OPPOSITE := {
	Direction.N: Direction.S, Direction.S: Direction.N,
	Direction.E: Direction.W, Direction.W: Direction.E,
}
const DIRECTION_DELTA := {
	Direction.N: Vector2i(0, -1), Direction.S: Vector2i(0, 1),
	Direction.E: Vector2i(1, 0), Direction.W: Vector2i(-1, 0),
}

var grid_x: int = 0
var grid_y: int = 0
var key: String = ""
var type: Type = Type.COMBAT
var doors: Array[int] = []
var visited: bool = false
var cleared: bool = false
var reward_granted: bool = false
var distance_from_start: int = 0
var spawned_content: bool = false
var rest_used: bool = false

## Sanctum rite only (see LevelFlow.begin_rite/update_rite).
var ritual_active: bool = false
var ritual_wave: int = 0
var ritual_wave_timer: float = 0.0

## Event room only — which WorldEventDefinition rolled for this room, and
## whether it's already been resolved. Event *interaction* itself (the
## actual choice UI) is step 9; the room still needs to remember which
## event id it rolled so a later step doesn't need to re-roll it.
var event_id: String = ""
var event_resolved: bool = false

## Live children — populated once by LevelGenerator.populate_room_content(),
## then left exactly as combat/pickups/interaction leave them.
var enemies: Array[EnemyCharacter] = []
var obstacles: Array[ObstacleNode] = []
var pickups: Array[Node2D] = []
var chest: ChestNode = null

var _is_active: bool = false
var _physics_bodies: Array[CollisionObject2D] = []
var _wall_bodies: Array[StaticBody2D] = []

## Walls aren't built here — doors keep growing on a room throughout zone
## generation (see LevelGenerator), so wall geometry is only meaningful
## once every room's doors are final. LevelGenerator calls refresh_walls()
## once per room right after generation finishes.
func init_grid(gx: int, gy: int, p_type: Type) -> void:
	grid_x = gx
	grid_y = gy
	type = p_type
	key = "%d,%d" % [gx, gy]
	# Every RoomContainer is a sibling of Player/DebugLabel/LiveLabel under
	# Main, added AFTER them (LevelFlow.start_new_run runs post-spawn) — 2D
	# canvas siblings draw in add-order, so without this, _draw()'s own
	# opaque floor rect (below) would paint over the player and every debug
	# label the instant a room activates. Obstacle/Chest/Pickup counter
	# this back to z_index 0 in their own _ready() so they don't inherit
	# it and vanish behind the floor themselves.
	z_index = -10
	set_active(false)

## Warden shield-bearer, elite, heart guardian and boss rooms lock their
## doors until cleared; the sanctum locks only while its rite is running.
func is_locked() -> bool:
	if cleared:
		return false
	if type == Type.SANCTUM:
		return ritual_active
	return type == Type.COMBAT or type == Type.ELITE or type == Type.HEART or type == Type.BOSS

func requires_clearing() -> bool:
	if type == Type.SANCTUM:
		return ritual_active
	return type == Type.COMBAT or type == Type.ELITE or type == Type.HEART or type == Type.BOSS

func check_cleared() -> bool:
	if cleared:
		return true
	if not requires_clearing():
		_mark_cleared()
		return true
	if spawned_content and enemies.size() > 0:
		var any_alive := false
		for e in enemies:
			if e.alive:
				any_alive = true
				break
		if not any_alive:
			_mark_cleared()
			return true
	return false

## refresh_walls() right here (not left to whoever called check_cleared())
## is what actually unseals the door the instant a room clears — is_locked()
## reads `cleared`, and get_walls() only fills the door gap back in while
## is_locked() is true, so the wall geometry has to be rebuilt the moment
## that flips or the (now unlocked) room stays physically sealed regardless.
func _mark_cleared() -> void:
	cleared = true
	refresh_walls()

func has_door(dir: int) -> bool:
	return doors.has(dir)

func add_door(dir: int) -> void:
	if not doors.has(dir):
		doors.append(dir)

func door_center(dir: int) -> Vector2:
	match dir:
		Direction.N: return Vector2(ROOM_WIDTH / 2.0, WALL_THICKNESS / 2.0)
		Direction.S: return Vector2(ROOM_WIDTH / 2.0, ROOM_HEIGHT - WALL_THICKNESS / 2.0)
		Direction.W: return Vector2(WALL_THICKNESS / 2.0, ROOM_HEIGHT / 2.0)
		Direction.E: return Vector2(ROOM_WIDTH - WALL_THICKNESS / 2.0, ROOM_HEIGHT / 2.0)
		_: return Vector2(ROOM_WIDTH / 2.0, ROOM_HEIGHT / 2.0)

func spawn_point_from(dir: int) -> Vector2:
	var inset := WALL_THICKNESS + 60.0
	match dir:
		Direction.N: return Vector2(ROOM_WIDTH / 2.0, inset)
		Direction.S: return Vector2(ROOM_WIDTH / 2.0, ROOM_HEIGHT - inset)
		Direction.W: return Vector2(inset, ROOM_HEIGHT / 2.0)
		Direction.E: return Vector2(ROOM_WIDTH - inset, ROOM_HEIGHT / 2.0)
		_: return Vector2(ROOM_WIDTH / 2.0, ROOM_HEIGHT / 2.0)

## Wall segments as Rect2 (local space). include_door_barriers=true fills the
## door gaps back in with a wall — what a locked room actually uses to keep
## the player from ever reaching a door-crossing check in the first place.
func get_walls(include_door_barriers: bool) -> Array[Rect2]:
	var walls: Array[Rect2] = []
	var t := WALL_THICKNESS
	var half := DOOR_WIDTH / 2.0
	var has_n := has_door(Direction.N)
	var has_s := has_door(Direction.S)
	var has_w := has_door(Direction.W)
	var has_e := has_door(Direction.E)

	if has_n:
		walls.append(Rect2(0.0, 0.0, ROOM_WIDTH / 2.0 - half, t))
		walls.append(Rect2(ROOM_WIDTH / 2.0 + half, 0.0, ROOM_WIDTH / 2.0 - half, t))
		if include_door_barriers:
			walls.append(Rect2(ROOM_WIDTH / 2.0 - half, 0.0, DOOR_WIDTH, t))
	else:
		walls.append(Rect2(0.0, 0.0, ROOM_WIDTH, t))

	if has_s:
		walls.append(Rect2(0.0, ROOM_HEIGHT - t, ROOM_WIDTH / 2.0 - half, t))
		walls.append(Rect2(ROOM_WIDTH / 2.0 + half, ROOM_HEIGHT - t, ROOM_WIDTH / 2.0 - half, t))
		if include_door_barriers:
			walls.append(Rect2(ROOM_WIDTH / 2.0 - half, ROOM_HEIGHT - t, DOOR_WIDTH, t))
	else:
		walls.append(Rect2(0.0, ROOM_HEIGHT - t, ROOM_WIDTH, t))

	if has_w:
		walls.append(Rect2(0.0, 0.0, t, ROOM_HEIGHT / 2.0 - half))
		walls.append(Rect2(0.0, ROOM_HEIGHT / 2.0 + half, t, ROOM_HEIGHT / 2.0 - half))
		if include_door_barriers:
			walls.append(Rect2(0.0, ROOM_HEIGHT / 2.0 - half, t, DOOR_WIDTH))
	else:
		walls.append(Rect2(0.0, 0.0, t, ROOM_HEIGHT))

	if has_e:
		walls.append(Rect2(ROOM_WIDTH - t, 0.0, t, ROOM_HEIGHT / 2.0 - half))
		walls.append(Rect2(ROOM_WIDTH - t, ROOM_HEIGHT / 2.0 + half, t, ROOM_HEIGHT / 2.0 - half))
		if include_door_barriers:
			walls.append(Rect2(ROOM_WIDTH - t, ROOM_HEIGHT / 2.0 - half, t, DOOR_WIDTH))
	else:
		walls.append(Rect2(ROOM_WIDTH - t, 0.0, t, ROOM_HEIGHT))

	return walls

func _rebuild_walls() -> void:
	for body in _wall_bodies:
		if is_instance_valid(body):
			_physics_bodies.erase(body)
			body.queue_free()
	_wall_bodies.clear()
	for rect in get_walls(is_locked()):
		var body := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = rect.size
		shape.shape = rect_shape
		shape.position = rect.position + rect.size / 2.0
		body.add_child(shape)
		add_child(body)
		_wall_bodies.append(body)
		_physics_bodies.append(body)
		_set_body_collision_enabled(body, _is_active)
	queue_redraw()

## Call once a room's `cleared` (or ritual_active) flips while it's the
## active room, so its door-barrier walls actually open/seal to match.
func refresh_walls() -> void:
	_rebuild_walls()

func add_enemy(enemy: EnemyCharacter) -> void:
	add_child(enemy)
	enemies.append(enemy)
	_physics_bodies.append(enemy)
	_set_body_collision_enabled(enemy, _is_active)
	if _is_active:
		enemy.add_to_group("enemies")
	else:
		enemy.remove_from_group("enemies")

## obstacles holds landmarks (stairs, merchant stall, shrine, brazier) as
## well as plain scatter — anything Obstacle.ts would push onto room.obstacles.
func add_obstacle(obstacle: ObstacleNode) -> void:
	add_child(obstacle)
	obstacles.append(obstacle)
	_physics_bodies.append(obstacle)
	_set_body_collision_enabled(obstacle, _is_active)

func add_pickup(pickup: Node2D) -> void:
	add_child(pickup)
	pickups.append(pickup)

func set_chest_node(c: ChestNode) -> void:
	add_child(c)
	chest = c

func _set_body_collision_enabled(body: CollisionObject2D, enabled: bool) -> void:
	body.collision_layer = 1 if enabled else 0
	body.collision_mask = 1 if enabled else 0

## The only room ever visible/simulating is the one the player is in.
## Toggles rendering, ALL processing of this room's whole subtree (Godot
## propagates process_mode to descendants, so one line stops every enemy's
## own _physics_process too), physics collision on every tracked body (see
## this file's header for why process_mode alone isn't enough), and the
## "enemies" group membership that combat/projectile code queries — without
## that last part, a hidden room's enemies would still be valid melee/
## projectile targets purely by sharing the same 0..1000,0..620 coordinates.
func set_active(active: bool) -> void:
	_is_active = active
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	for body in _physics_bodies:
		if is_instance_valid(body):
			_set_body_collision_enabled(body, active)
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if active:
			enemy.add_to_group("enemies")
		else:
			enemy.remove_from_group("enemies")

func _draw() -> void:
	# Placeholder-only floor + wall outline (no art pass yet — step 7) so a
	# room is actually navigable-by-eye: a faint floor rect, and each wall
	# segment get_walls() would collide against drawn as a solid bar.
	draw_rect(Rect2(0.0, 0.0, ROOM_WIDTH, ROOM_HEIGHT), Color(0.16, 0.14, 0.13), true)
	for rect in get_walls(is_locked()):
		draw_rect(rect, Color(0.32, 0.29, 0.27), true)
