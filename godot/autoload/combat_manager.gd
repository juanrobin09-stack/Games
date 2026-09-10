extends Node
## Autoload: CombatManager
##
## Ports combat/CombatSystem.ts — will become the single place every damage
## source (melee, projectiles, abilities, contact damage, hazard ticks,
## status-effect ticks) routes through, so every hit gets identical crit
## rolls, synergy math, knockback, damage numbers, particles, sound, and
## camera shake. Entities don't exist yet (build-order step 3), so this
## stub only wires the signal surface plus one dependency-free formula.
##
## The signals below are also the intended emission points for §7's
## TriggeredEffect procs (OnHit/OnCrit/OnDodge/OnAbilityCast) once the
## status-effect runtime lands — see GODOT_MIGRATION.md §7.

signal hit_landed(attacker: Node, target: Node, damage: float, was_crit: bool)
signal crit_landed(attacker: Node, target: Node)
signal dodge_perfected(character: Node)
signal ability_cast(character: Node, ability_id: String)
signal enemy_died(enemy: Node)
signal player_died()

## Ports world/Difficulty.ts's getDifficultyFactors — pure math, no entity
## dependency, safe to have working from step 1. corruption_ratio comes
## from RunState.corruption_ratio() (elapsed run time, soft-capped at 14min).
func difficulty_factors(zone_index: int, corruption_ratio: float) -> Dictionary:
	return {
		"hp_mult": 1.0 + zone_index * 0.32 + corruption_ratio * 0.55,
		"damage_mult": 1.0 + zone_index * 0.22 + corruption_ratio * 0.35,
	}

## TODO (build-order step 4): the real damagePlayerToEnemy/damageEnemyToPlayer
## pipeline — crit rolls, synergy multipliers, knockback, lifesteal, status-
## effect application, damage numbers, particles, sound, camera shake — once
## Player/Enemy exist.
func apply_damage(_attacker: Node, _target: Node, _base_damage: float) -> void:
	push_warning("CombatManager.apply_damage: not yet implemented (build-order step 4)")
