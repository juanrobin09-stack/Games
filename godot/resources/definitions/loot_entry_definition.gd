class_name LootEntryDefinition
extends Resource
## One weighted line in a LootTableDefinition — "this item, or this
## upgrade, this often, this many at once." A separate Resource (not an
## inline Dictionary) so it can be authored/edited as a nested .tres
## sub-resource, same reasoning as TriggeredEffect next to UpgradeDefinition.

enum Kind { ITEM, UPGRADE }

@export var kind: Kind = Kind.ITEM
## An ItemDefinition.id (Kind.ITEM) or UpgradeDefinition.id (Kind.UPGRADE).
@export var ref_id: String = ""
## Relative weight among this table's other entries — not a probability by
## itself, see LootTableDefinition.roll().
@export var weight: float = 1.0
@export var min_qty: int = 1
@export var max_qty: int = 1
