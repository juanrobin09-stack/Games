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

## Set by LevelGenerator right after creation — which zone this room
## belongs to, so _draw() can use that zone's own palette (build-order
## step 7) instead of one fixed color for every room in every zone.
var zone: ZoneDefinition = null

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

## A real floor TEXTURE (a supplied stone-flagstone image) replaces the
## flat zone-tinted floor rect this drew at build-order step 7. Stretched
## to fill the room rect exactly rather than tiled — the source has its
## own baked-in directional lighting (a warm highlight sweeping across it),
## so repeating it across a room would show seams and repeated hot spots;
## a single non-uniform stretch to 1000x620 has neither, at the cost of a
## slight aspect distortion from the source's own square 1254x1254, which
## is what the image was supplied for (its own construction assumes
## whatever stretch a target rect needs). One shared texture for every
## zone/room, not a per-zone set — only one image was supplied — so
## zone.palette_floor no longer has a floor rect to tint, and neither does
## palette_wall below now that the walls are a real texture too — see
## _draw_walls()'s own comment for why that one couldn't just be stretched
## the same simple way.
const FLOOR_TEXTURE := preload("res://assets/textures/floor_stone.png")

func _draw() -> void:
	draw_texture_rect(FLOOR_TEXTURE, Rect2(0.0, 0.0, ROOM_WIDTH, ROOM_HEIGHT), false)
	_draw_walls()

## A real WALL texture (a supplied stone-frame image covering all four
## walls and their corners in one picture) replaces the flat zone-tinted
## wall rects get_walls() used to draw directly. It can't be stretched
## once over the whole room the way FLOOR_TEXTURE is: the source is a
## fully CLOSED frame with no door gaps, but a room's actual walls have
## real gaps wherever has_door() is true — the same gaps get_walls()
## itself leaves out of its returned rects so the player can walk through
## them. get_walls()'s Rect2-only return doesn't carry which side each
## rect came from, and can't grow that without disturbing its other two
## callers (_setup_physics_bodies's collision geometry and projectile.gd's
## own wall check), so the same has_door()/is_locked() branching get_walls()
## itself uses is reproduced here, once per side, each piece pulling a
## proportional CROP of that side's own border band from WALL_TEXTURE
## instead of the whole image — sized and positioned in source pixels to
## match where that piece falls along the room's own width/height, so a
## door-split side crops the same real gap out of the source that
## get_walls() leaves out of the destination, and a LOCKED room's barrier
## piece (get_walls(true)'s third rect, sealing the gap during a boss
## fight) draws the middle crop that would otherwise be skipped, so a
## sealed door reads as sealed rather than showing an opening collision
## still blocks. Border thickness in the source (measured via a
## brightness scan out from each edge — this is a plain RGB image, no
## alpha, so "content" means "not near-black") is a consistent ~72px in
## from a ~26px empty margin on all four sides — comfortably inside the
## wall band, away from the frame's black interior, at any point along a
## side's MIDDLE stretch. The frame's outer silhouette is rounded at each
## corner, though, not square: right at a corner (the lengthwise coordinate
## near 0 or near that side's full length, not the thickness one above),
## the actual art pulls back well past that 26px margin — a first-lit-pixel
## scan out from a corner found nothing at all for roughly 80px, versus
## ~26px mid-span — so a piece that runs a side's full lengthwise range
## through a naive proportional map samples straight into that black
## pull-back exactly at its own corner ends (caught by a real screenshot's
## corner test, not by eye). WALL_TEXTURE_CORNER_MARGIN insets the
## lengthwise sampling window symmetrically on both ends before mapping
## the destination onto it, comfortably past the ~80px measured — every
## piece's own corner-adjacent end (whether that end is a true room
## corner or a door edge one span-length in) samples from just inside the
## corner posts' own solid art instead of their black surroundings, at
## the cost of never quite reaching the outermost sliver of that corner
## post's own pixels.
const WALL_TEXTURE := preload("res://assets/textures/wall_frame.png")
const WALL_TEXTURE_BORDER := 26.0
const WALL_TEXTURE_THICKNESS := 72.0
const WALL_TEXTURE_CORNER_MARGIN := 100.0

