class_name EventOption
extends Resource
## Ports data/types.ts's EventOption — one branch of a WorldEventDefinition.
## `value`/`cost` are only meaningful for the apply kinds that use them
## (e.g. GAIN_EMBERS reads value; LOSE_HP_FOR_EMBERS reads both) — mirrors
## the Web build's own optional fields, including its confirmed "some
## values are hardcoded at the call site instead of here" gap (see
## GODOT_MIGRATION.md §9 "Improve" list) — fix that AS you port apply(),
## not by inventing numbers here that the Web original doesn't have either.

enum EffectKind {
	GAIN_EMBERS,
	GAIN_HP,
	LOSE_HP_FOR_RARE_UPGRADE,
	GAIN_RANDOM_UPGRADE,
	GAMBLE_EMBERS,
	GAIN_SOUL_ASH_NOW,
	GAIN_SHIELD_CHARGE,
	GAIN_MAX_HP,
	LOSE_HP_FOR_EMBERS,
	NOTHING,
}

@export var id: String = ""
@export var label: String = ""
@export_multiline var detail: String = ""
@export var apply: EffectKind = EffectKind.NOTHING
@export var value: float = 0.0
@export var cost: float = 0.0
