class_name MeleeArcBehavior
extends WeaponBehavior
## The Ember Blade/Void Scythe archetype: an instant arc-overlap check the
## moment the swing starts, no persistent hitbox (GODOT_MIGRATION.md §6's
## own note on why that's a deliberate simplification, not a corner cut).
## The check itself already lives in CombatManager.perform_melee_attack
## (build-order step 4, confirmed working) — this is just that archetype's
## entry point into it.

func execute(attacker: PlayerCharacter, _weapon_def: WeaponDefinition) -> void:
	CombatManager.perform_melee_attack(attacker)
