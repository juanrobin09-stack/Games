class_name WeaponDefinition
extends Resource
## Ports data/types.ts's WeaponDefinition + data/weapons.ts's 4 entries
## (Ember Blade, Void Scythe, Solar Spear, Bow). See GODOT_MIGRATION.md §8
## for how execution (melee arc vs. projectile) splits away from this pure
## data as a WeaponBehavior strategy, once entities exist (build-order step 5).

enum Kind { MELEE, RANGED }

@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.MELEE
@export var base_damage: float = 0.0
@export var attack_cooldown: float = 0.0
@export var stamina_cost: float = 0.0
@export var range: float = 0.0
## Melee only.
@export var arc_degrees: float = 0.0
@export var knockback: float = 0.0
@export var crit_bonus: float = 0.0
## Ranged only.
@export var projectile_speed: float = 0.0
@export var pierce: int = 0
## Armory unlock cost in Soul Ash. 0 means not Armory-gated (the starter
## weapon, or a weapon granted by other means — see the Bow's own .tres).
@export var unlock_cost: int = 0
@export var color: String = ""

## New for Godot, §8 — empty on all 4 ported weapons today (nothing procs
## anything intrinsically yet). Lets a future weapon (a cursed dagger with
## innate poison-on-hit, say) carry an always-on effect independent of any
## upgrade, reusing triggered_effect.gd rather than a parallel system.
@export var intrinsic_effects: Array[TriggeredEffect] = []
