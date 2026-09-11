class_name UpgradePool
extends RefCounted
## Ports progression/UpgradePool.ts. All-static, like PlayerProgression next
## to it. `unlocked_tiers` mirrors the TS Set<string> as a Dictionary used
## set-like (id -> true) — this project's established convention wherever a
## TS Set crosses into GDScript (see MetaProgression.unlocks).
##
## Param order differs from the TS source in one place: GDScript requires
## every defaulted parameter to trail every required one, so `owned` (never
## actually omitted at any real TS call site either) moved before the
## optional `min_rarity` rather than sitting after it.

static func get_owned_stacks(owned: Array[OwnedUpgrade], id: String) -> int:
	for o in owned:
		if o.def.id == id:
			return o.stacks
	return 0

## An upgrade is offerable if it's still below its effective level cap for
## the current zone — not simply "not already owned". PlayerCharacter.add_upgrade()
## already supports stacking an owned upgrade up to max_stacks (see
## OwnedUpgrade), this is what actually lets that happen: an already-owned
## upgrade re-offered here and picked again becomes its next level.
static func is_upgrade_available(u: UpgradeDefinition, owned: Array[OwnedUpgrade], zone_index: int) -> bool:
	return get_owned_stacks(owned, u.id) < PlayerProgression.effective_upgrade_max_level(u.max_stacks, zone_index)

static func _is_gated(u: UpgradeDefinition, unlocked_tiers: Dictionary) -> bool:
	return u.requires_unlock == "" or unlocked_tiers.has(u.requires_unlock)

static func roll_upgrade_choices(rng: RandomNumberGenerator, count: int, luck: float, unlocked_tiers: Dictionary, owned: Array[OwnedUpgrade], zone_index: int, min_rarity: UpgradeDefinition.Rarity = UpgradeDefinition.Rarity.COMMON) -> Array[UpgradeDefinition]:
	var all_upgrades: Array = DataRegistry.all("upgrades")
	var pool: Array = all_upgrades.filter(func(u): return _is_gated(u, unlocked_tiers) and is_upgrade_available(u, owned, zone_index))
	if pool.is_empty():
		pool = all_upgrades.filter(func(u): return _is_gated(u, unlocked_tiers))
	if pool.is_empty():
		pool = all_upgrades
	var chosen: Array[UpgradeDefinition] = []
	var used: Dictionary = {}
	var attempts := 0
	while chosen.size() < count and attempts < count * 25:
		attempts += 1
		var rarity: UpgradeDefinition.Rarity = LevelGenerator.roll_rarity(rng, luck, min_rarity)
		var candidates: Array = pool.filter(func(u): return u.rarity == rarity and not used.has(u.id))
		if candidates.is_empty():
			continue
		var pick: UpgradeDefinition = candidates[rng.randi_range(0, candidates.size() - 1)]
		used[pick.id] = true
		chosen.append(pick)
	while chosen.size() < count:
		var remaining: Array = pool.filter(func(u): return not used.has(u.id))
		if remaining.is_empty():
			break
		var pick: UpgradeDefinition = remaining[rng.randi_range(0, remaining.size() - 1)]
		used[pick.id] = true
		chosen.append(pick)
	return chosen

## Picks a single upgrade guaranteed to be at or above min_rarity (chest
## rewards, rare-relic event offers). Rarity ordinals already match
## data/types.ts's RARITY_ORDER exactly (COMMON=0 .. LEGENDARY=4), so a
## plain int compare replaces the TS source's RARITY_ORDER.indexOf() calls.
## Returns null (with a push_error) in the practically-unreachable case
## where every gated upgrade is filtered out — the TS source's rng.pick([])
## silently returns undefined instead, which isn't a safe GDScript array
## index.
static func pick_upgrade_at_least_rarity(rng: RandomNumberGenerator, min_rarity: UpgradeDefinition.Rarity, unlocked_tiers: Dictionary, owned: Array[OwnedUpgrade], zone_index: int) -> UpgradeDefinition:
	var all_upgrades: Array = DataRegistry.all("upgrades")
	var pool: Array = all_upgrades.filter(func(u): return u.rarity >= min_rarity and _is_gated(u, unlocked_tiers) and is_upgrade_available(u, owned, zone_index))
	if pool.is_empty():
		pool = all_upgrades.filter(func(u): return u.rarity >= min_rarity and _is_gated(u, unlocked_tiers))
	if pool.is_empty():
		pool = all_upgrades.filter(func(u): return _is_gated(u, unlocked_tiers))
	if pool.is_empty():
		push_error("UpgradePool.pick_upgrade_at_least_rarity: no upgrade available even after every fallback (min_rarity=%d)" % min_rarity)
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]

## The level an upgrade would become if granted right now (current stacks +
## 1, or 1 if not yet owned) — for UI display on chest/reward/shop cards.
static func upcoming_upgrade_level(id: String, owned: Array[OwnedUpgrade]) -> int:
	return get_owned_stacks(owned, id) + 1
