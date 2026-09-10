class_name ZoneDefinition
extends Resource
## Ports data/types.ts's ZoneDefinition + data/zones.ts's 3 entries (Ashen
## Woods, The Hollow Ruins, The Ember Citadel). heart_guardian is an enemy
## id — see the important caveat on ZoneDefinition["Ember Citadel"] in
## GODOT_MIGRATION.md §3's enemy-roster callout: the Web build's own boss
## room never actually reads this field (the boss is hand-placed), so port
## the SAME dead-data warning forward rather than "fixing" it silently.

enum AmbientParticle { EMBERS, ASH, SPORES, DUST }

@export var id: String = ""
@export var name: String = ""
@export var subtitle: String = ""
@export var index: int = 0
@export var room_count: int = 0

@export_group("Palette (hex strings)")
@export var palette_floor: String = ""
@export var palette_floor_accent: String = ""
@export var palette_wall: String = ""
@export var palette_wall_top: String = ""
@export var palette_fog: String = ""
@export var palette_ambient: String = ""
@export var palette_accent: String = ""

@export_group("Content")
@export var enemy_pool: Array[String] = []
## Enemy id spawned (scaled up) as this zone's heart/boss-room guardian —
## see the class-level caveat above about the Ember Citadel's boss room.
@export var heart_guardian: String = ""
@export var ambient_particle: AmbientParticle = AmbientParticle.EMBERS

@export_group("Optional overrides")
## LightingSystem ambient darkness while in this zone (Web default: 0.4).
@export var darkness: float = 0.4
## Colour of the zone's living light (fungal growth, the open stairwell).
@export var fungal_color: String = ""
## Palette the ambient spore/ash motes are drawn from (defaults to accent).
@export var spore_colors: Array[String] = []
@export var material: ZoneMaterial = null
