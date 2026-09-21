class_name EnemyDefinition
extends Resource
## Ports data/types.ts's EnemyDefinition + data/enemies.ts's 11 entries.
## color/accent_color are hex strings (e.g. "#3d3229"), unconverted — build
## a real Color at the point of use via Color(hex_string) rather than here,
## so this stays a pure mechanical port of the source data.

enum Behavior { CHASER, TANK, RANGED, HEAVY, STALKER, ELITE, BLOAT, WARDEN }

@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var behavior: Behavior = Behavior.CHASER
@export var base_hp: float = 0.0
@export var base_damage: float = 0.0
@export var move_speed: float = 0.0
@export var radius: float = 0.0
@export var ember_value: int = 0
@export var attack_range: float = 0.0
@export var attack_cooldown: float = 0.0
@export var telegraph_time: float = 0.0
@export var contact_damage: float = 0.0
@export var xp_weight: int = 0
@export var color: String = ""
@export var accent_color: String = ""
@export var requires_unlock: String = ""

@export_group("Behavior-specific (only some apply, per behavior)")
@export var projectile_speed: float = 0.0
@export var vanish_duration: float = 0.0
@export var is_elite: bool = false
## bloat: radius of the detonation's direct hit, and of the spore cloud it leaves.
@export var burst_radius: float = 0.0
@export var cloud_radius: float = 0.0
@export var cloud_duration: float = 0.0
## warden: half-angle (radians) of the frontal arc its shield covers.
@export var shield_arc: float = 0.0
## warden: bash lunge speed/duration, and how long its guard stays down afterwards.
@export var bash_speed: float = 0.0
@export var bash_duration: float = 0.0
@export var exposed_duration: float = 0.0
## warden: max turn rate in rad/s.
@export var turn_rate: float = 0.0
## Heart-room champion: boss-style HP bar and a second phase at half health.
@export var champion: bool = false

## A LootTableDefinition.id this enemy rolls on death. Empty (the default)
## means no drop at all — deliberately opt-in per enemy, not a blanket
## "every enemy can drop everything" default; see loot_table_definition.gd.
@export var loot_table_id: String = ""
## Independent chance (0..1) that a death even attempts the roll above —
## LootTableDefinition.roll() always returns something once it runs (a
## weighted pick, not a chance-of-nothing itself), so THIS is what keeps a
## common enemy from dropping loot on every single kill. Only meaningful
## when loot_table_id is set.
@export_range(0.0, 1.0) var drop_chance: float = 1.0
