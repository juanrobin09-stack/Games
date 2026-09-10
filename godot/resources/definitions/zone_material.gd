class_name ZoneMaterial
extends Resource
## Ports data/types.ts's ZoneMaterial — per-zone knobs for the baked floor/
## wall material (how much moss, rubble, cracking and damp staining a
## zone's stone carries). Every field is a multiplier on the base zone's
## density except moss_color and damp_patches.

@export var moss_color: String = ""
@export var moss_density: float = 0.0
@export var rubble_density: float = 0.0
@export var crack_density: float = 0.0
@export var damp_patches: int = 0
