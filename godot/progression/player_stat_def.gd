class_name PlayerStatDef
extends RefCounted
## Ports data/playerProgression.ts's PlayerStatDefinition interface — one row
## of the 6-stat player-levelling table (see PlayerProgression.player_stats()).
## `stat`/`mode` name a StatBlock field and StatModifier.Mode directly (the
## same snake_case convention StatModifier.gd's own doc-comment documents),
## not a parallel string union — nothing else needs to distinguish them.

var id: String = ""
## An UiIcons icon id (see ui/ui_icons.gd's `match icon_id` dispatch).
var icon: String = ""
var stat: String = ""
var mode: StatModifier.Mode = StatModifier.Mode.FLAT
## Bonus applied per level beyond 1.
var value_per_level: float = 0.0

func _init(p_id: String, p_icon: String, p_stat: String, p_mode: StatModifier.Mode, p_value_per_level: float) -> void:
	id = p_id
	icon = p_icon
	stat = p_stat
	mode = p_mode
	value_per_level = p_value_per_level
