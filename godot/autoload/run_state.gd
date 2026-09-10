extends Node
## Autoload: RunState
##
## Ports progression/RunState.ts — per-run state: seed, zone/room position,
## the Player Level/XP layer, and (once build-order step 6 lands the level
## generator) every zone's room graph, kept resident for the whole run so
## retreating and re-descending never regenerates or resets anything. See
## GODOT_MIGRATION.md §3's `layouts` note and §5 step 6.

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

## Populated by the level generator (build-order step 6). Keyed by zone
## index; every zone's full room graph is generated once at run start and
## stays here for the whole run — do NOT regenerate a zone on re-entry, or
## the bidirectional stairs' state-preservation guarantee breaks.
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
	if awarded > 0:
		player_leveled_up.emit(player_level, awarded)

func corruption_ratio() -> float:
	return min(1.0, (elapsed_time / 60.0) / CORRUPTION_SOFT_CAP_MINUTES)

## TODO (build-order step 3+, once weapon/zone-unlock state exists): mirror
## data/playerProgression.ts's isPlayerStatLocked and refuse server-side even
## if a caller bypasses the UI lock — attackSpeed needs the Bow, abilityDamage
## needs Zone 2+. Left unchecked here deliberately rather than half-implemented.
func spend_stat_point(stat_id: String) -> bool:
	if stat_points <= 0:
		return false
	stat_points -= 1
	stat_levels[stat_id] = stat_levels.get(stat_id, 0) + 1
	return true

## TODO (build-order step 6, once world/LevelGenerator + Room port): mirror
## Game.ts's beginDescent/completeDescent — walk the physical stairsDown
## obstacle, land in the next zone's start room, generate+cache its layout
## into `layouts` if not already present, mark it visited.
func advance_zone() -> void:
	push_warning("RunState.advance_zone: not yet implemented — needs the level generator (build-order step 6)")

## TODO (build-order step 6): mirror Game.ts's beginAscent/completeAscent —
## the same stairs, walked in reverse, landing in the previous zone's
## heart/boss room. `layouts` staying resident for the whole run (never
## cleared on zone change) is what makes this safe — see the field comment.
func retreat_zone() -> void:
	zone_index = max(zone_index - 1, 0)
	push_warning("RunState.retreat_zone: zone_index decremented, but room landing is not yet implemented — needs the level generator (build-order step 6)")
