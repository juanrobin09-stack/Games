class_name StatusEffectDefinition
extends Resource
## New for Godot — see GODOT_MIGRATION.md §7. Generalizes the Web build's
## single hardcoded Burn slot (a stat field + an `if` in CombatSystem) into
## real data: bleed, poison, slow, burn, or any future timed effect is one
## of these, not new code. tint_color/particle_scene are pure feedback and
## have no gameplay effect.

enum Category { DOT, CC, BUFF, DEBUFF }
enum DamageFormula { FLAT, PERCENT_TARGET_MAX_HP, PERCENT_TARGET_CURRENT_HP, PERCENT_SOURCE_STAT, PERCENT_TRIGGERING_HIT }
enum StackRule { NONE, REFRESH, STACK_INTENSITY, STACK_INDEPENDENT }

@export var id: String = ""
@export var name: String = ""
@export var icon: String = ""
@export var category: Category = Category.DOT

@export_group("Damage")
@export var damage_formula: DamageFormula = DamageFormula.FLAT
## Meaning depends on damage_formula: a flat dps, or a 0..1 fraction.
## PERCENT_TRIGGERING_HIT exists specifically to port Burn faithfully: the
## Web build computes dps = max(2, hitDamage * 0.16) once, at the moment of
## application, from that specific hit — not from a fixed authored number
## or a persistent stat. Applying this formula is CombatManager's job (the
## real damage pipeline, build-order step 4) at the moment it creates the
## StatusEffectInstance; damage_value below is the fraction it multiplies by.
@export var damage_value: float = 0.0
## Only read when damage_formula == PERCENT_SOURCE_STAT — which StatBlock
## field (snake_case, e.g. "ability_damage_mult") to read from the source.
@export var source_stat: String = ""
## Only read when damage_formula == PERCENT_TRIGGERING_HIT — a floor under
## the computed dps, so a tiny hit still applies a meaningful tick (Burn's
## own `max(2, ...)`). 0 means no floor.
@export var damage_floor: float = 0.0

@export_group("Timing")
@export var tick_interval: float = 1.0
@export var duration: float = 4.0

@export_group("Stacking")
## Burn's own rule is a real nuance REFRESH doesn't fully capture: a new
## application only takes over (dps AND duration) if it's at least as
## strong as the active one; a weaker one just extends the stronger one's
## timer to whichever duration is longer, instead of being ignored outright
## or replacing outright. Treat REFRESH as "single active instance, newest
## wins" here and accept that approximation — see godot/README.md.
@export var stack_rule: StackRule = StackRule.REFRESH
## Only meaningful when stack_rule == STACK_INTENSITY.
@export var max_stacks: int = 1

@export_group("Feedback (no gameplay effect)")
@export var tint_color: String = ""
@export var particle_scene: PackedScene = null

## CC-type effects only (e.g. Slow) — multiplies move_speed while active.
## 1.0 = no change.
@export var move_speed_mult: float = 1.0
