class_name ItemDefinition
extends Resource
## A piece of "stuff" the player can find in a classified chest or from an
## enemy drop — see GODOT_MIGRATION's loot-system pass. Deliberately holds
## no stat/effect fields: this project has no equipment system yet (nothing
## reads an item to modify a stat), so authoring fake ones here would be
## dead data pretending to work. When a real equipment system exists, it
## reads a real mechanical field added then — not one invented ahead of it.

enum ItemType { MATERIAL, RELIC, KEY }

@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var icon: String = ""
## A LootRarity.Tier ordinal — @export can't take another class's enum as its
## type (GDScript limitation: "Export type can only be built-in, a
## resource, a node, or an enum" rejects a cross-class dotted enum path),
## so this is a plain int that happens to hold a LootRarity.Tier value; every
## call site compares/reads it through LootRarity.Tier.* constants as usual.
@export var rarity: int = LootRarity.Tier.C
@export var item_type: ItemType = ItemType.MATERIAL
## KEY items only — which ChestClassDefinition.tier this key opens. Same
## int-standing-in-for-LootRarity.Tier reasoning as `rarity` above.
@export var key_tier: int = LootRarity.Tier.C
