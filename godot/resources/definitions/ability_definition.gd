class_name AbilityDefinition
extends Resource
## Ports data/types.ts's AbilityDefinition + data/abilities.ts's 3 entries.
## Effect radius/damage/duration are still hardcoded at the call site in the
## Web build (not on this definition) — worth folding in here when the real
## ability-execution logic ports (build-order step 4+), not before.

@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var cooldown: float = 0.0
## Armory unlock cost in Soul Ash. 0 means not Armory-gated (the starter ability).
@export var unlock_cost: int = 0
@export var color: String = ""