func _draw_walls() -> void:
	var tex_w := float(WALL_TEXTURE.get_width())
	var tex_h := float(WALL_TEXTURE.get_height())
	var t := WALL_THICKNESS
	var half := DOOR_WIDTH / 2.0
	var b := WALL_TEXTURE_BORDER
	var bt := WALL_TEXTURE_THICKNESS
	var cm := WALL_TEXTURE_CORNER_MARGIN
	var sx := (tex_w - 2.0 * cm) / ROOM_WIDTH
	var sy := (tex_h - 2.0 * cm) / ROOM_HEIGHT
	var locked := is_locked()

	if has_door(Direction.N):
		var span := ROOM_WIDTH / 2.0 - half
		draw_texture_rect_region(WALL_TEXTURE, Rect2(0.0, 0.0, span, t), Rect2(cm, b, span * sx, bt))
		draw_texture_rect_region(WALL_TEXTURE, Rect2(ROOM_WIDTH / 2.0 + half, 0.0, span, t), Rect2(cm + (ROOM_WIDTH / 2.0 + half) * sx, b, span * sx, bt))
		if locked:
			draw_texture_rect_region(WALL_TEXTURE, Rect2(ROOM_WIDTH / 2.0 - half, 0.0, DOOR_WIDTH, t), Rect2(cm + span * sx, b, DOOR_WIDTH * sx, bt))
	else:
		draw_texture_rect_region(WALL_TEXTURE, Rect2(0.0, 0.0, ROOM_WIDTH, t), Rect2(cm, b, ROOM_WIDTH * sx, bt))

	if has_door(Direction.S):
		var span := ROOM_WIDTH / 2.0 - half
		draw_texture_rect_region(WALL_TEXTURE, Rect2(0.0, ROOM_HEIGHT - t, span, t), Rect2(cm, tex_h - b - bt, span * sx, bt))
		draw_texture_rect_region(WALL_TEXTURE, Rect2(ROOM_WIDTH / 2.0 + half, ROOM_HEIGHT - t, span, t), Rect2(cm + (ROOM_WIDTH / 2.0 + half) * sx, tex_h - b - bt, span * sx, bt))
		if locked:
			draw_texture_rect_region(WALL_TEXTURE, Rect2(ROOM_WIDTH / 2.0 - half, ROOM_HEIGHT - t, DOOR_WIDTH, t), Rect2(cm + span * sx, tex_h - b - bt, DOOR_WIDTH * sx, bt))
	else:
		draw_texture_rect_region(WALL_TEXTURE, Rect2(0.0, ROOM_HEIGHT - t, ROOM_WIDTH, t), Rect2(cm, tex_h - b - bt, ROOM_WIDTH * sx, bt))

	if has_door(Direction.W):
		var span := ROOM_HEIGHT / 2.0 - half
		draw_texture_rect_region(WALL_TEXTURE, Rect2(0.0, 0.0, t, span), Rect2(b, cm, bt, span * sy))
		draw_texture_rect_region(WALL_TEXTURE, Rect2(0.0, ROOM_HEIGHT / 2.0 + half, t, span), Rect2(b, cm + (ROOM_HEIGHT / 2.0 + half) * sy, bt, span * sy))
		if locked:
			draw_texture_rect_region(WALL_TEXTURE, Rect2(0.0, ROOM_HEIGHT / 2.0 - half, t, DOOR_WIDTH), Rect2(b, cm + span * sy, bt, DOOR_WIDTH * sy))
	else:
		draw_texture_rect_region(WALL_TEXTURE, Rect2(0.0, 0.0, t, ROOM_HEIGHT), Rect2(b, cm, bt, ROOM_HEIGHT * sy))

	if has_door(Direction.E):
		var span := ROOM_HEIGHT / 2.0 - half
		draw_texture_rect_region(WALL_TEXTURE, Rect2(ROOM_WIDTH - t, 0.0, t, span), Rect2(tex_w - b - bt, cm, bt, span * sy))
		draw_texture_rect_region(WALL_TEXTURE, Rect2(ROOM_WIDTH - t, ROOM_HEIGHT / 2.0 + half, t, span), Rect2(tex_w - b - bt, cm + (ROOM_HEIGHT / 2.0 + half) * sy, bt, span * sy))
		if locked:
			draw_texture_rect_region(WALL_TEXTURE, Rect2(ROOM_WIDTH - t, ROOM_HEIGHT / 2.0 - half, t, DOOR_WIDTH), Rect2(tex_w - b - bt, cm + span * sy, bt, DOOR_WIDTH * sy))
	else:
		draw_texture_rect_region(WALL_TEXTURE, Rect2(ROOM_WIDTH - t, 0.0, t, ROOM_HEIGHT), Rect2(tex_w - b - bt, cm, bt, ROOM_HEIGHT * sy))
