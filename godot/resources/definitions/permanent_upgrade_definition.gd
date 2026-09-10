class_name PermanentUpgradeDefinition
extends Resource
## Ports data/types.ts's PermanentUpgradeDefinition + data/
## permanentUpgrades.ts's 11 entries — the Soul Ash meta-progression tree,
## spent between runs, baked into StatBlock.fresh() once at each new run's
## start (unlike in-run UpgradeDefinition, which is picked up live).

@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var max_level: int = 0
@export var base_cost: int = 0
## Exponential per-level cost growth off base_cost — port the exact curve
## from progression/MetaProgression.ts's purchase-cost function when that
## system lands (build-order step 6+), rather than assuming a formula here.
@export var cost_growth: float = 0.0
@export var modifiers: Array[StatModifier] = []
@export var icon: String = ""
@export var tier: int = 0
## Id of another PermanentUpgradeDefinition that must be at least level 1
## before this one can be purchased. Empty means no prerequisite.
@export var requires: String = ""
