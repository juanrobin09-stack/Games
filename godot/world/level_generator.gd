class_name LevelGenerator
extends RefCounted
## Ports world/LevelGenerator.ts. All-static, like EnemyAI/StatusEffectRuntime/
## WeaponBehavior — pure generation logic, no per-instance state of its own.
##
## Determinism note (GODOT_MIGRATION.md §6): the source's Random is a custom
## mulberry32 PRNG seeded by hashing a string, specifically so a run seed
## fully reproduces its layout across sessions. The doc explicitly says not
## to chase that cross-engine — treat seeds as engine-local. Every seeded
## roll here uses Godot's own RandomNumberGenerator, seeded via _rng_from
## (hash of the same kind of "seed:purpose:key" label strings the source
## uses) — same *property* (a given seed always regenerates the same
## layout, in this engine), different algorithm underneath.

## A function rather than a top-level const for the same load-order reason
## as _obstacle_visuals_by_zone below — this is read at every call site
## well after every class_name script (RoomContainer included) is loaded.
static func _all_directions() -> Array[int]:
	return [RoomContainer.Direction.N, RoomContainer.Direction.S, RoomContainer.Direction.E, RoomContainer.Direction.W]

const OBSTACLE_SCENE := preload("res://world/obstacle_node.tscn")
const CHEST_SCENE := preload("res://world/chest_node.tscn")
const ENEMY_SCENE := preload("res://entities/enemy.tscn")

