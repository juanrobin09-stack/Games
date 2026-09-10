class_name StatModifier
extends Resource
## Ports data/types.ts's StatModifier. `stat` names a field on StatBlock
## (see stat_block.gd) by its snake_case name, e.g. "max_hp", "move_speed".

enum Mode { FLAT, MULT }

@export var stat: String = ""
@export var mode: Mode = Mode.FLAT
@export var value: float = 0.0
