class_name PlayerProgression
extends RefCounted
## Ports data/playerProgression.ts's stat-point spending layer — the XP/level
## curve itself already lives on RunState (see its own
## xp_required_for_next_level(), ported at build-order step 6). All-static,
## like LevelGenerator/EnemyAI/WeaponBehavior: pure lookup/formula logic, no
## per-instance state of its own.
##
## New home note: the TS source splits this across data/playerProgression.ts,
## progression/UpgradePool.ts and world/Shop.ts for its own import-graph
## reasons. Those three become player_progression.gd/upgrade_pool.gd/shop.gd
## here, grouped together under godot/progression/ instead of mirroring
## each original folder — they're one cohesive domain (the run-scoped
## upgrade economy), and this project already groups other logic-utility
## classes by domain rather than by source path (see rendering/, vfx/,
## combat/).

# ---------------------------------------------------------------- The 6 stats
# M1 damage was removed as a player-levelable stat entirely (base weapon
# damage is fixed) — see GAME_DESIGN.md's balancing-pass notes.

## Fresh array each call (cheap: 6 small objects, called on stat-point spend
## and inventory-screen refresh, never per-frame) — kept as a function
## rather than a static var so nothing here risks evaluating another
## script's enum (StatModifier.Mode) before that script is fully loaded.
static func player_stats() -> Array[PlayerStatDef]:
	return [
		PlayerStatDef.new("hp", "heart", "max_hp", StatModifier.Mode.FLAT, 6.0),
		PlayerStatDef.new("stamina", "stamina", "stamina_max", StatModifier.Mode.FLAT, 8.0),
		PlayerStatDef.new("abilityDamage", "ability", "ability_damage_mult", StatModifier.Mode.MULT, 0.05),
		PlayerStatDef.new("range", "range", "range_mult", StatModifier.Mode.MULT, 0.03),
		PlayerStatDef.new("moveSpeed", "boots", "move_speed", StatModifier.Mode.FLAT, 4.0),
		PlayerStatDef.new("attackSpeed", "haste", "attack_speed_mult", StatModifier.Mode.MULT, 0.03),
	]

static func get_player_stat_def(stat_id: String) -> PlayerStatDef:
	for s in player_stats():
		if s.id == stat_id:
			return s
	push_error("PlayerProgression.get_player_stat_def: unknown stat id '%s'" % stat_id)
	return null

## Whether a stat-point row is locked right now — the single source of truth
## both InventoryUI (hides the spend button, once it exists) and
## LevelFlow.spend_stat_point (refuses the spend even if called directly)
## check, so the two can never drift out of sync. Attack Speed unlocks with
## the Bow; ability damage unlocks once the run reaches Zone 1 (the Hollow
## Ruins).
static func is_player_stat_locked(stat_id: String, has_bow: bool, zone_index: int) -> bool:
	if stat_id == "attackSpeed":
		return not has_bow
	if stat_id == "abilityDamage":
		return zone_index < 1
	return false

# ---------------------------------------------------------------- Ability range display

## Purely presentational base value for the ability's range, shown to the
## player as "10" — scales with the exact same area_damage_mult the in-run
## range upgrades already apply, so the displayed number moves in lockstep
## with the real mechanic without introducing a second, competing formula.
const ABILITY_RANGE_DISPLAY_BASE := 10.0

static func get_ability_range_display(area_damage_mult: float) -> float:
	return roundf(ABILITY_RANGE_DISPLAY_BASE * area_damage_mult * 10.0) / 10.0

# ---------------------------------------------------------------- In-run upgrade level cap

## How high an in-run upgrade's level (stack count) can climb while in a
## given zone — index 0 (the Ashen Woods) caps at Lv.2, each zone after
## allows one more. Extend this array when future zones are added — every
## offer-generation call site reads it through get_zone_upgrade_level_cap,
## never a hardcoded number.
const ZONE_UPGRADE_LEVEL_CAP: Array[int] = [2, 3, 4]

## Ceiling for an upgrade that doesn't declare its own max_stacks (0) — a
## backstop against unbounded stacking, comfortably above anything the zone
## caps above currently allow.
const DEFAULT_UPGRADE_MAX_LEVEL := 6

static func get_zone_upgrade_level_cap(zone_index: int) -> int:
	if zone_index >= 0 and zone_index < ZONE_UPGRADE_LEVEL_CAP.size():
		return ZONE_UPGRADE_LEVEL_CAP[zone_index]
	return ZONE_UPGRADE_LEVEL_CAP[ZONE_UPGRADE_LEVEL_CAP.size() - 1]

## The effective max level (stack count) a specific upgrade can reach right
## now: the tighter of its own authored ceiling (0 = uncapped, see
## UpgradeDefinition.max_stacks) and the current zone's cap.
static func effective_upgrade_max_level(def_max_stacks: int, zone_index: int) -> int:
	var own_cap: int = def_max_stacks if def_max_stacks > 0 else DEFAULT_UPGRADE_MAX_LEVEL
	return mini(own_cap, get_zone_upgrade_level_cap(zone_index))