static func rng_from(label: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(label)
	return rng

static func _pick(rng: RandomNumberGenerator, arr: Array):
	return arr[rng.randi_range(0, arr.size() - 1)]

static func _shuffle(rng: RandomNumberGenerator, arr: Array) -> Array:
	var copy := arr.duplicate()
	for i in range(copy.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = copy[i]
		copy[i] = copy[j]
		copy[j] = tmp
	return copy

static func _weighted(rng: RandomNumberGenerator, arr: Array, weight_fn: Callable):
	var total := 0.0
	for item in arr:
		total += weight_fn.call(item)
	var roll: float = rng.randf() * total
	for item in arr:
		roll -= weight_fn.call(item)
		if roll <= 0.0:
			return item
	return arr[arr.size() - 1]

# ---------------------------------------------------------------- Zone layout

## Returns {"zone": ZoneDefinition, "rooms": Dictionary[String, RoomContainer],
## "start_key": String, "end_key": String}. `parent` is the Node every
## generated RoomContainer becomes a child of.
static func generate_zone_layout(zone: ZoneDefinition, rng: RandomNumberGenerator, parent: Node) -> Dictionary:
	var rooms: Dictionary = {}
	var start := RoomContainer.new()
	parent.add_child(start)
	start.init_grid(0, 0, RoomContainer.Type.START)
	start.visited = true
	start.cleared = true
	rooms[start.key] = start

	var frontier: Array = []
	for dir in _all_directions():
		frontier.append({"from": start, "dir": dir})
	var max_radius := 3

	while rooms.size() < zone.room_count and frontier.size() > 0:
		var idx := rng.randi_range(0, frontier.size() - 1)
		var edge = frontier[idx]
		frontier.remove_at(idx)
		var from: RoomContainer = edge["from"]
		var dir: int = edge["dir"]
		var delta: Vector2i = RoomContainer.DIRECTION_DELTA[dir]
		var nx: int = from.grid_x + delta.x
		var ny: int = from.grid_y + delta.y
		var key := "%d,%d" % [nx, ny]
		if rooms.has(key):
			continue
		if absi(nx) > max_radius or absi(ny) > max_radius:
			continue
		if rooms.size() > 2 and rng.randf() < 0.12:
			continue

		var room := RoomContainer.new()
		parent.add_child(room)
		room.init_grid(nx, ny, RoomContainer.Type.COMBAT)
		room.add_door(RoomContainer.OPPOSITE[dir])
		from.add_door(dir)
		rooms[key] = room

		for d2 in _all_directions():
			if d2 == RoomContainer.OPPOSITE[dir]:
				continue
			frontier.append({"from": room, "dir": d2})

	# BFS distances from start.
	var queue: Array[RoomContainer] = [start]
	start.distance_from_start = 0
	var seen: Dictionary = {start.key: true}
	var farthest := start
	while queue.size() > 0:
		var current: RoomContainer = queue.pop_front()
		for cdir in current.doors:
			var delta: Vector2i = RoomContainer.DIRECTION_DELTA[cdir]
			var key := "%d,%d" % [current.grid_x + delta.x, current.grid_y + delta.y]
			var neighbor: RoomContainer = rooms.get(key)
			if neighbor == null or seen.has(key):
				continue
			seen[key] = true
			neighbor.distance_from_start = current.distance_from_start + 1
			if neighbor.distance_from_start > farthest.distance_from_start:
				farthest = neighbor
			queue.append(neighbor)

	if rooms.size() < 2:
		# Degenerate layout (extremely unlucky rolls) — force one guaranteed
		# room so the zone is always completable.
		var fallback := RoomContainer.new()
		parent.add_child(fallback)
		fallback.init_grid(0, 1, RoomContainer.Type.COMBAT)
		fallback.add_door(RoomContainer.Direction.N)
		start.add_door(RoomContainer.Direction.S)
		fallback.distance_from_start = 1
		rooms[fallback.key] = fallback
		farthest = fallback

	# The layout is a spanning tree grown outward from the start, so the
	# farthest room is always a leaf with exactly one door — see
	# place_stairs_down for why that matters.
	var end_room: RoomContainer = farthest
	end_room.type = RoomContainer.Type.BOSS if zone.index == 2 else RoomContainer.Type.HEART

	var others: Array = []
	for r in rooms.values():
		if r != start and r != end_room:
			others.append(r)
	var shuffled: Array = _shuffle(rng, others)

	var take_from := func(pool: Array, predicate: Callable, count: int) -> Array:
		var taken: Array = []
		for i in range(pool.size()):
			if taken.size() >= count:
				break
			if predicate.call(pool[i]):
				taken.append(pool[i])
		for room in taken:
			pool.erase(room)
		return taken

	var always := func(_r): return true
	# `unconstrained` (not a predicate.call(always) equality check — Callable
	# comparison is a needless risk to lean on here) tells take_one whether
	# retrying with the always-true predicate would just be repeating itself.
	var take_one := func(predicate: Callable, type: RoomContainer.Type, unconstrained: bool = false) -> void:
		var taken: Array = take_from.call(shuffled, predicate, 1)
		if taken.is_empty() and not unconstrained:
			taken = take_from.call(shuffled, always, 1)
		if not taken.is_empty():
			(taken[0] as RoomContainer).type = type

	take_one.call(func(r): return r.distance_from_start >= 2, RoomContainer.Type.ELITE)
	take_one.call(always, RoomContainer.Type.SHOP, true)
	take_one.call(always, RoomContainer.Type.CHEST, true)
	# The Hollow Ruins' one guaranteed set-piece: the Drowned Sanctum.
	if zone.index == 1:
		take_one.call(func(r): return r.distance_from_start >= 2, RoomContainer.Type.SANCTUM)

	var min_combat: int = maxi(1, floori(shuffled.size() * 0.5))
	var bonus_budget: int = maxi(0, shuffled.size() - min_combat)
	var spend_bonus := func(type: RoomContainer.Type) -> void:
		if bonus_budget <= 0:
			return
		var taken: Array = take_from.call(shuffled, always, 1)
		if not taken.is_empty():
			(taken[0] as RoomContainer).type = type
			bonus_budget -= 1
	spend_bonus.call(RoomContainer.Type.EVENT)
	spend_bonus.call(RoomContainer.Type.REST)
	spend_bonus.call(RoomContainer.Type.EVENT)
	spend_bonus.call(RoomContainer.Type.CHEST)

	for room in rooms.values():
		(room as RoomContainer).refresh_walls()

	return {"zone": zone, "rooms": rooms, "start_key": start.key, "end_key": end_room.key}

# ---------------------------------------------------------------- Obstacle scatter

## A function rather than a top-level const specifically so these values
## are only ever read at call time, well after every class_name script
## (ObstacleNode included) is loaded — a top-level const array is evaluated
## eagerly at this script's own load time, which is a real risk for a value
## built from another script's enum members (see the combo_step incident in
## boss.gd this same session for what a wrong assumption about GDScript
## load-order costs).
static func _obstacle_visuals_by_zone(zone_index: int) -> Array:
	var by_zone: Array = [
		[ObstacleNode.Visual.TREE, ObstacleNode.Visual.ROCK, ObstacleNode.Visual.RUBBLE, ObstacleNode.Visual.BRAZIER],
		[ObstacleNode.Visual.PILLAR, ObstacleNode.Visual.STATUE, ObstacleNode.Visual.RUBBLE, ObstacleNode.Visual.CRYSTAL,
			ObstacleNode.Visual.FUNGUS, ObstacleNode.Visual.FUNGUS, ObstacleNode.Visual.SARCOPHAGUS],
		[ObstacleNode.Visual.PILLAR, ObstacleNode.Visual.BRAZIER, ObstacleNode.Visual.RUBBLE, ObstacleNode.Visual.STATUE],
	]
	return by_zone[zone_index] if zone_index < by_zone.size() else by_zone[0]

static func _obstacle_radius_for(visual: ObstacleNode.Visual, rng: RandomNumberGenerator) -> float:
	match visual:
		ObstacleNode.Visual.PILLAR, ObstacleNode.Visual.STATUE:
			return 22.0
		ObstacleNode.Visual.SARCOPHAGUS:
			return 26.0
		ObstacleNode.Visual.FUNGUS:
			return rng.randf_range(14.0, 20.0)
		_:
			return rng.randf_range(16.0, 28.0)

static func _clear_of_obstacles(room: RoomContainer, x: float, y: float, radius: float, padding: float) -> bool:
	for o in room.obstacles:
		if Vector2(x, y).distance_to(o.position) < radius + o.radius + padding:
			return false
	return true

const DOOR_LANE_DEPTH := 150.0

static func _distance_to_door_lane(dir: int, x: float, y: float) -> float:
	var w := RoomContainer.ROOM_WIDTH
	var h := RoomContainer.ROOM_HEIGHT
	var t := RoomContainer.WALL_THICKNESS
	match dir:
		RoomContainer.Direction.N:
			return absf(x - w / 2.0) if y <= t + DOOR_LANE_DEPTH else Vector2(x, y).distance_to(Vector2(w / 2.0, t + DOOR_LANE_DEPTH))
		RoomContainer.Direction.S:
			return absf(x - w / 2.0) if y >= h - t - DOOR_LANE_DEPTH else Vector2(x, y).distance_to(Vector2(w / 2.0, h - t - DOOR_LANE_DEPTH))
		RoomContainer.Direction.W:
			return absf(y - h / 2.0) if x <= t + DOOR_LANE_DEPTH else Vector2(x, y).distance_to(Vector2(t + DOOR_LANE_DEPTH, h / 2.0))
		RoomContainer.Direction.E:
			return absf(y - h / 2.0) if x >= w - t - DOOR_LANE_DEPTH else Vector2(x, y).distance_to(Vector2(w - t - DOOR_LANE_DEPTH, h / 2.0))
		_:
			return INF

static func _clear_of_door_lanes(room: RoomContainer, x: float, y: float, radius: float, padding: float) -> bool:
	for dir in room.doors:
		if _distance_to_door_lane(dir, x, y) < radius + padding:
			return false
	return true

static func scatter_obstacles(room: RoomContainer, rng: RandomNumberGenerator, zone_index: int, count: int, avoid_center_radius: float = 130.0, keep_clear: Array = []) -> void:
	var visuals: Array = _obstacle_visuals_by_zone(zone_index)
	var margin: float = RoomContainer.WALL_THICKNESS + 90.0
	var w := RoomContainer.ROOM_WIDTH
	var h := RoomContainer.ROOM_HEIGHT
	var center := Vector2(w / 2.0, h / 2.0)
	for i in range(count):
		var visual: ObstacleNode.Visual = _pick(rng, visuals)
		var radius: float = _obstacle_radius_for(visual, rng)
		var x := 0.0
		var y := 0.0
		var attempts := 0
		var ok := false
		while attempts < 18 and not ok:
			x = rng.randf_range(margin, w - margin)
			y = rng.randf_range(margin, h - margin)
			attempts += 1
			ok = Vector2(x, y).distance_to(center) >= avoid_center_radius \
				and _clear_of_obstacles(room, x, y, radius, 34.0) \
				and _clear_of_door_lanes(room, x, y, radius, 40.0)
			if ok:
				for k in keep_clear:
					if Vector2(x, y).distance_to(k["pos"]) < radius + k["radius"]:
						ok = false
						break
		# Rather than stack a rock onto a landmark or a doorway when the room
		# is crowded, simply place one fewer.
		if not ok:
			continue
		var obstacle: ObstacleNode = OBSTACLE_SCENE.instantiate()
		room.add_obstacle(obstacle)
		obstacle.setup(Vector2(x, y), radius, visual)

## A room's single "landmark" (chest, brazier, stall, shrine) offsets on
## both axes so it doesn't sit on the straight line between opposite doors.
static func _landmark_position(rng: RandomNumberGenerator) -> Vector2:
	var offset_x: float = _pick(rng, [-1.0, 1.0]) * rng.randf_range(90.0, 160.0)
	var offset_y: float = _pick(rng, [-1.0, 1.0]) * rng.randf_range(60.0, 110.0)
	return Vector2(RoomContainer.ROOM_WIDTH / 2.0 + offset_x, RoomContainer.ROOM_HEIGHT / 2.0 + offset_y)

static func _random_spawn_position(rng: RandomNumberGenerator, avoid_center_radius: float = 150.0, room: RoomContainer = null) -> Vector2:
	var margin: float = RoomContainer.WALL_THICKNESS + 70.0
	var w := RoomContainer.ROOM_WIDTH
	var h := RoomContainer.ROOM_HEIGHT
	var center := Vector2(w / 2.0, h / 2.0)
	var x := 0.0
	var y := 0.0
	var attempts := 0
	var ok := false
	while attempts < 18 and not ok:
		x = rng.randf_range(margin, w - margin)
		y = rng.randf_range(margin, h - margin)
		attempts += 1
		ok = Vector2(x, y).distance_to(center) >= avoid_center_radius and (room == null or _clear_of_obstacles(room, x, y, 22.0, 12.0))
	return Vector2(x, y)

# ---------------------------------------------------------------- Stairs

const STAIRS_RADIUS := 44.0

static func _stairs_down_anchor(entry_door: int) -> Dictionary:
	var w := RoomContainer.ROOM_WIDTH
	var h := RoomContainer.ROOM_HEIGHT
	match entry_door:
		RoomContainer.Direction.S:
			return {"pos": Vector2(w / 2.0, h / 2.0 - 165.0), "facing": -PI / 2.0}
		RoomContainer.Direction.N:
			return {"pos": Vector2(w / 2.0, h / 2.0 + 165.0), "facing": PI / 2.0}
		RoomContainer.Direction.W:
			return {"pos": Vector2(w / 2.0 + 270.0, h / 2.0), "facing": 0.0}
		RoomContainer.Direction.E:
			return {"pos": Vector2(w / 2.0 - 270.0, h / 2.0), "facing": PI}
		_:
			return {"pos": Vector2(w / 2.0, h / 2.0 - 165.0), "facing": -PI / 2.0}

static func place_stairs_down(room: RoomContainer) -> ObstacleNode:
	var entry: int = room.doors[0] if room.doors.size() > 0 else RoomContainer.Direction.S
	var anchor: Dictionary = _stairs_down_anchor(entry)
	var stairs: ObstacleNode = OBSTACLE_SCENE.instantiate()
	room.add_obstacle(stairs)
	stairs.setup(anchor["pos"], STAIRS_RADIUS, ObstacleNode.Visual.STAIRS_DOWN, {"facing": anchor["facing"], "blocks_projectiles": false})
	return stairs

## The arrival stairwell in a zone's first room: against a wall with no
## door (ascending toward it), or tucked into a quadrant if every wall has one.
static func place_stairs_up(room: RoomContainer) -> ObstacleNode:
	var free: int = -1
	for d in _all_directions():
		if not room.has_door(d):
			free = d
			break
	var w := RoomContainer.ROOM_WIDTH
	var h := RoomContainer.ROOM_HEIGHT
	var t := RoomContainer.WALL_THICKNESS
	var x: float
	var y: float
	var facing: float
	match free:
		RoomContainer.Direction.N:
			x = w / 2.0; y = t + 72.0; facing = -PI / 2.0
		RoomContainer.Direction.S:
			x = w / 2.0; y = h - t - 72.0; facing = PI / 2.0
		RoomContainer.Direction.W:
			x = t + 82.0; y = h / 2.0; facing = PI
		RoomContainer.Direction.E:
			x = w - t - 82.0; y = h / 2.0; facing = 0.0
		_:
			x = w * 0.27; y = h * 0.3; facing = -PI / 2.0
	var stairs: ObstacleNode = OBSTACLE_SCENE.instantiate()
	room.add_obstacle(stairs)
	stairs.setup(Vector2(x, y), STAIRS_RADIUS, ObstacleNode.Visual.STAIRS_UP, {"facing": facing, "blocks_projectiles": false})
	return stairs

## The spot at the foot of a stairwell — where the player stands to descend
## or arrives from above.
static func stairs_foot_position(stairs: ObstacleNode) -> Vector2:
	var dist: float = stairs.radius + 48.0
	return stairs.position - Vector2(cos(stairs.facing), sin(stairs.facing)) * dist

## A point a little way INTO the stairwell along its descent — the scripted
## walk target during the transition, still short of its far end.
static func stairs_mouth_position(stairs: ObstacleNode) -> Vector2:
	return stairs.position + Vector2(cos(stairs.facing), sin(stairs.facing)) * stairs.radius * 0.35

# ---------------------------------------------------------------- Encounters

## Each entry: {id, weight: Callable(distance)->float, core: Array[String], filler: Array[String]}.
const RUINS_ENCOUNTERS_DATA := [
	{"id": "shieldwall", "core": ["hollowWarden"], "filler": ["ashCrawler", "ashCrawler", "hollow"]},
	{"id": "bloatfield", "core": ["blightbloat", "blightbloat"], "filler": ["hollow", "gravebound", "ashCrawler"]},
	{"id": "vanguard", "core": ["hollowWarden", "blightbloat"], "filler": ["ashCrawler", "shadowStalker", "hollow"]},
	{"id": "ambush", "core": ["shadowStalker", "shadowStalker"], "filler": ["cinderWraith", "ashCrawler", "blightbloat"]},
	{"id": "phalanx", "core": ["hollowWarden", "hollowWarden"], "filler": ["blightbloat", "ashCrawler", "hollow"]},
]

const CITADEL_ENCOUNTERS_DATA := [
	{"id": "crossfire", "core": ["flameWisp", "flameWisp"], "filler": ["shadowStalker", "gravebound", "cinderWraith"]},
	{"id": "vanguard", "core": ["gravebound", "shadowStalker"], "filler": ["flameWisp", "shadowStalker", "gravebound"]},
	{"id": "ambush", "core": ["shadowStalker", "cinderWraith"], "filler": ["cinderWraith", "flameWisp", "shadowStalker"]},
	{"id": "siege", "core": ["gravebound", "gravebound"], "filler": ["shadowStalker", "flameWisp", "cinderWraith"]},
]

## Weight formulas keyed by "<pool>:<id>" — kept out of the const data arrays
## above since GDScript const literals can't hold Callables.
static func _encounter_weight(pool_id: String, template_id: String, distance: int) -> float:
	match "%s:%s" % [pool_id, template_id]:
		"ruins:shieldwall", "ruins:bloatfield":
			return 3.0 if distance <= 2 else 1.5
		"ruins:vanguard":
			return 3.0 if distance >= 2 else 0.8
		"ruins:ambush":
			return 2.0 if distance >= 2 else 0.5
		"ruins:phalanx":
			return 2.2 if distance >= 3 else 0.4
		"citadel:crossfire":
			return 3.0 if distance <= 2 else 1.5
		"citadel:vanguard":
			return 2.5 if distance <= 2 else 1.2
		"citadel:ambush":
			return 3.0 if distance >= 2 else 1.0
		"citadel:siege":
			return 2.0 if distance >= 2 else 0.5
		_:
			return 1.0

static func _compose_encounter(rng: RandomNumberGenerator, count: int, distance: int, pool: Array, pool_id: String, templates: Array) -> Array:
	var in_pool := func(id: String) -> bool: return pool.has(id)
	var usable: Array = []
	for tpl in templates:
		var all_in_pool := true
		for c in tpl["core"]:
			if not in_pool.call(c):
				all_in_pool = false
				break
		if all_in_pool:
			usable.append(tpl)
	if usable.is_empty():
		var ids: Array = []
		for i in range(count):
			ids.append(_pick(rng, pool))
		return ids

	var template: Dictionary = _weighted(rng, usable, func(t): return _encounter_weight(pool_id, t["id"], distance))
	var ids: Array = []
	var core: Array = template["core"]
	for i in range(mini(core.size(), maxi(1, count))):
		ids.append(core[i])
	var filler_pool: Array = []
	for f in template["filler"]:
		if in_pool.call(f):
			filler_pool.append(f)
	# Cycle the filler list round-robin (reshuffled once each lap) rather
	# than an independent re-roll per slot, so a template's flavor holds
	# even with only 2-3 filler options.
	var cycle: Array = []
	while ids.size() < count:
		if cycle.is_empty():
			cycle = _shuffle(rng, filler_pool if not filler_pool.is_empty() else pool)
		ids.append(cycle.pop_back())
	return ids

const MUTATED_VARIANT_CHANCE := 0.1
const MUTATED_HP_MULT := 1.35
const MUTATED_DAMAGE_MULT := 1.25
const MUTATED_RADIUS_MULT := 1.12

## Ember Citadel only: a rare, visibly tainted variant of a regular enemy.
## Elite-behavior and champion enemies are excluded — already special.
static func _maybe_apply_mutated_variant(enemy: EnemyCharacter, def: EnemyDefinition, rng: RandomNumberGenerator) -> void:
	if def.is_elite or def.champion:
		return
	if rng.randf() >= MUTATED_VARIANT_CHANCE:
		return
	enemy.is_mutated_variant = true
	enemy.max_hp = roundf(enemy.max_hp * MUTATED_HP_MULT)
	enemy.hp = enemy.max_hp
	enemy.difficulty_damage_mult *= MUTATED_DAMAGE_MULT
	enemy.radius *= MUTATED_RADIUS_MULT
	enemy.display_name = "%s, Ember-Marked" % def.name

# ---------------------------------------------------------------- Sanctum rite

const SANCTUM_WAVE_COUNT := 3
const SANCTUM_RING_RADIUS := 150.0
const SANCTUM_HP_MULT := 1.12
const SANCTUM_DAMAGE_MULT := 1.18

const SANCTUM_WAVES: Array = [
	["hollow", "hollow", "ashCrawler", "ashCrawler", "ashCrawler"],
	["blightbloat", "blightbloat", "hollowWarden", "ashCrawler"],
	["hollowWarden", "hollowWarden", "shadowStalker", "shadowStalker", "blightbloat"],
]

## The rite's spawn points: cardinal edges plus inner diagonals, all clear
## of the kneeling-warden statues at the corners (±200,±140) and door lanes.
static func _sanctum_spawn_slots() -> Array:
	var w := RoomContainer.ROOM_WIDTH / 2.0
	var h := RoomContainer.ROOM_HEIGHT / 2.0
	return [
		Vector2(w, h - 205.0), Vector2(w + 380.0, h), Vector2(w, h + 205.0), Vector2(w - 380.0, h),
		Vector2(w + 120.0, h - 190.0), Vector2(w - 120.0, h + 190.0),
		Vector2(w - 120.0, h - 190.0), Vector2(w + 120.0, h + 190.0),
	]

## Nudges a spawn point out of any obstacle it landed in, then back inside the floor.
static func _settle_spawn(room: RoomContainer, x: float, y: float, radius: float) -> Vector2:
	var margin: float = RoomContainer.WALL_THICKNESS + radius + 6.0
	for pass_i in range(3):
		for o in room.obstacles:
			var dx: float = x - o.position.x
			var dy: float = y - o.position.y
			var dist: float = maxf(Vector2(dx, dy).length(), 0.001)
			var need: float = radius + o.radius + 8.0
			if dist < need:
				x = o.position.x + (dx / dist) * need
				y = o.position.y + (dy / dist) * need
		x = clampf(x, margin, RoomContainer.ROOM_WIDTH - margin)
		y = clampf(y, margin, RoomContainer.ROOM_HEIGHT - margin)
	return Vector2(x, y)

## Spawns one wave of the rite around the circle's edge. Returns the new enemies.
static func spawn_sanctum_wave(room: RoomContainer, zone: ZoneDefinition, wave_index: int, opts: Dictionary) -> Array[EnemyCharacter]:
	var rng := rng_from("%s:%s:%s:wave%d" % [opts["run_seed"], zone.id, room.key, wave_index])
	var factors: Dictionary = CombatManager.difficulty_factors(zone.index, opts["corruption_ratio"])
	var ids: Array = SANCTUM_WAVES[mini(wave_index, SANCTUM_WAVES.size() - 1)]
	if wave_index == SANCTUM_WAVES.size() - 1 and opts["unlocked_enemy_ids"].has("awakenDeep"):
		var swapped: Array = []
		for id in ids:
			swapped.append("cinderWraith" if id == "blightbloat" else id)
		ids = swapped
	var slots := _sanctum_spawn_slots()
	var slot_offset := rng.randi_range(0, slots.size() - 1)
	var spawned: Array[EnemyCharacter] = []
	for i in range(ids.size()):
		var def: EnemyDefinition = DataRegistry.get_enemy(ids[i])
		if def == null:
			continue
		var slot: Vector2 = slots[(slot_offset + i * 3) % slots.size()]
		var pos: Vector2 = _settle_spawn(room, slot.x + rng.randf_range(-16.0, 16.0), slot.y + rng.randf_range(-12.0, 12.0), def.radius)
		var enemy: EnemyCharacter = ENEMY_SCENE.instantiate()
		room.add_enemy(enemy)
		enemy.setup(def, pos, factors["hp_mult"] * SANCTUM_HP_MULT, factors["damage_mult"] * SANCTUM_DAMAGE_MULT)
		enemy.state_timer = -0.14 * i
		spawned.append(enemy)
	return spawned

# ---------------------------------------------------------------- Rarity

## Weighted rarity roll biased by luck: luck exponentially skews a uniform
## roll toward 1 before walking the cumulative weight table.
static func roll_rarity(rng: RandomNumberGenerator, luck: float, min_tier: UpgradeDefinition.Rarity = UpgradeDefinition.Rarity.COMMON) -> UpgradeDefinition.Rarity:
	var weights: Array[float] = [40.0, 30.0, 18.0, 9.0, 3.0]
	var total := 0.0
	for w in weights:
		total += w
	var biased: float = pow(rng.randf(), 1.0 / (1.0 + maxf(0.0, luck) * 2.0))
	var cumulative := 0.0
	for i in range(weights.size()):
		cumulative += weights[i] / total
		if biased <= cumulative:
			return maxi(i, min_tier)
	return maxi(min_tier, weights.size() - 1)

# ---------------------------------------------------------------- Room content

## opts: {"unlocked_enemy_ids": Dictionary (set-like), "corruption_ratio": float,
## "rarity_luck": float, "run_seed": String}.
static func populate_room_content(room: RoomContainer, zone: ZoneDefinition, opts: Dictionary) -> void:
	if room.spawned_content:
		return
	room.spawned_content = true
	var rng := rng_from("%s:%s:%s" % [opts["run_seed"], zone.id, room.key])
	var unlocked: Dictionary = opts["unlocked_enemy_ids"]
	var pool: Array = []
	for id in zone.enemy_pool:
		var def: EnemyDefinition = DataRegistry.get_enemy(id)
		if def != null and (def.requires_unlock == "" or unlocked.has(def.requires_unlock)):
			pool.append(id)
	var safe_pool: Array = pool if not pool.is_empty() else zone.enemy_pool
	var factors: Dictionary = CombatManager.difficulty_factors(zone.index, opts["corruption_ratio"])

	match room.type:
		RoomContainer.Type.COMBAT:
			scatter_obstacles(room, rng, zone.index, rng.randi_range(2, 5))
			var count: int = CombatManager.get_combat_room_enemy_count(zone.index, opts["corruption_ratio"], rng.randf())
			var ids: Array
			if zone.index == 1:
				ids = _compose_encounter(rng, count, room.distance_from_start, safe_pool, "ruins", RUINS_ENCOUNTERS_DATA)
			elif zone.index == 2:
				ids = _compose_encounter(rng, count, room.distance_from_start, safe_pool, "citadel", CITADEL_ENCOUNTERS_DATA)
			else:
				ids = []
				for i in range(count):
					ids.append(_pick(rng, safe_pool))
			for id in ids:
				var def: EnemyDefinition = DataRegistry.get_enemy(id)
				if def == null:
					continue
				var pos: Vector2 = _random_spawn_position(rng, 150.0, room)
				var enemy: EnemyCharacter = ENEMY_SCENE.instantiate()
				room.add_enemy(enemy)
				enemy.setup(def, pos, factors["hp_mult"], factors["damage_mult"])
				if zone.index == 2:
					_maybe_apply_mutated_variant(enemy, def, rng)

		RoomContainer.Type.ELITE:
			scatter_obstacles(room, rng, zone.index, rng.randi_range(1, 3))
			var leader_id: String = _pick(rng, safe_pool)
			var leader_def: EnemyDefinition = DataRegistry.get_enemy(leader_id)
			var leader_pos: Vector2 = _random_spawn_position(rng, 0.0, room)
			var leader: EnemyCharacter = ENEMY_SCENE.instantiate()
			room.add_enemy(leader)
			leader.setup(leader_def, leader_pos, factors["hp_mult"] * 2.1, factors["damage_mult"] * 1.35)
			leader.is_elite_instance = true
			leader.display_name = "Empowered %s" % leader_def.name
			leader.radius *= 1.25
			for i in range(2):
				var id: String = _pick(rng, safe_pool)
				var def: EnemyDefinition = DataRegistry.get_enemy(id)
				var pos: Vector2 = _random_spawn_position(rng, 150.0, room)
				var escort: EnemyCharacter = ENEMY_SCENE.instantiate()
				room.add_enemy(escort)
				escort.setup(def, pos, factors["hp_mult"], factors["damage_mult"])
				if zone.index == 2:
					_maybe_apply_mutated_variant(escort, def, rng)

		RoomContainer.Type.HEART:
			# The sealed stairwell goes in first so nothing else lands on
			# it, then the guardian between it and the door.
			place_stairs_down(room)
			scatter_obstacles(room, rng, zone.index, rng.randi_range(2, 4))
			var guard_def: EnemyDefinition = DataRegistry.get_enemy(zone.heart_guardian)
			var pos := Vector2(RoomContainer.ROOM_WIDTH / 2.0, RoomContainer.ROOM_HEIGHT / 2.0 - 60.0)
			var champion: bool = guard_def != null and guard_def.champion
			var guardian: EnemyCharacter = ENEMY_SCENE.instantiate()
			room.add_enemy(guardian)
			var guard_hp_mult: float = (factors["hp_mult"] as float) if champion else (factors["hp_mult"] as float) * 3.2
			var guard_damage_mult: float = (factors["damage_mult"] as float) * 1.1 if champion else (factors["damage_mult"] as float) * 1.5
			guardian.setup(guard_def, pos, guard_hp_mult, guard_damage_mult)
			guardian.is_elite_instance = true
			guardian.display_name = guard_def.name if champion else "%s, Heart Warden" % guard_def.name
			if not champion:
				guardian.radius *= 1.4
			var escort_pool: Array = safe_pool
			if champion:
				escort_pool = []
				for id in safe_pool:
					if id != "hollowWarden" and id != "blightbloat":
						escort_pool.append(id)
			for i in range(2):
				var id: String = _pick(rng, escort_pool if not escort_pool.is_empty() else safe_pool)
				var def: EnemyDefinition = DataRegistry.get_enemy(id)
				var spawn_pos: Vector2 = _random_spawn_position(rng, 150.0, room)
				var escort: EnemyCharacter = ENEMY_SCENE.instantiate()
				room.add_enemy(escort)
				escort.setup(def, spawn_pos, factors["hp_mult"], factors["damage_mult"])

		RoomContainer.Type.CHEST:
			scatter_obstacles(room, rng, zone.index, rng.randi_range(1, 3))
			var tier: UpgradeDefinition.Rarity = roll_rarity(rng, opts["rarity_luck"])
			var pos: Vector2 = _landmark_position(rng)
			var chest: ChestNode = CHEST_SCENE.instantiate()
			room.set_chest_node(chest)
			chest.setup(pos, tier)

		RoomContainer.Type.REST:
			var pos: Vector2 = _landmark_position(rng)
			var brazier: ObstacleNode = OBSTACLE_SCENE.instantiate()
			room.add_obstacle(brazier)
			brazier.setup(pos, 20.0, ObstacleNode.Visual.BRAZIER)
			scatter_obstacles(room, rng, zone.index, rng.randi_range(1, 2))

		RoomContainer.Type.SHOP:
			var pos: Vector2 = _landmark_position(rng)
			var stall: ObstacleNode = OBSTACLE_SCENE.instantiate()
			room.add_obstacle(stall)
			stall.setup(pos, 26.0, ObstacleNode.Visual.MERCHANT_STALL)
			scatter_obstacles(room, rng, zone.index, rng.randi_range(1, 2))

		RoomContainer.Type.EVENT:
			var pos: Vector2 = _landmark_position(rng)
			var shrine: ObstacleNode = OBSTACLE_SCENE.instantiate()
			room.add_obstacle(shrine)
			shrine.setup(pos, 22.0, ObstacleNode.Visual.SHRINE)
			scatter_obstacles(room, rng, zone.index, rng.randi_range(1, 2))

		RoomContainer.Type.SANCTUM:
			# Four kneeling wardens at the corners of the rite, off both
			# door centerlines; the circle itself is drawn, not an
			# obstacle, so the arena stays open ground.
			var w := RoomContainer.ROOM_WIDTH / 2.0
			var h := RoomContainer.ROOM_HEIGHT / 2.0
			for corner in [Vector2(-200.0, -140.0), Vector2(200.0, -140.0), Vector2(-200.0, 140.0), Vector2(200.0, 140.0)]:
				var statue: ObstacleNode = OBSTACLE_SCENE.instantiate()
				room.add_obstacle(statue)
				statue.setup(Vector2(w, h) + corner, 22.0, ObstacleNode.Visual.STATUE)
			scatter_obstacles(room, rng, zone.index, rng.randi_range(1, 2), 300.0)

		RoomContainer.Type.START:
			if zone.index > 0:
				# Arriving from above: the stairwell you came down, and a
				# near-empty room around it.
				var stairs: ObstacleNode = place_stairs_up(room)
				var foot: Vector2 = stairs_foot_position(stairs)
				scatter_obstacles(room, rng, zone.index, rng.randi_range(0, 1), 200.0, [{"pos": foot, "radius": 70.0}])
			else:
				scatter_obstacles(room, rng, zone.index, rng.randi_range(0, 2))

		_: # BOSS and anything else
			scatter_obstacles(room, rng, zone.index, rng.randi_range(0, 2))
