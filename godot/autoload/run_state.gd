extends Node
## Autoload: RunState
##
## Ports progression/RunState.ts — per-run state: seed, zone/room position,
## the Player Level/XP layer, and every zone's room graph (build-order
## step 6), kept resident for the whole run so retreating and re-descending
## never regenerates or resets anything. See GODOT_MIGRATION.md §3's
## `layouts` note and §5 step 6.

const LEVEL_CAP: int = 30
const XP_BASE_COST: float = 25.0
const XP_GROWTH: float = 1.35
const CORRUPTION_SOFT_CAP_MINUTES: float = 14.0

## Fired once per grant_xp() call that crosses at least one level, after all
## levels in that grant are resolved — mirrors RunState.ts's single
## synchronous loop, so one large XP grant (an AoE kill chain) can never
## desync or skip a level.
signal player_leveled_up(new_level: int, stat_points_awarded: int)
signal zone_changed(zone_index: int)

var seed_value: String = ""
var zone_index: int = 0
var current_room_key: String = ""

## Keyed by zone index (int) -> {"zone": ZoneDefinition, "rooms":
## Dictionary[String, RoomContainer], "start_key": String, "end_key":
## String} — LevelFlow.start_new_run() generates and stores all 3 zones'
## layouts up front (mirrors RunState.ts's own constructor), and every
## zone's full room graph stays here for the whole run — do NOT regenerate
## a zone on re-entry, or the bidirectional stairs' state-preservation
## guarantee breaks (see retreat_zone()'s own comment).
var layouts: Dictionary = {}

var embers: int = 0
var elapsed_time: float = 0.0

var player_level: int = 1
## Progress toward the NEXT level only — resets to 0 (carrying any
## remainder) each time player_level increases, not a cumulative total.
var xp: float = 0.0
var stat_points: int = 0
## stat id (String) -> level spent (int). Stat ids match the 6 spendable
## stats from the Web build: hp, stamina, abilityDamage, range, moveSpeed,
## attackSpeed.
var stat_levels: Dictionary = {}

func reset_for_new_run(new_seed: String) -> void:
	seed_value = new_seed
	zone_index = 0
	current_room_key = ""
	layouts.clear()
	embers = 0
	elapsed_time = 0.0
	player_level = 1
	xp = 0.0
	stat_points = 0
	stat_levels.clear()

## XP required to go from (player_level) to (player_level + 1). Level 2
## costs XP_BASE_COST; every level after costs XP_GROWTH more.
func xp_required_for_next_level() -> float:
	if player_level >= LEVEL_CAP:
		return INF
	var cost := XP_BASE_COST
	for l in range(2, player_level + 1):
		cost *= XP_GROWTH
	return cost

func grant_xp(amount: float) -> void:
	if player_level >= LEVEL_CAP or amount <= 0.0:
		return
	xp += amount
	var awarded := 0
	while player_level < LEVEL_CAP and xp >= xp_required_for_next_level():
		xp -= xp_required_for_next_level()
		player_level += 1
		stat_points += 1
		awarded += 1
	# No real HUD exists yet (step 9) — the only other place XP/level shows
	# is main.gd's small debug corner text, easy to miss in a wall of other
	# live values. This print is the one immediate, hard-to-miss confirmation
	# that a kill actually granted XP until that real UI exists.
	print("RunState: +%.0f XP (%.0f/%.0f toward level %d)" % [amount, xp, xp_required_for_next_level(), player_level + 1])
	if awarded > 0:
		print("RunState: LEVEL UP -> %d (+%d stat point%s)" % [player_level, awarded, "" if awarded == 1 else "s"])
		player_leveled_up.emit(player_level, awarded)

func corruption_ratio() -> float:
	return min(1.0, (elapsed_time / 60.0) / CORRUPTION_SOFT_CAP_MINUTES)

func neighbor_room(dir: int) -> RoomContainer:
	var room := current_room()
	if room == null:
		return null
	var delta: Vector2i = RoomContainer.DIRECTION_DELTA[dir]
	var key := "%d,%d" % [room.grid_x + delta.x, room.grid_y + delta.y]
	return (current_layout()["rooms"] as Dictionary).get(key)

## Mirrors RunState.ts's moveThroughDoor: steps current_room_key onto the
## neighbor in `dir` and marks it visited, or returns null (no room there —
## LevelFlow.check_door_crossing clamps the player back inside instead).
func move_through_door(dir: int) -> RoomContainer:
	var neighbor := neighbor_room(dir)
	if neighbor == null:
		return null
	current_room_key = neighbor.key
	neighbor.visited = true
	return neighbor

## Pure bookkeeping only — no isPlayerStatLocked check here, deliberately:
## RunState has no reference to the Player node the lock check needs
## (player.unlockedWeapons.has('bow')). LevelFlow.spend_stat_point (step 9)
## is the real entry point UI should call — it checks the lock, calls this
## for the bookkeeping, then applies the resulting StatModifier to the
## player. Calling this directly bypasses the lock, same as calling the TS
## source's own run.statLevels[id]++ directly would.
func spend_stat_point(stat_id: String) -> bool:
	if stat_points <= 0:
		return false
	stat_points -= 1
	stat_levels[stat_id] = stat_levels.get(stat_id, 0) + 1
	return true

## Ports RunState.ts's spendEmbers: fails (no mutation) if embers can't
## cover the cost. The shop's Buy/Heal/Reroll actions are the only callers
## so far, each already checking this return value before acting further.
func spend_embers(amount: int) -> bool:
	if embers < amount:
		return false
	embers -= amount
	return true

func current_layout() -> Dictionary:
	return layouts.get(zone_index, {})

func current_room() -> RoomContainer:
	var layout := current_layout()
	if layout.is_empty():
		return null
	return (layout["rooms"] as Dictionary).get(current_room_key)

func is_final_zone() -> bool:
	return zone_index >= layouts.size() - 1

## Mirrors RunState.ts's advanceZone(): steps into the next zone's own
## (already generated at run start) layout, landing in its start room.
func advance_zone() -> RoomContainer:
	zone_index = mini(zone_index + 1, layouts.size() - 1)
	var layout := current_layout()
	current_room_key = layout["start_key"]
	var start: RoomContainer = (layout["rooms"] as Dictionary)[current_room_key]
	start.visited = true
	zone_changed.emit(zone_index)
	return start

## Symmetric to advance_zone(): steps back into the previous zone's own
## (already fully-generated, never-discarded) layout, landing in its
## heart/boss room — where its own down-stairs are — rather than its start
## room, since the return trip retraces the same physical stairwell the
## player originally descended. Every room object (visited/cleared/chest/
## enemy state) is untouched by a zone switch either direction, so nothing
## needs to be saved or restored here beyond which room is current.
func retreat_zone() -> RoomContainer:
	zone_index = maxi(zone_index - 1, 0)
	var layout := current_layout()
	var rooms: Dictionary = layout["rooms"]
	var landing: RoomContainer = null
	for r in rooms.values():
		if r.type == RoomContainer.Type.HEART or r.type == RoomContainer.Type.BOSS:
			landing = r
			break
	if landing == null:
		landing = rooms[layout["start_key"]]
	current_room_key = landing.key
	landing.visited = true
	zone_changed.emit(zone_index)
	return landing
