class_name StatusEffectInstance
extends RefCounted
## New for Godot — see GODOT_MIGRATION.md §7. A live, active status effect on
## some Character (Player or Enemy). Not a Resource — this is per-run
## runtime state, never authored or saved as an asset, exactly the
## StatusEffectInstance shape sketched in §7: {definition, remaining
## duration, stacks, tick timer, source}.

var definition: StatusEffectDefinition
var remaining_duration: float = 0.0
var stacks: int = 1
var tick_timer: float = 0.0
## Whoever applied this (for kill-credit/lifesteal attribution once combat
## needs it) — a PlayerCharacter or EnemyCharacter, or null for an
## environmental source.
var source: Node = null
## Only meaningful for DamageFormula.PERCENT_TRIGGERING_HIT — the dps
## resolved once at apply time from the specific hit that triggered this
## effect (e.g. Burn's max(2, hitDamage * 0.16)). -1 means "not applicable."
var resolved_dps: float = -1.0

func _init(p_definition: StatusEffectDefinition, p_duration: float, p_source: Node = null) -> void:
	definition = p_definition
	remaining_duration = p_duration
	tick_timer = p_definition.tick_interval
	source = p_source
