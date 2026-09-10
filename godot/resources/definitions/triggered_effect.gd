class_name TriggeredEffect
extends Resource
## New for Godot — see GODOT_MIGRATION.md §7. The generalization of the Web
## build's hardcoded `burnChance` stat check: "chance to do X on event Y,"
## attachable to an upgrade's `triggered_effects`, later a weapon's
## `intrinsic_effects` (§8), or an enemy attack. Emit these from real
## signals the combat/dodge/ability systems already need to fire anyway
## (CombatManager.hit_landed/crit_landed/dodge_perfected/ability_cast).
##
## Implemented here as a Resource — GODOT_MIGRATION.md's §7 prose first
## sketched this as "a plain struct, not a Resource"; in practice it needs
## to be a Resource so it can be embedded inline in another Resource's
## exported Array and authored/edited as a nested .tres sub-resource. That
## doc's wording should be read as superseded by this file.

enum Trigger { ON_HIT, ON_CRIT, ON_KILL, ON_DODGE, ON_ABILITY_CAST, ON_BLOCK, ON_TAKE_DAMAGE }
enum Target { SELF, ENEMY }

@export var trigger: Trigger = Trigger.ON_HIT
@export_range(0.0, 1.0) var chance: float = 1.0
## A StatusEffectDefinition to apply, OR leave null and use stat_modifier
## instead for a direct, non-DoT proc (e.g. a brief flat damage buff with
## no visual status). At most one of the two should be set.
@export var status_effect: StatusEffectDefinition = null
@export var stat_modifier: StatModifier = null
@export var target: Target = Target.ENEMY
