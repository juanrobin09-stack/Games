class_name DungeonChestConfig
extends Resource
## "Dungeon Level -> Chest Class -> Loot Table" (plus the class's spawn
## chance at that level) in one row, matching the loot-system pass's own
## conceptual layout exactly. Kept separate from ChestClassDefinition: tier
## and required key are what C/B/A/S/SS mechanically ARE, unchanging;
## spawn_chance and loot_table_id are what they mean IN A GIVEN ZONE, which
## a later zone is expected to configure differently without touching the
## class definitions at all.

@export var id: String = ""
@export var zone_index: int = 0
## A ChestClassDefinition.id.
@export var chest_class_id: String = ""
## Independent per-class probability (0..1) — see
## world/classified_chest_rules.gd for how these combine (they do NOT get
## normalized to sum to 1.0; each is its own coin flip).
@export_range(0.0, 1.0) var spawn_chance: float = 0.0
## A LootTableDefinition.id.
@export var loot_table_id: String = ""
