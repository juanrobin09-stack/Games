class_name UpgradeDefinition
extends Resource
## Ports data/types.ts's UpgradeDefinition + data/upgrades.ts's 28 entries
## across 5 rarities. `tags` are SynergyTag strings (e.g. "ember", "dodge")
## — a pair of upgrades sharing a SynergyDefinition's required tags is how
## the 5 cross-upgrade synergies activate.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var rarity: Rarity = Rarity.COMMON
@export var tags: Array[String] = []
@export var modifiers: Array[StatModifier] = []
## 0 means "use the zone's default upgrade-level cap" (the Web build's
## `maxStacks` was optional for the same reason).
@export var max_stacks: int = 0
## Non-empty only for the Bow's own Attack-Speed upgrades today
## (requires_unlock = "bow") — see GODOT_MIGRATION.md §8 for how this same
## gate mechanism is meant to extend to requires_weapon on future gear.
@export var requires_unlock: String = ""
@export var icon: String = ""

## New for Godot, §7/§12 — empty on every one of the 28 ported upgrades
## today (none of them proc anything yet), but the field exists so a future
## upgrade like Hemorrhage/Bleed is a new .tres entry with one array item,
## not new CombatManager code. See triggered_effect.gd.
@export var triggered_effects: Array[TriggeredEffect] = []
