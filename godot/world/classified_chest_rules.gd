class_name ClassifiedChestRules
extends RefCounted
## Rolls which classified chests (if any) appear when a room clears — see
## resources/definitions/dungeon_chest_config.gd. All-static, same
## convention as LevelGenerator/UpgradePool next to it.

## Each configured (zone, chest_class) pair is its OWN independent coin
## flip at its own authored chance — NOT normalized against each other and
## NOT mutually exclusive. For Dungeon Level 1 (zone_index 0) that's
## exactly C=15%, B=3%, A=0.5%, S=0.2%, SS=0.1%: 18.8% combined chance of
## at least one chest, 81.2% of none, by construction (five independent
## Bernoulli trials, not five slices of one 100% pie). Because they're
## independent, more than one CAN hit for the same room clear (e.g. both C
## and B, chance ~0.45%) — that's a deliberate, accepted consequence of
## "independent," not a bug; a room simply gets more than one bonus chest
## that time.
static func roll_spawns(rng: RandomNumberGenerator, zone_index: int) -> Array[DungeonChestConfig]:
	var hits: Array[DungeonChestConfig] = []
	for config in DataRegistry.dungeon_chest_configs_for_zone(zone_index):
		if rng.randf() < config.spawn_chance:
			hits.append(config)
	return hits
