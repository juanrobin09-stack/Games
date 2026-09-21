class_name LootTableDefinition
extends Resource
## A weighted set of LootEntryDefinition lines, rollable independently of
## what owns it (a ChestClassDefinition, an EnemyDefinition) — one generic
## table shape reused everywhere loot is granted, per the loot-system pass.
## Entries can be left empty; roll() on an empty table simply returns [].

@export var id: String = ""
@export var entries: Array[LootEntryDefinition] = []

## Picks `count` entries by weight, WITH replacement (the same entry can be
## picked more than once — e.g. two rolls both landing on the same common
## material is fine; this table is about "what came out," not "draw
## without replacement from a deck"). Returns [] if the table has no
## entries or every weight is <= 0.
func roll(rng: RandomNumberGenerator, count: int = 1) -> Array[LootEntryDefinition]:
	var picks: Array[LootEntryDefinition] = []
	var total_weight := 0.0
	for e in entries:
		total_weight += maxf(0.0, e.weight)
	if total_weight <= 0.0:
		return picks
	for i in range(count):
		var roll_point := rng.randf() * total_weight
		var acc := 0.0
		for e in entries:
			acc += maxf(0.0, e.weight)
			if roll_point < acc:
				picks.append(e)
				break
	return picks
