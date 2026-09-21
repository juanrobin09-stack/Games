class_name ChestClassDefinition
extends Resource
## One generic definition shared by every classified chest (C/B/A/S/SS) —
## see world/chest_node.gd's is_classified fields. Deliberately NOT five
## separate chest scripts/scenes: a new class later (e.g. adding a rank
## above SS) is one more .tres file, never new code, same DataRegistry
## "add a data entry" convention every other content category already uses.

@export var id: String = ""
## A LootRarity.Tier ordinal — see ItemDefinition.rarity's own comment for why
## this is a plain int rather than a LootRarity.Tier-typed export.
@export var tier: int = LootRarity.Tier.C
## An ItemDefinition.id (ItemType.KEY) required to open this chest class.
@export var required_key_item_id: String = ""
